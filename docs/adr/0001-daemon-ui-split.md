# ADR-0001: Agent 拆分为守护进程和菜单栏 UI 两个独立进程

Agent 拆分为两个独立进程：守护进程（后台，负责语音识别、Apple TV 控制、HTTP server）和菜单栏 UI（前台，仅配置和日志查看）。两者通过 localhost HTTP 通信。

## Why

Mac mini 无显示器、无键鼠常驻运行。守护进程需要开机自启动，但 SwiftUI 菜单栏应用依赖 WindowServer（用户登录后才能跑）。

如果单体 app 崩溃或需要重启 UI，整个识别链路中断。拆开后守护进程独立存活，UI 只是可选的配置前端。

## Considered Options

- **A) 单体 SwiftUI App**：简单，但 Mac mini headless 场景下菜单栏依赖 WindowServer，且无法开机自启。崩溃时全部中断。
- **B) 守护进程 + 菜单栏 UI 两个独立进程**：守护进程可开机自启动，UI 可选。多了一些 IPC 样板，但两者通过同一套 HTTP API 通信，和 Dashboard 共用接口，实际成本低。
- **C) LaunchAgent + XPC Service**：macOS 原生 IPC，但需要定义 XPC protocol、配置 plist，过度工程。且未来换远程 Agent 需要重写通信层。

选 B —— 守护进程开机自启、UI 可选、HTTP 通信统一，未来换远程 Agent 零改动。
