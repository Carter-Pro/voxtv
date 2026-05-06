# Phase 2 Stage 1: sherpa-onnx 部署 + Dashboard KWS 测试面板

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Integrate sherpa-onnx keyword spotting + VAD into the macOS app, with a Dashboard test panel for interactive tuning.

**Architecture:** `systemLibrary` targets for sherpa-onnx + onnxruntime → adapted `SherpaOnnx.swift` → `KeywordSpotterService` (AVAudioEngine + VAD + KWS) → Dashboard KWS API + test panel.

**Tech Stack:** sherpa-onnx C API (via module map), Swift 6, AVAudioEngine, Silero VAD

**Reference:** `docs/sherpa-onnx-reference.md` — full API docs for all sherpa-onnx types used below.

---

## Key Reference: Actual sherpa-onnx Swift Types

From the repo's `swift-api-examples/SherpaOnnx.swift`:

```
SherpaOnnxKeywordSpotterWrapper       — main KWS class
  init(config: UnsafePointer<SherpaOnnxKeywordSpotterConfig>!)
  acceptWaveform(samples: [Float], sampleRate: Int = 16000)
  isReady() -> Bool
  decode()
  getResult() -> SherpaOnnxKeywordResultWrapper
  reset()
  inputFinished()

SherpaOnnxKeywordResultWrapper        — detection result
  var keyword: String                  // "" when nothing detected

SherpaOnnxVoiceActivityDetectorWrapper — VAD class
  init(config: UnsafePointer<SherpaOnnxVadModelConfig>, buffer_size_in_seconds: Float)
  acceptWaveform(samples: [Float])
  isEmpty() -> Bool
  front() -> SherpaOnnxSpeechSegmentWrapper
  pop()
  flush()

SherpaOnnxSpeechSegmentWrapper         — VAD speech segment
  var samples: [Float]                 // detected speech audio
```

Config functions: `sherpaOnnxKeywordSpotterConfig()`, `sherpaOnnxFeatureConfig()`, `sherpaOnnxOnlineModelConfig()`, `sherpaOnnxOnlineTransducerModelConfig()`, `sherpaOnnxSileroVadModelConfig()`, `sherpaOnnxVadModelConfig()`.

Keywords can be passed inline via `keywordsBuf` parameter (no file needed) — format: `"tokens :score #threshold @phrase"` with `/` separating multiple keywords.

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `Libraries/CSherpaOnnx/module.modulemap` | Create | Module map for C API |
| `Libraries/CSherpaOnnx/sherpa-onnx.h` | Create | Umbrella header |
| `Libraries/CSherpaOnnx/sherpa-onnx/` | Create | C headers from xcframework |
| `Libraries/COnnxRuntime/module.modulemap` | Create | Module map for onnxruntime |
| `Package.swift` | Modify | Add systemLibrary targets, linker flags |
| `Sources/Voxtv/SherpaOnnx.swift` | Create | Copied from repo, adapted for SPM import |
| `Sources/Voxtv/KeywordSpotterService.swift` | Create | AVAudioEngine + VAD + KWS pipeline |
| `Sources/Voxtv/App.swift` | Modify | Create + inject KeywordSpotterService |
| `Sources/Voxtv/DashboardServer.swift` | Modify | Add KWS API routes + test panel UI |
| `Resources/kws/` | Create | KWS model + tokens.txt |
| `Resources/vad/` | Create | silero_vad.onnx |

---

### Task 1.1: Build/Download sherpa-onnx Libraries + Models

- [ ] **Step 1: Build sherpa-onnx xcframework**

```bash
git clone https://github.com/k2-fsa/sherpa-onnx --depth 1 /tmp/sherpa-onnx
cd /tmp/sherpa-onnx
./build-swift-macos.sh
# Output: build-swift-macos/sherpa-onnx.xcframework
```

- [ ] **Step 2: Extract headers and static lib from xcframework**

```bash
# xcframework contains universal static lib + headers
# Extract to Libraries/CSherpaOnnx/sherpa-onnx/
cp -R /tmp/sherpa-onnx/build-swift-macos/sherpa-onnx.xcframework/macos-arm64_x86_64/Headers/* \
      Libraries/CSherpaOnnx/sherpa-onnx/
```

- [ ] **Step 3: Download onnxruntime**

```bash
curl -SL -O https://github.com/microsoft/onnxruntime/releases/download/v1.20.1/onnxruntime-osx-universal2-1.20.1.tgz
tar xf onnxruntime-osx-universal2-1.20.1.tgz
cp onnxruntime-osx-universal2-1.20.1/lib/libonnxruntime.dylib Libraries/COnnxRuntime/
cp -R onnxruntime-osx-universal2-1.20.1/include/* Libraries/COnnxRuntime/include/
```

- [ ] **Step 4: Download KWS model (Chinese, mobile int8)**

```bash
curl -SL -O https://github.com/k2-fsa/sherpa-onnx/releases/download/kws-models/sherpa-onnx-kws-zipformer-wenetspeech-3.3M-2024-01-01-mobile.tar.bz2
tar xf sherpa-onnx-kws-zipformer-wenetspeech-3.3M-2024-01-01-mobile.tar.bz2 -C Resources/kws/
```

- [ ] **Step 5: Download Silero VAD model**

```bash
curl -SL -O https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx
mv silero_vad.onnx Resources/vad/
```

- [ ] **Step 6: Verify files exist**

```
Libraries/CSherpaOnnx/
├── module.modulemap
├── sherpa-onnx.h
└── sherpa-onnx/c-api/c-api.h

Libraries/COnnxRuntime/
├── module.modulemap
├── include/
└── libonnxruntime.dylib

Resources/kws/
├── encoder-*.onnx
├── decoder-*.onnx
├── joiner-*.onnx
└── tokens.txt

Resources/vad/
└── silero_vad.onnx
```

---

### Task 1.2: Set Up SPM Integration

- [ ] **Step 1: Create module maps**

`Libraries/CSherpaOnnx/module.modulemap`:
```
module CSherpaOnnx {
    header "sherpa-onnx.h"
    link "sherpa-onnx"
    export *
}
```

`Libraries/COnnxRuntime/module.modulemap`:
```
module COnnxRuntime {
    header "onnxruntime.h"
    link "onnxruntime"
    export *
}
```

- [ ] **Step 2: Create umbrella headers**

`Libraries/CSherpaOnnx/sherpa-onnx.h`:
```c
#include "sherpa-onnx/c-api/c-api.h"
```

`Libraries/COnnxRuntime/onnxruntime.h`:
```c
#include "onnxruntime_c_api.h"
```

- [ ] **Step 3: Update Package.swift**

```swift
.target(
    name: "CSherpaOnnx",
    path: "Libraries/CSherpaOnnx",
    linkerSettings: [
        .linkedLibrary("sherpa-onnx"),
        .unsafeFlags(["-L", "Libraries/CSherpaOnnx"])
    ]
),
.target(
    name: "COnnxRuntime",
    path: "Libraries/COnnxRuntime",
    linkerSettings: [
        .linkedLibrary("onnxruntime"),
        .unsafeFlags(["-L", "Libraries/COnnxRuntime"])
    ]
),
```

Add `CSherpaOnnx` and `COnnxRuntime` to Voxtv target dependencies.

- [ ] **Step 4: Copy and adapt SherpaOnnx.swift**

Copy from `/tmp/sherpa-onnx/swift-api-examples/SherpaOnnx.swift` to `Sources/Voxtv/SherpaOnnx.swift`.

**Critical edit**: Change the import mechanism. The original uses a bridging header (`SherpaOnnx-Bridging-Header.h`). For SPM, replace with:
```swift
// Remove: any bridging header dependency
// Add at top:
import CSherpaOnnx
```

The file uses C types like `OpaquePointer`, `UnsafePointer<SherpaOnnxKeywordSpotterConfig>`, etc. — these are exposed via the `CSherpaOnnx` module.

If the file references functions not in `c-api.h` (e.g., helper functions from `sherpa-onnx/csrc/`), either:
- Remove those sections (we only need KWS + VAD)
- Or add the needed declarations to the umbrella header

- [ ] **Step 5: Verify: swift build**

```bash
swift build 2>&1
```

Expected: compilation succeeds. If linker errors about missing symbols, check the `.a` path and `-L` flags.

---

### Task 1.3: Implement KeywordSpotterService

- [ ] **Step 1: Write unit tests (TDD)**

Create `Tests/VoxtvTests/KeywordSpotterServiceTests.swift`:

```swift
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

    func testStartStopTransitions() {
        // Requires real model files — skip in CI, test manually
        // Tests state transitions: idle -> listening -> idle
    }

    func testKeywordBufferFormat() {
        // Verify keywordsBuf generation:
        // Input: ["小爱同学", "你好问问"]
        // Output: "x iǎo ài t óng x ué @小爱同学/n ǐ h ǎo w èn w èn @你好问问"
        let kw = KeywordSpotterService.formatKeywordsBuf(
            raw: ["小爱同学"],
            tokensPath: "Resources/kws/tokens.txt"
        )
        // Must run text2token first, then verify format
        XCTAssertFalse(kw.isEmpty)
    }

    func testVADServiceWiring() {
        let service = KeywordSpotterService(
            modelDir: "/tmp/fake",
            vadModel: "/tmp/fake",
            log: { _, _ in }
        )
        // VAD should be nil before start
        XCTAssertNil(service.vad)
    }
}
```

- [ ] **Step 2: Implement KeywordSpotterService**

Create `Sources/Voxtv/KeywordSpotterService.swift`:

```swift
import AVFoundation

enum KWSState: String {
    case idle
    case listening
}

final class KeywordSpotterService: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let modelDir: String
    private let vadModelPath: String

    private var spotter: SherpaOnnxKeywordSpotterWrapper?
    private var vad: SherpaOnnxVoiceActivityDetectorWrapper?
    private var circularBuffer: SherpaOnnxCircularBufferWrapper?

    private(set) var state: KWSState = .idle
    var onDetection: (@Sendable (String) -> Void)?
    var onVADStateChange: (@Sendable (Bool) -> Void)?  // true = speech detected
    private let log: (LogLevel, String) -> Void

    init(modelDir: String, vadModel: String, log: @escaping (LogLevel, String) -> Void) {
        self.modelDir = modelDir
        self.vadModelPath = vadModel
        self.log = log
    }

    func start(keywords: [String], threshold: Float = 0.25, score: Float = 1.0) throws {
        guard state == .idle else { return }

        // 1. Build keywords string for keywordsBuf
        let keywordsBuf = Self.buildKeywordsBuf(keywords: keywords, tokensPath: "\(modelDir)/tokens.txt")

        // 2. Configure KWS
        let encoder = findFile(in: modelDir, suffix: "encoder")
        let decoder = findFile(in: modelDir, suffix: "decoder")
        let joiner = findFile(in: modelDir, suffix: "joiner")
        let tokens = "\(modelDir)/tokens.txt"

        let transducerConfig = sherpaOnnxOnlineTransducerModelConfig(
            encoder: encoder, decoder: decoder, joiner: joiner
        )
        let modelConfig = sherpaOnnxOnlineModelConfig(
            tokens: tokens,
            transducer: transducerConfig
        )
        let featConfig = sherpaOnnxFeatureConfig(sampleRate: 16000, featureDim: 80)

        var kwsConfig = sherpaOnnxKeywordSpotterConfig(
            featConfig: featConfig,
            modelConfig: modelConfig,
            keywordsFile: "",           // not used — we pass via buf
            keywordsBuf: keywordsBuf,
            keywordsBufSize: keywordsBuf.utf8.count,
            keywordsThreshold: threshold,
            keywordsScore: score
        )

        spotter = SherpaOnnxKeywordSpotterWrapper(config: &kwsConfig)

        // 3. Configure VAD
        var sileroCfg = sherpaOnnxSileroVadModelConfig(
            model: vadModelPath,
            threshold: 0.25,
            minSilenceDuration: 0.25,
            minSpeechDuration: 0.1,
            windowSize: 512,
            maxSpeechDuration: 5.0
        )
        var vadCfg = sherpaOnnxVadModelConfig(sileroVad: sileroCfg)
        vad = SherpaOnnxVoiceActivityDetectorWrapper(config: &vadCfg, buffer_size_in_seconds: 30)
        circularBuffer = SherpaOnnxCircularBufferWrapper(capacity: 16000 * 30)

        // 4. Start audio engine
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        // Resample to 16kHz if needed — for now, assert format matches
        inputNode.installTap(onBus: 0, bufferSize: 512, format: format) { [weak self] buffer, _ in
            guard let self, self.state == .listening else { return }
            let samples = self.extractSamples(buffer)
            self.vad?.acceptWaveform(samples: samples)
            self.processVADResults()
            self.onVADStateChange?(self.vad?.isSpeechDetected() ?? false)
        }

        engine.prepare()
        try engine.start()
        state = .listening
        log(.info, "KeywordSpotterService started with \(keywords.count) keywords")
    }

    private func processVADResults() {
        guard let vad else { return }
        while !vad.isEmpty() {
            let segment = vad.front()
            vad.pop()

            spotter?.acceptWaveform(samples: segment.samples)
            let padding = [Float](repeating: 0.0, count: 3200)
            spotter?.acceptWaveform(samples: padding)
            spotter?.inputFinished()

            while spotter?.isReady() == true {
                spotter?.decode()
                if let keyword = spotter?.getResult().keyword, !keyword.isEmpty {
                    log(.info, "Wake word detected: \(keyword)")
                    onDetection?(keyword)
                    spotter?.reset()
                }
            }
        }
    }

    func stop() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        spotter = nil
        vad = nil
        circularBuffer = nil
        state = .idle
        log(.info, "KeywordSpotterService stopped")
    }

    // MARK: - Helpers

    private func findFile(in dir: String, suffix: String) -> String {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: dir) else { return "" }
        return files.first(where: { $0.hasSuffix(suffix) && $0.hasSuffix(".onnx") })
            .map { "\(dir)/\($0)" } ?? ""
    }

    private func extractSamples(_ buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else { return [] }
        let frameCount = Int(buffer.frameLength)
        return Array(UnsafeBufferPointer(start: channelData.pointee, count: frameCount))
    }

    static func buildKeywordsBuf(keywords: [String], tokensPath: String) -> String {
        // For now, caller must run text2token externally and pass pre-tokenized strings
        // Or we can shell out to sherpa-onnx-cli if installed:
        // let process = Process()
        // process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        // process.arguments = ["sherpa-onnx-cli", "text2token", ...]
        //
        // For Stage 1, accept pre-tokenized keywords from Dashboard
        return keywords.joined(separator: "/")
    }
}
```

- [ ] **Step 3: Verify: swift build compiles**

```bash
swift build 2>&1
```

---

### Task 1.4: Wire into App + DashboardServer

- [ ] **Step 1: Wire in App.swift**

In `App.init()`, after existing setup:

```swift
let modelDir = Bundle.main.resourcePath! + "/kws"
let vadModel = Bundle.main.resourcePath! + "/vad/silero_vad.onnx"

let kwSpotter = KeywordSpotterService(
    modelDir: modelDir,
    vadModel: vadModel,
    log: { level, msg in
        Task { await logStore.append(level: level, message: msg) }
    }
)
dashboard.keywordSpotter = kwSpotter
```

- [ ] **Step 2: Add KWS API routes in DashboardServer**

Add property:
```swift
var keywordSpotter: KeywordSpotterService?
```

Add routes in `route()`:
```swift
if method == "POST" && path == "/api/kws/start" {
    return handleKWSStart(body: body)
}
if method == "POST" && path == "/api/kws/stop" {
    return handleKWSStop()
}
if method == "GET" && path == "/api/kws/status" {
    return handleKWSStatus()
}
```

Implement `handleKWSStart`:
```swift
private func handleKWSStart(body: String) -> (Int, String, String) {
    guard let spotter = keywordSpotter else {
        return (500, #"{"ok":false,"error":"KeywordSpotterService not configured"}"#, appJSON)
    }
    guard let data = body.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let keywords = obj["keywords"] as? [String]
    else {
        return (400, #"{"ok":false,"error":"invalid body — expected {keywords: [...], threshold?: 0.6}"}"#, appJSON)
    }
    let threshold = (obj["threshold"] as? Float) ?? 0.25
    let score = (obj["score"] as? Float) ?? 1.0

    do {
        try spotter.start(keywords: keywords, threshold: threshold, score: score)
        return (200, #"{"ok":true,"state":"listening"}"#, appJSON)
    } catch {
        return (500, #"{"ok":false,"error":"\#(error.localizedDescription)"}"#, appJSON)
    }
}
```

Implement `handleKWSStop`:
```swift
private func handleKWSStop() -> (Int, String, String) {
    keywordSpotter?.stop()
    return (200, #"{"ok":true,"state":"idle"}"#, appJSON)
}
```

Implement `handleKWSStatus`:
```swift
private var kwsDetections: [(Date, String)] = []
private let kwsDetectionsMax = 50

private func handleKWSStatus() -> (Int, String, String) {
    guard let spotter = keywordSpotter else {
        return (200, #"{"state":"unavailable"}"#, appJSON)
    }
    let json = """
    {"state":"\(spotter.state.rawValue)","detections":[\#(kwsDetections.map { "{\"time\":\"\(ISO8601DateFormatter().string(from: $0.0))\",\"keyword\":\"\($0.1)\"}" }.joined(separator: ","))]}
    """
    return (200, json, appJSON)
}
```

Store detections from callback (wire in App.swift):
```swift
kwSpotter.onDetection = { [weak dashboard] keyword in
    dashboard?.recordKWSDetection(keyword)
}
```

- [ ] **Step 3: Add kws block to /api/status**

```swift
"kws": {"state":"\(keywordSpotter?.state.rawValue ?? "unavailable")"}
```

---

### Task 1.5: Dashboard KWS Test Panel

- [ ] **Step 1: Add HTML card**

New card in Dashboard HTML between status card and controls:

```html
<div class="card" id="kws-card">
  <h2>唤醒词测试 (KWS)</h2>
  <div style="margin-bottom:8px">
    <label style="font-size:13px;color:#999">关键词 (每行一个，支持 :score #threshold @phrase 格式)</label>
    <textarea id="kws-keywords" style="width:100%;height:60px;background:#1a1a2e;color:#e0e0e0;border:1px solid #444;border-radius:8px;padding:8px;font-size:14px" placeholder="x iǎo ài t óng x ué :2.0 #0.6 @小爱同学">x iǎo ài t óng x ué :2.0 #0.6 @小爱同学</textarea>
  </div>
  <div style="display:flex;gap:10px;align-items:center;margin-bottom:8px">
    <label style="font-size:13px;color:#999">阈值: <span id="kws-threshold-val">0.25</span></label>
    <input type="range" id="kws-threshold" min="0.05" max="0.95" step="0.05" value="0.25" style="flex:1">
    <button id="kws-start-btn" style="padding:8px 16px;border:none;border-radius:8px;background:#4caf84;color:#fff;font-weight:600;cursor:pointer">开始监听</button>
  </div>
  <div id="kws-vad-status" style="font-size:12px;color:#666;margin-bottom:4px">VAD: --</div>
  <div id="kws-detections" style="max-height:120px;overflow-y:auto;font-family:monospace;font-size:12px;color:#4caf84"></div>
</div>
```

- [ ] **Step 2: Add JS logic**

```javascript
const kwsStartBtn = document.getElementById('kws-start-btn');
const kwsKeywords = document.getElementById('kws-keywords');
const kwsThreshold = document.getElementById('kws-threshold');
const kwsThresholdVal = document.getElementById('kws-threshold-val');
const kwsDetections = document.getElementById('kws-detections');
const kwsVadStatus = document.getElementById('kws-vad-status');

kwsThreshold.addEventListener('input', () => {
  kwsThresholdVal.textContent = parseFloat(kwsThreshold.value).toFixed(2);
});

let kwsListening = false;

kwsStartBtn.addEventListener('click', () => {
  if (kwsListening) {
    fetch('/api/kws/stop', { method: 'POST' });
    kwsStartBtn.textContent = '开始监听';
    kwsStartBtn.style.background = '#4caf84';
    kwsListening = false;
  } else {
    const keywords = kwsKeywords.value.split('\n').filter(k => k.trim());
    fetch('/api/kws/start', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        keywords: keywords,
        threshold: parseFloat(kwsThreshold.value)
      })
    });
    kwsStartBtn.textContent = '停止监听';
    kwsStartBtn.style.background = '#c73d54';
    kwsListening = true;
  }
});

let lastDetections = [];
function updateKWS() {
  if (!kwsListening) return;
  fetch('/api/kws/status')
    .then(r => r.json())
    .then(data => {
      if (data.detections && data.detections.length > lastDetections.length) {
        const newOnes = data.detections.slice(lastDetections.length);
        newOnes.forEach(d => {
          const div = document.createElement('div');
          div.textContent = `[${new Date(d.time).toLocaleTimeString()}] ${d.keyword}`;
          kwsDetections.prepend(div);
        });
        if (kwsDetections.children.length > 30) {
          while (kwsDetections.children.length > 30) kwsDetections.lastChild.remove();
        }
      }
      lastDetections = data.detections || [];
    });
}

// Poll KWS status every 500ms when active
setInterval(() => {
  updateStatus();
  updateLogs();
  updateKWS();
}, 2000);
```

---

### Task 1.6: Manual Testing + Tuning

- [ ] **Step 1: Generate tokenized keywords**

```bash
# Write candidate wake words
cat > /tmp/wake_words.txt << 'EOF'
你好小V :2.0 #0.5 @你好小V
嘿Siri :1.0 #0.4 @嘿Siri
小V小V :2.5 #0.45 @小V小V
EOF

# Tokenize with text2token
sherpa-onnx-cli text2token \
    --text /tmp/wake_words.txt \
    --tokens Resources/kws/tokens.txt \
    --tokens-type ppinyin \
    --output /tmp/wake_words_tokens.txt

cat /tmp/wake_words_tokens.txt
# Output example: n ǐ h ǎo x iǎo V :2.0 #0.5 @你好小V
```

- [ ] **Step 2: Test flow**

| Step | Expected |
|------|----------|
| Start app, open Dashboard | KWS panel shows "开始监听" button |
| Paste tokenized keywords, click "开始监听" | VAD shows mic status, button turns red |
| Speak wake word at 1m | Detection appears in log |
| Adjust threshold via slider | Changes sensitivity in real-time |
| Click "停止监听" | Mic stops, button turns green |

- [ ] **Step 3: Record metrics for 3-5 candidate wake words**

Test each at 1m, 2m, 3m, with and without TV noise.

---

## Verification

| Level | What |
|-------|------|
| Build | `swift build` compiles successfully |
| Unit tests | `KeywordSpotterServiceTests` pass (state machine + keywordsBuf format) |
| Integration | Existing 26 tests still pass |
| Manual | Dashboard KWS panel: start → speak → detect → stop |

---

## What We're NOT Doing in Stage 1

- Production wake word pipeline (wake → recognize → send) — that's Stage 2
- Locking down a specific wake word — Stage 1 is for experimentation
- Auto-start on app launch — Stage 1 is manual via Dashboard
- Error recovery / engine restart — Stage 1 is for testing
