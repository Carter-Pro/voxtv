# CLAUDE.md

本文件定义 Claude Code 在本项目中的工作方式、边界和交付标准。所有开发任务开始前，必须先阅读本文件和 `docs/technical-plan.md`。

---

## 1. 项目定位

这是一个运行在 Mac mini 上的 macOS Apple TV Voice Agent。

核心目标：

> 通过 Apple Speech 识别用户短句语音，并通过 `atvremote` 向 Apple TV 当前输入框发送文本。

当前项目阶段不开发 iOS App，不开发完整商业化产品 UI，不做多 ASR 引擎，不做自动控制 tvOS App UI。

---

## 2. 核心架构原则

1. **macOS Agent 是核心。**
2. **Web Dashboard 只是 Phase 1A 调试入口，不是正式产品入口。**
3. **macOS 菜单栏 / 设置界面主要用于配置、权限状态、日志查看、打开 Dashboard。**
4. **Apple TV 控制必须通过独立 `AppleTVBridge` 封装。**
5. **Apple Speech 识别必须通过独立 `SpeechService` 封装。**
6. **Push-to-Talk 与识别流程必须由 `SessionController` 管理。**
7. Web Dashboard 只能调用 Agent 暴露的 API，不允许直接访问底层实现细节。
8. 不允许把 Phase 2 的唤醒词逻辑提前塞进 Phase 1A。
9. 不允许把 iOS App 相关代码加入当前仓库。
10. 所有阶段必须保持小步可运行、可测试、可回滚。

---

## 3. 当前技术栈

- macOS App：Swift / SwiftUI
- Speech Recognition：Apple Speech Framework
- Audio Capture：AVAudioEngine
- Apple TV Control：`atvremote` CLI
- Web Debug Dashboard：embedded local HTTP server + static HTML/CSS/JS
- Config：UserDefaults 或本地 JSON 文件
- Logs：in-memory ring buffer，必要时再加本地文件日志

---

## 4. atvremote 命令约束

发送文本必须使用：

```bash
atvremote --id <device_id> text_set="<text>"
```

不要使用其他未经项目验证的命令格式。

`AppleTVBridge` 必须负责：

- 构造命令
- 执行命令
- 捕获 stdout / stderr
- 返回成功或失败
- 记录日志

上层模块不应该直接拼接或执行 `atvremote` 命令。

---

## 5. Phase 边界

### Phase 0：Apple TV 控制链路验证

状态：已完成。

已验证：

- Mac mini 可发现并配对 Apple TV
- 开机、关机、文本输入均可用
- `text_set` 可成功向 Apple TV 当前输入框发送中文文本

---

### Phase 1A：Apple Speech + Web Debug Dashboard + text_set 闭环

实现：

- macOS Agent 基础框架
- Apple Speech 短句识别
- AVAudioEngine 麦克风采集
- Web Debug Dashboard
- Dashboard Push-to-Talk 按住说话
- 手动文本发送到 Apple TV
- Apple TV device id 配置
- 日志查看
- 状态查看
- 菜单栏入口用于配置、状态、打开 Dashboard

不实现：

- 唤醒词
- 全局快捷键
- iOS App
- App Store 沙盒化
- 多 ASR 引擎
- 自动打开搜索页
- 自动选择影片播放
- 复杂 Web 登录系统

---

### Phase 1B：全局快捷键 Push-to-Talk

实现：

- macOS 全局快捷键触发 Push-to-Talk
- 按下开始录音
- 松开结束录音
- 复用 Phase 1A 的 `SessionController`

不实现：

- 唤醒词
- iOS App
- 自动控制 tvOS App UI

---

### Phase 2：Porcupine 本地唤醒词

实现：

- 本地唤醒词监听
- 唤醒后启动 Apple Speech 短句识别
- 提示音
- 误唤醒 / 漏唤醒调试

不实现：

- 云端唤醒词
- 长时间持续 Apple Speech 识别
- 复杂语义控制

---

### Phase 3：稳定性与日常使用打磨

实现：

- 长时间运行稳定性
- 错误恢复
- 日志导出
- 配置持久化完善
- 客厅真实环境测试
- 文本清洗优化

---

### Phase 4：Mac 产品化与上架预研

实现：

- App Store 沙盒可行性评估
- 权限说明
- 打包方式评估
- 是否需要绕开或替代 `atvremote` CLI 的预研

---

## 6. 推荐模块边界

### `SessionController`

负责：

- Push-to-Talk 生命周期
- 状态机管理
- 调用 `SpeechService`
- 调用 `TextNormalizer`
- 调用 `AppleTVBridge`
- 对外暴露当前状态

状态机：

```text
idle -> listening -> finalizing -> sending -> success/error
```

---

### `SpeechService`

负责：

- 麦克风权限检查
- Speech Recognition 权限检查
- AVAudioEngine 采集
- Apple Speech 识别
- 返回最终识别文本

不负责：

- Apple TV 控制
- Dashboard API
- 文本发送

---

### `AppleTVBridge`

负责：

- `atvremote` 路径检查
- device id 配置读取
- 发送文本
- 记录执行结果

不负责：

- 语音识别
- UI
- Push-to-Talk 状态机

---

### `TextNormalizer`

负责轻量文本清洗：

- 去除首尾空格
- 去除末尾常见标点
- 压缩连续空格
- 保留中文、英文、数字

不要做复杂 NLP。

---

### `ConfigStore`

负责：

- Apple TV device id
- Dashboard port
- Dashboard token
- 基础偏好设置

---

### `LogStore`

负责：

- 保存最近 N 条日志
- 给 Dashboard 和 macOS UI 查询
- 记录关键链路事件

---

## 7. Web Dashboard 定位

Web Dashboard 是 Phase 1A 的调试入口，不是正式产品入口。

它应该支持：

- 查看当前状态
- Push-to-Talk 按住说话
- 手动输入文本并发送
- 查看最近识别结果
- 查看最近日志
- 配置 Apple TV device id
- 测试 Apple TV text_set

它不应该支持：

- 用户系统
- 外网访问
- 复杂 UI
- iOS App 替代品设计
- 长期产品化功能

---

## 8. Web API 建议

```http
GET  /api/status
GET  /api/logs
GET  /api/config
POST /api/config
POST /api/ptt/begin
POST /api/ptt/end
POST /api/ptt/cancel
POST /api/apple-tv/send-text
```

Push-to-Talk 语义：

```text
mousedown / touchstart -> POST /api/ptt/begin
mouseup / touchend     -> POST /api/ptt/end
mouseleave / cancel    -> POST /api/ptt/cancel 或 /api/ptt/end
```

---

## 9. 工作流程要求

每次收到任务后，必须按以下流程执行：

1. 先阅读 `CLAUDE.md` 和 `docs/technical-plan.md`。
2. 用自己的话复述任务目标。
3. 明确本次任务属于哪个 Phase。
4. 明确本次不会做什么。
5. 列出将新增或修改的文件。
6. 给出分步骤实现计划。
7. 等待用户确认后再写代码。
8. 写代码时保持最小变更。
9. 写完后运行构建和测试。
10. 如果无法运行测试，说明原因，并给出手动验证步骤。
11. 最后对照设计文档做交付 review。

---

## 10. 禁止行为

- 不要跳过计划直接写代码。
- 不要擅自改变 Phase 范围。
- 不要引入重型依赖，除非先说明理由并获得确认。
- 不要把 Dashboard 做成正式产品入口。
- 不要把配置写死在代码里。
- 不要吞掉错误。
- 不要只报告“完成了”，必须说明如何验证。
- 不要在没有测试的情况下声称功能正常。
- 不要提前实现唤醒词、iOS App、Whisper、多 ASR 引擎。
- 不要顺手做未要求的优化、重构或扩展功能。

如认为需要额外改动，必须先说明理由并等待确认。

---

## 11. 每次任务开始时必须输出

```markdown
## 我对任务的理解

本次任务是……
本次属于 Phase ……
本次完成后应该可以……

## 本次明确不做

- ...

## 实现计划

1. ...
2. ...
3. ...

## 预计修改文件

- ...

## 验证方式

- 自动测试：...
- 手动验证：...
```

必须等待用户确认后再开始写代码。

---

## 12. 每次交付时必须输出

```markdown
## 本次完成内容

- ...

## 修改文件

- ...

## 如何运行

...

## 如何测试

...

## 测试结果

- 构建：通过 / 未通过
- 自动测试：通过 / 未运行，原因是...
- 手动验证：...

## 设计文档核对

- 是否仍符合当前 Phase 范围：是/否
- 是否引入了 Phase 外内容：是/否
- 是否保持 Dashboard 只是调试入口：是/否
- 是否通过 AppleTVBridge 封装 atvremote：是/否/不涉及
- 是否通过 SpeechService 封装 Apple Speech：是/否/不涉及

## 已知问题

- ...

## 下一步建议

- ...
```

---

## 13. 测试策略

### 自动测试适合覆盖

- `TextNormalizer`
- `ConfigStore`
- `LogStore`
- `SessionController` 状态机
- `AppleTVBridge` 命令构造
- API JSON 格式

### 半自动测试适合覆盖

- HTTP Server 是否启动
- `/api/status` 是否返回
- Dashboard 是否能打开
- `atvremote` 是否存在
- Apple TV device id 是否配置

### 必须手动验收

- 麦克风权限
- Apple Speech 中文识别
- 客厅 2 米识别效果
- Apple TV 当前输入框 `text_set`
- 电视背景音干扰

---

## 14. 推荐 Git 提交节奏

每个小闭环一个 commit：

```text
commit 1: create macOS menu bar agent skeleton
commit 2: add embedded debug dashboard server
commit 3: add AppleTVBridge text_set support
commit 4: add Apple Speech one-shot recognition
commit 5: add push-to-talk session controller
commit 6: add config and log viewer
```

任何一步失败，应优先修复当前闭环，不要继续堆功能。

---

## 15. Agent skills

### Issue tracker

Issues are tracked in GitHub. See `docs/agents/issue-tracker.md`.

### Triage labels

Uses the canonical defaults: needs-triage, needs-info, ready-for-agent, ready-for-human, wontfix. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context layout — one `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.
