# VoxTV

[![CI](https://github.com/Carter-Pro/voxtv/actions/workflows/ci.yml/badge.svg)](https://github.com/Carter-Pro/voxtv/actions/workflows/ci.yml)
[![Release](https://github.com/Carter-Pro/voxtv/actions/workflows/release.yml/badge.svg)](https://github.com/Carter-Pro/voxtv/releases)
[![Download](https://img.shields.io/badge/Download-Latest%20DMG-brightgreen)](https://github.com/Carter-Pro/voxtv/releases/latest)

Apple TV 语音控制 —— 一个 macOS 菜单栏应用，让你完全免提用中文语音控制 Apple TV。

## 功能特性

- **唤醒词检测** — 基于 sherpa-onnx 的本地离线关键词识别（"电视电视"）
- **语音识别** — 使用 Apple Speech 框架进行中文语音识别，支持静音自动结束
- **Apple TV 控制** — 通过 pyatv/atvremote 将识别文本发送到 Apple TV 输入框
- **菜单栏应用** — 常驻 macOS 菜单栏，随时待命
- **Web 调试面板** — 内建调试面板，访问 localhost:8765
- **高度可配置** — 自定义唤醒词、提示音、超时时间、冷却时间、语音反馈
- **开机自启** — 可选的登录自动启动
- **DMG 安装包** — 标准 macOS 拖拽安装

## 系统要求

- macOS 14.0 或更高版本
- Apple Silicon Mac (arm64)
- 同一局域网内的 Apple TV
- 麦克风权限
- 已安装 [pyatv](https://github.com/postlund/pyatv)（`pipx install pyatv`）

## 安装

### 下载 DMG（推荐）

从 [Releases](https://github.com/Carter-Pro/voxtv/releases) 下载最新 `VoxTV-Installer.dmg`，打开后将 `VoxTV.app` 拖入 `/Applications`。

### 从源码构建

```bash
git clone https://github.com/Carter-Pro/voxtv.git
cd voxtv
swift build -c release
./scripts/package-app.sh
# DMG 文件位于 .build/VoxTV-Installer.dmg
```

## 使用说明

1. 配对 Apple TV：`atvremote --id <device_id> pair`
2. 启动 VoxTV
3. 点击菜单栏图标 → 设置 → Apple TV 标签页 → 输入 device ID
4. 按提示授权麦克风权限
5. 点击菜单栏的「开始监听」
6. 说"电视电视"（唤醒词），听到提示音后说出搜索内容

## 工作原理

```
麦克风（常驻监听）
  → sherpa-onnx KWS（唤醒词检测）
  → PromptPlayer（提示音）
  → Apple Speech（语音识别，1.5 秒静音自动结束）
  → TextNormalizer（文本清洗）
  → CommandDispatcher（关键词路由）
  → AppleTVBridge → atvremote text_set → Apple TV 输入框
```

## 架构

| 组件 | 职责 |
|------|------|
| `KeywordSpotterService` | sherpa-onnx 关键词检测 + Silero VAD |
| `WakePipeline` | 状态机：空闲 → 监听 → 识别中 → 分发中 |
| `SpeechService` | Apple Speech 语音识别 |
| `AppleTVBridge` | atvremote text_set 封装 |
| `TextNormalizer` | 轻量文本清洗 |
| `CommandDispatcher` | 关键词命令路由 |
| `PromptPlayer` | 系统提示音或 TTS 提示播放 |
| `FeedbackSpeaker` | TTS 语音反馈 |
| `DashboardServer` | 内嵌 HTTP 调试面板 |
| `PinyinTokenizer` | 中文 → ppinyin token 转换 |

## 使用的开源项目

- [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) — 设备端关键词检测（Apache 2.0）
- [ONNX Runtime](https://github.com/microsoft/onnxruntime) — 机器学习推理引擎（MIT）
- [pyatv](https://github.com/postlund/pyatv) — Apple TV 通信（MIT）

## 开发

```bash
swift build     # 构建
swift run       # 运行
swift test      # 测试
./scripts/package-app.sh  # 打包
```

## 项目状态

Phase 2 已完成 —— 唤醒词 + 语音识别 + Apple TV 控制链路可正常运行。Phase 3（稳定性与日常使用打磨）进行中。

## 许可证

MIT
