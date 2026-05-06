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

    // Callback for Dashboard
    var onStateChange: (@Sendable (PipelineState) -> Void)?

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
    }

    func stop() {
        cooldownTask?.cancel()
        spotter?.stop()
        transition(to: .idle)
    }

    // MARK: - Pipeline stages

    private func handleWakeDetection(_ keyword: String) {
        transition(to: .cooldown)
        spotter?.stop()

        transition(to: .prompting)
        if promptType == "tts" {
            prompt?.speak(promptText)
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.startRecognition()
            }
        } else {
            prompt?.playBeep()
            startRecognition()
        }
    }

    private func startRecognition() {
        transition(to: .recognizing)
        guard let speech = speech else {
            handlePipelineError("SpeechService not configured")
            return
        }

        let timeoutTask = DispatchWorkItem { [weak self] in
            self?.speech?.cancelRecognition()
            self?.feedback?.speakNoSpeech()
            self?.startCooldown(duration: self?.cooldownDuration ?? 3.0)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + recognitionTimeout, execute: timeoutTask)

        speech.recognize { [weak self] result in
            timeoutTask.cancel()
            switch result {
            case .success(let r):
                self?.handleRecognitionResult(r.text)
            case .failure(let e):
                self?.handleRecognitionError(e)
            }
        }
    }

    private func handleRecognitionResult(_ text: String) {
        let cleaned = TextNormalizer.normalize(text)
        guard !cleaned.isEmpty else {
            feedback?.speakNoSpeech()
            startCooldown(duration: cooldownDuration)
            return
        }

        transition(to: .dispatching)
        let result = dispatcher?.dispatch(text: cleaned) ?? DispatchResult(action: .sendText, text: cleaned)

        let sendOk = bridge?.send(text: result.text).success ?? false

        transition(to: .feedback)
        if feedbackEnabled {
            if sendOk {
                feedback?.speakSuccess(query: result.text)
            } else {
                feedback?.speakSendFailed()
            }
        }

        startCooldown(duration: cooldownDuration)
    }

    private func handleRecognitionError(_ error: SpeechError) {
        if feedbackEnabled {
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
        transition(to: .error)
        feedback?.speak(message)
        startCooldown(duration: cooldownDuration)
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
        do {
            try spotter?.start(keywordsBuf: cachedKeywordsBuf, threshold: cachedThreshold)
            spotter?.onDetection = { [weak self] keyword in
                self?.handleWakeDetection(keyword)
            }
            transition(to: .kwsListening)
        } catch {
            transition(to: .error)
        }
    }

    // MARK: - State

    private func transition(to newState: PipelineState) {
        state = newState
        onStateChange?(newState)
    }
}
