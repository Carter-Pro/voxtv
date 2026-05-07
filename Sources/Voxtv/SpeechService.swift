import AVFoundation
import Speech

enum SpeechError: Error {
    case permissionDenied
    case networkUnavailable
    case rateLimited
    case microphoneInUse
    case noSpeech
    case recognitionFailed

    var localizedDescription: String {
        switch self {
        case .permissionDenied:
            return "麦克风或语音识别权限未授权，请在系统设置中开启"
        case .networkUnavailable:
            return "网络不可用，语音识别需要联网"
        case .rateLimited:
            return "语音识别请求过于频繁，请稍后再试"
        case .microphoneInUse:
            return "麦克风被其他应用占用"
        case .noSpeech:
            return "未检测到语音"
        case .recognitionFailed:
            return "语音识别失败"
        }
    }
}

struct SpeechResult {
    let text: String
    let rawText: String
    let isFinal: Bool
}

final class SpeechService: @unchecked Sendable {
    private var engine = AVAudioEngine()
    private var engineDidCleanup = false
    private var recognizer: SFSpeechRecognizer?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var latestResult: SpeechResult?
    private var resultSemaphore: DispatchSemaphore?
    /// Best non-empty partial text — preserved when final result comes back empty.
    private var bestPartialText: String = ""
    /// Duration of silence before auto-finalizing (calls endAudio).
    var silenceDuration: TimeInterval = 1.5
    private var silenceTask: DispatchWorkItem?
    var onLog: (@Sendable (String) -> Void)?

    var micPermission: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    var speechPermission: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh_CN"))
    }

    func requestPermissions() async -> (mic: Bool, speech: Bool) {
        let mic = await AVCaptureDevice.requestAccess(for: .audio)
        let speech = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        return (mic, speech)
    }

    func recognize(completion: @escaping @Sendable (Result<SpeechResult, SpeechError>) -> Void) {
        engineDidCleanup = false
        guard micPermission, speechPermission else {
            log("permission denied (mic=\(micPermission) speech=\(speechPermission))")
            completion(.failure(.permissionDenied))
            return
        }

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.inputFormat(forBus: 0)
        log("input format: \(recordingFormat)")
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            log("invalid input format, returning microphoneInUse")
            completion(.failure(.microphoneInUse))
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        self.recognitionRequest = request
        self.resultSemaphore = DispatchSemaphore(value: 0)
        self.latestResult = nil
        request.shouldReportPartialResults = true

        guard let recognizer = recognizer, recognizer.isAvailable else {
            log("recognizer unavailable")
            completion(.failure(.networkUnavailable))
            return
        }
        log("recognizer ready, locale=\(recognizer.locale.identifier)")

        // [DEBUG-h7k2] Count buffers to verify audio flow
        var bufferCount = 0
        bestPartialText = ""
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let error {
                let nsErr = error as NSError
                self.log("recognition error: domain=\(nsErr.domain) code=\(nsErr.code) desc=\(nsErr.localizedDescription) buffers=\(bufferCount) bestPartial='\(self.bestPartialText)'")
                let speechErr: SpeechError = {
                    if nsErr.domain == "kLSRErrorDomain" {
                        switch nsErr.code {
                        case 209: return .rateLimited
                        case 203: return .noSpeech
                        default: return .recognitionFailed
                        }
                    }
                    return .recognitionFailed
                }()
                completion(.failure(speechErr))
                self.cleanupEngine()
                return
            }
            if let result = result {
                let raw = result.bestTranscription.formattedString
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                self.log("partial result: '\(trimmed)' isFinal=\(result.isFinal) buffers=\(bufferCount)")
                let speechResult = SpeechResult(text: trimmed, rawText: raw, isFinal: result.isFinal)
                self.latestResult = speechResult
                if !trimmed.isEmpty {
                    self.bestPartialText = trimmed
                    // Reset silence timer — each new partial result defers auto-finalize
                    self.silenceTask?.cancel()
                    let task = DispatchWorkItem { [weak self] in
                        guard let self else { return }
                        self.log("silence timer fired (bestPartial='\(self.bestPartialText)'), ending audio")
                        self.recognitionRequest?.endAudio()
                    }
                    self.silenceTask = task
                    DispatchQueue.global().asyncAfter(deadline: .now() + self.silenceDuration, execute: task)
                }
                if result.isFinal {
                    self.resultSemaphore?.signal()
                    // If final result is empty but we have a good partial, use it
                    let finalResult: SpeechResult
                    if trimmed.isEmpty && !self.bestPartialText.isEmpty {
                        self.log("final result empty, using bestPartial='\(self.bestPartialText)'")
                        finalResult = SpeechResult(text: self.bestPartialText, rawText: self.bestPartialText, isFinal: true)
                    } else {
                        finalResult = speechResult
                    }
                    completion(.success(finalResult))
                    self.cleanupEngine()
                }
            }
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { buffer, _ in
            bufferCount += 1
            request.append(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
            log("engine started, tap installed")
        } catch {
            log("engine start failed: \(error.localizedDescription)")
            completion(.failure(.microphoneInUse))
            return
        }
    }

    func finish() -> SpeechResult? {
        recognitionRequest?.endAudio()
        _ = resultSemaphore?.wait(timeout: .now() + 5)
        cleanupEngine()
        // If final result was empty but we captured partial text, use it
        if let r = latestResult, r.text.isEmpty, !bestPartialText.isEmpty {
            return SpeechResult(text: bestPartialText, rawText: bestPartialText, isFinal: true)
        }
        return latestResult
    }

    func cancelRecognition() {
        silenceTask?.cancel()
        silenceTask = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        resultSemaphore?.signal()
        cleanupEngine()
    }

    private func cleanupEngine() {
        guard !engineDidCleanup else { return }
        engineDidCleanup = true
        silenceTask?.cancel()
        silenceTask = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        engine = AVAudioEngine()  // recreate — stop/start reuse is unreliable
    }

    private func log(_ message: String) {
        onLog?("[SpeechService] \(message)")
    }
}
