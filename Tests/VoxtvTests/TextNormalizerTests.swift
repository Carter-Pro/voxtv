import XCTest
@testable import Voxtv

final class TextNormalizerTests: XCTestCase {

    // MARK: - Trimming whitespace

    func testTrimsWhitespace() {
        XCTAssertEqual(TextNormalizer.normalize("  星际穿越  "), "星际穿越")
        XCTAssertEqual(TextNormalizer.normalize("\n星际穿越\n"), "星际穿越")
        XCTAssertEqual(TextNormalizer.normalize("  星际  穿越  "), "星际 穿越")
    }

    // MARK: - Trailing punctuation

    func testRemovesTrailingPunctuation() {
        XCTAssertEqual(TextNormalizer.normalize("星际穿越。"), "星际穿越")
        XCTAssertEqual(TextNormalizer.normalize("Rick and Morty."), "Rick and Morty")
        XCTAssertEqual(TextNormalizer.normalize("速度与激情！"), "速度与激情")
    }

    // MARK: - Consecutive spaces

    func testCompressesConsecutiveSpaces() {
        XCTAssertEqual(TextNormalizer.normalize("星际  穿越"), "星际 穿越")
        XCTAssertEqual(TextNormalizer.normalize("  星际   穿越  "), "星际 穿越")
    }

    // MARK: - Empty and edge cases

    func testEmptyAndWhitespaceOnly() {
        XCTAssertEqual(TextNormalizer.normalize(""), "")
        XCTAssertEqual(TextNormalizer.normalize("   "), "")
        XCTAssertEqual(TextNormalizer.normalize("。"), "")
    }

    // MARK: - Comma and ellipsis

    func testRemovesChineseCommaAndEllipsis() {
        XCTAssertEqual(TextNormalizer.normalize("星际穿越，"), "星际穿越")
        XCTAssertEqual(TextNormalizer.normalize("速度与激情…"), "速度与激情")
    }

    // MARK: - Mixed content

    func testMixedContent() {
        XCTAssertEqual(TextNormalizer.normalize("  速度与激情 7。"), "速度与激情 7")
        XCTAssertEqual(TextNormalizer.normalize("  Rick and Morty!  "), "Rick and Morty")
        XCTAssertEqual(TextNormalizer.normalize("  星际  穿越。。。"), "星际 穿越")
    }
}
