# macOS Apple TV Voice Agent

通过客厅麦克风采集用户语音，使用 sherpa-onnx 本地唤醒词 + Apple Speech 短句识别，再通过 pyatv 将识别文本发送到 Apple TV 当前输入框的 macOS 语音代理。

## 语言

**Wake Word（唤醒词）**:
用户说出特定词语以触发语音识别的免提交互模式。当前使用 "电视电视"。
_别名/勿用_: keyword, hotword, trigger phrase

**WakePipeline**:
管理唤醒词 → 提示音 → 语音识别 → 分发 → Apple TV 发送的完整状态机。Phase 2 替代 Phase 1A 的 SessionController。
_别名/勿用_: 编排器, orchestrator, session manager

**Agent（守护进程）**:
后台常驻的进程，负责语音识别、Apple TV 控制、HTTP server、配置管理、日志。配置的唯一归属。
_别名/勿用_: 后台服务, service, daemon

**Menu Bar UI（菜单栏界面）**:
前台进程，通过 localhost HTTP 调用 Agent API，提供配置和日志查看入口。
_别名/勿用_: 设置窗口, 控制面板

**Web Dashboard**:
嵌入 Agent 的调试 HTTP 页面。不是正式产品入口。
_别名/勿用_: 前端, 控制台, admin panel

**text_set**:
pyatv 的 atvremote CLI 子命令，向 Apple TV 当前输入框发送文本。格式：`atvremote --id <device_id> text_set="<text>"`。

**device id**:
Apple TV 的唯一标识符，由 `atvremote scan` 获取。

## 模块

**WakePipeline**:
状态机：`kwsListening → prompting → recognizing → dispatching → cooldown → kwsListening`。协调 `KeywordSpotterService`、`PromptPlayer`、`SpeechService`、`CommandDispatcher`、`AppleTVBridge`、`FeedbackSpeaker`。
_别名/勿用_: 编排器, PTT manager

**KeywordSpotterService**:
封装 sherpa-onnx KWS + Silero VAD + AVAudioEngine。使用 ppinyin token 格式配置关键词。所有音频引擎操作在后台线程执行。
_别名/勿用_: KWS engine, wake word detector

**SpeechService**:
封装 Apple Speech Framework + AVAudioEngine。支持静音自动结束（1.5s）和超时兜底（8s），zh-CN locale。
_别名/勿用_: 语音识别器, ASR engine

**AppleTVBridge**:
封装 atvremote CLI。构造命令、执行、捕获结果。不做内部重试。
_别名/勿用_: TV controller, remote sender

**TextNormalizer**:
轻量文本清洗：去首尾空格、末尾标点、压缩连续空格。
_别名/勿用_: 文本处理, text processor

**CommandDispatcher**:
基于关键字的命令路由。支持搜索、播放等关键词匹配，可扩展 handler 协议。
_别名/勿用_: command router, intent parser

**PromptPlayer**:
播放提示音（系统 beep 或 NSSound），唤醒后提示用户开始说话。
_别名/勿用_: chime player, notification sound

**FeedbackSpeaker**:
使用 AVSpeechSynthesizer 朗读 TTS 反馈。
_别名/勿用_: TTS engine, voice feedback

**LogStore**:
内存环形缓冲区 + `~/Library/Logs/Voxtv/` 持久化文件日志。7 天自动清理。
_别名/勿用_: 日志系统, logger

**PinyinTokenizer**:
使用 `CFStringTransform` 将中文唤醒词转换为 sherpa-onnx ppinyin token 格式。
_别名/勿用_: pinyin converter

## 关系

- **WakePipeline** 接收 **KeywordSpotterService** 的检测回调
- **WakePipeline** 调用 **PromptPlayer** 播放提示音
- **WakePipeline** 调用 **SpeechService** 开始/停止识别
- **WakePipeline** 调用 **TextNormalizer** 清洗识别文本
- **WakePipeline** 调用 **CommandDispatcher** 路由命令
- **CommandDispatcher** 调用 **AppleTVBridge** 发送文本
- **WakePipeline** 调用 **FeedbackSpeaker** 在失败时朗读错误
- **Menu Bar UI** 和 **Web Dashboard** 通过 HTTP 调用 Agent API
- **AppState** 通过 **WakePipeline** 管理 KWS 启动/停止
