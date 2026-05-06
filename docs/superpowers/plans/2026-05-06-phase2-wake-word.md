# Phase 2: Porcupine Wake Word Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** User says a wake word ("Hey Voxtv") → Mac mini plays a prompt sound → user speaks search term → recognized text auto-sent to Apple TV. No button click needed.

**Architecture:** WakeWordService owns an AVAudioEngine that runs continuously. Audio frames feed Porcupine for wake word detection. On detection, the same audio stream feeds SFSpeechRecognizer for one-shot recognition. Result goes through TextNormalizer → AppleTVBridge.

**Tech Stack:** Porcupine SPM (v3.x), AVAudioEngine, SFSpeechRecognizer

---

## ⚠️ Pre-req: Porcupine AccessKey

Picovoice requires a free AccessKey. Get one at https://console.picovoice.ai/. No credit card needed for personal use.

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `Sources/Voxtv/WakeWordService.swift` | Create | Owns AVAudioEngine, runs Porcupine, coordinates wake→recognize→send pipeline |
| `Tests/VoxtvTests/WakeWordServiceTests.swift` | Create | Unit tests for state machine, Porcupine integration |
| `Package.swift` | Modify | Add Porcupine SPM dependency |
| `Sources/Voxtv/SpeechService.swift` | Modify | Add method to share engine for wake word flow |
| `Sources/Voxtv/App.swift` | Modify | Start WakeWordService on launch, inject dependencies |
| `Sources/Voxtv/DashboardServer.swift` | Modify | Add wake word status to /api/status, log events |

---

### Task 0: Porcupine macOS Verification

- [ ] **Step 1: Add Porcupine SPM dependency**

Check if Porcupine SPM supports macOS. Add to Package.swift:

```swift
// In Package.swift dependencies:
.package(url: "https://github.com/Picovoice/porcupine.git", from: "3.0.0"),

// In Voxtv target dependencies:
.product(name: "Porcupine", package: "porcupine"),
```

- [ ] **Step 2: Build test — verify macOS compilation**

```bash
swift build 2>&1
```

If Porcupine SPM doesn't support macOS → fall back to C library integration via systemLibrary target.

- [ ] **Step 3: Verify built-in keywords available**

```swift
// Test which built-in keywords are available
print(Porcupine.BuiltInKeyword.allCases)
```

Pick one for testing (e.g., "porcupine" or "picovoice").

---

### Task 1: WakeWordService — audio pipeline

**Files:**
- Create: `Sources/Voxtv/WakeWordService.swift`
- Create: `Tests/VoxtvTests/WakeWordServiceTests.swift`
- Modify: `Package.swift`

- [ ] **Step 1:** Implement WakeWordService core

```swift
import AVFoundation
import Porcupine

enum WakeWordState {
    case stopped
    case listening        // waiting for wake word
    case recognizing      // wake word detected, recognizing speech
}

final class WakeWordService: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var porcupineManager: PorcupineManager?
    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var latestText: String?

    var onWakeWordDetected: (@Sendable () -> Void)?
    var onRecognitionComplete: (@Sendable (String) -> Void)?
    var onStateChange: (@Sendable (WakeWordState) -> Void)?

    private let accessKey: String
    private var state: WakeWordState = .stopped
    private let log: (LogLevel, String) -> Void

    init(accessKey: String, log: @escaping (LogLevel, String) -> Void) {
        self.accessKey = accessKey
        self.log = log
        self.recognizer = SFSpeechRecognizer()
    }

    func start() throws {
        // 1. Validate permissions
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
              SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw WakeWordError.permissionDenied
        }

        // 2. Create PorcupineManager with built-in keyword
        porcupineManager = try PorcupineManager(
            accessKey: accessKey,
            keywords: [.porcupine],
            onDetection: { [weak self] keywordIndex in
                self?.handleWakeWord()
            }
        )

        // 3. Start audio engine
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 512, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            // Feed Porcupine
            let frame = try? porcupineManager!.process(buffer)
            // If in recognition mode, also feed speech recognizer
            if self.state == .recognizing {
                self.recognitionRequest?.append(buffer)
            }
        }

        try porcupineManager?.start()
        engine.prepare()
        try engine.start()
        setState(.listening)
        log(.info, "WakeWordService started — listening for wake word")
    }
}
```

- [ ] **Step 2:** Implement wake word → recognize → send flow

```swift
private func handleWakeWord() {
    guard state == .listening else { return }
    log(.info, "Wake word detected — starting recognition")
    setState(.recognizing)
    onWakeWordDetected?()

    // Play prompt sound
    NSSound(named: .tink)?.play()

    // Start speech recognition on the running audio stream
    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = false
    self.recognitionRequest = request
    self.latestText = nil

    recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
        guard let self else { return }
        if let error {
            self.log(.error, "Wake word recognition failed: \(error.localizedDescription)")
            self.setRecognitionIdle()
            return
        }
        if let result = result, result.isFinal {
            let text = result.bestTranscription.formattedString
                .trimmingCharacters(in: .whitespacesAndNewlines)
            self.latestText = text
            self.log(.info, "Wake word recognition result: \(text)")
            self.onRecognitionComplete?(text)
            self.setRecognitionIdle()
        }
    }

    // Auto-stop recognition after 8 seconds of no final result
    DispatchQueue.global().asyncAfter(deadline: .now() + 8) { [weak self] in
        if self?.state == .recognizing {
            self?.recognitionRequest?.endAudio()
            self?.log(.warn, "Wake word recognition timed out")
            self?.setRecognitionIdle()
        }
    }
}

private func setRecognitionIdle() {
    recognitionTask?.cancel()
    recognitionTask = nil
    recognitionRequest?.endAudio()
    recognitionRequest = nil
    setState(.listening)
}

private func setState(_ newState: WakeWordState) {
    state = newState
    onStateChange?(newState)
}

func stop() {
    engine.stop()
    engine.inputNode.removeTap(onBus: 0)
    porcupineManager?.stop()
    porcupineManager?.delete()
    porcupineManager = nil
    recognitionTask?.cancel()
    setState(.stopped)
    log(.info, "WakeWordService stopped")
}

enum WakeWordError: Error {
    case permissionDenied
    case porcupineInitFailed
}
```

- [ ] **Step 3:** Write tests

```swift
// WakeWordServiceTests.swift — test what can be tested without real audio hardware

func testStateMachineInitialState() {
    // service starts in .stopped
}

func testPermissionsCheckFailsWithoutAuthorization() {
    // if Mic/Speech permissions not granted, start() throws .permissionDenied
}

func testStopFromListeningState() {
    // stop() transitions to .stopped and cleans up
}

func testSetStateCallback() {
    // onStateChange fires with correct states
}
```

Note: Porcupine integration tests require real microphone. Most tests will focus on state machine, permission checks, and error paths.

- [ ] **Step 4:** Build and run tests

```bash
swift build 2>&1 && swift test 2>&1 | grep -E "Executed|failures"
```

- [ ] **Step 5:** Commit

```bash
git add Package.swift Sources/Voxtv/WakeWordService.swift Tests/VoxtvTests/WakeWordServiceTests.swift
git commit -m "feat: WakeWordService — Porcupine wake word detection pipeline"
```

---

### Task 2: Wire into App + Dashboard

**Files:**
- Modify: `Sources/Voxtv/App.swift`
- Modify: `Sources/Voxtv/DashboardServer.swift`

- [ ] **Step 1: Wire in App.swift**

```swift
// In App.init(), after existing setup:
let wakeWord = WakeWordService(
    accessKey: "<ACCESS_KEY>",  // from config/environment
    log: { level, msg in
        Task { await logStore.append(level: level, message: msg) }
    }
)
wakeWord.onRecognitionComplete = { text in
    let cleaned = TextNormalizer.normalize(text)
    guard !cleaned.isEmpty else { return }
    // Send to Apple TV
    let result = bridge.send(text: cleaned)
    Task {
        if result.success {
            await logStore.append(level: .info, message: "wake-word sent to Apple TV: \(cleaned)")
        } else {
            await logStore.append(level: .error, message: "wake-word send failed: \(result.stderr)")
        }
    }
}

// Start wake word service
Task {
    do {
        try wakeWord.start()
    } catch {
        await logStore.append(level: .error, message: "WakeWordService failed: \(error.localizedDescription)")
    }
}
```

- [ ] **Step 2: Add wake word status to /api/status**

```swift
// In statusResponse(), add wake word state:
"wakeWord": {"state":"\(wakeWordState)"}
```

- [ ] **Step 3: Add wake word indicator to Dashboard HTML**

Add a status line showing wake word service state.

- [ ] **Step 4: Build and run tests**

```bash
swift build 2>&1 && swift test 2>&1 | grep -E "Executed|failures"
```

- [ ] **Step 5: Commit**

```bash
git add Sources/Voxtv/App.swift Sources/Voxtv/DashboardServer.swift
git commit -m "feat: wire WakeWordService into App and Dashboard"
```

---

### Task 3: Manual integration test

- [ ] **Step 1: Run the app**

```bash
swift run
```

- [ ] **Step 2: Test wake word flow**

| 操作 | 预期 |
|------|------|
| App 启动 | 菜单栏图标常亮，日志显示"WakeWordService started" |
| 说唤醒词 | 播放提示音，日志记录"Wake word detected" |
| 说"三体" | 识别完成，文本清洗后发到 Apple TV |
| 不说话（8 秒超时） | 回到 listening 状态 |
| Apple TV 收到"三体" | `atvremote text_set` 成功 |

- [ ] **Step 3: Verify continuous operation**

Talk 2m from Mac mini with TV background noise. Check:
- Wake word detection rate
- Recognition accuracy
- No crashes

- [ ] **Step 4: Commit any fixes**

```bash
git add -u
git commit -m "fix: wake word integration tweaks from manual testing"
```

---

### Verification

- `swift build` — passes
- `swift test` — all tests pass
- Manual: speak wake word + search term → Apple TV receives text
- Manual: verify Dashboard shows wake word status and logs

---

### What We're NOT Doing
- Custom wake word training (use built-in "porcupine" for prototype)
- Multiple wake words
- Wake word sensitivity tuning UI
- Cloud wake word verification
- Automatic app launching on Apple TV
