# VoxTV

[![CI](https://github.com/Carter-Pro/voxtv/actions/workflows/ci.yml/badge.svg)](https://github.com/Carter-Pro/voxtv/actions/workflows/ci.yml)
[![Release](https://github.com/Carter-Pro/voxtv/actions/workflows/release.yml/badge.svg)](https://github.com/Carter-Pro/voxtv/releases)

Voice control for Apple TV — a macOS menu bar app that lets you speak to your Apple TV in Chinese, completely hands-free.

## Features

- **Wake Word Detection** — Local, offline keyword spotting ("电视电视") using sherpa-onnx
- **Speech Recognition** — Apple Speech framework with silence auto-finalize for Chinese voice input
- **Apple TV Control** — Sends recognized text to Apple TV input fields via pyatv/atvremote
- **Menu Bar App** — Lives in the macOS menu bar, always ready
- **Web Dashboard** — Built-in debug dashboard at localhost:8765
- **Configurable** — Custom wake word, prompt sound, timeout, cooldown, and feedback voice
- **Login Item** — Optional auto-start on login
- **DMG Installer** — Standard macOS drag-to-install distribution

## System Requirements

- macOS 14.0 or later
- Apple Silicon Mac (arm64)
- Apple TV on the same local network
- Microphone access
- [pyatv](https://github.com/postlund/pyatv) installed (`pipx install pyatv`)

## Installation

### Download DMG (Recommended)

Download the latest `VoxTV-Installer.dmg` from [Releases](https://github.com/Carter-Pro/voxtv/releases), open it, and drag `VoxTV.app` to `/Applications`.

### Build from Source

```bash
git clone https://github.com/Carter-Pro/voxtv.git
cd voxtv
swift build -c release
./scripts/package-app.sh
# DMG will be at .build/VoxTV-Installer.dmg
```

## Setup

1. Pair with your Apple TV: `atvremote --id <device_id> pair`
2. Launch VoxTV from `/Applications`
3. Click the menu bar icon → Settings → Apple TV tab → enter your device ID
4. Grant microphone permission when prompted
5. Click "Start Listening" in the menu bar
6. Say "电视电视" (the wake word), wait for the beep, then speak your search query

## How It Works

```
Microphone (always listening)
  → sherpa-onnx KWS (wake word detection)
  → PromptPlayer (beep sound)
  → Apple Speech (speech recognition, auto-finalize on 1.5s silence)
  → TextNormalizer (text cleanup)
  → CommandDispatcher (keyword routing)
  → AppleTVBridge → atvremote text_set → Apple TV input field
```

## Architecture

| Component | Responsibility |
|-----------|---------------|
| `KeywordSpotterService` | sherpa-onnx keyword spotting with Silero VAD |
| `WakePipeline` | State machine: idle → listening → recognizing → dispatching |
| `SpeechService` | Apple Speech recognition via AVAudioEngine |
| `AppleTVBridge` | atvremote text_set encapsulation |
| `TextNormalizer` | Lightweight text cleaning |
| `CommandDispatcher` | Keyword-based command routing |
| `PromptPlayer` | System beep or TTS prompt playback |
| `FeedbackSpeaker` | TTS feedback after command execution |
| `DashboardServer` | Embedded HTTP server for debug UI |
| `PinyinTokenizer` | Chinese → ppinyin token conversion for KWS |

## Open Source Libraries

VoxTV is built on these excellent open source projects:

- [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) — On-device keyword spotting (Apache 2.0)
- [ONNX Runtime](https://github.com/microsoft/onnxruntime) — ML model inference (MIT)
- [pyatv](https://github.com/postlund/pyatv) — Apple TV communication via atvremote CLI (MIT)

## Development

```bash
# Build
swift build

# Run
swift run

# Test
swift test

# Package for distribution
./scripts/package-app.sh
```

## Project Status

Phase 2 complete — wake word + speech recognition + Apple TV control loop is functional. Phase 3 (stability and daily-use polish) in progress.

## License

MIT
