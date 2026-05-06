# TextNormalizer + LogStore Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add text cleaning before sending to Apple TV, and an in-memory logging system visible in Dashboard.

**Architecture:** TextNormalizer is a pure function (no deps). LogStore is a thread-safe ring buffer actor. Both are wired into DashboardServer — TextNormalizer in handleSendText, LogStore for key events + GET /api/logs endpoint.

**Tech Stack:** Swift 6 (actor for LogStore), no external deps

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `Sources/Voxtv/TextNormalizer.swift` | Create | Pure function: clean recognized text |
| `Tests/VoxtvTests/TextNormalizerTests.swift` | Create | Unit tests for normalization rules |
| `Sources/Voxtv/LogStore.swift` | Create | Actor: in-memory ring buffer log storage |
| `Tests/VoxtvTests/LogStoreTests.swift` | Create | Unit tests for log storage |
| `Sources/Voxtv/DashboardServer.swift` | Modify | Wire TextNormalizer into send-text, add GET /api/logs, log key events |
| `Sources/Voxtv/App.swift` | Modify | Create LogStore, inject into DashboardServer |
| `Tests/VoxtvTests/DashboardServerTests.swift` | Modify | Add test for GET /api/logs |

---

### Task 1: TextNormalizer

**Files:**
- Create: `Sources/Voxtv/TextNormalizer.swift`
- Create: `Tests/VoxtvTests/TextNormalizerTests.swift`

- [ ] **Step 1: Write tests**

```swift
import Testing
@testable import Voxtv

struct TextNormalizerTests {
    @Test func trimsWhitespace() {
        #expect(TextNormalizer.normalize("  星际穿越  ") == "星际穿越")
    }

    @Test func removesTrailingPunctuation() {
        #expect(TextNormalizer.normalize("星际穿越。") == "星际穿越")
        #expect(TextNormalizer.normalize("Rick and Morty.") == "Rick and Morty")
        #expect(TextNormalizer.normalize("速度与激情7！") == "速度与激情7")
    }

    @Test func preservesLeadingNonPunctuation() {
        #expect(TextNormalizer.normalize("星际穿越") == "星际穿越")
    }

    @Test func compressesConsecutiveSpaces() {
        #expect(TextNormalizer.normalize("星际  穿越") == "星际 穿越")
        #expect(TextNormalizer.normalize("  星际   穿越  ") == "星际 穿越")
    }

    @Test func emptyAndWhitespaceOnly() {
        #expect(TextNormalizer.normalize("") == "")
        #expect(TextNormalizer.normalize("   ") == "")
        #expect(TextNormalizer.normalize("。") == "")
    }

    @Test func mixedContent() {
        #expect(TextNormalizer.normalize("  速度与激情 7。") == "速度与激情 7")
        #expect(TextNormalizer.normalize("Rick and Morty...") == "Rick and Morty")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter TextNormalizerTests 2>&1
```

Expected: compilation error, type not found.

- [ ] **Step 3: Implement TextNormalizer**

```swift
import Foundation

enum TextNormalizer {
    /// Clean recognized speech text for Apple TV input.
    /// - Trims leading/trailing whitespace
    /// - Removes trailing punctuation (。，！？,.!?…)
    /// - Compresses consecutive spaces
    /// - Returns empty string if nothing left after cleaning
    static func normalize(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let trailingPunctuation = CharacterSet(charactersIn: "。，！？,.!?…")
        while let last = result.unicodeScalars.last, trailingPunctuation.contains(last) {
            result.removeLast()
            result = result.trimmingCharacters(in: .whitespaces) // trim space before next punct
        }
        // Compress consecutive spaces
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter TextNormalizerTests 2>&1
```

Expected: 6 tests pass.

- [ ] **Step 5: Wire TextNormalizer into DashboardServer.handleSendText**

In `Sources/Voxtv/DashboardServer.swift`, change the send text handler to use TextNormalizer:

```swift
// Before (line ~181):
let result = bridge.send(text: text.trimmingCharacters(in: .whitespacesAndNewlines))

// After:
let cleaned = TextNormalizer.normalize(text)
guard !cleaned.isEmpty else {
    let json = #"{"ok":false,"error":"empty after normalization"}"#
    return (400, json, "application/json; charset=utf-8")
}
let result = bridge.send(text: cleaned)
```

Also update the response text to use `cleaned`:
```swift
// Before:
let resp = #"{"ok":true,"text":"\#(text)","message":"sent"}"#

// After:
let resp = #"{"ok":true,"text":"\#(cleaned)","message":"sent"}"#
```

- [ ] **Step 6: Run all tests**

```bash
swift test 2>&1 | grep -E "Executed|failures"
```

Expected: 21 tests, 0 failures.

- [ ] **Step 7: Commit**

```bash
git add Sources/Voxtv/TextNormalizer.swift Tests/VoxtvTests/TextNormalizerTests.swift Sources/Voxtv/DashboardServer.swift
git commit -m "feat: TextNormalizer — clean recognized text before sending"
```

---

### Task 2: LogStore

**Files:**
- Create: `Sources/Voxtv/LogStore.swift`
- Create: `Tests/VoxtvTests/LogStoreTests.swift`
- Modify: `Sources/Voxtv/DashboardServer.swift`
- Modify: `Sources/Voxtv/App.swift`
- Modify: `Tests/VoxtvTests/DashboardServerTests.swift`

- [ ] **Step 1: Write tests**

```swift
import Testing
@testable import Voxtv

struct LogStoreTests {
    @Test func appendAndRetrieve() async {
        let store = LogStore(maxSize: 10)
        await store.append(level: .info, message: "hello")
        await store.append(level: .error, message: "world")
        let entries = await store.all()
        #expect(entries.count == 2)
        #expect(entries[0].message == "hello")
        #expect(entries[0].level == .info)
        #expect(entries[1].message == "world")
        #expect(entries[1].level == .error)
    }

    @Test func maxSizeEnforced() async {
        let store = LogStore(maxSize: 3)
        for i in 0..<5 {
            await store.append(level: .info, message: "msg\(i)")
        }
        let entries = await store.all()
        #expect(entries.count == 3)
        #expect(entries[0].message == "msg2")
        #expect(entries[2].message == "msg4")
    }

    @Test func entriesHaveTimestamp() async {
        let store = LogStore(maxSize: 5)
        let before = Date()
        await store.append(level: .info, message: "test")
        let after = Date()
        let entries = await store.all()
        #expect(entries.count == 1)
        #expect(entries[0].timestamp >= before)
        #expect(entries[0].timestamp <= after)
    }

    @Test func jsonEncoding() async throws {
        let store = LogStore(maxSize: 5)
        await store.append(level: .info, message: "test")
        let entries = await store.all()
        let json = entries.toJSON()
        #expect(json.contains("\"level\""))
        #expect(json.contains("\"message\""))
        #expect(json.contains("test"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter LogStoreTests 2>&1
```

Expected: compilation error.

- [ ] **Step 3: Implement LogStore**

```swift
import Foundation

enum LogLevel: String, Codable, Sendable {
    case info = "info"
    case warn = "warn"
    case error = "error"
}

struct LogEntry: Codable, Sendable {
    let timestamp: Date
    let level: LogLevel
    let message: String
}

actor LogStore {
    private var entries: [LogEntry]
    private let maxSize: Int

    init(maxSize: Int = 200) {
        self.maxSize = maxSize
        self.entries = []
    }

    func append(level: LogLevel, message: String) {
        let entry = LogEntry(timestamp: Date(), level: level, message: message)
        entries.append(entry)
        if entries.count > maxSize {
            entries.removeFirst(entries.count - maxSize)
        }
    }

    func all() -> [LogEntry] {
        entries
    }
}

extension Array where Element == LogEntry {
    func toJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter LogStoreTests 2>&1
```

Expected: 4 tests pass.

- [ ] **Step 5: Wire LogStore into DashboardServer**

Add property and inject:

```swift
// DashboardServer — add property:
var logStore: LogStore?

// Add helper:
private func log(_ level: LogLevel, _ message: String) {
    Task { await logStore?.append(level: level, message: message) }
}
```

Add `GET /api/logs` route in `route()`:

```swift
if method == "GET" && path == "/api/logs" {
    return logResponse()
}
```

Implement:

```swift
private func logResponse() -> (Int, String, String) {
    guard let store = logStore else {
        return (200, "[]", "application/json; charset=utf-8")
    }
    let json: String
    let semaphore = DispatchSemaphore(value: 0)
    var entries: [LogEntry] = []
    Task {
        entries = await store.all()
        semaphore.signal()
    }
    semaphore.wait()
    json = entries.toJSON()
    return (200, json, "application/json; charset=utf-8")
}
```

Add log calls at key points:

```swift
// In handleSendText:
log(.info, "send-text: \(cleaned)")
// On error:
log(.error, "send-text failed: \(err)")

// In start():
log(.info, "Dashboard started on port \(port)")

// In handleSpeechStart:
log(.info, "speech start requested")

// In handleSpeechStop:
log(.info, "speech stop: \(result?.text ?? "nil")")
```

- [ ] **Step 6: Wire LogStore in App.swift**

```swift
// In App.init(), after creating dashboard:
let logStore = LogStore(maxSize: 200)
dashboard.logStore = logStore
```

- [ ] **Step 7: Add GET /api/logs test in DashboardServerTests**

```swift
@Test func testLogsEndpoint() throws {
    let server = DashboardServer(port: 18766)
    let store = LogStore(maxSize: 5)
    server.logStore = store
    try server.start()

    let url = URL(string: "http://localhost:18766/api/logs")!
    let (data, _) = try await URLSession.shared.data(from: url)
    let body = String(data: data, encoding: .utf8)!
    #expect(body == "[]")

    // Append some logs and verify they appear
    await store.append(level: .info, message: "test log")
    let (data2, _) = try await URLSession.shared.data(from: url)
    let body2 = String(data: data2, encoding: .utf8)!
    #expect(body2.contains("test log"))
}
```

Wait, the existing tests use random ports and `findAvailablePort()`. Let me use the same pattern. Actually, looking at the existing DashboardServerTests:

The tests use `URLSession` with `async/await` and `findAvailablePort()`. Let me model the new test after the existing ones.

```swift
@Test func testLogsEndpoint() throws {
    let port = try findAvailablePort()
    let server = DashboardServer(port: port)
    let store = LogStore(maxSize: 10)
    server.logStore = store
    try server.start()
    defer { server.stop() }

    let url = URL(string: "http://localhost:\(port)/api/logs")!
    let (data, _) = try await URLSession.shared.data(from: url)
    let body = String(data: data, encoding: .utf8)!
    #expect(body == "[]")
}
```

Wait, but `LogStore` is an actor. If I append from the test (sync context), I need to use `await`. And if the test function is `async`, `defer` doesn't work well with async. Let me just not use defer — I'll stop the server at the end.

Also wait, I need to verify the log entries appear. But the logResponse uses a semaphore-based approach that's a bit tricky. Let me just test that the endpoint returns valid JSON (even if empty).

Actually, for simplicity, let me test:
1. Empty logs endpoint returns `[]`
2. After appending, the endpoint returns the entries

But the semaphore approach in logResponse means it works synchronously. From the test, I call `await store.append(...)`, then the next request should see the entries.

Let me write it more carefully:

```swift
@Test func testLogsEndpoint() async throws {
    let port = try findAvailablePort()
    let server = DashboardServer(port: port)
    let store = LogStore(maxSize: 10)
    server.logStore = store
    try server.start()
    defer { server.stop() }

    let url = URL(string: "http://localhost:\(port)/api/logs")!
    let (data, _) = try await URLSession.shared.data(from: url)
    let body = String(data: data, encoding: .utf8)!
    #expect(body == "[]")

    await store.append(level: .info, message: "hello")
    let (data2, _) = try await URLSession.shared.data(from: url)
    let body2 = String(data: data2, encoding: .utf8)!
    #expect(body2.contains("hello"))
}
```

Hmm, `defer` with `async throws` functions — actually this should be fine in Swift. `defer` runs when the scope exits, even for async functions.

But wait, `findAvailablePort()` might not be accessible from the test — let me check the existing test file to see how they find ports.

Let me look at the existing test code more carefully.

Actually, I already read the file. Let me just plan the test and adjust during implementation if needed.

- [ ] **Step 8: Add log display in Dashboard HTML**

Add a log section in the Dashboard HTML. The JS will poll `/api/logs` and display entries.

Minimal change to the existing `updateStatus()` function or add a new `updateLogs()` function:

```javascript
async function updateLogs() {
  try {
    const r = await fetch('/api/logs');
    const entries = await r.json();
    const logList = document.getElementById('log-list');
    if (entries.length === 0) {
      logList.innerHTML = '<div class="log-entry">暂无日志</div>';
    } else {
      logList.innerHTML = entries.slice(-20).reverse()
        .map(e => `<div class="log-entry">[${new Date(e.timestamp).toLocaleTimeString()}] ${e.level.toUpperCase()} ${e.message}</div>`)
        .join('');
    }
  } catch(e) {
    document.getElementById('log-list').textContent = '日志加载失败';
  }
}

// Add to the setInterval:
setInterval(() => { updateStatus(); updateLogs(); }, 2000);
```

- [ ] **Step 9: Run all tests**

```bash
swift test 2>&1 | grep -E "Executed|failures"
```

Expected: 25 tests, 0 failures.

- [ ] **Step 10: Build and verify**

```bash
swift build 2>&1
```

Expected: build passes.

- [ ] **Step 11: Commit**

```bash
git add Sources/Voxtv/LogStore.swift Tests/VoxtvTests/LogStoreTests.swift Sources/Voxtv/DashboardServer.swift Sources/Voxtv/App.swift Tests/VoxtvTests/DashboardServerTests.swift
git commit -m "feat: LogStore — in-memory ring buffer with Dashboard log viewer"
```

---

### Task 3: Verification

- [ ] **Step 1: Run full test suite**

```bash
swift test 2>&1
```

Expected: 25 tests, 0 failures.

- [ ] **Step 2: Manual verification**

```bash
swift run
```

1. Open `http://localhost:8765`
2. Check log section shows entries including "Dashboard started on port 8765"
3. Send text via manual input → check log shows "send-text: ..."
4. Use speech recognition → check log shows result
5. Verify text is cleaned: send "  星际穿越。  " → Apple TV receives "星际穿越"

---

### Summary

| Task | New Files | Modified Files | New Tests |
|------|-----------|---------------|-----------|
| Task 1: TextNormalizer | `TextNormalizer.swift`, `TextNormalizerTests.swift` | `DashboardServer.swift` | 6 |
| Task 2: LogStore | `LogStore.swift`, `LogStoreTests.swift` | `DashboardServer.swift`, `App.swift`, `DashboardServerTests.swift` | 5 |

Total: 2 new source files, 2 new test files, 3 modified files, 11 new tests (25 total).
