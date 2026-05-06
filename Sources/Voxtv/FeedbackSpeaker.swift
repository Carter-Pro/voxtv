import AVFoundation

/// Speaks feedback messages via macOS built-in TTS.
final class FeedbackSpeaker {
    private let synth = AVSpeechSynthesizer()

    /// Speak a feedback message (non-blocking). Stops any in-progress speech first.
    func speak(_ text: String) {
        if synth.isSpeaking {
            synth.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        synth.speak(utterance)
    }

    /// "已搜索 星际穿越"
    func speakSuccess(query: String) {
        speak("已搜索\(query)")
    }

    /// "发送失败，请检查 Apple TV"
    func speakSendFailed() {
        speak("发送失败，请检查 Apple TV")
    }

    /// "语音识别失败，请重试"
    func speakRecognitionFailed() {
        speak("语音识别失败，请重试")
    }

    /// "未检测到语音"
    func speakNoSpeech() {
        speak("未检测到语音")
    }
}
