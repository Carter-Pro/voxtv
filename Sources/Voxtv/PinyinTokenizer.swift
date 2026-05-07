import Foundation

enum PinyinTokenizer {
    /// Chinese initials (consonants) in longest-match order.
    private static let initials = [
        "zh", "ch", "sh",
        "b", "p", "m", "f", "d", "t", "n", "l",
        "g", "k", "h", "j", "q", "x",
        "r", "z", "c", "s",
        "y", "w"
    ]

    /// Convert a Chinese phrase to sherpa-onnx ppinyin keyword format.
    /// "电视电视" → "d iàn sh ì d iàn sh ì @电视电视"
    static func tokenize(_ text: String) -> String {
        guard !text.isEmpty else { return "" }

        let mutable = NSMutableString(string: text)
        // Produce pinyin with tone marks: 电视 → diàn shì
        CFStringTransform(mutable, nil, kCFStringTransformToLatin, false)
        // Do NOT strip diacritics — sherpa-onnx needs tone marks

        let rawPinyin = mutable as String
        let syllables = rawPinyin.components(separatedBy: " ")

        var tokens: [String] = []
        for syllable in syllables where !syllable.isEmpty {
            var found = false
            for initial in initials {
                if syllable.hasPrefix(initial) {
                    tokens.append(initial)
                    let final = String(syllable.dropFirst(initial.count))
                    if !final.isEmpty {
                        tokens.append(final)
                    }
                    found = true
                    break
                }
            }
            if !found {
                tokens.append(syllable)
            }
        }

        let joined = tokens.joined(separator: " ")
        return "\(joined) @\(text)"
    }

    /// Generate a keywordsBuf string for one or more wake words.
    static func keywordsBuf(from words: [String]) -> String {
        words.map { tokenize($0) }.joined(separator: "\n")
    }

    static func keywordsBuf(from word: String) -> String {
        tokenize(word)
    }
}
