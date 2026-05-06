import XCTest
@testable import Voxtv

final class AppleTVBridgeTests: XCTestCase {

    func testBuildCommand() {
        let bridge = AppleTVBridge(deviceId: "abc123")
        let cmd = bridge.buildCommand(text: "interstellar")
        XCTAssertEqual(cmd, ["atvremote", "--id", "abc123", "text_set=interstellar"])
    }

    func testBuildCommandPreservesSpaces() {
        let bridge = AppleTVBridge(deviceId: "abc123")
        let cmd = bridge.buildCommand(text: "hello world")
        XCTAssertEqual(cmd[3], "text_set=hello world")
    }

    func testFindAtvremotePathDoesNotCrash() {
        let bridge = AppleTVBridge(deviceId: "test")
        let path = bridge.findAtvremotePath()
        if let path = path {
            XCTAssertTrue(path.hasSuffix("atvremote") || path.contains("atvremote"))
        }
    }

    func testSendReturnsErrorWhenAtvremoteNotFound() {
        let bridge = AppleTVBridge(deviceId: "test")
        let result = bridge.send(text: "test")
        XCTAssertFalse(result.success)
        // If atvremote is not in PATH, stderr contains the "not found" message.
        // If it is in PATH but the device is invalid, stderr contains an atvremote error.
        // Either way, stderr should be non-empty.
        XCTAssertFalse(result.stderr.isEmpty)
    }
}
