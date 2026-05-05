# Task 4: SpeechService — Apple Speech voice recognition

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** SpeechService module that captures microphone audio via AVAudioEngine and performs one-shot speech recognition using SFSpeechRecognizer.

**Architecture:** SpeechService is a standalone class wrapping AVAudioEngine + SFSpeechRecognizer. It handles permission checks, starts/stops recording, and returns recognition results or classified errors. A simple test endpoint (`POST /api/speech/test`) lets Dashboard trigger one-shot recognition for manual verification. Full PTT lifecycle with SessionController is Task 5.

**Tech Stack:** Swift 6.3 / AVFoundation (AVAudioEngine) / Speech (SFSpeechRecognizer) / No external dependencies

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `Sources/Voxtv/SpeechService.swift` | Create | Permission checks, audio capture, speech recognition, result/error types |
| `Tests/VoxtvTests/SpeechServiceTests.swift` | Create | Unit tests for result types and permission state |
| `Sources/Voxtv/DashboardServer.swift` | Modify | Add `POST /api/speech/test` endpoint, wire SpeechService, enrich `/api/status` |
| `Sources/Voxtv/App.swift` | Modify | Create SpeechService, pass to DashboardServer |
| `Sources/Voxtv/DashboardServer.swift` | Modify | Update dashboard HTML: enable PTT button for one-shot test |

---

### Task 1: SpeechService module — types and permission checks

**Files:**
- Create: `Sources/Voxtv/SpeechService.swift`
- Create: `Tests/VoxtvTests/SpeechServiceTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/VoxtvTests/SpeechServiceTests.swift
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
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter SpeechServiceTests 2>&1
```
Expected: build error — SpeechService not found

- [ ] **Step 3: Write SpeechService implementation**

```swift
// Sources/Voxtv/SpeechService.swift
import AVFoundation
import Speech

enum SpeechError: Error {
    case permissionDenied
    case networkUnavailable
    case rateLimited
    case microphoneInUse
    case noSpeech
    case recognitionFailed

    var localizedDescription: String {
        switch self {
        case .permissionDenied:
            return "麦克风或语音识别权限未授权，请在系统设置中开启"
        case .networkUnavailable:
            return "网络不可用，语音识别需要联网"
        case .rateLimited:
            return "语音识别请求过于频繁，请稍后再试"
        case .microphoneInUse:
            return "麦克风被其他应用占用"
        case .noSpeech:
            return "未检测到语音"
        case .recognitionFailed:
            return "语音识别失败"
        }
    }
}

struct SpeechResult {
    let text: String
    let rawText: String
    let isFinal: Bool
}

final class SpeechService: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var recognitionTask: SFSpeechRecognitionTask?

    var micPermission: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    var speechPermission: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    init() {
        recognizer = SFSpeechRecognizer()  // system default locale
    }

    func requestPermissions() async -> (mic: Bool, speech: Bool) {
        let mic = await AVCaptureDevice.requestAccess(for: .audio)
        let speech = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        return (mic, speech)
    }

    // Core one-shot recognition: start audio, capture, recognize, stop, return result
    func recognize(completion: @escaping @Sendable (Result<SpeechResult, SpeechError>) -> Void) {
        guard micPermission, speechPermission else {
            completion(.failure(.permissionDenied))
            return
        }

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = false  // one-shot: only final

        guard let recognizer = recognizer, recognizer.isAvailable else {
            completion(.failure(.networkUnavailable))
            return
        }

        var rawText = ""
        var finalText = ""

        recognitionTask = recognizer.recognitionTask(with: request) { result, error in
            if let error {
                let speechErr: SpeechError = {
                    let nsErr = error as NSError
                    if nsErr.domain == "kLSRErrorDomain" {
                        switch nsErr.code {
                        case 209: return .rateLimited
                        case 203: return .noSpeech
                        default: return .recognitionFailed
                        }
                    }
                    return .recognitionFailed
                }()
                completion(.failure(speechErr))
                return
            }
            if let result = result {
                rawText = result.bestTranscription.formattedString
                finalText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
                if result.isFinal {
                    completion(.success(SpeechResult(
                        text: finalText,
                        rawText: rawText,
                        isFinal: true
                    )))
                }
            }
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            completion(.failure(.microphoneInUse))
            return
        }
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        recognitionTask?.cancel()
        recognitionTask = nil
        engine.stop()
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter SpeechServiceTests 2>&1
```
Expected: testSpeechErrorDescriptions PASS, testSpeechResultInitialState PASS, testServiceCanBeCreated PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/Voxtv/SpeechService.swift Tests/VoxtvTests/SpeechServiceTests.swift
git commit -m "Task 4a: SpeechService — types, permissions, core recognition"
```

---

### Task 2: Wire SpeechService into App and DashboardServer

**Files:**
- Modify: `Sources/Voxtv/App.swift` — create SpeechService, pass to DashboardServer
- Modify: `Sources/Voxtv/DashboardServer.swift` — add SpeechService reference, enrich status, add test endpoint

- [ ] **Step 1: Add SpeechService reference to DashboardServer**

In `Sources/Voxtv/DashboardServer.swift`, add stored property next to `appleTVBridge`:

```swift
var speechService: SpeechService?
```

- [ ] **Step 2: Enrich `/api/status` response**

Replace the `statusResponse()` method with one that includes speech and Apple TV status:

```swift
private func statusResponse() -> (Int, String, String) {
    let micOk = speechService?.micPermission ?? false
    let speechOk = speechService?.speechPermission ?? false
    let deviceConfigured = appleTVBridge?.deviceId.isEmpty == false

    let json = """
    {"state":"idle","stateSince":"\(ISO8601DateFormatter().string(from: Date()))","speech":{"microphoneAuthorized":\(micOk),"speechAuthorized":\(speechOk)},"appleTV":{"configured":\(deviceConfigured)}}
    """
    return (200, json, "application/json; charset=utf-8")
}
```

- [ ] **Step 3: Add `POST /api/speech/test` endpoint for one-shot recognition test**

Add route in the `route()` method:

```swift
if method == "POST" && path == "/api/speech/test" {
    return handleSpeechTest()
}
```

Add the handler method:

```swift
private func handleSpeechTest() -> (Int, String, String) {
    guard let svc = speechService else {
        return (500, #"{"ok":false,"error":"SpeechService not configured"}"#, "application/json; charset=utf-8")
    }
    guard svc.micPermission && svc.speechPermission else {
        return (400, #"{"ok":false,"error":"Microphone or speech permission not granted"}"#, "application/json; charset=utf-8")
    }

    svc.recognize { result in
        // Recognition runs async; result is logged for now
        switch result {
        case .success(let r):
            print("[Voxtv] Speech test: \(r.text)")
        case .failure(let e):
            print("[Voxtv] Speech test failed: \(e.localizedDescription)")
        }
    }

    return (200, #"{"ok":true,"message":"recognition started","state":"listening"}"#, "application/json; charset=utf-8")
}
```

- [ ] **Step 4: Create SpeechService and pass to DashboardServer**

In `Sources/Voxtv/App.swift`, update `init()`:

Add before `appState.bind(dashboard)`:
```swift
let speech = SpeechService()
dashboard.speechService = speech
```

- [ ] **Step 5: Build and run tests**

```bash
swift test 2>&1
```
Expected: 11 tests pass (4 DashboardServer + 4 AppleTVBridge + 3 SpeechService)

- [ ] **Step 6: Commit**

```bash
git add Sources/Voxtv/App.swift Sources/Voxtv/DashboardServer.swift
git commit -m "Task 4b: wire SpeechService into app and DashboardServer"
```

---

### Task 3: Enable PTT button in Dashboard HTML for one-shot test

**Files:**
- Modify: `Sources/Voxtv/DashboardServer.swift` — update embedded HTML: enable PTT button for one-shot speech test

- [ ] **Step 1: Update the controls section in dashboardHTML**

Find the PTT button:
```html
<button class="btn btn-talk" id="ptt-btn" disabled>按住说话（开发中）</button>
```

Replace with:
```html
<button class="btn btn-talk" id="ptt-btn">点击开始语音识别</button>
```

- [ ] **Step 2: Add button click handler to the script block**

Add after the `sendBtn.addEventListener` block (before `manualText.addEventListener`):

```javascript
const pttBtn = document.getElementById('ptt-btn');

pttBtn.addEventListener('click', () => {
  pttBtn.disabled = true;
  pttBtn.textContent = '识别中...';
  statusCard.classList.add('listening');
  fetch('/api/speech/test', { method: 'POST' })
    .then(r => r.json())
    .then(data => {
      if (data.ok) {
        pttBtn.textContent = '正在听...说完后等待结果';
      } else {
        pttBtn.textContent = '识别失败: ' + (data.error || '');
        statusCard.classList.remove('listening');
        pttBtn.disabled = false;
      }
    })
    .catch(err => {
      pttBtn.textContent = '网络错误';
      statusCard.classList.remove('listening');
      pttBtn.disabled = false;
    });
});
```

Note: The button stays disabled after recognition starts because the current architecture doesn't push results to the client. The result is logged server-side. Full push-to-talk cycle comes in Task 5 (SessionController).

- [ ] **Step 3: Build and run tests**

```bash
swift build 2>&1 && swift test 2>&1 | grep "Executed" | tail -1
```
Expected: Build passes, 11 tests pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/Voxtv/DashboardServer.swift
git commit -m "Task 4c: enable PTT button for one-shot speech recognition test"
```

---

### Task 4: End-to-end verification

- [ ] **Step 1: Run full test suite**

```bash
swift test 2>&1
```
Expected: 11 tests, 0 failures.

- [ ] **Step 2: Manual verification checklist**

```bash
swift run
```

Then verify:
- [ ] App starts, menu bar shows "守护进程运行中"
- [ ] First launch: macOS prompts for microphone permission
- [ ] First launch: macOS prompts for speech recognition permission
- [ ] Browser at `http://localhost:8765` — `/api/status` includes speech permissions
- [ ] Click PTT button → says "正在听..." → speak "三体" → server logs recognition result
- [ ] Check server terminal output for `[Voxtv] Speech test: 三体` (or close match)
- [ ] Settings window opens and keyboard input works
- [ ] Apple TV text sending still works (regression test)
- [ ] `/api/status` returns enriched JSON with speech permissions

---
