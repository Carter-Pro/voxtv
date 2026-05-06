import Foundation

/// Result of command dispatch.
struct DispatchResult {
    enum Action: String {
        case sendText
    }
    let action: Action
    let text: String
}

/// Protocol for pluggable command handling (LLM extension point).
protocol CommandHandler: Sendable {
    func handle(text: String) async -> DispatchResult
}

/// Default handler: strip search keywords, forward as text to Apple TV.
final class CommandDispatcher: @unchecked Sendable {

    private let searchPrefixes = ["搜索", "搜", "看", "找", "查", "播放", "放"]

    func dispatch(text: String) -> DispatchResult {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return DispatchResult(action: .sendText, text: cleaned)
        }

        for prefix in searchPrefixes {
            if cleaned.hasPrefix(prefix) {
                let remainder = String(cleaned.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespaces)
                let final = remainder.isEmpty ? cleaned : remainder
                return DispatchResult(action: .sendText, text: final)
            }
        }

        return DispatchResult(action: .sendText, text: cleaned)
    }
}
