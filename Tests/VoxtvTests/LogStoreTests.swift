import XCTest
@testable import Voxtv

final class LogStoreTests: XCTestCase {

    func testAppendAndRetrieve() async {
        let store = LogStore(maxSize: 200)
        await store.append(level: .info, message: "first")
        await store.append(level: .warn, message: "second")
        let entries = await store.all()
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].level, .info)
        XCTAssertEqual(entries[0].message, "first")
        XCTAssertEqual(entries[1].level, .warn)
        XCTAssertEqual(entries[1].message, "second")
    }

    func testMaxSizeEnforced() async {
        let store = LogStore(maxSize: 3)
        for i in 1...5 {
            await store.append(level: .info, message: "msg\(i)")
        }
        let entries = await store.all()
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[0].message, "msg3")
        XCTAssertEqual(entries[1].message, "msg4")
        XCTAssertEqual(entries[2].message, "msg5")
    }

    func testEntriesHaveTimestamp() async {
        let before = Date()
        let store = LogStore(maxSize: 10)
        await store.append(level: .error, message: "timed")
        let after = Date()
        guard let entry = await store.all().first else {
            XCTFail("expected one entry")
            return
        }
        XCTAssertGreaterThanOrEqual(entry.timestamp, before)
        XCTAssertLessThanOrEqual(entry.timestamp, after)
    }

    func testJSONEncoding() async {
        let store = LogStore(maxSize: 10)
        await store.append(level: .info, message: "hello json")
        let entries = await store.all()
        let json = entries.toJSON()
        XCTAssertTrue(json.contains("\"level\""))
        XCTAssertTrue(json.contains("\"message\""))
        XCTAssertTrue(json.contains("hello json"))
        // Verify valid JSON
        let data = Data(json.utf8)
        let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.count, 1)
    }
}
