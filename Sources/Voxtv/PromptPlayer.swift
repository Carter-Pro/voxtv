import AppKit
import AVFoundation

/// Plays configurable prompt sounds (system beep or TTS) to cue the user to speak.
final class PromptPlayer {
    private let synth = AVSpeechSynthesizer()
    /// Strong reference prevents NSSound from deallocating mid-playback.
    private var currentBeep: NSSound?
    var onLog: (@Sendable (String) -> Void)?

    /// Play a short system prompt sound (non-blocking).
    func playBeep() {
        let soundName = UserDefaults.standard.string(forKey: "beepSoundName") ?? "Tink"
        if let sound = NSSound(named: soundName) {
            currentBeep = sound
            sound.play()
            log("beep: playing NSSound '\(soundName)'")
        } else {
            log("beep: NSSound '\(soundName)' not found, falling back to system beep")
            NSSound.beep()
        }
    }

    /// Speak text via macOS built-in TTS (non-blocking).
    func speak(_ text: String) {
        if synth.isSpeaking {
            synth.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        synth.speak(utterance)
        log("tts: speaking '\(text)'")
    }

    private func log(_ message: String) {
        onLog?("[PromptPlayer] \(message)")
    }
}
