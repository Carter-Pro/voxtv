import Foundation
import AppKit

final class DashboardServer: @unchecked Sendable {
    var port: UInt16
    private let socketQueue = DispatchQueue(label: "voxtv.dashboard.socket")
    private var listenSocket: Int32 = -1
    private var source: DispatchSourceRead?

    var isRunning: Bool { source != nil }
    var appleTVBridge: AppleTVBridge?
    var speechService: SpeechService?
    var logStore: LogStore?
    var keywordSpotter: KeywordSpotterService?
    private var kwsDetections: [(Date, String)] = []
    private let kwsDetectionsMax = 50
    private let appJSON = "application/json; charset=utf-8"

    private let dashboardHTML: String = {
        guard let url = Bundle.module.url(forResource: "dashboard", withExtension: "html"),
              let html = try? String(contentsOf: url, encoding: .utf8) else {
            fatalError("dashboard.html not found in Bundle.module")
        }
        return html
    }()


    init(port: UInt16 = 8765) {
        self.port = port
    }

    func start() throws {
        listenSocket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard listenSocket >= 0 else {
            throw DashboardError.socketCreationFailed
        }

        var reuse: Int32 = 1
        Darwin.setsockopt(listenSocket, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = CFSwapInt16HostToBig(port)
        addr.sin_addr.s_addr = INADDR_ANY

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(listenSocket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult >= 0 else {
            Darwin.close(listenSocket)
            listenSocket = -1
            throw DashboardError.bindFailed
        }

        guard Darwin.listen(listenSocket, 8) >= 0 else {
            Darwin.close(listenSocket)
            listenSocket = -1
            throw DashboardError.listenFailed
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: listenSocket, queue: socketQueue)
        source.setEventHandler { [weak self] in
            self?.acceptConnection()
        }
        source.setCancelHandler { [weak self] in
            if let self, self.listenSocket >= 0 {
                Darwin.close(self.listenSocket)
                self.listenSocket = -1
            }
        }
        source.resume()
        self.source = source
        log(.info, "Dashboard started on port \(port)")
    }

    func stop() {
        source?.cancel()
        source = nil
        if listenSocket >= 0 {
            Darwin.close(listenSocket)
            listenSocket = -1
        }
    }

    func restart(with newPort: UInt16) throws {
        stop()
        port = newPort
        try start()
    }

    private func log(_ level: LogLevel, _ message: String) {
        Task { await logStore?.append(level: level, message: message) }
    }

    private func acceptConnection() {
        var addr = sockaddr()
        var len = socklen_t(MemoryLayout<sockaddr>.size)
        let client = Darwin.accept(listenSocket, &addr, &len)
        guard client >= 0 else { return }

        DispatchQueue.global(qos: .background).async {
            self.handle(client: client)
        }
    }

    private func handle(client: Int32) {
        defer { Darwin.close(client) }

        var buffer = [UInt8](repeating: 0, count: 8192)
        let bytesRead = Darwin.read(client, &buffer, buffer.count)
        guard bytesRead > 0,
              let request = String(bytes: buffer[0..<Int(bytesRead)], encoding: .utf8)
        else { return }

        // Split headers and body on first \r\n\r\n
        let headerAndBody = request.components(separatedBy: "\r\n\r\n")
        let headerSection = headerAndBody.first ?? ""
        var requestBody = headerAndBody.dropFirst().joined(separator: "\r\n\r\n")

        // Check Content-Length and read remaining body if needed
        var contentLength = 0
        for line in headerSection.components(separatedBy: "\r\n") {
            let lower = line.lowercased()
            if lower.hasPrefix("content-length:") {
                let val = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                contentLength = Int(val) ?? 0
                break
            }
        }
        while requestBody.utf8.count < contentLength {
            let n = Darwin.read(client, &buffer, buffer.count)
            guard n > 0 else { break }
            requestBody += String(bytes: buffer[0..<Int(n)], encoding: .utf8) ?? ""
        }

        let lines = headerSection.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { return }

        let requestParts = firstLine.components(separatedBy: " ")
        guard requestParts.count >= 2 else { return }

        let method = requestParts[0]
        let path = requestParts[1]

        let (status, body, contentType) = route(method: method, path: path, body: requestBody)

        let bodyData = body.data(using: .utf8) ?? Data()
        var reader = bodyData.makeIterator()

        let responseHeader = """
        HTTP/1.0 \(status)\r
        Content-Type: \(contentType)\r
        Content-Length: \(bodyData.count)\r
        Connection: close\r
        \r\n
        """

        guard let headerData = responseHeader.data(using: .utf8) else { return }
        Darwin.write(client, [UInt8](headerData), headerData.count)
        while let chunk = reader.next() {
            Darwin.write(client, [chunk], 1)
        }
    }

    private func route(method: String, path: String, body: String) -> (Int, String, String) {
        if method == "GET" && path == "/api/status" {
            return statusResponse()
        }
        if method == "GET" && (path == "/" || path == "/index.html") {
            return (200, dashboardHTML, "text/html; charset=utf-8")
        }
        if method == "POST" && path == "/api/apple-tv/send-text" {
            return handleSendText(body: body)
        }
        if method == "POST" && path == "/api/speech/start" {
            return handleSpeechStart()
        }
        if method == "POST" && path == "/api/speech/stop" {
            return handleSpeechStop()
        }
        if method == "GET" && path == "/api/logs" {
            return logResponse()
        }
        if method == "POST" && path == "/api/kws/start" {
            return handleKWSStart(body: body)
        }
        if method == "POST" && path == "/api/kws/stop" {
            return handleKWSStop()
        }
        if method == "GET" && path == "/api/kws/status" {
            return handleKWSStatus()
        }
        return (404, "Not Found", "text/plain; charset=utf-8")
    }

    private func handleSendText(body: String) -> (Int, String, String) {
        guard let bridge = appleTVBridge else {
            let json = #"{"ok":false,"error":"AppleTVBridge not configured"}"#
            return (500, json, "application/json; charset=utf-8")
        }
        guard let data = body.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = obj["text"] as? String
        else {
            let json = #"{"ok":false,"error":"invalid request body"}"#
            return (400, json, "application/json; charset=utf-8")
        }

        let cleaned = TextNormalizer.normalize(text)

        guard !cleaned.isEmpty else {
            let json = #"{"ok":false,"error":"empty after normalization"}"#
            return (400, json, "application/json; charset=utf-8")
        }

        let result = bridge.send(text: cleaned)

        if result.success {
            log(.info, "send-text: \(cleaned)")
            let resp = #"{"ok":true,"text":"\#(cleaned)","message":"sent"}"#
            return (200, resp, "application/json; charset=utf-8")
        } else {
            let err = result.stderr.isEmpty ? "send failed" : result.stderr
            log(.error, "send-text failed: \(err)")
            let json = #"{"ok":false,"error":"\#(err)"}"#
            return (500, json, "application/json; charset=utf-8")
        }
    }

    private func logResponse() -> (Int, String, String) {
        guard let store = logStore else {
            return (200, "[]", "application/json; charset=utf-8")
        }
        // Semaphore bridge: blocks a background dispatch thread to await actor.
        // Safe under Phase 1A single-user load; would need async route() for scale.
        final class Box: @unchecked Sendable {
            var entries: [LogEntry] = []
            let sema: DispatchSemaphore
            init(sema: DispatchSemaphore) { self.sema = sema }
        }
        let box = Box(sema: DispatchSemaphore(value: 0))
        Task {
            box.entries = await store.all()
            box.sema.signal()
        }
        box.sema.wait()
        return (200, box.entries.toJSON(), "application/json; charset=utf-8")
    }

    private func statusResponse() -> (Int, String, String) {
        let micOk = speechService?.micPermission ?? false
        let speechOk = speechService?.speechPermission ?? false
        let deviceConfigured = appleTVBridge?.deviceId.isEmpty == false

        let json = """
        {"state":"idle","stateSince":"\(ISO8601DateFormatter().string(from: Date()))","speech":{"microphoneAuthorized":\(micOk),"speechAuthorized":\(speechOk)},"appleTV":{"configured":\(deviceConfigured)},"kws":{"state":"\(keywordSpotter?.state.rawValue ?? "unavailable")"}}
        """
        return (200, json, "application/json; charset=utf-8")
    }

    private func handleSpeechStart() -> (Int, String, String) {
        guard let svc = speechService else {
            return (500, #"{"ok":false,"error":"SpeechService not configured"}"#, "application/json; charset=utf-8")
        }

        Task {
            // Switch to .regular so permission dialogs appear (documented best practice)
            _ = await MainActor.run {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
            }
            // Request permissions — no-op if already granted, pops system dialog if not
            let (mic, speech) = await svc.requestPermissions()
            // Restore .accessory
            _ = await MainActor.run {
                NSApp.setActivationPolicy(.accessory)
            }
            guard mic, speech else {
                print("[Voxtv] Speech: permissions denied")
                return
            }
            svc.recognize { result in
                switch result {
                case .success(let r): print("[Voxtv] Speech: \(r.text)")
                case .failure(let e): print("[Voxtv] Speech failed: \(e.localizedDescription)")
                }
            }
        }

        return (200, #"{"ok":true,"state":"listening"}"#, "application/json; charset=utf-8")
    }

    private func handleSpeechStop() -> (Int, String, String) {
        guard let svc = speechService else {
            return (500, #"{"ok":false,"error":"SpeechService not configured"}"#, "application/json; charset=utf-8")
        }
        guard let result = svc.finish() else {
            return (200, #"{"ok":false,"error":"no speech detected"}"#, "application/json; charset=utf-8")
        }
        if result.text.isEmpty {
            return (200, #"{"ok":true,"text":"","message":"no speech"}"#, "application/json; charset=utf-8")
        }
        return (200, #"{"ok":true,"text":"\#(result.text)"}"#, "application/json; charset=utf-8")
    }

    // MARK: - KWS Handlers

    func recordKWSDetection(_ keyword: String) {
        kwsDetections.append((Date(), keyword))
        if kwsDetections.count > kwsDetectionsMax {
            kwsDetections.removeFirst(kwsDetections.count - kwsDetectionsMax)
        }
    }

    private func handleKWSStart(body: String) -> (Int, String, String) {
        guard let spotter = keywordSpotter else {
            return (500, #"{"ok":false,"error":"KeywordSpotterService not configured"}"#, appJSON)
        }
        guard let data = body.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let keywordsBuf = obj["keywordsBuf"] as? String
        else {
            return (400, #"{"ok":false,"error":"invalid body — expected {keywordsBuf: token_string, threshold: 0.6}"}"#, appJSON)
        }
        let threshold = (obj["threshold"] as? Float) ?? 0.25
        let score = (obj["score"] as? Float) ?? 1.0

        do {
            try spotter.start(keywordsBuf: keywordsBuf, threshold: threshold, score: score)
            return (200, #"{"ok":true,"state":"listening"}"#, appJSON)
        } catch {
            return (500, #"{"ok":false,"error":"\#(error.localizedDescription)"}"#, appJSON)
        }
    }

    private func handleKWSStop() -> (Int, String, String) {
        keywordSpotter?.stop()
        return (200, #"{"ok":true,"state":"idle"}"#, appJSON)
    }

    private func handleKWSStatus() -> (Int, String, String) {
        guard let spotter = keywordSpotter else {
            return (200, #"{"ok":false,"state":"unavailable"}"#, appJSON)
        }
        let df = ISO8601DateFormatter()
        let detectionJSON = kwsDetections.map { d in
            "{\"time\":\"\(df.string(from: d.0))\",\"keyword\":\"\(d.1)\"}"
        }.joined(separator: ",")
        let json = """
        {"state":"\(spotter.state.rawValue)","detections":[\(detectionJSON)]}
        """
        return (200, json, appJSON)
    }
}

enum DashboardError: Error {
    case socketCreationFailed
    case bindFailed
    case listenFailed
}

