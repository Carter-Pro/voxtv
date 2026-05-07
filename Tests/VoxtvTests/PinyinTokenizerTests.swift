import XCTest
@testable import Voxtv

final class PinyinTokenizerTests: XCTestCase {

    func testSingleCharacter() {
        let result = PinyinTokenizer.tokenize("电")
        XCTAssertTrue(result.contains("d"), "expected initial 'd', got: \(result)")
        XCTAssertTrue(result.contains("iàn"), "expected final 'iàn', got: \(result)")
        XCTAssertTrue(result.hasSuffix("@电"), "expected @电 suffix, got: \(result)")
    }

    func testTwoCharacterWord() {
        let result = PinyinTokenizer.tokenize("电视")
        XCTAssertTrue(result.contains("d"), "expected initial 'd', got: \(result)")
        XCTAssertTrue(result.contains("sh"), "expected initial 'sh', got: \(result)")
        XCTAssertTrue(result.hasSuffix("@电视"), "expected @电视 suffix, got: \(result)")
    }

    func testFourCharacterPhrase() {
        let result = PinyinTokenizer.tokenize("电视电视")
        XCTAssertTrue(result.contains("@电视电视"), "expected @电视电视 suffix, got: \(result)")
        let parts = result.replacingOccurrences(of: " @电视电视", with: "").components(separatedBy: " ")
        XCTAssertEqual(parts.count, 8, "expected 8 tokens for 4 chars, got: \(parts)")
    }

    func testEmptyReturnsEmpty() {
        let result = PinyinTokenizer.tokenize("")
        XCTAssertEqual(result, "")
    }

    func testEnglishPassthrough() {
        let result = PinyinTokenizer.tokenize("Hello")
        XCTAssertTrue(result.hasSuffix("@Hello"), "expected @Hello suffix, got: \(result)")
    }

    func testKeywordsBufGeneration() {
        let buf = PinyinTokenizer.keywordsBuf(from: "电视电视")
        XCTAssertFalse(buf.contains("\n"), "expected single line, got: \(buf)")
        XCTAssertTrue(buf.contains("@电视电视"), "expected @电视电视, got: \(buf)")
    }

    func testKeywordsBufWithMultipleKeywords() {
        let buf = PinyinTokenizer.keywordsBuf(from: ["电视电视", "小爱同学"])
        let lines = buf.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].hasSuffix("@电视电视"))
        XCTAssertTrue(lines[1].hasSuffix("@小爱同学"))
    }
}
