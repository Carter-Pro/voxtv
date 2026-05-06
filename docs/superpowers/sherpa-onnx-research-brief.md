# sherpa-onnx 调研任务

## 背景

我在开发一个 macOS Swift 语音代理应用（Voxtv），目前需要集成 sherpa-onnx 的关键词检测（keyword spotting）功能作为唤醒词方案。

这不是一个通用的调研——目标非常具体：

> 在 macOS Swift 6 项目中（使用 `swift build` 构建，不是 Xcode），通过 sherpa-onnx 实现本地离线唤醒词检测。

## 你需要做的

1. 深入阅读你面前这个 sherpa-onnx 仓库
2. 聚焦以下问题，给出可直接指导开发的答案
3. 输出到 `/Users/carter/Programs/voxtv/docs/sherpa-onnx-reference.md`

## 你的任务清单

按优先级排序：

### 1. Swift API 完整参考

找到实际的 Swift API 源码（可能在 `swift-api-examples/SherpaOnnx.swift` 或 `swift-api/` 目录下），列出：

- 所有与 **keyword spotting** 相关的类/结构体/枚举（忽略 ASR、TTS、VAD 等无关功能）
- 每个类型的完整公开 API：初始化参数、方法签名、属性
- Swift 和底层 C API 之间的 import/module 关系
- 特别注意：`SherpaOnnxKeywordSpotter` 或类似名称的类的构造函数需要哪些参数

### 2. 关键词配置

- 关键词文件的完整格式规范（中文 `ppinyin` 和英文 `bpe` 两种 token 类型都要）
- `sherpa-onnx-cli text2token` 命令行工具的具体用法和参数
- boosting score 和 trigger threshold 的实际效果和调优建议
- 能否在运行时动态切换关键词列表而不重新加载模型？

### 3. VAD（语音活动检测）

我们需要知道：

- sherpa-onnx 的 VAD 模块类名和 API（Swift 端）
- VAD 和 KWS 如何串联？是先 VAD → 有语音再 KWS，还是并行？
- VAD 的配置参数（静音阈值、语音持续时间等）
- Silero VAD 模型从哪里下载？是否已经打包在预编译库中？
- 有没有 VAD + KWS 串联的官方示例代码？
- CPU 开销对比：纯 KWS vs VAD+KWS 串联

### 4. 模型文件

- 中文 KWS 预训练模型的完整下载链接和文件清单
- 每个文件的作用（encoder.onnx、decoder.onnx、joiner.onnx、tokens.txt）
- 有没有更小/更适合 macOS 的模型变体？
- 模型加载的性能特征（启动时间、内存占用）

### 5. macOS 集成路径

- 仓库的 `build-swift-macos.sh` 或 `build-macos.sh` 脚本做了什么？
- 有没有预编译的 macOS dylib 或 XCFramework？在哪里下载？
- 如果用 SPM 的 `systemLibrary` + module map 集成，需要哪些头文件和 dylib？
- `swift-api-examples/` 下的示例项目是如何组织的？（Xcode 工程？Package.swift？直接编译？）

### 6. 示例代码提取

从仓库中找到所有与 keyword spotting 相关的示例代码：
- Swift 示例（如果有）
- C API 示例
- 提取完整可编译的最小示例代码

## 边界：忽略以下内容

- ASR（语音识别）、TTS（语音合成）的实现细节（VAD 除外，VAD 是我们需要的）
- Python、C#、Go、Dart 等语言的 API
- 模型训练细节
- iOS 特定的内容（除非明确标注也适用于 macOS）
- 编译原理、ONNX Runtime 内部实现
- sherpa-onnx 的整体架构设计文档

## 输出格式

输出到 `/Users/carter/Programs/voxtv/docs/sherpa-onnx-reference.md`，按以下结构组织：

```
# sherpa-onnx macOS Swift 集成参考

## 1. Swift API 参考
### 1.1 Keyword Spotter 类型
### 1.2 相关枚举/配置结构体

## 2. 关键词配置
### 2.1 关键词文件格式
### 2.2 text2token 工具
### 2.3 参数调优

## 3. VAD 语音活动检测
### 3.1 VAD API 参考
### 3.2 VAD + KWS 串联方式
### 3.3 VAD 配置参数

## 4. 模型
### 4.1 可用模型列表
### 4.2 文件清单和用途
### 4.3 下载方式

## 5. macOS 集成
### 5.1 依赖库获取
### 5.2 SPM 集成方式
### 5.3 示例项目结构

## 6. 最小示例
### 6.1 Swift 示例
### 6.2 命令行验证方式
```

每个章节给出**具体可操作的代码、命令、文件路径**，不要泛泛而谈。

## 关键原则

- 我们是 SPM 项目（`Package.swift` + `swift build`），不是 Xcode 项目。优先给出适合 SPM 的集成方式
- 我们只需要 keyword spotting，不要输出 ASR/TTS/VAD 的内容浪费篇幅
- 代码示例要完整、可编译，不要留"..."省略
- 文件路径必须是仓库中的真实路径
