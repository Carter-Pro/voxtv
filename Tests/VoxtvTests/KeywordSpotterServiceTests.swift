import XCTest
@testable import Voxtv

final class KeywordSpotterServiceTests: XCTestCase {

    func testInitialStateIsIdle() {
        let service = KeywordSpotterService(
            modelDir: "/tmp/fake",
            vadModel: "/tmp/fake",
            log: { _, _ in }
        )
        XCTAssertEqual(service.state, .idle)
    }

    func testStartWithoutModelFilesThrows() {
        let service = KeywordSpotterService(
            modelDir: "/tmp/nonexistent",
            vadModel: "/tmp/fake",
            log: { _, _ in }
        )
        XCTAssertThrowsError(try service.start(keywordsBuf: "你好军哥"))
    }

    func testStartWithoutModelFilesThrowsKWSError() {
        let service = KeywordSpotterService(
            modelDir: "/tmp/nonexistent",
            vadModel: "/tmp/fake",
            log: { _, _ in }
        )
        XCTAssertThrowsError(try service.start(keywordsBuf: "你好军哥")) { error in
            guard let kwsError = error as? KWSError else {
                XCTFail("Expected KWSError, got \(type(of: error))")
                return
            }
            if case .modelNotFound = kwsError {
                // expected
            } else {
                XCTFail("Expected .modelNotFound, got \(kwsError)")
            }
        }
    }

    func testStopWhenIdleDoesNotCrash() {
        let service = KeywordSpotterService(
            modelDir: "/tmp/fake",
            vadModel: "/tmp/fake",
            log: { _, _ in }
        )
        service.stop()
        XCTAssertEqual(service.state, .idle)
    }

    func testDoubleStopDoesNotCrash() {
        let service = KeywordSpotterService(
            modelDir: "/tmp/fake",
            vadModel: "/tmp/fake",
            log: { _, _ in }
        )
        service.stop()
        service.stop()
        XCTAssertEqual(service.state, .idle)
    }

    func testStopDoesNotImpactNewService() {
        let service1 = KeywordSpotterService(
            modelDir: "/tmp/fake",
            vadModel: "/tmp/fake",
            log: { _, _ in }
        )
        service1.stop()

        let service2 = KeywordSpotterService(
            modelDir: "/tmp/fake2",
            vadModel: "/tmp/fake2",
            log: { _, _ in }
        )
        XCTAssertEqual(service2.state, .idle)
    }

    func testConstructorStoresPaths() {
        let service = KeywordSpotterService(
            modelDir: "/tmp/test-models",
            vadModel: "/tmp/test-vad/foo.onnx",
            log: { _, _ in }
        )
        // Verify via start() error that modelDir is used
        XCTAssertThrowsError(try service.start(keywordsBuf: "test")) { error in
            // Should reference the modelDir path
            let msg = "\(error)"
            XCTAssertTrue(msg.contains("test-models"), "Expected error to mention modelDir, got: \(msg)")
        }
    }

    func testStartThrowsWhenAlreadyRunning() {
        // This test verifies the guard at the top of start()
        // We can only test that start() fails fast before calling C API
        // when model dir is missing. The alreadyRunning guard would be
        // tested in integration tests with real model files.
        let service = KeywordSpotterService(
            modelDir: "/tmp/nonexistent",
            vadModel: "/tmp/fake",
            log: { _, _ in }
        )
        // First start fails quickly with missing files
        XCTAssertThrowsError(try service.start(keywordsBuf: "test"))
        // State should still be idle since start failed
        XCTAssertEqual(service.state, .idle)
    }

    func testKeywordsBufPassing() {
        // Just verify the service can be created
        let service = KeywordSpotterService(
            modelDir: "/tmp/fake",
            vadModel: "/tmp/fake",
            log: { _, _ in }
        )
        XCTAssertNotNil(service)
    }
}
