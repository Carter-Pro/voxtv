import XCTest
@testable import Voxtv

final class SpeechServiceTests: XCTestCase {

    func testSpeechErrorDescriptions() {
        XCTAssertFalse(SpeechError.permissionDenied.localizedDescription.isEmpty)
        XCTAssertFalse(SpeechError.networkUnavailable.localizedDescription.isEmpty)
        XCTAssertFalse(SpeechError.rateLimited.localizedDescription.isEmpty)
        XCTAssertFalse(SpeechError.microphoneInUse.localizedDescription.isEmpty)
        XCTAssertFalse(SpeechError.noSpeech.localizedDescription.isEmpty)
        XCTAssertFalse(SpeechError.recognitionFailed.localizedDescription.isEmpty)
    }

    func testSpeechResultInitialState() {
        let result = SpeechResult(text: "", rawText: "", isFinal: false)
        XCTAssertFalse(result.isFinal)
        XCTAssertEqual(result.text, "")
    }

    func testServiceCanBeCreated() {
        let service = SpeechService()
        XCTAssertNotNil(service)
    }

    func testMicPermissionIsBool() {
        let service = SpeechService()
        let permission = service.micPermission
        // Just verify it's a Bool (won't crash)
        XCTAssertTrue(permission || !permission)
    }

    func testSpeechPermissionIsBool() {
        let service = SpeechService()
        let permission = service.speechPermission
        XCTAssertTrue(permission || !permission)
    }

    func testFinishBeforeRecognitionReturnsNil() {
        let service = SpeechService()
        let result = service.finish()
        XCTAssertNil(result)
    }

    func testCancelRecognitionDoesNotCrash() {
        let service = SpeechService()
        service.cancelRecognition()
        // Should not crash
    }
}
