@preconcurrency import Foundation

/// States for the wake-word → recognition → send pipeline.
enum PipelineState: String, Sendable {
    case idle
    case kwsListening
    case cooldown
    case prompting
    case recognizing
    case dispatching
    case feedback
    case error
}

final class WakePipeline: @unchecked Sendable {

    // Injected dependencies
    private weak var spotter: KeywordSpotterService?
    private let speech: SpeechService?
    private let bridge: AppleTVBridge?
    private let dispatcher: CommandDispatcher?
    private let prompt: PromptPlayer?
    private let feedback: FeedbackSpeaker?

    // Config
    var promptType: String = "beep"
    var promptText: String = "请说"
    var feedbackEnabled: Bool = true
    var recognitionTimeout: TimeInterval = 8.0
    var cooldownDuration: TimeInterval = 3.0

    // State
    private(set) var state: PipelineState = .idle
    private var cooldownTask: DispatchWorkItem?
    private var cachedKeywordsBuf: String = ""
    private var cachedThreshold: Float = 0.25

    // Callbacks for Dashboard / logging
    var onStateChange: (@Sendable (PipelineState) -> Void)?
    var onLog: (@Sendable (String) -> Void)?

    // MARK: - Init

    init(spotter: KeywordSpotterService?, speech: SpeechService?, bridge: AppleTVBridge?,
         dispatcher: CommandDispatcher?, prompt: PromptPlayer?, feedback: FeedbackSpeaker?) {
        self.spotter = spotter
        self.speech = speech
        self.bridge = bridge
        self.dispatcher = dispatcher
        self.prompt = prompt
        self.feedback = feedback
    }

    // MARK: - Pipeline lifecycle

    func start(keywordsBuf: String, threshold: Float = 0.25) throws {
        guard state == .idle else { return }
        cachedKeywordsBuf = keywordsBuf
        cachedThreshold = threshold
        spotter?.onDetection = { [weak self] keyword in
            self?.handleWakeDetection(keyword)
        }
        try spotter?.start(keywordsBuf: keywordsBuf, threshold: threshold)
        transition(to: .kwsListening)
        log("pipeline started, listening for wake word")
    }

    func stop() {
        cooldownTask?.cancel()
        spotter?.stop()
        transition(to: .idle)
        log("pipeline stopped")
    }

    // MARK: - Pipeline stages

    private func handleWakeDetection(_ keyword: String) {
        log("wake word detected: '\(keyword)', stopping KWS")
        transition(to: .cooldown)
        spotter?.stop()

        let currentPromptType = UserDefaults.standard.string(forKey: "promptType") ?? promptType
        let currentPromptText = UserDefaults.standard.string(forKey: "promptText") ?? promptText
        log("starting recognition engine before prompt (type=\(currentPromptType))")

        // Start recognition engine first — initializes synchronously before cueing user
        startRecognition()

        // Engine is now running, play prompt to cue user
        if currentPromptType == "tts" {
            prompt?.speak(currentPromptText)
            // TTS plays while recognition is already capturing audio
        } else {
            prompt?.playBeep()
            log("beep played, recognition already active")
        }
    }

    private func startRecognition() {
        transition(to: .recognizing)
        log("speech recognition started (timeout=\(recognitionTimeout)s)")
        guard let speech = speech else {
            handlePipelineError("SpeechService not configured")
            return
        }

        final class TimeoutFlag: @unchecked Sendable { var fired = false }
        let flag = TimeoutFlag()
        let timeoutTask = DispatchWorkItem { [weak self] in
            guard let self, !flag.fired else { return }
            flag.fired = true
            self.log("recognition timeout, finishing")
            if let result = self.speech?.finish(), !result.text.isEmpty {
                self.log("recognition finished with text: '\(result.text)'")
                self.handleRecognitionResult(result.text)
            } else {
                self.log("recognition finished — no speech detected")
                self.handleRecognitionError(.noSpeech)
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + recognitionTimeout, execute: timeoutTask)

        speech.recognize { [weak self] result in
            timeoutTask.cancel()
            guard !flag.fired else { return }
            switch result {
            case .success(let r):
                self?.log("recognition result: '\(r.text)' (raw: '\(r.rawText)')")
                self?.handleRecognitionResult(r.text)
            case .failure(let e):
                self?.log("recognition error: \(e.localizedDescription)")
                self?.handleRecognitionError(e)
            }
        }
        log("recognition engine initialized, audio capture active")
    }

    private func handleRecognitionResult(_ text: String) {
        let cleaned = TextNormalizer.normalize(text)
        guard !cleaned.isEmpty else {
            log("recognition result empty after normalization")
            feedback?.speakNoSpeech()
            startCooldown(duration: cooldownDuration)
            return
        }

        transition(to: .dispatching)
        let result = dispatcher?.dispatch(text: cleaned) ?? DispatchResult(action: .sendText, text: cleaned)
        log("dispatch: action=\(result.action.rawValue) text='\(result.text)'")

        let bridgeResult = bridge?.send(text: result.text)
        let sendOk = bridgeResult?.success ?? false
        log("appleTV send: ok=\(sendOk)" + (sendOk ? "" : " stderr=\(bridgeResult?.stderr ?? "")"))

        transition(to: .feedback)
        let feedbackOn = UserDefaults.standard.object(forKey: "feedbackEnabled") as? Bool ?? feedbackEnabled
        if feedbackOn {
            if sendOk {
                log("speaking feedback: success '\(result.text)'")
                feedback?.speakSuccess(query: result.text)
            } else {
                log("speaking feedback: send failed")
                feedback?.speakSendFailed()
            }
        } else {
            log("feedback disabled, skipping TTS")
        }

        startCooldown(duration: cooldownDuration)
    }

    private func handleRecognitionError(_ error: SpeechError) {
        log("handling recognition error: \(error)")
        let feedbackOn = UserDefaults.standard.object(forKey: "feedbackEnabled") as? Bool ?? feedbackEnabled
        if feedbackOn {
            switch error {
            case .noSpeech:
                feedback?.speakNoSpeech()
            case .permissionDenied:
                feedback?.speak("麦克风或语音识别权限未授权")
            case .networkUnavailable:
                feedback?.speak("网络连接不可用")
            default:
                feedback?.speakRecognitionFailed()
            }
        }
        startCooldown(duration: cooldownDuration)
    }

    private func handlePipelineError(_ message: String) {
        log("pipeline error: \(message)")
        transition(to: .error)
        feedback?.speak(message)
        startCooldown(duration: cooldownDuration)
    }

    // MARK: - Helpers

    private func log(_ message: String) {
        onLog?("[Pipeline] \(message)")
    }

    // MARK: - Cooldown

    func startCooldown(duration: TimeInterval) {
        transition(to: .cooldown)
        let task = DispatchWorkItem { [weak self] in
            self?.restartKWS()
        }
        cooldownTask = task
        DispatchQueue.global().asyncAfter(deadline: .now() + duration, execute: task)
    }

    private func restartKWS() {
        guard state != .idle else { return }
        log("restarting KWS in 0.3s...")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.state != .idle else { return }
            do {
                try self.spotter?.start(keywordsBuf: self.cachedKeywordsBuf, threshold: self.cachedThreshold)
                self.spotter?.onDetection = { [weak self] keyword in
                    self?.handleWakeDetection(keyword)
                }
                self.transition(to: .kwsListening)
                self.log("KWS restarted after cooldown")
            } catch {
                self.transition(to: .error)
                self.log("KWS restart failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - State

    private func transition(to newState: PipelineState) {
        state = newState
        onStateChange?(newState)
    }
}
