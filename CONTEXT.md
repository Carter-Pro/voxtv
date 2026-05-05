# macOS Apple TV Voice Agent

通过客厅麦克风采集用户语音，使用 Apple Speech 完成短句识别，再通过 pyatv 将识别文本发送到 Apple TV 当前输入框的 macOS 语音代理。

## Language

**Push-to-Talk (PTT)**:
用户按住按钮/按键说话、松开发送的交互模式。
_Avoid_: 语音触发, voice trigger, manual recording

**Session**:
一次完整的 PTT 交互：从按下开始到发送完成（或取消/失败）。
_Avoid_: 请求, request, transaction

**Agent（守护进程）**:
后台常驻的进程，负责语音识别、Apple TV 控制、HTTP server、配置管理。配置的唯一归属。
_Avoid_: 后台服务, service, daemon（当与进程架构无关时）

**Menu Bar UI（菜单栏界面）**:
前台可选进程，通过 localhost HTTP 调用 Agent API，提供配置和日志查看入口。
_Avoid_: 设置窗口, 控制面板

**Web Dashboard**:
Phase 1A 的调试入口，运行在 Agent 内嵌 HTTP server 上的 HTML 页面。不是正式产品入口。
_Avoid_: 前端, 控制台, admin panel

**text_set**:
pyatv 的 atvremote CLI 子命令，向 Apple TV 当前输入框发送文本。命令格式：`atvremote --id <device_id> text_set="<text>"`。

**device id**:
Apple TV 的唯一标识符，由 `atvremote scan` 获取，用于所有 atvremote 命令的 `--id` 参数。

**LAN mode**:
Dashboard HTTP server 监听 `0.0.0.0`（而非 `localhost`）以允许局域网内其他设备访问的开关。

**TTS Feedback**:
使用 macOS 内置 `NSSpeechSynthesizer` 朗读错误提示和修复建议，由 `FeedbackSpeaker` 模块负责。
_Avoid_: 语音播报, voice alert, audio notification

## Modules

**SessionController**:
管理 PTT 生命周期和状态机。协调 SpeechService、TextNormalizer、AppleTVBridge、FeedbackSpeaker。
_Avoid_: 编排器, orchestrator, PTT manager

**SpeechService**:
封装 Apple Speech Framework 和 AVAudioEngine，负责麦克风采集和短句识别。使用系统默认 locale 支持中英文混杂。
_Avoid_: 语音识别器, ASR engine

**AppleTVBridge**:
封装 atvremote CLI 调用。负责命令构造、执行、结果捕获。不做内部重试。
_Avoid_: TV controller, remote sender

**TextNormalizer**:
轻量文本清洗：去首尾空格、去末尾标点、压缩连续空格。
_Avoid_: 文本处理, text processor

**ConfigStore**:
守护进程内配置持久化。Agent 是配置唯一归属，UI 和 Dashboard 通过 `/api/config` 读写。
_Avoid_: 设置管理器, preferences

**LogStore**:
内存环形缓冲区日志，供 Dashboard 和 UI 查询。记录关键链路事件。
_Avoid_: 日志系统, logger

**FeedbackSpeaker**:
使用 NSSpeechSynthesizer 朗读 TTS 反馈，告知用户发送失败、权限缺失、识别失败等错误及修复建议。
_Avoid_: TTS engine, voice feedback

## Relationships

- **SessionController** 调用 **SpeechService** 开始/停止识别
- **SessionController** 调用 **TextNormalizer** 清洗识别文本
- **SessionController** 调用 **AppleTVBridge** 发送文本
- **SessionController** 调用 **FeedbackSpeaker** 在失败时朗读错误
- **Menu Bar UI** 和 **Web Dashboard** 通过 HTTP 调用 **Agent** API，不直接访问模块
- **ConfigStore** 归 **Agent**（守护进程）所有

## Example dialogue

> **Dev:** "When the user holds the button in Dashboard, does that go directly to SpeechService?"
> **Domain expert:** "No — Dashboard POSTs to `/api/ptt/begin`, the HTTP handler calls SessionController, and SessionController calls SpeechService. Dashboard never touches SpeechService directly."
>
> **Dev:** "And if both the Dashboard button and the keyboard shortcut fire at the same time?"
> **Domain expert:** "SessionController rejects the second one — `session_in_progress`. All PTT entry points share one session. First to grab idle wins."
>
> **Dev:** "What happens when atvremote fails to send?"
> **Domain expert:** "AppleTVBridge does not retry internally. SessionController tells FeedbackSpeaker to read the error aloud, the state goes to `error`, and the Dashboard shows a retry button."

## Flagged ambiguities

- "Agent" originally referred to the whole macOS app. Resolved: **Agent（守护进程）** is specifically the background daemon; the menu bar process is the **Menu Bar UI**.
