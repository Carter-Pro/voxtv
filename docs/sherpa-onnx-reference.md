# sherpa-onnx macOS Swift 集成参考

## 1. Swift API 参考

sherpa-onnx 的 Swift API 位于仓库的 `swift-api-examples/` 目录，通过桥接头文件导入 C API。**没有 Package.swift**——官方使用 `swiftc` 直接编译。

源文件：`swift-api-examples/SherpaOnnx.swift`（2250 行），KWS 相关部分在 1520–1634 行。

### 1.1 Keyword Spotter 类型

#### SherpaOnnxKeywordSpotterWrapper

主类，封装了 keyword spotter 引擎和流。

```swift
class SherpaOnnxKeywordSpotterWrapper {
    let spotter: OpaquePointer!   // C 层 spotter 句柄
    var stream: OpaquePointer!    // C 层 stream 句柄

    // 构造函数：接受配置指针，创建 spotter 和 stream
    init(config: UnsafePointer<SherpaOnnxKeywordSpotterConfig>!)

    deinit  // 销毁 stream，然后销毁 spotter

    // 喂入音频样本（必须是 16kHz 单声道 32-bit float PCM）
    func acceptWaveform(samples: [Float], sampleRate: Int = 16000)

    // 检查 stream 是否有足够帧进行解码
    func isReady() -> Bool

    // 执行一次神经网络推理 + 解码
    func decode()

    // 检测到关键词后必须立即调用 reset()
    func reset()

    // 获取当前关键词检测结果
    func getResult() -> SherpaOnnxKeywordResultWrapper

    // 信号：不再有音频输入（文件处理完时调用）
    func inputFinished()
}
```

**典型调用流程**（循环处理音频流）：

```
acceptWaveform(samples) → isReady() → decode() → getResult() → reset()
```

#### SherpaOnnxKeywordResultWrapper

封装检测结果。

```swift
class SherpaOnnxKeywordResultWrapper {
    let result: UnsafePointer<SherpaOnnxKeywordResult>!

    var keyword: String     // 触发到的关键词文本。无触发时为空字符串 ""
    var count: Int32        // 解码出的 token 数量
    var tokens: [String]    // token 数组

    init(result: UnsafePointer<SherpaOnnxKeywordResult>!)
    deinit
}
```

判断是否触发关键词：检查 `getResult().keyword != ""`。

### 1.2 配置辅助函数

#### sherpaOnnxKeywordSpotterConfig

构建 `SherpaOnnxKeywordSpotterConfig` C 结构体。

```swift
func sherpaOnnxKeywordSpotterConfig(
    featConfig: SherpaOnnxFeatureConfig,
    modelConfig: SherpaOnnxOnlineModelConfig,
    keywordsFile: String,
    maxActivePaths: Int = 4,
    numTrailingBlanks: Int = 1,
    keywordsScore: Float = 1.0,
    keywordsThreshold: Float = 0.25,
    keywordsBuf: String = "",
    keywordsBufSize: Int = 0
) -> SherpaOnnxKeywordSpotterConfig
```

#### sherpaOnnxFeatureConfig

```swift
func sherpaOnnxFeatureConfig(
    sampleRate: Int = 16000,
    featureDim: Int = 80
) -> SherpaOnnxFeatureConfig
```

#### sherpaOnnxOnlineModelConfig

```swift
func sherpaOnnxOnlineModelConfig(
    tokens: String,
    transducer: SherpaOnnxOnlineTransducerModelConfig =
        sherpaOnnxOnlineTransducerModelConfig(),
    numThreads: Int = 1,
    provider: String = "cpu",
    debug: Int = 0,
    modelType: String = "",
    modelingUnit: String = "cjkchar",
    bpeVocab: String = ""
) -> SherpaOnnxOnlineModelConfig
```

#### sherpaOnnxOnlineTransducerModelConfig

```swift
func sherpaOnnxOnlineTransducerModelConfig(
    encoder: String = "",
    decoder: String = "",
    joiner: String = ""
) -> SherpaOnnxOnlineTransducerModelConfig
```

### 1.3 C 层结构体对应关系

Swift 导入的 C 头文件：`sherpa-onnx/c-api/c-api.h`（通过 `SherpaOnnx-Bridging-Header.h` 桥接）。

| Swift 类型 | C 结构体 | 说明 |
|---|---|---|
| `SherpaOnnxKeywordSpotterConfig` | `SherpaOnnxKeywordSpotterConfig` | 关键词检测配置 |
| `SherpaOnnxKeywordResult` | `SherpaOnnxKeywordResult` | 检测结果 |
| `SherpaOnnxFeatureConfig` | `SherpaOnnxFeatureConfig` | 特征提取配置 |
| `SherpaOnnxOnlineModelConfig` | `SherpaOnnxOnlineModelConfig` | 在线模型配置 |
| `SherpaOnnxOnlineTransducerModelConfig` | `SherpaOnnxOnlineTransducerModelConfig` | Transducer 模型路径 |

关键：keyword spotting 只有 **online（流式）** 模式，没有 offline 模式。`feat_config` 和 `model_config` 全部走 online 路径。

---

## 2. 关键词配置

### 2.1 关键词文件格式

`keywords.txt` 是一个纯文本文件，每行一个关键词。每个 token 由空格分隔。支持三个可选的附加字段：

| 字段 | 格式 | 作用 |
|---|---|---|
| `:score` | `:2.0` | 提升该关键词在 beam search 中的存活概率（越大越容易命中） |
| `#threshold` | `#0.6` | 该关键词的触发概率阈值（越大越难触发） |
| `@phrase` | `@小爱同学` | 触发时显示的原始文本（否则显示 token 序列） |

#### ppinyin 格式（中文，Wenetspeech 模型）

```
x iǎo ài t óng x ué :2.0 #0.6 @小爱同学
n ǐ h ǎo w èn w èn :3.5 @你好问问
x iǎo y ì x iǎo y ì #0.6 @小艺小艺
```

中文使用部分拼音（ppinyin），将拼音拆分为声母和韵母，以空格分隔。

#### BPE 格式（英文，Gigaspeech 模型）

```
▁HE LL O ▁WORLD :1.5 #0.4
▁HI ▁GO O G LE :2.0 #0.8
▁HE Y ▁S I RI #0.35
```

英文使用 BPE token，`▁` 表示词首。注意令牌中含有空格字符作为词边界标记。

#### 通过 `keywordsBuf` 内联传关键词

无需文件，直接在内存中传递关键词字符串。多关键词用 `/` 分隔：

```swift
// 单个关键词
let keywords = "y ǎn y uán @演员"

// 多个关键词
let keywords = "y ǎn y uán @演员/zh ī m íng @知名"
```

在 Swift 中通过 `keywordsBuf` 和 `keywordsBufSize` 参数传入 `sherpaOnnxKeywordSpotterConfig()`。

### 2.2 text2token 工具

将自然语言短语转换为 token 格式的命令行工具。

#### 安装和运行

```bash
pip install sherpa-onnx
sherpa-onnx-cli text2token \
    --text input.txt \
    --tokens tokens.txt \
    --tokens-type ppinyin \
    --output keywords.txt
```

或使用仓库中的独立脚本：

```bash
python3 scripts/text2token.py \
    --text input.txt \
    --tokens tokens.txt \
    --tokens-type bpe \
    --bpe-model bpe.model \
    --output keywords.txt
```

#### 参数说明

| 参数 | 必需 | 说明 |
|---|---|---|
| `--text` | 是 | 输入文件，每行一个短语（可含 `:score`、`#threshold`、`@phrase` 附加字段） |
| `--tokens` | 是 | 模型对应的 tokens.txt 文件路径 |
| `--tokens-type` | 是 | 可选值：`cjkchar`、`bpe`、`cjkchar+bpe`、`fpinyin`（全拼音带声调）、`ppinyin`（部分拼音，声韵分离）、`phone+ppinyin` |
| `--bpe-model` | bpe 类型时必需 | BPE 模型文件路径（`bpe.model`） |
| `--lexicon` | phone+ppinyin 时必需 | 词典文件路径 |
| `--output` | 是 | 输出文件路径 |

#### 输入输出示例

**输入**（中文，tokens_type = ppinyin）：
```
小爱同学 :2.0 #0.6 @小爱同学
你好问问 :3.5 @你好问问
```

**输出**：
```
x iǎo ài t óng x ué :2.0 #0.6 @小爱同学
n ǐ h ǎo w èn w èn :3.5 @你好问问
```

**输入**（英文，tokens_type = bpe）：
```
HELLO WORLD :1.5 #0.4
HEY SIRI #0.35
```

**输出**：
```
▁HE LL O ▁WORLD :1.5 #0.4
▁HE Y ▁S I RI #0.35
```

### 2.3 参数调优

#### 默认值

| 参数 | 默认值 | 说明 |
|---|---|---|
| `max_active_paths` | 4 | Beam search 路径数。增大可提高召回但增加计算量 |
| `keywords_score` | 1.0 | 全局 boosting score。增大使所有关键词更容易被触发 |
| `keywords_threshold` | 0.25 | 全局触发阈值。增大使触发更保守（减少误触发） |
| `num_trailing_blanks` | 1 | 关键词匹配后的 trailing blank 帧数 |

#### 触发逻辑

检测到关键词需同时满足两个条件（见 `sherpa-onnx/csrc/transducer-keyword-decoder.cc`）：
1. 匹配到的 token 序列的平均概率 >= `keywords_threshold`
2. trailing blank 帧数 > `num_trailing_blanks`

每个关键词可以单独设置 score 和 threshold，覆盖全局默认值。

#### 调优建议

- **误触发太多**：降低 `keywords_score` 或提高 `keywords_threshold`
- **漏触发太多**：提高 `keywords_score` 或降低 `keywords_threshold`
- **特定关键词**：在 keywords 文件中对该关键词单独调优，如 `:3.0 #0.15`

### 2.4 运行时动态切换关键词

**支持。** 通过 `SherpaOnnxCreateKeywordStreamWithKeywords()` 创建携带不同关键词的新 stream，不需要重新加载模型。

在 Swift 层，当前 `SherpaOnnxKeywordSpotterWrapper` 的 init 只调用 `SherpaOnnxCreateKeywordStream`（使用预定义关键词）。如需运行时切换，需要扩展 Swift wrapper 增加一个创建带关键词 stream 的方法。C API 已提供：

```c
SherpaOnnxCreateKeywordStreamWithKeywords(spotter, "y ǎn y uán @演员/zh ī m íng @知名");
```

stream 切换的开销极低（只是重置解码状态并注入新的关键词 graph），不涉及模型重新加载。

---

## 3. VAD 语音活动检测

### 3.1 VAD API 参考

sherpa-onnx 支持两种 VAD 模型：**Silero VAD** 和 **Ten VAD**。Swift 端共用相同的 API。

#### SherpaOnnxVoiceActivityDetectorWrapper

```swift
class SherpaOnnxVoiceActivityDetectorWrapper {
    private let vad: OpaquePointer

    // config: VAD 模型配置指针；buffer_size_in_seconds: 内部缓冲区时长（秒）
    init(config: UnsafePointer<SherpaOnnxVadModelConfig>, buffer_size_in_seconds: Float)

    // 喂入音频样本
    func acceptWaveform(samples: [Float])

    // 是否有已完成的语音段待处理
    func isEmpty() -> Bool

    // 当前是否检测到语音
    func isSpeechDetected() -> Bool

    // 弹出队列中的第一个语音段
    func pop()

    // 清空所有待处理语音段
    func clear()

    // 获取队列中第一个语音段（不弹出）
    func front() -> SherpaOnnxSpeechSegmentWrapper

    // 重置检测器状态
    func reset()

    // 冲刷缓冲区，完成最后的语音段
    func flush()
}
```

#### SherpaOnnxSpeechSegmentWrapper

```swift
class SherpaOnnxSpeechSegmentWrapper {
    var start: Int          // 语音段起始采样点索引
    var n: Int              // 语音段采样点数
    var samples: [Float]    // 语音段的 PCM 样本
}
```

#### SherpaOnnxCircularBufferWrapper

用于外部管理音频缓冲区的辅助类：

```swift
class SherpaOnnxCircularBufferWrapper {
    init(capacity: Int)
    func push(samples: [Float])
    func get(startIndex: Int, n: Int) -> [Float]
    func pop(n: Int)
    func size() -> Int
    func reset()
}
```

#### VAD 配置函数

```swift
func sherpaOnnxSileroVadModelConfig(
    model: String = "",                    // silero_vad.onnx 路径
    threshold: Float = 0.5,                // 语音概率阈值
    minSilenceDuration: Float = 0.25,      // 最小静音时长（秒），用于关闭语音段
    minSpeechDuration: Float = 0.5,        // 最小语音时长（秒），用于保留语音段
    windowSize: Int = 512,                 // 输入窗口大小（采样点数）
    maxSpeechDuration: Float = 5.0         // 最大语音持续时长（秒），超时强制分割
) -> SherpaOnnxSileroVadModelConfig

func sherpaOnnxTenVadModelConfig(
    model: String = "",
    threshold: Float = 0.5,
    minSilenceDuration: Float = 0.25,
    minSpeechDuration: Float = 0.5,
    windowSize: Int = 256,                 // Ten VAD 通常用 256
    maxSpeechDuration: Float = 5.0
) -> SherpaOnnxTenVadModelConfig

func sherpaOnnxVadModelConfig(
    sileroVad: SherpaOnnxSileroVadModelConfig,
    sampleRate: Int32 = 16000,
    numThreads: Int = 1,
    provider: String = "cpu",
    debug: Int = 0,
    tenVad: SherpaOnnxTenVadModelConfig
) -> SherpaOnnxVadModelConfig
```

### 3.2 VAD + KWS 串联方式

**仓库中没有官方的 VAD + KWS 串联示例。** 需要自行实现。推荐方案：

#### 推荐方案：VAD 先分割 → KWS 处理每个语音段

```
麦克风输入 → VAD → 语音段(samples) → KWS(acceptWaveform → decode → getResult) → 唤醒词触发
```

**流程伪代码**：

```swift
// 1. 创建 VAD
var sileroCfg = sherpaOnnxSileroVadModelConfig(model: "silero_vad.onnx", threshold: 0.25)
var vadCfg = sherpaOnnxVadModelConfig(sileroVad: sileroCfg)
let vad = SherpaOnnxVoiceActivityDetectorWrapper(config: &vadCfg, buffer_size_in_seconds: 30)

// 2. 创建 KWS
var kwsConfig = sherpaOnnxKeywordSpotterConfig(featConfig: featConfig, modelConfig: modelConfig, keywordsFile: "keywords.txt")
let kws = SherpaOnnxKeywordSpotterWrapper(config: &kwsConfig)

// 3. 音频循环
while let samples = getNextAudioChunk() {
    vad.acceptWaveform(samples: samples)

    // 处理已完成的语音段
    while !vad.isEmpty() {
        let segment = vad.front()
        vad.pop()

        // 将语音段喂入 KWS
        kws.acceptWaveform(samples: segment.samples)

        // 尾部加静音
        let padding = [Float](repeating: 0.0, count: 3200)
        kws.acceptWaveform(samples: padding)
        kws.inputFinished()

        // 解码循环
        while kws.isReady() {
            kws.decode()
            let result = kws.getResult()
            if result.keyword != "" {
                print("唤醒词: \(result.keyword)")
                kws.reset()
                // 触发唤醒回调...
            }
        }
    }
}
vad.flush()
// 处理最后剩余的语音段...
```

#### 替代方案：KWS 持续运行 + VAD 作为可选的省电层

直接让 KWS 持续接收音频，不经过 VAD。KWS 引擎本身对非语音段不会误触发（关键词的声学模型表示与噪音、静音不匹配）。VAD 仅用作"暂停 KWS 推理"的省电开关：

- VAD 检测到语音 → 启动 KWS 推理
- VAD 检测到静音超过阈值 → 暂停 KWS 推理

这种方案更简单但省电效果不如"先分割再 KWS"。

### 3.3 VAD 配置参数调优

| 参数 | 默认值 | 作用 | 调优建议 |
|---|---|---|---|
| `threshold` | 0.5 | 语音概率阈值。Silero VAD 对每帧输出 0-1 概率 | 降低到 0.25 可提高灵敏度，减少漏检 |
| `min_speech_duration` | 0.5s | 短于此值的语音段被丢弃 | 唤醒词通常不到 1 秒，建议设为 0.1–0.25s |
| `min_silence_duration` | 0.25s (Swift) / 0.5s (C) | 用于判断语音段结束的静音时长 | 减小可更快截断，增大可避免句中停顿被截断 |
| `max_speech_duration` | 5.0s (Swift) / 20.0s (C) | 超时强制分割 | 对唤醒词场景影响不大（唤醒词很短） |
| `window_size` | 512 (Silero) / 256 (Ten) | 每帧输入采样点数 | Silero 必须用 512，Ten VAD 用 256 |

### 3.4 Silero VAD 模型下载

Silero VAD 模型不打包在 sherpa-onnx 中，需单独下载。

从 sherpa-onnx 的模型下载脚本和测试代码中可以提炼出下载地址：

```
https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx
```

或从 sherpa-onnx 的 `scripts/` 目录中的模型管理脚本获取。silero_vad.onnx 约 1.1 MB，非常轻量。

Ten VAD 模型更小（约 100 KB），适合移动/嵌入式场景。

### 3.5 CPU 开销对比

| 模式 | CPU 占用 | 说明 |
|---|---|---|
| 纯 KWS | 低 | KWS 在无语音输入时也在做推理，但 transducer 模型很小（3.3M 参数），开销可控 |
| VAD 串联 KWS | 更低 | VAD 在静音时阻止 KWS 推理。VAD 本身开销可忽略（Silero VAD 极小） |

对于 macOS 桌面应用，3.3M 参数的 KWS 模型 CPU 开销很低——几个百分点单核占用。在 Apple Silicon 上通过 CoreML 推理会更快。

---

## 4. 模型

### 4.1 可用模型列表

| 模型名称 | 语言 | Token 类型 | 参数量 | 发布标签 |
|---|---|---|---|---|
| `sherpa-onnx-kws-zipformer-wenetspeech-3.3M-2024-01-01` | 中文 | ppinyin | ~3.3M | `kws-models` |
| `sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01` | 英文 | BPE | ~3.3M | `kws-models` |

每个模型有两个变体：

| 变体 | 说明 |
|---|---|
| 标准版 | 全部 FP32 ONNX 模型 |
| `-mobile` 后缀 | encoder 和 joiner 使用 int8 量化，decoder 保持 FP32，体积更小，适合设备端 |

### 4.2 文件清单和用途

以中文模型为例，下载后得到：

```
sherpa-onnx-kws-zipformer-wenetspeech-3.3M-2024-01-01/
├── encoder-epoch-12-avg-2-chunk-16-left-64.onnx   # 编码器：声学特征→编码状态
├── decoder-epoch-12-avg-2-chunk-16-left-64.onnx   # 解码器：联合编码状态和预测进行解码
├── joiner-epoch-12-avg-2-chunk-16-left-64.onnx    # joiner：连接编码器和解码器的投影层
├── tokens.txt                                      # 词汇表，token ID ↔ token 文本映射
├── test_wavs/                                      # 测试音频
│   ├── 3.wav
│   └── test_keywords.txt                           # 示例关键词文件
├── bpe.model                        # 仅英文模型有，用于 BPE 分词
└── README.md
```

Mobile 变体中 encoder 和 joiner 为 `*.int8.onnx`。

### 4.3 下载方式

#### 从 GitHub Releases 下载

```bash
# 中文模型（标准版）
curl -SL -O https://github.com/k2-fsa/sherpa-onnx/releases/download/kws-models/sherpa-onnx-kws-zipformer-wenetspeech-3.3M-2024-01-01.tar.bz2
tar xf sherpa-onnx-kws-zipformer-wenetspeech-3.3M-2024-01-01.tar.bz2

# 中文模型（mobile 量化版）
curl -SL -O https://github.com/k2-fsa/sherpa-onnx/releases/download/kws-models/sherpa-onnx-kws-zipformer-wenetspeech-3.3M-2024-01-01-mobile.tar.bz2
tar xf sherpa-onnx-kws-zipformer-wenetspeech-3.3M-2024-01-01-mobile.tar.bz2

# 英文模型（mobile 量化版）
curl -SL -O https://github.com/k2-fsa/sherpa-onnx/releases/download/kws-models/sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01-mobile.tar.bz2
tar xf sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01-mobile.tar.bz2
```

#### macOS 桌面应用推荐

- **中文唤醒词**：使用 mobile 量化版，3.3M 参数 + int8 量化，加载快，内存占用低
- **英文唤醒词**：同样使用 mobile 版
- 所有模型文件可打包在 app bundle 的 Resources 目录中

### 4.4 模型加载特征

基于 Zipformer transducer 架构，3.3M 参数：
- **加载时间**：~50–200ms（取决于存储速度）
- **内存占用**：标准版 ~25–30MB，mobile 量化版 ~10–15MB
- **推理延迟**：< 5ms 每帧（Apple Silicon CPU），实时率 > 100x
- **CoreML 加速**：如果 sherpa-onnx 编译时启用 CoreML provider，推理速度可进一步提升

---

## 5. macOS 集成

### 5.1 依赖库获取

#### 方式 A：从源码构建（推荐）

运行仓库中的构建脚本：

```bash
cd /path/to/sherpa-onnx
./build-swift-macos.sh
```

产物路径：`build-swift-macos/sherpa-onnx.xcframework`

此 xcframework 包含：
- `libsherpa-onnx.a`：universal 静态库（arm64 + x86_64）
- 头文件：所有 C API 头文件

**依赖关系**：`libsherpa-onnx.a` 本身是一个合并的静态库（通过 `libtool -static` 合并了多个子库），但仍需单独链接 `libonnxruntime`。

`build-swift-macos.sh` 做了什么：

1. CMake 配置：`-DSHERPA_ONNX_ENABLE_C_API=ON -DBUILD_SHARED_LIBS=OFF -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64"`
2. 编译静态库（`make -j4 && make install`）
3. 用 `libtool -static` 将多个 `.a` 合并为单个 `libsherpa-onnx.a`
4. 用 `xcodebuild -create-xcframework` 打包为 xcframework

#### 方式 B：从 GitHub Releases 下载预编译版

sherpa-onnx 在 GitHub Releases 上发布预编译的 macOS xcframework。检查：

```
https://github.com/k2-fsa/sherpa-onnx/releases
```

搜索 "macos" 或 "xcframework" 的 tar.bz2 文件。

### 5.2 SPM 集成方式

sherpa-onnx 没有官方的 SPM（Swift Package Manager）支持。对于 SPM 项目（`Package.swift` + `swift build`），有两条路：

#### 方案 1：systemLibrary + module map（推荐）

在 Package.swift 中添加 `systemLibrary` target：

```swift
// Package.swift
targets: [
    .systemLibrary(
        name: "CSherpaOnnx",
        path: "Libraries/CSherpaOnnx",
        pkgConfig: nil,
        providers: nil
    ),
    .target(
        name: "SherpaOnnx",
        dependencies: ["CSherpaOnnx"],
        path: "Sources/SherpaOnnx"
    ),
]
```

然后在 `Libraries/CSherpaOnnx/` 下创建：

**module.modulemap**：
```
module CSherpaOnnx {
    header "sherpa-onnx.h"
    link "sherpa-onnx"
    link "onnxruntime"
    export *
}
```

**sherpa-onnx.h**（伞头文件，引用所有需要的 C API）：
```c
#include "sherpa-onnx/c-api/c-api.h"
```

目录结构：
```
Libraries/CSherpaOnnx/
├── module.modulemap
├── sherpa-onnx.h
└── sherpa-onnx/          # 从 xcframework 中解压的头文件
    └── c-api/
        └── c-api.h
```

将 `SherpaOnnx.swift`（从仓库复制）放入 `Sources/SherpaOnnx/`。

构建时需要指定库搜索路径：
```bash
swift build -Xlinker -L/path/to/libsherpa-onnx.a/dir
```

#### 方案 2：binaryTarget + xcframework

如果已将 xcframework 托管在可下载的位置：

```swift
// Package.swift
targets: [
    .binaryTarget(
        name: "SherpaOnnx",
        url: "https://example.com/sherpa-onnx.xcframework.zip",
        checksum: "xxx"
    )
]
```

但这需要你自行维护 xcframework 的下载分发。

#### onnxruntime 依赖

无论哪种方案，都需要 `libonnxruntime`。推荐同样通过 systemLibrary 引入，或从 onnxruntime 官方下载 macOS 预编译库：

```
https://github.com/microsoft/onnxruntime/releases
```

下载 `onnxruntime-osx-universal2-<version>.tgz`，提取 `libonnxruntime.dylib`。

### 5.3 Swift 编译命令（手动方式）

如果不走 SPM，直接用 `swiftc` 编译（官方方式）：

```bash
swiftc \
    -lc++ \
    -I build-swift-macos/install/include \
    -import-objc-header SherpaOnnx-Bridging-Header.h \
    keyword-spotting-from-file.swift SherpaOnnx.swift \
    -L build-swift-macos/install/lib/ \
    -l sherpa-onnx \
    -l onnxruntime \
    -o keyword-spotting-from-file
```

关键点：
- `-lc++`：链接 libc++
- `-import-objc-header`：指定桥接头文件
- `-l sherpa-onnx`：链接合并后的静态库
- `-l onnxruntime`：链接 ONNX Runtime

### 5.4 示例项目结构

`swift-api-examples/` 目录结构：

```
swift-api-examples/
├── SherpaOnnx.swift                          # 主 API 绑定文件
├── SherpaOnnx-Bridging-Header.h              # 桥接头文件（单行 #import）
├── keyword-spotting-from-file.swift          # KWS 示例
├── run-keyword-spotting-from-file.sh         # 编译+运行脚本
├── generate-subtitles.swift                  # ASR + VAD 示例
├── run-generate-subtitles.sh
├── ...                                       # 其他 ASR/TTS 示例
```

这是纯 `swiftc` 编译的示例集，不是 Xcode 工程也不是 SPM 包。

---

## 6. 最小示例

### 6.1 Swift 完整示例（从文件）

```swift
import AVFoundation

extension AudioBuffer {
    func array() -> [Float] {
        return Array(UnsafeBufferPointer(self))
    }
}

extension AVAudioPCMBuffer {
    func array() -> [Float] {
        return self.audioBufferList.pointee.mBuffers.array()
    }
}

func run() {
    // --- 模型和关键词文件路径 ---
    let modelDir = "./sherpa-onnx-kws-zipformer-wenetspeech-3.3M-2024-01-01"
    let encoder = "\(modelDir)/encoder-epoch-12-avg-2-chunk-16-left-64.onnx"
    let decoder = "\(modelDir)/decoder-epoch-12-avg-2-chunk-16-left-64.onnx"
    let joiner = "\(modelDir)/joiner-epoch-12-avg-2-chunk-16-left-64.onnx"
    let tokens = "\(modelDir)/tokens.txt"
    let keywordsFile = "\(modelDir)/test_wavs/test_keywords.txt"
    let wavFile = "\(modelDir)/test_wavs/3.wav"

    // --- 配置 ---
    let transducerConfig = sherpaOnnxOnlineTransducerModelConfig(
        encoder: encoder,
        decoder: decoder,
        joiner: joiner
    )

    let modelConfig = sherpaOnnxOnlineModelConfig(
        tokens: tokens,
        transducer: transducerConfig
    )

    let featConfig = sherpaOnnxFeatureConfig(
        sampleRate: 16000,
        featureDim: 80
    )

    var config = sherpaOnnxKeywordSpotterConfig(
        featConfig: featConfig,
        modelConfig: modelConfig,
        keywordsFile: keywordsFile
    )

    // --- 创建 Keyword Spotter ---
    let spotter = SherpaOnnxKeywordSpotterWrapper(config: &config)

    // --- 读取 WAV 文件 ---
    let fileURL = NSURL(fileURLWithPath: wavFile)
    let audioFile = try! AVAudioFile(forReading: fileURL as URL)

    let audioFormat = audioFile.processingFormat
    assert(audioFormat.sampleRate == 16000)
    assert(audioFormat.channelCount == 1)
    assert(audioFormat.commonFormat == AVAudioCommonFormat.pcmFormatFloat32)

    let audioFrameCount = UInt32(audioFile.length)
    let audioFileBuffer = AVAudioPCMBuffer(
        pcmFormat: audioFormat,
        frameCapacity: audioFrameCount
    )

    try! audioFile.read(into: audioFileBuffer!)
    let array: [Float]! = audioFileBuffer?.array()
    spotter.acceptWaveform(samples: array)

    // --- 尾部加 0.2 秒静音 ---
    let tailPadding = [Float](repeating: 0.0, count: 3200)
    spotter.acceptWaveform(samples: tailPadding)

    // --- 信号输入结束 ---
    spotter.inputFinished()

    // --- 解码循环 ---
    while spotter.isReady() {
        spotter.decode()
        let keyword = spotter.getResult().keyword
        if keyword != "" {
            // 检测到关键词后必须立即 reset
            spotter.reset()
            print("Detected: \(keyword)")
        }
    }
}

@main
struct App {
    static func main() {
        run()
    }
}
```

### 6.2 命令行验证方式

```bash
# 1. 构建 macOS 库
cd /path/to/sherpa-onnx
./build-swift-macos.sh

# 2. 下载中文 KWS 模型
cd swift-api-examples
curl -SL -O https://github.com/k2-fsa/sherpa-onnx/releases/download/kws-models/sherpa-onnx-kws-zipformer-wenetspeech-3.3M-2024-01-01.tar.bz2
tar xf sherpa-onnx-kws-zipformer-wenetspeech-3.3M-2024-01-01.tar.bz2

# 3. 编译并运行
./run-keyword-spotting-from-file.sh
```

期望输出类似：
```
Detected: 小爱同学
```

### 6.3 VAD + KWS 串联完整示例

```swift
import AVFoundation

func runVadKws() {
    let modelDir = "./sherpa-onnx-kws-zipformer-wenetspeech-3.3M-2024-01-01"

    // --- 创建 VAD ---
    var sileroCfg = sherpaOnnxSileroVadModelConfig(
        model: "./silero_vad.onnx",
        threshold: 0.25,
        minSilenceDuration: 0.25,
        minSpeechDuration: 0.1,
        windowSize: 512,
        maxSpeechDuration: 5.0
    )
    var vadCfg = sherpaOnnxVadModelConfig(sileroVad: sileroCfg)
    let vad = SherpaOnnxVoiceActivityDetectorWrapper(
        config: &vadCfg,
        buffer_size_in_seconds: 30
    )

    // --- 创建 KWS ---
    let encoder = "\(modelDir)/encoder-epoch-12-avg-2-chunk-16-left-64.onnx"
    let decoder = "\(modelDir)/decoder-epoch-12-avg-2-chunk-16-left-64.onnx"
    let joiner = "\(modelDir)/joiner-epoch-12-avg-2-chunk-16-left-64.onnx"
    let tokens = "\(modelDir)/tokens.txt"
    let keywordsFile = "\(modelDir)/test_wavs/test_keywords.txt"

    let transducerConfig = sherpaOnnxOnlineTransducerModelConfig(
        encoder: encoder, decoder: decoder, joiner: joiner
    )
    let modelConfig = sherpaOnnxOnlineModelConfig(
        tokens: tokens, transducer: transducerConfig
    )
    let featConfig = sherpaOnnxFeatureConfig(sampleRate: 16000, featureDim: 80)
    var kwsConfig = sherpaOnnxKeywordSpotterConfig(
        featConfig: featConfig,
        modelConfig: modelConfig,
        keywordsFile: keywordsFile
    )
    let kws = SherpaOnnxKeywordSpotterWrapper(config: &kwsConfig)

    // --- 读取音频 ---
    let wavFile = "\(modelDir)/test_wavs/3.wav"
    let fileURL = NSURL(fileURLWithPath: wavFile)
    let audioFile = try! AVAudioFile(forReading: fileURL as URL)
    let audioFormat = audioFile.processingFormat
    let audioFrameCount = UInt32(audioFile.length)
    let audioFileBuffer = AVAudioPCMBuffer(
        pcmFormat: audioFormat,
        frameCapacity: audioFrameCount
    )
    try! audioFile.read(into: audioFileBuffer!)
    let allSamples: [Float] = audioFileBuffer!.array()

    // --- VAD: 分块喂入音频 ---
    let windowSize = 512
    for offset in stride(from: 0, to: allSamples.count, by: windowSize) {
        let end = min(offset + windowSize, allSamples.count)
        let chunk = [Float](allSamples[offset..<end])
        vad.acceptWaveform(samples: chunk)
    }
    vad.flush()

    // --- 处理每个 VAD 给出的语音段 ---
    while !vad.isEmpty() {
        let segment = vad.front()
        vad.pop()

        // 喂给 KWS
        kws.acceptWaveform(samples: segment.samples)
        let padding = [Float](repeating: 0.0, count: 3200)
        kws.acceptWaveform(samples: padding)
        kws.inputFinished()

        // KWS 解码
        while kws.isReady() {
            kws.decode()
            let result = kws.getResult()
            if result.keyword != "" {
                print("唤醒词: \(result.keyword)")
                kws.reset()
            }
        }
    }
}

@main
struct App {
    static func main() {
        runVadKws()
    }
}
```

---

## 附录：关键文件路径速查

| 用途 | 仓库路径 |
|---|---|
| Swift API 主文件 | `swift-api-examples/SherpaOnnx.swift` |
| Swift KWS 示例 | `swift-api-examples/keyword-spotting-from-file.swift` |
| 桥接头文件 | `swift-api-examples/SherpaOnnx-Bridging-Header.h` |
| KWS 示例编译脚本 | `swift-api-examples/run-keyword-spotting-from-file.sh` |
| C API 主头文件 | `sherpa-onnx/c-api/c-api.h` |
| C API KWS 示例 | `c-api-examples/kws-c-api.c` |
| C++ KWS 核心 | `sherpa-onnx/csrc/keyword-spotter.h` |
| C++ KWS 实现 | `sherpa-onnx/csrc/keyword-spotter.cc` |
| KWS transducer 解码器 | `sherpa-onnx/csrc/transducer-keyword-decoder.cc` |
| 关键词编码 (`EncodeKeywords`) | `sherpa-onnx/csrc/utils.cc` |
| macOS 构建脚本 | `build-swift-macos.sh` |
| text2token CLI | `sherpa-onnx/python/sherpa_onnx/cli.py` |
| text2token 核心函数 | `sherpa-onnx/python/sherpa_onnx/utils.py` |
| 模型下载脚本 | `scripts/mobile-asr-models/generate-kws.py` |
| CI 测试脚本 | `.github/scripts/test-kws.sh` |
