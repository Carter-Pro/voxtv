# Task 3: AppleTVBridge — atvremote text_set encapsulation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** AppleTVBridge module wrapping atvremote CLI; Dashboard manual text input sends text to Apple TV.

**Architecture:** AppleTVBridge is a standalone class using `Process` to execute `atvremote --id <id> text_set="<text>"`. DashboardServer gains POST body parsing and a `/api/apple-tv/send-text` route. AppState stores device ID with UserDefaults persistence. SettingsView Apple TV tab gets a device ID input field. Dashboard HTML enables the text input and send button.

**Tech Stack:** Swift 6.3 / Foundation (Process, Pipe, FileManager) / Darwin sockets (existing) / HTML+JS (existing dashboard)

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `Sources/Voxtv/AppleTVBridge.swift` | Create | Find atvremote, build command, execute via Process, return result |
| `Tests/VoxtvTests/AppleTVBridgeTests.swift` | Create | Unit tests for command construction + PATH lookup |
| `Sources/Voxtv/AppState.swift` | Modify | Add `appleTVDeviceId` with UserDefaults, `saveDeviceId()` |
| `Sources/Voxtv/App.swift` | Modify | Create AppleTVBridge, wire to DashboardServer |
| `Sources/Voxtv/DashboardServer.swift` | Modify | POST body parsing, `/api/apple-tv/send-text` route |
| `Sources/Voxtv/SettingsView.swift` | Modify | Apple TV tab: device ID input with save button |

---

### Task 1: AppleTVBridge module and tests

**Files:**
- Create: `Sources/Voxtv/AppleTVBridge.swift`
- Create: `Tests/VoxtvTests/AppleTVBridgeTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/VoxtvTests/AppleTVBridgeTests.swift
import XCTest
@testable import Voxtv

final class AppleTVBridgeTests: XCTestCase {

    func testBuildCommand() {
        let bridge = AppleTVBridge(deviceId: "abc123")
        let cmd = bridge.buildCommand(text: "星际穿越")
        XCTAssertEqual(cmd, ["atvremote", "--id", "abc123", "text_set=星际穿越"])
    }

    func testBuildCommandPreservesSpaces() {
        let bridge = AppleTVBridge(deviceId: "abc123")
        let cmd = bridge.buildCommand(text: "hello world")
        XCTAssertEqual(cmd[3], "text_set=hello world")
    }

    func testFindAtvremotePathDoesNotCrash() {
        let bridge = AppleTVBridge(deviceId: "test")
        let path = bridge.findAtvremotePath()
        // Returns nil if not installed, or a valid path if installed
        if let path = path {
            XCTAssertTrue(path.hasSuffix("atvremote") || path.contains("atvremote"))
        }
    }

    func testSendReturnsErrorWhenAtvremoteNotFound() {
        // Temporarily override PATH so which fails
        let bridge = AppleTVBridge(deviceId: "test")
        let result = bridge.send(text: "test")
        XCTAssertFalse(result.success)
        XCTAssertTrue(result.stderr.contains("not found") || result.stderr.contains("pipx"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AppleTVBridgeTests 2>&1`
Expected: build error — `AppleTVBridge` not found in module Voxtv

- [ ] **Step 3: Write AppleTVBridge implementation**

```swift
// Sources/Voxtv/AppleTVBridge.swift
import Foundation

struct AppleTVBridgeResult {
    let success: Bool
    let stdout: String
    let stderr: String
}

final class AppleTVBridge {
    let deviceId: String

    init(deviceId: String) {
        self.deviceId = deviceId
    }

    func buildCommand(text: String) -> [String] {
        ["atvremote", "--id", deviceId, "text_set=\(text)"]
    }

    func findAtvremotePath() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["which", "atvremote"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.isEmpty ? nil : path
    }

    func send(text: String) -> AppleTVBridgeResult {
        guard let atvPath = findAtvremotePath() else {
            return AppleTVBridgeResult(
                success: false,
                stdout: "",
                stderr: "atvremote not found in PATH. Install with: pipx install pyatv"
            )
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: atvPath)
        task.arguments = ["--id", deviceId, "text_set=\(text)"]
        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return AppleTVBridgeResult(
                success: false,
                stdout: "",
                stderr: error.localizedDescription
            )
        }

        let stdout = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(),
                            encoding: .utf8) ?? ""
        let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                            encoding: .utf8) ?? ""

        return AppleTVBridgeResult(
            success: task.terminationStatus == 0,
            stdout: stdout.trimmingCharacters(in: .whitespacesAndNewlines),
            stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter AppleTVBridgeTests 2>&1`
Expected:
```
testBuildCommand PASS
testBuildCommandPreservesSpaces PASS
testFindAtvremotePathDoesNotCrash PASS
testSendReturnsErrorWhenAtvremoteNotFound PASS
```

- [ ] **Step 5: Commit**

```bash
git add Sources/Voxtv/AppleTVBridge.swift Tests/VoxtvTests/AppleTVBridgeTests.swift
git commit -m "Task 3a: AppleTVBridge — command construction and PATH lookup"
```

---

### Task 2: Apple TV device ID in AppState and SettingsView

**Files:**
- Modify: `Sources/Voxtv/AppState.swift` — add `appleTVDeviceId` property and `saveDeviceId()` method
- Modify: `Sources/Voxtv/SettingsView.swift` — Apple TV tab with device ID TextField

- [ ] **Step 1: Add appleTVDeviceId to AppState**

In `Sources/Voxtv/AppState.swift`, add a new `@Published` property after line 11:

```swift
@Published var appleTVDeviceId: String = ""
```

In `AppState.init()`, add after the port loading (after line 21):

```swift
appleTVDeviceId = defaults.string(forKey: "appleTVDeviceId") ?? ""
```

Add a new method after `updateDashboardURL()`:

```swift
func saveDeviceId(_ id: String) {
    appleTVDeviceId = id.trimmingCharacters(in: .whitespacesAndNewlines)
    defaults.set(appleTVDeviceId, forKey: "appleTVDeviceId")
}
```

Add a method to check if device ID is configured:

```swift
var deviceConfigured: Bool {
    !appleTVDeviceId.isEmpty
}
```

- [ ] **Step 2: Update Apple TV tab in SettingsView**

In `Sources/Voxtv/SettingsView.swift`, add `@State private var deviceIdText: String = ""` next to the existing `@State private var portText: String = ""` on line 5.

Replace the Apple TV placeholder tab (the entire `VStack` for "Apple TV 配置") with:

```swift
VStack(alignment: .leading, spacing: 12) {
    Text("Apple TV 配置")
        .font(.headline)

    HStack {
        Text("Device ID:")
        TextField("例如: AABBCCDDEEFF@192.168.1.100", text: $deviceIdText)
            .frame(width: 220)
            .onAppear {
                deviceIdText = appState.appleTVDeviceId
            }
        Button("保存") {
            appState.saveDeviceId(deviceIdText)
        }
    }

    if appState.appleTVDeviceId.isEmpty {
        Text("未配置。运行 atvremote scan 获取 device ID。")
            .font(.caption)
            .foregroundColor(.orange)
    } else {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.caption)
            Text("已配置: \(appState.appleTVDeviceId)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
.padding()
```

- [ ] **Step 3: Build and verify**

```bash
swift build 2>&1
```
Expected: Build complete!

- [ ] **Step 4: Commit**

```bash
git add Sources/Voxtv/AppState.swift Sources/Voxtv/SettingsView.swift
git commit -m "Task 3b: Apple TV device ID config in AppState and Settings UI"
```

---

### Task 3: POST /api/apple-tv/send-text endpoint

**Files:**
- Modify: `Sources/Voxtv/DashboardServer.swift` — POST body parsing, new route, AppleTVBridge reference
- Modify: `Sources/Voxtv/App.swift` — create AppleTVBridge, pass to DashboardServer

- [ ] **Step 1: Add AppleTVBridge property and POST body parsing to DashboardServer**

Add new property after `var isRunning: Bool { source != nil }` on line 9:

```swift
var appleTVBridge: AppleTVBridge?
```

Replace the entire `handle(client:)` method (lines 86-122). The change adds body extraction from POST requests:

```swift
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
        let requestBody = headerAndBody.dropFirst().joined(separator: "\r\n\r\n")

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
```

- [ ] **Step 2: Update route signature and add send-text handler**

Replace the `route` method (lines 124-132) with version that accepts body:

```swift
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
        return (404, "Not Found", "text/plain; charset=utf-8")
    }
```

Add the `handleSendText` method after `route`:

```swift
    private func handleSendText(body: String) -> (Int, String, String) {
        guard let bridge = appleTVBridge else {
            let json = #"{"ok":false,"error":"AppleTVBridge not configured"}"#
            return (500, json, "application/json; charset=utf-8")
        }
        guard let data = body.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = obj["text"] as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            let json = #"{"ok":false,"error":"invalid request body"}"#
            return (400, json, "application/json; charset=utf-8")
        }

        let result = bridge.send(text: text.trimmingCharacters(in: .whitespacesAndNewlines))

        if result.success {
            let resp = #"{"ok":true,"text":"\#(text)","message":"sent"}"#
            return (200, resp, "application/json; charset=utf-8")
        } else {
            let err = result.stderr.isEmpty ? "send failed" : result.stderr
            let json = #"{"ok":false,"error":"\#(err)"}"#
            return (500, json, "application/json; charset=utf-8")
        }
    }
```

- [ ] **Step 3: Wire AppleTVBridge in App.swift**

In `Sources/Voxtv/App.swift`, update `init()`:

```swift
init() {
    let appState = AppState.shared
    do {
        try dashboard.start()
        appState.serverRunning = true
        appState.daemonRunning = true
        print("[Voxtv] Dashboard started on port \(dashboard.port)")
    } catch {
        print("[Voxtv] Dashboard failed: \(error)")
    }
    dashboard.appleTVBridge = AppleTVBridge(deviceId: appState.appleTVDeviceId)
    appState.bind(dashboard)
}
```

- [ ] **Step 4: Build and run all tests**

```bash
swift test 2>&1
```
Expected: All 4 DashboardServer tests + 4 AppleTVBridge tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Voxtv/DashboardServer.swift Sources/Voxtv/App.swift
git commit -m "Task 3c: POST /api/apple-tv/send-text with AppleTVBridge integration"
```

---

### Task 4: Enable manual text input in Dashboard HTML

**Files:**
- Modify: `Sources/Voxtv/DashboardServer.swift` — update embedded `dashboardHTML` string

- [ ] **Step 1: Enable controls and add send logic**

In the `dashboardHTML` string constant, locate the `<div class="controls">` block (around line 200) and the `<script>` block (around line 212).

Replace the controls div:

Old:
```html
  <div class="controls">
    <button class="btn btn-talk" id="ptt-btn" disabled>按住说话（开发中）</button>
    <div class="text-input-row">
      <input type="text" id="manual-text" placeholder="手动输入文本..." disabled>
      <button id="send-btn" disabled>发送</button>
    </div>
  </div>
```

New:
```html
  <div class="controls">
    <button class="btn btn-talk" id="ptt-btn" disabled>按住说话（开发中）</button>
    <div class="text-input-row">
      <input type="text" id="manual-text" placeholder="输入文本并发送到 Apple TV...">
      <button id="send-btn">发送</button>
    </div>
    <div id="send-status" style="margin-top:8px;font-size:13px;min-height:20px;"></div>
  </div>
```

Replace the entire `<script>` block:

Old:
```html
<script>
const stateLabel = document.getElementById('state-label');
const statusCard = document.getElementById('status-card');
const logList = document.getElementById('log-list');
function updateStatus() {
  fetch('/api/status')
    .then(r => r.json())
    .then(data => {
      stateLabel.textContent = data.state;
      statusCard.className = 'card';
      if (data.state === 'listening' || data.state === 'finalizing') {
        statusCard.classList.add('listening');
      }
    })
    .catch(() => {
      stateLabel.textContent = 'offline';
    });
}
updateStatus();
setInterval(updateStatus, 2000);
</script>
```

New:
```html
<script>
const stateLabel = document.getElementById('state-label');
const statusCard = document.getElementById('status-card');
const sendBtn = document.getElementById('send-btn');
const manualText = document.getElementById('manual-text');
const sendStatus = document.getElementById('send-status');

function updateStatus() {
  fetch('/api/status')
    .then(r => r.json())
    .then(data => {
      stateLabel.textContent = data.state;
      statusCard.className = 'card';
      if (data.state === 'listening' || data.state === 'finalizing') {
        statusCard.classList.add('listening');
      }
    })
    .catch(() => { stateLabel.textContent = 'offline'; });
}

sendBtn.addEventListener('click', () => {
  const text = manualText.value.trim();
  if (!text) return;
  sendBtn.disabled = true;
  sendBtn.textContent = '发送中...';
  sendStatus.textContent = '';
  fetch('/api/apple-tv/send-text', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ text: text })
  })
    .then(r => r.json())
    .then(data => {
      if (data.ok) {
        sendStatus.innerHTML = '<span style="color:#4caf84">已发送: ' + text + '</span>';
        manualText.value = '';
      } else {
        sendStatus.innerHTML = '<span style="color:#e94560">发送失败: ' + (data.error || 'unknown') + '</span>';
      }
    })
    .catch(err => {
      sendStatus.innerHTML = '<span style="color:#e94560">网络错误</span>';
    })
    .finally(() => {
      sendBtn.disabled = false;
      sendBtn.textContent = '发送';
    });
});

manualText.addEventListener('keydown', (e) => {
  if (e.key === 'Enter') sendBtn.click();
});

updateStatus();
setInterval(updateStatus, 2000);
</script>
```

- [ ] **Step 2: Build and verify**

```bash
swift build 2>&1
```
Expected: Build complete!

- [ ] **Step 3: Run full test suite**

```bash
swift test 2>&1
```
Expected: All 8 tests pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/Voxtv/DashboardServer.swift
git commit -m "Task 3d: enable manual text input and send in Dashboard HTML"
```

---

### Task 5: End-to-end verification

- [ ] **Step 1: Run full test suite one final time**

```bash
swift test 2>&1
```
Expected: 8 tests, 0 failures.

- [ ] **Step 2: Manual verification checklist**

```bash
swift run
```

Then verify:
- [ ] Menu bar shows "守护进程运行中" with green circle
- [ ] Browser at `http://localhost:8765` shows Dashboard
- [ ] Type "星际穿越" in text input, click "发送" or press Enter
- [ ] Without atvremote installed: Dashboard shows "发送失败: atvremote not found in PATH"
- [ ] With atvremote and device ID: text appears on Apple TV
- [ ] Settings window → Apple TV tab → save device ID persists across restart
- [ ] `curl -X POST http://localhost:8765/api/apple-tv/send-text -H 'Content-Type: application/json' -d '{"text":"test"}'` returns JSON

---
