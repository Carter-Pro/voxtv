import Testing
@testable import Voxtv

struct CommandDispatcherTests {
    @Test func testPassthroughWithoutKeyword() {
        let dispatcher = CommandDispatcher()
        let result = dispatcher.dispatch(text: "星际穿越")
        #expect(result.action == .sendText)
        #expect(result.text == "星际穿越")
    }

    @Test func testSearchKeywordStripped() {
        let dispatcher = CommandDispatcher()
        let cases = ["搜索星际穿越", "看三体", "找权力的游戏", "查繁花", "搜甄嬛传"]
        for input in cases {
            let result = dispatcher.dispatch(text: input)
            #expect(result.action == .sendText, "input: \(input)")
            #expect(!result.text.contains(input.prefix(2)), "keyword should be stripped from: \(input) -> \(result.text)")
        }
    }

    @Test func testPlayKeyword() {
        let dispatcher = CommandDispatcher()
        let result = dispatcher.dispatch(text: "播放繁花")
        #expect(result.action == .sendText)
        #expect(result.text == "繁花")
    }

    @Test func testWhitespaceTrimming() {
        let dispatcher = CommandDispatcher()
        let result = dispatcher.dispatch(text: "  搜索  奥本海默  ")
        #expect(result.text == "奥本海默")
    }

    @Test func testEmptyAfterStripReturnsOriginal() {
        let dispatcher = CommandDispatcher()
        let result = dispatcher.dispatch(text: "搜索")
        #expect(result.text == "搜索")
    }

    @Test func testEnglishTitle() {
        let dispatcher = CommandDispatcher()
        let result = dispatcher.dispatch(text: "搜索Rick and Morty")
        #expect(result.text == "Rick and Morty")
    }
}
