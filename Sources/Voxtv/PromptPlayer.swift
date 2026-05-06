import AppKit
import AVFoundation

/// Plays configurable prompt sounds (system beep or TTS) to cue the user to speak.
final class PromptPlayer {
    private let synth = AVSpeechSynthesizer()

    /// Play a short system prompt sound (non-blocking).
    func playBeep() {
        NSSound(named: "Tink")?.play()
    }

    /// Speak text via macOS built-in TTS (non-blocking).
    func speak(_ text: String) {
        if synth.isSpeaking {
            synth.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        synth.speak(utterance)
    }
}
