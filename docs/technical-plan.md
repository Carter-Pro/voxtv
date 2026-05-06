# Apple TV 语音输入助手技术任务文档

## 1. 项目背景

用户家中有一台 Apple TV 和一台常驻运行的 Mac mini。Apple TV 未在中国大陆正式发售，中文输入体验差，Siri 不支持普通话，用户在搜索影片、剧集时需要用遥控器在横向键盘中输入拼音，效率低、体验差。

本项目目标是开发一个运行在 Mac mini 上的 macOS Voice Agent，通过客厅麦克风采集用户语音，使用 Apple Speech 完成短句识别，再通过 `atvremote` 将识别文本发送到 Apple TV 当前输入框。

第一阶段重点不是做完整商业产品，而是验证：

> 在真实客厅环境中，Apple Speech + Mac mini 麦克风 + Apple TV `text_set` 是否能形成一个足够自然、稳定、低延迟的语音输入闭环。

---

## 2. 已验证事实

Phase 0 已完成。

已验证：

- Mac mini 可发现并配对 Apple TV。
- Apple TV 可通过 `atvremote` 控制。
- 开机、关机、文本输入均正常。
- 中文文本输入已成功。
- 正确文本发送命令为：

```bash
atvremote --id xxxxx text_set="xxx"
```

后续所有实现必须基于上述命令形式，不要使用未经验证的其他格式。

---

## 3. 不推荐方向

以下方向不作为当前项目路线：

1. **不做 tvOS App 作为日常入口。**
   - tvOS App 不能作为系统级输入法。
   - 不能稳定控制其他第三方 tvOS App。
   - 会打破观看沉浸感。

2. **不自研 tvOS 输入法。**
   - 基本不可行。
   - 系统限制较多。

3. **不在第一阶段做复杂语音控制。**
   - 不做“打开某 App 搜索某片并播放”。
   - 第三方 App UI 状态不可可靠获取。

4. **不做多 ASR 引擎横向评测。**
   - 当前明确采用 Apple Speech。
   - 先学习并实测 Apple 原生技术栈。

5. **不开发 iOS App。**
   - iOS App 是未来可能的正式辅助入口。
   - 当前文档不覆盖 iOS App 开发。

---

## 4. 总体技术路线

```text
macOS Voice Agent on Mac mini
  ↓
麦克风采集 AVAudioEngine
  ↓
Apple Speech 短句识别
  ↓
TextNormalizer 文本清洗
  ↓
SessionController 状态编排
  ↓
AppleTVBridge
  ↓
atvremote --id xxxxx text_set="xxx"
  ↓
Apple TV 当前输入框
```

Phase 2 再增加本地唤醒词：

```text
sherpa-onnx 本地唤醒词
  ↓
启动一次 Apple Speech 短句识别
```

---

## 5. 产品入口分层

### 5.1 macOS Agent（守护进程）

长期核心。拆分为两部分：

- **守护进程**（后台）：负责语音识别、Apple TV 控制、配置管理、日志、HTTP server。开机自启动（可配置）。
- **菜单栏 UI**（前台）：仅用于配置和维护。通过 localhost HTTP 调守护进程 API，不直接访问底层模块。

守护进程负责：

- 麦克风采集
- Apple Speech 识别
- Apple TV 文本发送
- 配置管理（配置唯一归属，UI 通过 `/api/config` 读写）
- 状态管理
- 日志记录
- Web Debug Dashboard 服务
- TTS 语音反馈（错误朗读）
- 未来唤醒词监听

菜单栏 UI 负责：

- 显示守护进程运行状态
- 显示权限状态
- 打开 Dashboard
- 配置 Apple TV device id 等参数
- 查看日志
- 启动 / 停止守护进程
- 退出

---

### 5.2 Web Debug Dashboard

仅作为 Phase 1A 调试入口，不是正式产品入口。

设计原因：

- Mac mini 无显示器、无键盘鼠标。
- 用户主要通过书房台式机远程连接管理 Mac mini。
- 但客厅实际验证时，不能在书房点一下再跑去客厅看电视。
- Dashboard 可以让用户在手机或电脑浏览器中直接触发测试。

职责：

- 远程触发 Push-to-Talk。
- 查看识别结果。
- 手动发送文本。
- 查看 Apple TV 发送结果。
- 查看日志。
- 配置 Apple TV device id。

不追求：

- 长期产品化。
- 漂亮 UI。
- 登录系统。
- 外网访问。
- iOS App 替代品。

---

### 5.3 macOS 菜单栏 / 设置界面

主要用于配置和维护，不作为客厅验证主入口。

职责：

- 显示 Agent 运行状态。
- 显示权限状态。
- 打开 Dashboard。
- 配置 Apple TV device id。
- 查看日志。
- 启动 / 停止 Agent。
- 退出 App。

不承担主要客厅调试触发职责。

---

### 5.4 iOS App

未来可能开发，但不在本文档范围内。

如果未来开发，iOS App 应作为正式辅助入口：

```text
iOS App
  ↓
Mac mini Agent
  ↓
Apple TV
```

iOS App 不直接控制 Apple TV，而是控制 Mac mini Agent。

---

## 6. 开发阶段总览

```text
Phase 0：Apple TV 控制链路验证，已完成
Phase 1A：Apple Speech + Web Debug Dashboard + macOS 配置/日志入口 + text_set 闭环
Phase 1B：全局快捷键 Push-to-Talk（已跳过）
Phase 2：sherpa-onnx 本地唤醒词
Phase 3：稳定性与日常使用打磨
Phase 4：Mac 产品化与上架预研
```

---

# Phase 1A：Apple Speech + Web Debug Dashboard + text_set 闭环

## 7. Phase 1A 目标

在 Mac mini 无显示器、无键鼠的情况下，通过局域网 Web Debug Dashboard 触发 Apple Speech 语音识别，并把识别文本发送到 Apple TV 当前输入框。

第一版交互：

```text
1. 用户在 Apple TV 上手动进入某 App 的搜索框
2. 用户用手机或书房电脑打开 Web Debug Dashboard
3. 用户按住“按住说话”按钮
4. Mac mini 开始录音和识别
5. 用户说：“星际穿越”
6. 用户松开按钮
7. App 停止录音并等待 Apple Speech 最终结果
8. Dashboard 显示识别结果
9. App 自动执行：
   atvremote --id xxxxx text_set="星际穿越"
10. Apple TV 搜索框出现文字
```

---

## 8. Phase 1A 必做功能

### 8.1 macOS Agent

- 常驻运行。
- 请求并管理麦克风权限。
- 请求并管理 Speech Recognition 权限。
- 使用 Apple Speech 识别短句中文。
- 调用 `atvremote --id xxxxx text_set="xxx"`。
- 保存 Apple TV device id。
- 保存基础配置。
- 记录最近日志。
- 启动 Web Debug Dashboard 服务。

---

### 8.2 Web Debug Dashboard

- 显示当前 Agent 状态。
- Push-to-Talk 按住说话。
- 松开后自动识别并发送。
- 显示实时或最终识别文本。
- 显示最近一次发送结果。
- 手动输入文本并发送到 Apple TV。
- 显示最近日志。
- 配置 Apple TV device id。
- 测试 Apple TV `text_set`。

---

### 8.3 macOS 菜单栏 / 设置入口

- 显示 Agent 是否运行。
- 显示 Dashboard 地址。
- 一键打开 Dashboard。
- 查看或修改 Apple TV device id。
- 查看权限状态。
- 查看日志。
- 退出 App。

---

## 9. Phase 1A 暂不做

- 唤醒词。
- 全局快捷键。
- iOS App。
- App Store 沙盒化。
- 多 ASR 引擎。
- 自动打开搜索页面。
- 自动选择视频播放。
- 复杂语义命令。
- 复杂 Web 登录系统。
- 外网访问。
- Dashboard 产品化 UI。

---

## 10. Phase 1A 状态机

```text
idle
listening
finalizing
sending
success
error
```

含义：

- `idle`：空闲。
- `listening`：正在录音。
- `finalizing`：录音结束，等待 Apple Speech 最终结果。
- `sending`：正在发送到 Apple TV。
- `success`：完成，5 秒后自动回到 `idle`。
- `error`：失败，5 秒后自动回到 `idle`。

状态转换：

```text
idle -- ptt.begin --> listening
listening -- ptt.end --> finalizing
finalizing -- recognized text --> sending
sending -- text_set success --> success
success -- 5s timeout --> idle

listening -- ptt.cancel --> idle
any -- fatal error --> error
error -- 5s timeout --> idle
```

客户端轮询策略：

- `/api/status` 返回 `stateSince` 字段（进入当前状态的时间戳）。
- 客户端在 `listening`/`finalizing`/`sending` 时 200ms 快轮询。
- 客户端在 `idle`/`success`/`error` 时 2s 慢轮询。

---

## 11. Push-to-Talk 行为

Dashboard 按钮文案：

```text
按住说话
```

按下时：

```text
正在听...
松开发送
```

松开后：

```text
识别中...
```

发送成功后：

```text
已发送：星际穿越
```

失败时：

```text
发送失败，点击重试
```

浏览器事件映射：

```text
桌面浏览器：
mousedown -> POST /api/ptt/begin
mouseup -> POST /api/ptt/end
mouseleave -> POST /api/ptt/end 或 /api/ptt/cancel

手机浏览器：
touchstart -> POST /api/ptt/begin
touchend -> POST /api/ptt/end
touchcancel -> POST /api/ptt/cancel
```

---

## 12. Phase 1A 保护逻辑

### 12.1 最短录音时长（客户端防误触）

由 Dashboard 前端判断：按住时长 < 300ms 时不调用 `/api/ptt/end`。

服务端不做最短录音时长判断，由客户端控制。

---

### 12.2 最长录音时长

如果按住超过 10 秒：

```text
自动结束录音并进入 finalizing。
```

---

### 12.3 空文本不发送

如果 Apple Speech 返回空文本：

```text
不调用 text_set。
Dashboard 显示：未识别到有效文本。
```

---

### 12.4 并发保护

如果已经处于：

```text
listening / finalizing / sending
```

新的 `ptt.begin` 应该被拒绝。

返回类似：

```json
{
  "ok": false,
  "error": "session_in_progress"
}
```

---

### 12.5 发送失败处理

`AppleTVBridge` 不做内部重试。发送失败时：

- 状态机进入 `error`。
- 记录日志（包含 stdout/stderr）。
- `FeedbackSpeaker` 朗读错误原因，引导用户检查 Apple TV 状态。
- Dashboard 显示错误信息，提供"重发"按钮手动重试。

---

## 13. Web API 设计

### 13.1 状态查询

```http
GET /api/status
```

示例响应：

```json
{
  "state": "idle",
  "stateSince": "2026-05-05T20:30:05+08:00",
  "dashboard": {
    "port": 8765,
    "lanEnabled": true
  },
  "appleTV": {
    "deviceId": "xxxxx",
    "configured": true,
    "lastSendOk": true
  },
  "speech": {
    "microphoneAuthorized": true,
    "speechAuthorized": true
  },
  "lastRecognition": {
    "text": "星际穿越",
    "timestamp": "2026-05-05T20:30:00+08:00"
  },
  "lastError": null
}
```

`stateSince` 为进入当前 state 的时间戳，客户端可用此字段判断状态转移。

---

### 13.2 Push-to-Talk 开始

```http
POST /api/ptt/begin
```

响应：

```json
{
  "ok": true,
  "sessionId": "20260505-001",
  "state": "listening"
}
```

---

### 13.3 Push-to-Talk 结束

```http
POST /api/ptt/end
```

请求：

```json
{
  "sessionId": "20260505-001"
}
```

响应：

```json
{
  "ok": true,
  "state": "finalizing"
}
```

最终识别结果通过 `GET /api/status` 查询。

---

### 13.4 Push-to-Talk 取消

```http
POST /api/ptt/cancel
```

---

### 13.5 手动发送文本

```http
POST /api/apple-tv/send-text
Content-Type: application/json

{
  "text": "星际穿越"
}
```

响应：

```json
{
  "ok": true,
  "text": "星际穿越",
  "message": "sent"
}
```

---

### 13.6 日志查询

```http
GET /api/logs
```

---

### 13.7 配置查询

```http
GET /api/config
```

---

### 13.8 配置更新

```http
POST /api/config
```

可配置项：

- Apple TV device id
- Dashboard port
- Dashboard token
- LAN mode 是否开启

---

## 14. Dashboard 安全边界

Phase 1A 个人项目，不做安全措施：

- 默认监听 `localhost`。
- 需要远程调试时，显式开启 LAN mode。
- LAN mode 监听固定端口，例如 `8765`。
- 不做 token 验证。
- 不做 HTTPS。

不做：

- 用户名密码系统。
- OAuth。
- 外网访问。
- HTTPS。
- 访问 token。

---

## 15. 模块设计

## 15.1 SessionController

职责：

- 管理 Push-to-Talk Session。
- 管理状态机。
- 调用 `SpeechService` 开始 / 停止识别。
- 调用 `TextNormalizer` 清洗文本。
- 调用 `AppleTVBridge` 发送文本。
- 记录日志。
- 对 Dashboard 和 macOS UI 暴露状态。

不负责：

- 直接采集音频。
- 直接执行 `atvremote`。
- 直接处理 HTTP。

---

## 15.2 SpeechService

职责：

- 检查 Speech Recognition 权限。
- 检查麦克风权限。
- 使用 `AVAudioEngine` 采集音频。
- 使用 `SFSpeechRecognizer`（系统默认 locale）做短句识别。
- 返回最终识别文本或分类错误。

第一版使用系统默认 locale（不固定 zh-CN），以支持中英文混杂识别。

错误分类（`SpeechError` 枚举）：

| 错误类型 | 说明 | 可恢复 |
|---------|------|--------|
| `permissionDenied` | 麦克风或语音识别权限未授权 | 否，引导用户去系统设置 |
| `networkUnavailable` | 网络不可用，Apple Speech 需要联网 | 是 |
| `rateLimited` | Apple Speech 限流 | 是，等待后恢复 |
| `microphoneInUse` | 麦克风被其他应用占用 | 是 |
| `noSpeech` | 未检测到语音 | — |
| `recognitionFailed` | 其他识别失败 | — |

注意：

- 保留原始识别结果，便于后续分析。
- 不做多语言识别切换。

---

## 15.3 AppleTVBridge

职责：

- 读取 Apple TV device id（通过 `ConfigStore`）。
- 在 PATH 中查找 `atvremote` 命令。
- 构造命令：

```bash
atvremote --id <device_id> text_set="<text>"
```

- 执行命令。
- 捕获 stdout / stderr。
- 返回成功或失败（不做内部重试）。
- 记录日志。

前置依赖：

```bash
pipx install pyatv
pipx ensurepath
```

首次配对通过终端手动完成：

```bash
atvremote wizard
```

device id 通过菜单栏 UI 或 Dashboard 配置。

atvremote 查找策略：遍历 PATH，找不到则返回明确错误。

---

## 15.4 TextNormalizer

第一版只做轻量处理：

```text
去掉首尾空格
去掉末尾句号、逗号、问号等常见标点
压缩连续空格
保留英文大小写
保留数字
```

示例：

```text
“星际穿越。” -> “星际穿越”
“Rick and Morty。” -> “Rick and Morty”
“速度与激情 7。” -> “速度与激情 7”
```

不要做复杂 NLP。

---

## 15.5 ConfigStore

归属：守护进程是配置的唯一 owner。菜单栏 UI 和 Dashboard 通过 `/api/config` 读写配置。

职责：

- 保存 Apple TV device id。
- 保存 Dashboard port。
- 保存 LAN mode 开关。
- 保存开机自启动开关。
- 保存基础偏好设置。

实现方式：

- Phase 1A 可用 UserDefaults。
- 如果配置变复杂，再迁移到 JSON 文件。

---

## 15.6 LogStore

职责：

- 保存最近 N 条日志。
- Dashboard 可查询。
- macOS 设置界面可查看。

日志至少记录：

- App 启动。
- Dashboard 启动。
- 权限状态。
- PTT begin / end / cancel。
- Apple Speech 结果。
- TextNormalizer 输出。
- `atvremote` 执行命令摘要。
- `atvremote` stdout / stderr。
- 错误信息。

---

## 15.7 FeedbackSpeaker

职责：

- 使用 `NSSpeechSynthesizer`（macOS 内置 TTS）朗读反馈。
- 发送失败时朗读错误原因和修复建议。
- 语音识别失败时朗读错误类型。
- 权限缺失时引导用户去系统设置。

示例朗读文本：

- "发送失败，请检查 Apple TV 是否开机。"
- "语音识别失败，请检查网络连接。"
- "麦克风权限未授权，请在系统设置中开启。"

不负责：

- 唤醒词提示音（Phase 2）。
- 复杂交互语音引导。

---

## 16. Phase 1A 验收标准

### 16.1 功能验收

- App 可在 Mac mini 上启动并常驻。
- Dashboard 可从手机或书房电脑访问。
- Dashboard 可显示当前状态。
- Dashboard 可配置 Apple TV device id。
- Dashboard 可手动发送文本到 Apple TV。
- Dashboard 可按住说话并松开发送。
- Apple TV 当前输入框能收到识别文本。
- 日志能记录完整链路。

---

### 16.2 语音识别验收

测试词库：

```text
星际穿越
权力的游戏
三体
甄嬛传
繁花
奥本海默
速度与激情
哈利波特
指环王
盗梦空间
Rick and Morty
Breaking Bad
Better Call Saul
The Last of Us
Mission Impossible
Spider Man
```

目标：

```text
中文片名准确率 >= 85%
常见中英文片名结果可接受
录音结束到 Apple TV 出现文字 <= 1.5 秒为理想
<= 3 秒为勉强可接受
```

---

### 16.3 Apple TV 输入验收

- `text_set` 成功率 >= 95%。
- 失败时 Dashboard 能显示错误。
- 失败时日志包含可排查信息。

---

### 16.4 Headless 调试验收

- 不需要给 Mac mini 接显示器、键盘、鼠标。
- 可以用手机或书房电脑完成主要验证。
- 不需要在书房操作后跑到客厅才能触发语音识别。

---

# Phase 1B：全局快捷键 Push-to-Talk

## 17. Phase 1B 目标

在 Phase 1A 闭环可用后，增加 macOS 全局快捷键 Push-to-Talk，使用户可以在本机或远程控制环境下通过按键触发语音输入。

目标交互：

```text
按住快捷键 -> 开始听
说片名
松开快捷键 -> 停止听并发送
```

候选快捷键：

```text
Option + Space
F8
自定义快捷键
```

---

## 18. Phase 1B 状态：已跳过

Phase 1B（全局快捷键 Push-to-Talk）已决定跳过。理由：

- 当前产品原型已可用（Dashboard 语音识别 + Apple TV 发送）。
- 用户主要场景在客厅，不在电脑前，全局快捷键价值有限。
- 直接进入 Phase 2 唤醒词，实现真正的免提交互。

Phase 1B 原验收标准保留供未来参考，不做实现。

---

# Phase 2：本地唤醒词（sherpa-onnx）

## 19. Phase 2 目标

在 Phase 1A 可用后，加入本地离线唤醒词，实现完全免提交互。

目标交互：

```text
用户说唤醒词
Mac mini 播放轻提示音
用户说片名
Apple Speech 识别 → TextNormalizer → AppleTVBridge
发送到 Apple TV
```

## 20. Phase 2 技术路线

```text
AVAudioEngine 麦克风输入（常驻）
  ↓
sherpa-onnx Keyword Spotter（本地离线，Swift SPM）
  ↓
唤醒词检测
  ↓
播放提示音 + Apple Speech 短句识别
  ↓
TextNormalizer 文本清洗
  ↓
AppleTVBridge text_set
```

唤醒词引擎：**sherpa-onnx**（替代原方案 Porcupine）

- 完全开源（Apache 2.0），无需付费或注册
- Swift 集成方式：`systemLibrary` + module map（非标准 SPM，需手动集成 dylib 和头文件）
- prebuilt macOS xcframework：`build-swift-macos.sh` 构建或 GitHub Releases 下载
- 中文预训练 KWS 模型：`sherpa-onnx-kws-zipformer-wenetspeech-3.3M-2024-01-01`（mobile int8 ~10MB）
- Silero VAD 模型可选接入（~1.1MB），降低静音时 CPU 占用

## 21. Phase 2 分两阶段

### 阶段一：sherpa-onnx 部署 + Dashboard 测试界面

**目标**：让 sherpa-onnx 在项目中跑通，在 Dashboard 上提供交互式测试面板，用于验证唤醒词方案可行性和调优参数。

**内容**：
- `systemLibrary` + module map 集成 sherpa-onnx xcframework + onnxruntime dylib
- 创建 `KeywordSpotterService` 封装 AVAudioEngine + Silero VAD + sherpa-onnx KWS
- Dashboard 测试面板：关键词输入（支持 ppinyin token 格式）、阈值/boosting 滑块、VAD 语音状态指示、实时检测日志
- 用真实客厅环境测试候选唤醒词，选择最优方案

**验收**：
- Dashboard 上可启动/停止关键词检测
- 实时显示检测到的关键词
- 确定一个唤醒率高、误唤醒低的生产唤醒词

### 阶段二：生产唤醒词集成

**前提**：阶段一验证通过。

**内容**：
- 锁定生产唤醒词和最优阈值
- 接通完整链路：唤醒 → 提示音 → Apple Speech → TextNormalizer → AppleTVBridge
- 8 秒识别超时，超时回到监听
- 常驻运行稳定性（引擎中断恢复、重试、内存管理）
- Dashboard 显示唤醒词服务状态、最后检测时间、最后识别结果

**验收**：
- 说唤醒词 → 提示音 → 说片名 → Apple TV 收到文本，全程免提
- 客厅 2 米距离唤醒率可接受
- 电视背景音下误唤醒可控
- 连续运行 4+ 小时不崩溃、无内存泄漏

## 22. Phase 2 暂不做

- 云端唤醒词。
- 持续 Apple Speech 识别（仍为短句识别）。
- 自定义唤醒词训练（使用预训练模型的开放词汇能力）。
- 复杂命令控制。
- 自动打开 App 搜索页。
- 唤醒词灵敏度 UI 配置（阶段一用 Dashboard 手动调参，阶段二硬编码最优值）。

---

# Phase 3：稳定性与日常使用打磨

## 25. Phase 3 目标

把原型变成自己日常愿意使用的工具。

重点不是增加大功能，而是解决日常使用中的卡顿、失败、误触发、难排查问题。

---

## 26. Phase 3 工作项

- 长时间运行稳定性测试。
- 异常恢复。
- Apple Speech session 失败恢复。
- `atvremote` 失败重试。
- Apple TV 断连提示。
- 日志导出。
- 文本清洗优化。
- 识别结果重发。
- 最近识别历史。
- 权限状态自检。
- 启动时自检。
- Dashboard debug 能力完善。

---

## 27. Phase 3 验收标准

- 可连续运行一周。
- 常见错误有明确提示。
- 不需要频繁重启 App。
- 失败后可恢复。
- 用户能从日志判断问题发生在：
  - 麦克风
  - Apple Speech
  - 文本清洗
  - Apple TV bridge
  - 网络 / 配对

---

# Phase 4：Mac 产品化与上架预研

## 28. Phase 4 目标

评估这个工具是否适合产品化，尤其是未来是否可能进入 Mac App Store。

---

## 29. Phase 4 关键问题

- App Store 沙盒下是否允许调用 `atvremote` CLI。
- 是否能打包 pyatv / atvremote。
- 是否需要改为原生协议实现。
- Speech 权限说明是否符合审核要求。
- 麦克风常驻监听是否会影响审核。
- sherpa-onnx Apache 2.0 授权是否满足发布要求。
- Dashboard 是否应该在正式版移除。
- 是否需要 iOS App 作为正式入口。

---

## 30. Phase 4 可能结论

可能路线 A：继续自用版。

```text
macOS Agent + Dashboard + Wake Word
不追求 App Store
```

可能路线 B：Mac App Store 版。

```text
移除或替代 atvremote CLI
强化权限说明
减少调试入口
产品化 UI
```

可能路线 C：自用版 + iOS 辅助 App。

```text
Mac mini Agent 常驻
 iOS App 作为正式遥控入口
不一定上架 Mac App Store
```

---

## 31. 推荐开发任务拆解

### Task 1：项目骨架和菜单栏 Agent

目标：

- 启动 macOS App。
- 显示菜单栏图标。
- 显示当前状态。
- 提供退出。
- 提供打开 Dashboard 入口。

不做：

- 语音识别。
- Apple TV 控制。
- 唤醒词。

验收：

- App 可启动。
- 菜单栏可见。
- 点击可打开基础窗口或 Dashboard 地址。
- 退出正常。

---

### Task 2：Web Debug Dashboard 骨架

目标：

- 启动本地 HTTP Server。
- 提供静态 Dashboard 页面。
- 提供 `/api/status`。
- Dashboard 能显示 Agent 状态。

验收：

- 手机或电脑可访问 Dashboard。
- 页面显示 `idle`。
- `/api/status` 返回 JSON。

---

### Task 3：AppleTVBridge

目标：

- 封装 `atvremote text_set`。
- 提供手动发送文本接口。
- Dashboard 支持输入文本并发送。
- 记录执行结果和错误。

验收：

- Dashboard 输入“星际穿越”。
- Apple TV 当前输入框出现“星际穿越”。
- 错误能显示在日志里。

---

### Task 4：SpeechService

目标：

- 请求麦克风权限。
- 请求 Speech Recognition 权限。
- 使用 Apple Speech 做一次短句识别。
- 返回最终文本。

注意：

- 此任务先不接 Apple TV。

验收：

- 说“三体”。
- Dashboard 显示“三体”或可接受识别结果。

---

### Task 5：Push-to-Talk SessionController

目标：

- 实现 `ptt.begin`。
- 实现 `ptt.end`。
- 实现状态机。
- 实现识别完成后自动调用 `AppleTVBridge`。

验收：

- Dashboard 按住说话。
- 说“星际穿越”。
- 松开。
- Apple TV 出现文本。
- Dashboard 显示最终状态。

---

### Task 6：配置、日志和错误处理

目标：

- 配置 Apple TV device id。
- 配置 Dashboard token。
- 展示最近日志。
- 处理权限错误。
- 处理 `atvremote` 不存在。
- 处理 Apple Speech 无权限。
- 处理空识别结果。

验收：

- 首次启动可配置 device id。
- 错误信息可读。
- 日志可追踪完整链路。

---

### Task 7：全局快捷键 Push-to-Talk（已跳过）

决定跳过，直接进入 Phase 2。原目标保留供未来参考：

- 实现 Phase 1B。
- 按下快捷键开始，松开结束。
- 复用 `SessionController`。

---

### Task 8：本地唤醒词（Phase 2）

目标：

- 集成 sherpa-onnx 本地唤醒词。
- 阶段一：Dashboard 测试面板验证方案。
- 阶段二：锁定唤醒词，接通完整链路。
- 唤醒后 1 秒内启动 Apple Speech 短句识别。
- 识别结果经 TextNormalizer → AppleTVBridge 发送。

验收：

- Dashboard 可实时测试关键词检测。
- 客厅 2 米距离唤醒率可接受。
- 电视背景音下误唤醒可控。
- 连续运行 4+ 小时稳定。

---

## 32. Claude Code 执行原则

每次只执行一个任务，不要一次性实现整个项目。

每次开发前必须：

- 阅读 `CLAUDE.md`。
- 阅读本文档。
- 复述任务。
- 明确 Phase。
- 明确不做内容。
- 提出计划。
- 等待用户确认。

每次开发后必须：

- 说明完成内容。
- 列出修改文件。
- 给出运行方式。
- 给出测试方式。
- 说明测试结果。
- 对照本文档 review。
- 给出下一步建议。

---

## 33. 当前推荐下一步

Phase 1A 已完成（Task 1–4 + TextNormalizer + LogStore），Phase 1B 已跳过。下一步：

```text
Phase 2 阶段一：sherpa-onnx 部署 + Dashboard 测试界面
```

不要直接实现语音识别或 Apple TV 控制。

先让项目能稳定启动、能显示 Agent 状态、能打开 Dashboard 入口，再进入 Task 2。
