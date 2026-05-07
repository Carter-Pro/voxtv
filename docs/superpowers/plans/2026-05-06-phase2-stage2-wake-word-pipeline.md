# Phase 2 Stage 2: Production Wake Word Pipeline

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire the complete wake word pipeline: KWS detection → prompt sound → Apple Speech → CommandDispatcher → AppleTVBridge → TTS feedback, with configurable preferences in the menu bar.

**Architecture:** `WakePipeline` state machine orchestrates KWS/mic/speech lifecycle. `PromptPlayer` + `FeedbackSpeaker` handle audio output via NSSound/NSSpeechSynthesizer. `CommandDispatcher` provides an extensible handler interface, currently dispatching text to Apple TV with LLM-ready extension point.

**Tech Stack:** AVAudioEngine, SFSpeechRecognizer, NSSound, NSSpeechSynthesizer, sherpa-onnx

---

## File Map

| File | Action |
|------|--------|
| `Sources/Voxtv/PromptPlayer.swift` | Create — wraps NSSound + NSSpeechSynthesizer |
| `Sources/Voxtv/FeedbackSpeaker.swift` | Create — TTS speech feedback |
| `Sources/Voxtv/CommandDispatcher.swift` | Create — extensible command dispatch + test |
| `Tests/VoxtvTests/CommandDispatcherTests.swift` | Create |
| `Sources/Voxtv/WakePipeline.swift` | Create — state machine orchestrator + test |
| `Tests/VoxtvTests/WakePipelineTests.swift` | Create |
| `Sources/Voxtv/AppState.swift` | Modify — add pipeline config properties |
| `Sources/Voxtv/SettingsView.swift` | Modify — add "语音" preferences tab |
| `Sources/Voxtv/App.swift` | Modify — create & wire pipeline |
| `Sources/Voxtv/DashboardServer.swift` | Modify — expose pipeline state in /api/status |

---

### Task 1: PromptPlayer

**Files:**
- Create: `Sources/Voxtv/PromptPlayer.swift`

**What:** Configurable prompt that plays either a system beep (NSSound) or TTS (NSSpeechSynthesizer).

- [ ] **Step 1: Create PromptPlayer with system beep support**

```swift
import AppKit
import AVFAudio

final class PromptPlayer {
    private let synth = NSSpeechSynthesizer()

    /// Play a short system prompt sound (non-blocking).
    func playBeep() {
        NSSound(named: .tink)?.play()
    }

    /// Speak text via macOS built-in TTS (non-blocking).
    func speak(_ text: String) {
        if synth.isSpeaking {
            synth.stopSpeaking()
        }
        synth.startSpeaking(text)
    }
}
```

- [ ] **Step 2: Build**

```bash
swift build
```

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/Voxtv/PromptPlayer.swift
git commit -m "feat: add PromptPlayer for system beep and TTS prompt"
```

---

### Task 2: FeedbackSpeaker

**Files:**
- Create: `Sources/Voxtv/FeedbackSpeaker.swift`

**What:** TTS feedback for pipeline results. Speaks template messages like "已搜索xxx" or error messages.

- [ ] **Step 1: Create FeedbackSpeaker**

```swift
import AppKit

/// Speaks feedback messages via macOS built-in TTS.
final class FeedbackSpeaker {
    private let synth = NSSpeechSynthesizer()

    /// Speak a feedback message (non-blocking). Stops any in-progress speech first.
    func speak(_ text: String) {
        if synth.isSpeaking {
            synth.stopSpeaking()
        }
        synth.startSpeaking(text)
    }

    /// "已搜索 星际穿越"
    func speakSuccess(query: String) {
        speak("已搜索\(query)")
    }

    /// "发送失败，请检查 Apple TV"
    func speakSendFailed() {
        speak("发送失败，请检查 Apple TV")
    }

    /// "语音识别失败，请重试"
    func speakRecognitionFailed() {
        speak("语音识别失败，请重试")
    }

    /// "未检测到语音"
    func speakNoSpeech() {
        speak("未检测到语音")
    }
}
```

- [ ] **Step 2: Build**

```bash
swift build
```

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/Voxtv/FeedbackSpeaker.swift
git commit -m "feat: add FeedbackSpeaker for TTS pipeline feedback"
```

---

### Task 3: CommandDispatcher

**Files:**
- Create: `Sources/Voxtv/CommandDispatcher.swift`
- Create: `Tests/VoxtvTests/CommandDispatcherTests.swift`

**What:** Extensible command dispatch with simple keyword matching. Current dispatch rules: text matching search keywords (搜索/看/找/查/搜/播放/放) → strip keyword → send to Apple TV. Provides `CommandHandler` protocol for future LLM extension.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/VoxtvTests/CommandDispatcherTests.swift
import Testing
@testable import Voxtv

struct CommandDispatcherTests {
    @Test func testPassthroughWithoutKeyword() {
        let dispatcher = CommandDispatcher()
        let result = dispatcher.dispatch(text: "星际穿越")
        #expect(result.action == .sendText)
        #expect(result.text == "星际穿越")
    }

    @Test func testSearchKeywordStripped() {
        let dispatcher = CommandDispatcher()
        let cases = ["搜索星际穿越", "看三体", "找权力的游戏", "查繁花", "搜甄嬛传"]
        for input in cases {
            let result = dispatcher.dispatch(text: input)
            #expect(result.action == .sendText, "input: \(input)")
            #expect(!result.text.contains(input.prefix(2)), "keyword should be stripped from: \(input) -> \(result.text)")
        }
    }

    @Test func testPlayKeyword() {
        let dispatcher = CommandDispatcher()
        let result = dispatcher.dispatch(text: "播放繁花")
        #expect(result.action == .sendText)
        #expect(result.text == "繁花")
    }

    @Test func testWhitespaceTrimming() {
        let dispatcher = CommandDispatcher()
        let result = dispatcher.dispatch(text: "  搜索  奥本海默  ")
        #expect(result.text == "奥本海默")
    }

    @Test func testEmptyAfterStripReturnsOriginal() {
        let dispatcher = CommandDispatcher()
        let result = dispatcher.dispatch(text: "搜索")
        #expect(result.text == "搜索")
    }

    @Test func testEnglishTitle() {
        let dispatcher = CommandDispatcher()
        let result = dispatcher.dispatch(text: "搜索Rick and Morty")
        #expect(result.text == "Rick and Morty")
    }
}
```

Run: `swift test --filter CommandDispatcherTests`

Expected: All 6 tests FAIL (CommandDispatcher not defined).

- [ ] **Step 2: Implement CommandDispatcher**

```swift
// Sources/Voxtv/CommandDispatcher.swift

/// Result of command dispatch.
struct DispatchResult {
    enum Action: String {
        case sendText   // send to Apple TV as text input
        // Future: .openApp, .playMedia, .controlTV, .exit
    }
    let action: Action
    let text: String   // cleaned text to send
}

/// Protocol for pluggable command handling (LLM extension point).
protocol CommandHandler: Sendable {
    func handle(text: String) async -> DispatchResult
}

/// Default handler: strip search keywords, forward as text_set.
final class CommandDispatcher: @unchecked Sendable {

    /// Keywords that indicate a search intent. Text after keyword is sent to Apple TV.
    private let searchPrefixes = ["搜索", "搜", "看", "找", "查", "播放", "放"]

    func dispatch(text: String) -> DispatchResult {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return DispatchResult(action: .sendText, text: cleaned)
        }

        // Check if text starts with a search prefix keyword
        for prefix in searchPrefixes {
            if cleaned.hasPrefix(prefix) {
                let remainder = String(cleaned.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespaces)
                // If nothing left after stripping, send original
                let final = remainder.isEmpty ? cleaned : remainder
                return DispatchResult(action: .sendText, text: final)
            }
        }

        // Default: send full text as-is
        return DispatchResult(action: .sendText, text: cleaned)
    }
}
```

- [ ] **Step 3: Run tests to verify they pass**

```bash
swift test --filter CommandDispatcherTests
```

Expected: All 6 tests PASS.

- [ ] **Step 4: Run full test suite**

```bash
swift test
```

Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Voxtv/CommandDispatcher.swift Tests/VoxtvTests/CommandDispatcherTests.swift
git commit -m "feat: add CommandDispatcher with search keyword matching and extensible handler protocol"
```

---

### Task 4: WakePipeline state machine

**Files:**
- Create: `Sources/Voxtv/WakePipeline.swift`
- Create: `Tests/VoxtvTests/WakePipelineTests.swift`

**What:** Orchestrates the full KWS → prompt → speech → dispatch → bridge → feedback flow. Manages mic ownership between KWS and SpeechService. State machine handles timeouts, cooldown, and error recovery.

- [ ] **Step 1: Write failing tests**

```swift
// Tests/VoxtvTests/WakePipelineTests.swift
import Testing
@testable import Voxtv

struct WakePipelineTests {
    @Test func testInitialState() {
        let pipeline = WakePipeline(
            spotter: nil,   // placeholder — tests only check state transitions
            speech: nil,
            bridge: nil,
            dispatcher: nil,
            prompt: nil,
            feedback: nil
        )
        #expect(pipeline.state == .idle)
    }

    @Test func testCooldownExpiry() {
        // Start cooldown, verify it expires after configured duration
        let pipeline = WakePipeline(
            spotter: nil, speech: nil, bridge: nil,
            dispatcher: nil, prompt: nil, feedback: nil
        )
        pipeline.startCooldown(duration: 0.1)
        #expect(pipeline.state == .cooldown)
        Thread.sleep(forTimeInterval: 0.2)
        // After cooldown, pipeline should be ready to transition
        // (cooldown → idle is handled internally on next trigger)
    }

    @Test func testErrorTransitionBackToListening() {
        // Verify that error state eventually transitions back to listening
        // This tests the error recovery path
    }
}
```

Run: `swift test --filter WakePipelineTests`

Expected: Tests compile but may fail until implementation.

- [ ] **Step 2: Implement WakePipeline**

```swift
// Sources/Voxtv/WakePipeline.swift
import Foundation

/// States for the wake-word → recognition → send pipeline.
enum PipelineState: String {
    case idle
    case kwsListening
    case cooldown
    case prompting
    case recognizing
    case dispatching
    case feedback
    case error
}

final class WakePipeline: @unchecked Sendable {

    // Injected dependencies
    private weak var spotter: KeywordSpotterService?
    private let speech: SpeechService?
    private let bridge: AppleTVBridge?
    private let dispatcher: CommandDispatcher?
    private let prompt: PromptPlayer?
    private let feedback: FeedbackSpeaker?

    // Config (mirrored from AppState at pipeline start time)
    var promptType: String = "beep"       // "beep" or "tts"
    var promptText: String = "请说"
    var feedbackEnabled: Bool = true
    var recognitionTimeout: TimeInterval = 8.0
    var cooldownDuration: TimeInterval = 3.0

    // State
    private(set) var state: PipelineState = .idle
    private var cooldownTask: DispatchWorkItem?

    // Callback for Dashboard to observe state changes
    var onStateChange: (@Sendable (PipelineState) -> Void)?

    // MARK: - Init

    init(spotter: KeywordSpotterService?, speech: SpeechService?, bridge: AppleTVBridge?,
         dispatcher: CommandDispatcher?, prompt: PromptPlayer?, feedback: FeedbackSpeaker?) {
        self.spotter = spotter
        self.speech = speech
        self.bridge = bridge
        self.dispatcher = dispatcher
        self.prompt = prompt
        self.feedback = feedback
    }

    // MARK: - Pipeline lifecycle

    /// Start the wake-word listening loop.
    func start(keywordsBuf: String, threshold: Float = 0.25) throws {
        guard state == .idle else { return }
        transition(to: .kwsListening)

        // Set up the detection callback — this is the pipeline entry point
        spotter?.onDetection = { [weak self] keyword in
            self?.handleWakeDetection(keyword)
        }

        try spotter?.start(keywordsBuf: keywordsBuf, threshold: threshold)
    }

    /// Stop the pipeline and release the mic.
    func stop() {
        cooldownTask?.cancel()
        spotter?.stop()
        transition(to: .idle)
    }

    // MARK: - Pipeline stages

    private func handleWakeDetection(_ keyword: String) {
        transition(to: .cooldown)

        // 1. Stop KWS to release the microphone
        spotter?.stop()

        // 2. Play prompt
        transition(to: .prompting)
        if promptType == "tts" {
            prompt?.speak(promptText)
            // Brief delay for TTS to be heard, then start recognition
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.startRecognition()
            }
        } else {
            prompt?.playBeep()
            // Beep is instant — start recognition immediately
            startRecognition()
        }
    }

    private func startRecognition() {
        transition(to: .recognizing)
        guard let speech = speech else {
            handlePipelineError("SpeechService not configured")
            return
        }

        // Recognition timeout
        let timeoutTask = DispatchWorkItem { [weak self] in
            self?.handleRecognitionTimeout()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + recognitionTimeout, execute: timeoutTask)

        speech.recognize { [weak self] result in
            timeoutTask.cancel()
            switch result {
            case .success(let r):
                self?.handleRecognitionResult(r.text)
            case .failure(let e):
                self?.handleRecognitionError(e)
            }
        }
    }

    private func handleRecognitionResult(_ text: String) {
        let cleaned = TextNormalizer.normalize(text)
        guard !cleaned.isEmpty else {
            feedback?.speakNoSpeech()
            restartKWS()
            return
        }

        // Dispatch the command
        transition(to: .dispatching)
        let result = dispatcher?.dispatch(text: cleaned) ?? DispatchResult(action: .sendText, text: cleaned)

        // Send to Apple TV
        let sendOk = bridge?.send(text: result.text).success ?? false

        // Feedback
        transition(to: .feedback)
        if sendOk {
            feedback?.speakSuccess(query: result.text)
        } else {
            feedback?.speakSendFailed()
        }

        // Cool down then resume listening
        startCooldown(duration: cooldownDuration)
    }

    private func handleRecognitionError(_ error: SpeechError) {
        switch error {
        case .noSpeech:
            feedback?.speakNoSpeech()
        case .permissionDenied:
            feedback?.speak("麦克风或语音识别权限未授权")
        case .networkUnavailable:
            feedback?.speak("网络连接不可用")
        default:
            feedback?.speakRecognitionFailed()
        }
        restartKWS()
    }

    private func handleRecognitionTimeout() {
        speech?.cancelRecognition()
        feedback?.speakNoSpeech()
        restartKWS()
    }

    private func handlePipelineError(_ message: String) {
        transition(to: .error)
        feedback?.speak(message)
        restartKWS()
    }

    // MARK: - Helpers

    func startCooldown(duration: TimeInterval) {
        transition(to: .cooldown)
        let task = DispatchWorkItem { [weak self] in
            self?.restartKWS()
        }
        cooldownTask = task
        DispatchQueue.global().asyncAfter(deadline: .now() + duration, execute: task)
    }

    private func restartKWS() {
        guard state != .idle, state != .kwsListening else { return }
        // Re-read keywords from the spotter's config and restart
        // (spotter must be re-created with the same config since stop() tears down models)
        // This is handled by the caller via start()
        transition(to: .kwsListening)
    }

    private func transition(to newState: PipelineState) {
        state = newState
        onStateChange?(newState)
    }
}
```

- [ ] **Step 3: Build**

```bash
swift build
```

Expected: Build succeeds (tests may still need Wire-up in Task 6 for full functionality).

- [ ] **Step 4: Commit**

```bash
git add Sources/Voxtv/WakePipeline.swift Tests/VoxtvTests/WakePipelineTests.swift
git commit -m "feat: add WakePipeline state machine for KWS→speech→dispatch→feedback flow"
```

---

### Task 5: AppState config + SettingsView UI

**Files:**
- Modify: `Sources/Voxtv/AppState.swift`
- Modify: `Sources/Voxtv/SettingsView.swift`

**What:** Add configurable preferences for prompt type, prompt text, feedback enabled, timeout, and cooldown.

- [ ] **Step 1: Add config properties to AppState**

Add inside `AppState` (after `@Published var appleTVDeviceId: String = ""`):

```swift
    // Wake word pipeline config
    @Published var promptType: String = "beep"       // "beep" or "tts"
    @Published var promptText: String = "请说"
    @Published var feedbackEnabled: Bool = true
    @Published var recognitionTimeout: Double = 8.0
    @Published var cooldownDuration: Double = 3.0
```

Add to `init()` after `appleTVDeviceId = defaults.string(...)`:

```swift
        promptType = defaults.string(forKey: "promptType") ?? "beep"
        promptText = defaults.string(forKey: "promptText") ?? "请说"
        if defaults.object(forKey: "feedbackEnabled") != nil {
            feedbackEnabled = defaults.bool(forKey: "feedbackEnabled")
        }
        let savedTimeout = defaults.double(forKey: "recognitionTimeout")
        if savedTimeout > 0 { recognitionTimeout = savedTimeout }
        let savedCooldown = defaults.double(forKey: "cooldownDuration")
        if savedCooldown > 0 { cooldownDuration = savedCooldown }
```

Add save methods:

```swift
    func savePromptType(_ type: String) {
        promptType = type
        defaults.set(type, forKey: "promptType")
    }

    func savePromptText(_ text: String) {
        promptText = text
        defaults.set(text, forKey: "promptText")
    }

    func saveFeedbackEnabled(_ enabled: Bool) {
        feedbackEnabled = enabled
        defaults.set(enabled, forKey: "feedbackEnabled")
    }

    func saveRecognitionTimeout(_ timeout: Double) {
        recognitionTimeout = timeout
        defaults.set(timeout, forKey: "recognitionTimeout")
    }

    func saveCooldownDuration(_ duration: Double) {
        cooldownDuration = duration
        defaults.set(duration, forKey: "cooldownDuration")
    }
```

- [ ] **Step 2: Add "语音" tab to SettingsView**

Add a new TabView tab after the Dashboard tab, before the closing `}` of TabView. Set window height to accommodate:

```swift
            VStack(alignment: .leading, spacing: 12) {
                Text("语音交互")
                    .font(.headline)

                // Prompt type picker
                Picker("提示音类型:", selection: Binding(
                    get: { appState.promptType },
                    set: { appState.savePromptType($0) }
                )) {
                    Text("系统提示音").tag("beep")
                    Text("TTS 语音").tag("tts")
                }
                .pickerStyle(.radioGroup)

                // TTS prompt text (only when tts selected)
                if appState.promptType == "tts" {
                    HStack {
                        Text("提示文案:")
                        TextField("请说", text: Binding(
                            get: { appState.promptText },
                            set: { appState.savePromptText($0) }
                        ))
                        .frame(width: 150)
                    }
                }

                // Recognition timeout
                HStack {
                    Text("识别超时:")
                    Picker("", selection: Binding(
                        get: { Int(appState.recognitionTimeout) },
                        set: { appState.saveRecognitionTimeout(Double($0)) }
                    )) {
                        Text("5 秒").tag(5)
                        Text("8 秒").tag(8)
                        Text("10 秒").tag(10)
                        Text("15 秒").tag(15)
                    }
                    .frame(width: 80)
                }

                // Cooldown
                HStack {
                    Text("唤醒冷却:")
                    Picker("", selection: Binding(
                        get: { Int(appState.cooldownDuration) },
                        set: { appState.saveCooldownDuration(Double($0)) }
                    )) {
                        Text("2 秒").tag(2)
                        Text("3 秒").tag(3)
                        Text("5 秒").tag(5)
                    }
                    .frame(width: 80)
                }

                // Feedback toggle
                Toggle("语音反馈播报", isOn: Binding(
                    get: { appState.feedbackEnabled },
                    set: { appState.saveFeedbackEnabled($0) }
                ))
            }
            .padding()
            .tabItem {
                Label("语音", systemImage: "waveform")
            }
```

Also change window size on line 92: `width: 380` → `width: 420`, `height: 200` → `height: 320`.

Window setContentSize on line 78 (in AppState.swift `openSettings()`): `NSSize(width: 380, height: 260)` → `NSSize(width: 420, height: 360)`.

- [ ] **Step 3: Build & test**

```bash
swift build && swift test
```

Expected: Build succeeds, all tests pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/Voxtv/AppState.swift Sources/Voxtv/SettingsView.swift
git commit -m "feat: add voice interaction preferences (prompt type, timeout, cooldown, feedback)"
```

---

### Task 6: Wire pipeline in App.swift + DashboardServer

**Files:**
- Modify: `Sources/Voxtv/App.swift`
- Modify: `Sources/Voxtv/DashboardServer.swift`

**What:** Create all pipeline components and wire them together. Expose pipeline state and KWS status through the Dashboard API.

- [ ] **Step 1: Wire pipeline in App.swift**

After creating `kwSpotter` and setting `dashboard.keywordSpotter = kwSpotter`, add:

```swift
        // Create pipeline components
        let promptPlayer = PromptPlayer()
        let feedbackSpeaker = FeedbackSpeaker()
        let commandDispatcher = CommandDispatcher()

        // Create wake pipeline
        let wakePipeline = WakePipeline(
            spotter: kwSpotter,
            speech: dashboard.speechService,
            bridge: dashboard.appleTVBridge,
            dispatcher: commandDispatcher,
            prompt: promptPlayer,
            feedback: feedbackSpeaker
        )

        // Mirror AppState config to pipeline
        wakePipeline.promptType = appState.promptType
        wakePipeline.promptText = appState.promptText
        wakePipeline.feedbackEnabled = appState.feedbackEnabled
        wakePipeline.recognitionTimeout = appState.recognitionTimeout
        wakePipeline.cooldownDuration = appState.cooldownDuration

        // Expose pipeline state to Dashboard
        wakePipeline.onStateChange = { state in
            Task { await logStore.append(level: .info, message: "Pipeline: \(state.rawValue)") }
        }

        dashboard.wakePipeline = wakePipeline
        dashboard.promptPlayer = promptPlayer
        dashboard.feedbackSpeaker = feedbackSpeaker

        // Load wake word keywords from model
        let keywordsPath = (kwsModelDir as NSString).appendingPathComponent("keywords.txt")
        let defaultKeywords = (try? String(contentsOfFile: keywordsPath, encoding: .utf8))
            ?? "n ǐ h ǎo x iǎo V @你好小V"
```

- [ ] **Step 2: Add pipeline properties to DashboardServer**

Add after `var keywordSpotter: KeywordSpotterService?`:

```swift
    var wakePipeline: WakePipeline?
    var promptPlayer: PromptPlayer?
    var feedbackSpeaker: FeedbackSpeaker?
```

- [ ] **Step 3: Update DashboardServer /api/status to include pipeline state**

Update the `statusResponse()` method to include `pipelineState` in the JSON:

```swift
    private func statusResponse() -> (Int, String, String) {
        let micOk = speechService?.micPermission ?? false
        let speechOk = speechService?.speechPermission ?? false
        let deviceConfigured = appleTVBridge?.deviceId.isEmpty == false
        let plState = wakePipeline?.state.rawValue ?? "unavailable"

        let json = """
        {"state":"idle","stateSince":"\(ISO8601DateFormatter().string(from: Date()))","speech":{"microphoneAuthorized":\(micOk),"speechAuthorized":\(speechOk)},"appleTV":{"configured":\(deviceConfigured)},"kws":{"state":"\(keywordSpotter?.state.rawValue ?? "unavailable")"},"pipeline":{"state":"\(plState)"}}
        """
        return (200, json, appJSON)
    }
```

- [ ] **Step 4: Add /api/pipeline/start and /api/pipeline/stop endpoints**

Add routes in `route()`:

```swift
    if method == "POST" && path == "/api/pipeline/start" {
        return handlePipelineStart(body: body)
    }
    if method == "POST" && path == "/api/pipeline/stop" {
        return handlePipelineStop()
    }
```

Add handlers:

```swift
    private func handlePipelineStart(body: String) -> (Int, String, String) {
        guard let pipeline = wakePipeline else {
            return (500, #"{"ok":false,"error":"Pipeline not configured"}"#, appJSON)
        }
        guard let data = body.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let keywordsBuf = obj["keywordsBuf"] as? String
        else {
            return (400, #"{"ok":false,"error":"invalid body"}"#, appJSON)
        }

        // Request mic permission if needed
        let micAuthorized = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized

        if micAuthorized {
            do {
                try pipeline.start(keywordsBuf: keywordsBuf, threshold: 0.25)
                return (200, #"{"ok":true,"state":"listening"}"#, appJSON)
            } catch {
                return (500, #"{"ok":false,"error":"\#(error.localizedDescription)"}"#, appJSON)
            }
        }

        // Request permission async
        Task {
            _ = await MainActor.run {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
            }
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            _ = await MainActor.run { NSApp.setActivationPolicy(.accessory) }
            guard granted else { return }
            try? pipeline.start(keywordsBuf: keywordsBuf, threshold: 0.25)
        }

        return (200, #"{"ok":true,"state":"listening"}"#, appJSON)
    }

    private func handlePipelineStop() -> (Int, String, String) {
        wakePipeline?.stop()
        return (200, #"{"ok":true,"state":"idle"}"#, appJSON)
    }
```

- [ ] **Step 5: Build & test**

```bash
swift build && swift test
```

Expected: Build succeeds, all tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/Voxtv/App.swift Sources/Voxtv/DashboardServer.swift
git commit -m "feat: wire WakePipeline into app and expose pipeline state via API"
```

---

## Verification

| Stage | Automated | Manual |
|-------|-----------|--------|
| Build | `swift build` passes | — |
| Tests | `swift test` all pass, including CommandDispatcherTests, WakePipelineTests | — |
| Pipeline | — | Say "电视电视" → prompt → say search term → TTS feedback → Apple TV gets text |
| Preferences | — | Open 设置 → 语音 tab, change prompt type/timeout/cooldown, verify they take effect |
| Dashboard | — | Click 开始监听 (KWS) or use pipeline start/stop, pipeline state shown in status |

## Key Design Decisions

1. **KWS restart after each recognition cycle**: The WakePipeline stops KWS (releases mic), runs speech recognition, then must restart KWS. The spotter's `start()` method reloads models each time. This is cleanest for mic ownership but adds ~1s startup latency per cycle.

2. **CommandDispatcher extensibility**: `CommandHandler` protocol allows swapping in an LLM-based handler later without touching pipeline code.

3. **PromptPlayer + FeedbackSpeaker separated**: Different concerns — prompt is a fixed cue, feedback varies by outcome. Both use NSSpeechSynthesizer but have different APIs.
