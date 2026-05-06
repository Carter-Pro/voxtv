import XCTest
@testable import Voxtv

final class DashboardServerTests: XCTestCase {

    func testStatusEndpoint() throws {
        let port = try findAvailablePort()
        let server = DashboardServer(port: port)
        try server.start()
        defer { server.stop() }

        let done = expectation(description: "status")
        let url = URL(string: "http://localhost:\(port)/api/status")!
        URLSession.shared.dataTask(with: url) { data, _, error in
            XCTAssertNil(error)
            let body = String(data: data ?? Data(), encoding: .utf8) ?? ""
            XCTAssertTrue(body.contains("\"state\":\"idle\""))
            done.fulfill()
        }.resume()

        wait(for: [done], timeout: 3)
    }

    func testDashboardHTML() throws {
        let port = try findAvailablePort()
        let server = DashboardServer(port: port)
        try server.start()
        defer { server.stop() }

        let done = expectation(description: "html")
        let url = URL(string: "http://localhost:\(port)/")!
        URLSession.shared.dataTask(with: url) { data, _, error in
            XCTAssertNil(error)
            let body = String(data: data ?? Data(), encoding: .utf8) ?? ""
            XCTAssertTrue(body.contains("Voxtv Dashboard"))
            done.fulfill()
        }.resume()

        wait(for: [done], timeout: 3)
    }

    func test404() throws {
        let port = try findAvailablePort()
        let server = DashboardServer(port: port)
        try server.start()
        defer { server.stop() }

        let done = expectation(description: "404")
        let url = URL(string: "http://localhost:\(port)/nonexistent")!
        URLSession.shared.dataTask(with: url) { data, _, error in
            XCTAssertNil(error)
            let body = String(data: data ?? Data(), encoding: .utf8) ?? ""
            XCTAssertEqual(body, "Not Found")
            done.fulfill()
        }.resume()

        wait(for: [done], timeout: 3)
    }

    func testLogsEndpoint() throws {
        let port = try findAvailablePort()
        let server = DashboardServer(port: port)
        let store = LogStore(maxSize: 10)
        server.logStore = store
        try server.start()
        defer { server.stop() }

        let url = URL(string: "http://localhost:\(port)/api/logs")!
        let done = expectation(description: "logs")
        URLSession.shared.dataTask(with: url) { data, _, error in
            XCTAssertNil(error)
            let body = String(data: data ?? Data(), encoding: .utf8) ?? ""
            // Should contain at minimum the startup log entry
            XCTAssertTrue(body.contains("Dashboard started"))
            XCTAssertTrue(body.contains("\"level\""))
            XCTAssertTrue(body.contains("\"message\""))
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 3)
    }

    func testRestart() throws {
        let port1 = try findAvailablePort()
        let port2 = try findAvailablePort()

        let server = DashboardServer(port: port1)
        try server.start()
        XCTAssertTrue(server.isRunning)

        let done1 = expectation(description: "old port")
        let url1 = URL(string: "http://localhost:\(port1)/api/status")!
        URLSession.shared.dataTask(with: url1) { data, _, error in
            XCTAssertNil(error)
            done1.fulfill()
        }.resume()
        wait(for: [done1], timeout: 3)

        try server.restart(with: port2)
        XCTAssertEqual(server.port, port2)
        XCTAssertTrue(server.isRunning)

        let done2 = expectation(description: "new port")
        let url2 = URL(string: "http://localhost:\(port2)/api/status")!
        URLSession.shared.dataTask(with: url2) { data, _, error in
            XCTAssertNil(error)
            done2.fulfill()
        }.resume()
        wait(for: [done2], timeout: 3)

        server.stop()
        XCTAssertFalse(server.isRunning)
    }
}

private func findAvailablePort() throws -> UInt16 {
    let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { throw NSError(domain: "socket", code: 1) }
    defer { Darwin.close(fd) }

    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = 0
    addr.sin_addr.s_addr = INADDR_ANY

    let r = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    guard r >= 0 else { throw NSError(domain: "bind", code: 2) }

    var bound = sockaddr_in()
    var len = socklen_t(MemoryLayout<sockaddr_in>.size)
    let g = withUnsafeMutablePointer(to: &bound) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.getsockname(fd, $0, &len)
        }
    }
    guard g >= 0 else { throw NSError(domain: "getsockname", code: 3) }

    return CFSwapInt16BigToHost(bound.sin_port)
}
