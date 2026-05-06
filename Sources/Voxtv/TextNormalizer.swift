import Foundation

enum TextNormalizer {
    static func normalize(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let trailingPunctuation = CharacterSet(charactersIn: "。，！？,.!?…")
        while let last = result.unicodeScalars.last, trailingPunctuation.contains(last) {
            result.removeLast()
            result = result.trimmingCharacters(in: .whitespaces)
        }
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
