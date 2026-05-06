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

    var micPermission: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    var speechPermission: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    init() {
        recognizer = SFSpeechRecognizer()  // system default locale
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
            completion(.failure(.permissionDenied))
            return
        }

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.inputFormat(forBus: 0)
        print("[SpeechService] format: \(recordingFormat)")
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            completion(.failure(.microphoneInUse))
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        self.recognitionRequest = request
        self.resultSemaphore = DispatchSemaphore(value: 0)
        self.latestResult = nil
        request.shouldReportPartialResults = true

        guard let recognizer = recognizer, recognizer.isAvailable else {
            completion(.failure(.networkUnavailable))
            return
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let error {
                let nsErr = error as NSError
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
                let speechResult = SpeechResult(text: trimmed, rawText: raw, isFinal: result.isFinal)
                self.latestResult = speechResult
                if result.isFinal {
                    self.resultSemaphore?.signal()
                    completion(.success(speechResult))
                    self.cleanupEngine()
                }
            }
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { buffer, _ in
            request.append(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            completion(.failure(.microphoneInUse))
            return
        }
    }

    func finish() -> SpeechResult? {
        recognitionRequest?.endAudio()
        _ = resultSemaphore?.wait(timeout: .now() + 5)
        cleanupEngine()
        return latestResult
    }

    func cancelRecognition() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        resultSemaphore?.signal()
        cleanupEngine()
    }

    private func cleanupEngine() {
        guard !engineDidCleanup else { return }
        engineDidCleanup = true
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        engine.reset()
    }
}
