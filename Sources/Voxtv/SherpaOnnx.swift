/// SherpaOnnx.swift - SPM-adapted Swift wrappers for sherpa-onnx C API
/// Originally from sherpa-onnx/swift-api-examples/SherpaOnnx.swift
/// Copyright (c) 2023 Xiaomi Corporation
///
/// Trimmed to KWS + VAD portions only. For SPM, imports CSherpaOnnx instead of
/// using a bridging header.

import Foundation  // For NSString
import CSherpaOnnx

// MARK: - C Pointer Helper

/// Convert a String to a `const char*` so we can pass it to the C API.
func toCPointer(_ s: String) -> UnsafePointer<Int8>! {
  let cs = (s as NSString).utf8String
  return UnsafePointer<Int8>(cs)
}

// MARK: - Streaming ASR Model Configs (needed by KeywordSpotter)

func sherpaOnnxOnlineTransducerModelConfig(
  encoder: String = "",
  decoder: String = "",
  joiner: String = ""
) -> SherpaOnnxOnlineTransducerModelConfig {
  return SherpaOnnxOnlineTransducerModelConfig(
    encoder: toCPointer(encoder),
    decoder: toCPointer(decoder),
    joiner: toCPointer(joiner)
  )
}

func sherpaOnnxOnlineParaformerModelConfig(
  encoder: String = "",
  decoder: String = ""
) -> SherpaOnnxOnlineParaformerModelConfig {
  return SherpaOnnxOnlineParaformerModelConfig(
    encoder: toCPointer(encoder),
    decoder: toCPointer(decoder)
  )
}

func sherpaOnnxOnlineZipformer2CtcModelConfig(
  model: String = ""
) -> SherpaOnnxOnlineZipformer2CtcModelConfig {
  return SherpaOnnxOnlineZipformer2CtcModelConfig(
    model: toCPointer(model)
  )
}

func sherpaOnnxOnlineNemoCtcModelConfig(
  model: String = ""
) -> SherpaOnnxOnlineNemoCtcModelConfig {
  return SherpaOnnxOnlineNemoCtcModelConfig(
    model: toCPointer(model)
  )
}

func sherpaOnnxOnlineToneCtcModelConfig(
  model: String = ""
) -> SherpaOnnxOnlineToneCtcModelConfig {
  return SherpaOnnxOnlineToneCtcModelConfig(
    model: toCPointer(model)
  )
}

func sherpaOnnxOnlineModelConfig(
  tokens: String,
  transducer: SherpaOnnxOnlineTransducerModelConfig = sherpaOnnxOnlineTransducerModelConfig(),
  paraformer: SherpaOnnxOnlineParaformerModelConfig = sherpaOnnxOnlineParaformerModelConfig(),
  zipformer2Ctc: SherpaOnnxOnlineZipformer2CtcModelConfig =
    sherpaOnnxOnlineZipformer2CtcModelConfig(),
  numThreads: Int = 1,
  provider: String = "cpu",
  debug: Int = 0,
  modelType: String = "",
  modelingUnit: String = "cjkchar",
  bpeVocab: String = "",
  tokensBuf: String = "",
  tokensBufSize: Int = 0,
  nemoCtc: SherpaOnnxOnlineNemoCtcModelConfig = sherpaOnnxOnlineNemoCtcModelConfig(),
  toneCtc: SherpaOnnxOnlineToneCtcModelConfig = sherpaOnnxOnlineToneCtcModelConfig()
) -> SherpaOnnxOnlineModelConfig {
  return SherpaOnnxOnlineModelConfig(
    transducer: transducer,
    paraformer: paraformer,
    zipformer2_ctc: zipformer2Ctc,
    tokens: toCPointer(tokens),
    num_threads: Int32(numThreads),
    provider: toCPointer(provider),
    debug: Int32(debug),
    model_type: toCPointer(modelType),
    modeling_unit: toCPointer(modelingUnit),
    bpe_vocab: toCPointer(bpeVocab),
    tokens_buf: toCPointer(tokensBuf),
    tokens_buf_size: Int32(tokensBufSize),
    nemo_ctc: nemoCtc,
    t_one_ctc: toneCtc
  )
}

func sherpaOnnxFeatureConfig(
  sampleRate: Int = 16000,
  featureDim: Int = 80
) -> SherpaOnnxFeatureConfig {
  return SherpaOnnxFeatureConfig(
    sample_rate: Int32(sampleRate),
    feature_dim: Int32(featureDim))
}

// MARK: - Voice Activity Detection

func sherpaOnnxSileroVadModelConfig(
  model: String = "",
  threshold: Float = 0.5,
  minSilenceDuration: Float = 0.25,
  minSpeechDuration: Float = 0.5,
  windowSize: Int = 512,
  maxSpeechDuration: Float = 5.0
) -> SherpaOnnxSileroVadModelConfig {
  return SherpaOnnxSileroVadModelConfig(
    model: toCPointer(model),
    threshold: threshold,
    min_silence_duration: minSilenceDuration,
    min_speech_duration: minSpeechDuration,
    window_size: Int32(windowSize),
    max_speech_duration: maxSpeechDuration
  )
}

func sherpaOnnxTenVadModelConfig(
  model: String = "",
  threshold: Float = 0.5,
  minSilenceDuration: Float = 0.25,
  minSpeechDuration: Float = 0.5,
  windowSize: Int = 256,
  maxSpeechDuration: Float = 5.0
) -> SherpaOnnxTenVadModelConfig {
  return SherpaOnnxTenVadModelConfig(
    model: toCPointer(model),
    threshold: threshold,
    min_silence_duration: minSilenceDuration,
    min_speech_duration: minSpeechDuration,
    window_size: Int32(windowSize),
    max_speech_duration: maxSpeechDuration
  )
}

func sherpaOnnxVadModelConfig(
  sileroVad: SherpaOnnxSileroVadModelConfig = sherpaOnnxSileroVadModelConfig(),
  sampleRate: Int32 = 16000,
  numThreads: Int = 1,
  provider: String = "cpu",
  debug: Int = 0,
  tenVad: SherpaOnnxTenVadModelConfig = sherpaOnnxTenVadModelConfig()
) -> SherpaOnnxVadModelConfig {
  return SherpaOnnxVadModelConfig(
    silero_vad: sileroVad,
    sample_rate: sampleRate,
    num_threads: Int32(numThreads),
    provider: toCPointer(provider),
    debug: Int32(debug),
    ten_vad: tenVad
  )
}

// MARK: - Circular Buffer Wrapper

class SherpaOnnxCircularBufferWrapper {
  private let buffer: OpaquePointer

  init(capacity: Int) {
    guard let ptr = SherpaOnnxCreateCircularBuffer(Int32(capacity)) else {
      fatalError("Failed to create SherpaOnnxCircularBuffer")
    }
    self.buffer = ptr
  }

  deinit {
    SherpaOnnxDestroyCircularBuffer(buffer)
  }

  func push(samples: [Float]) {
    guard !samples.isEmpty else { return }
    SherpaOnnxCircularBufferPush(buffer, samples, Int32(samples.count))
  }

  func get(startIndex: Int, n: Int) -> [Float] {
    guard startIndex >= 0 else { return [] }
    guard n > 0 else { return [] }

    guard let ptr = SherpaOnnxCircularBufferGet(buffer, Int32(startIndex), Int32(n)) else {
      return []
    }
    defer { SherpaOnnxCircularBufferFree(ptr) }

    return Array(UnsafeBufferPointer(start: ptr, count: n))
  }

  func pop(n: Int) {
    guard n > 0 else { return }
    SherpaOnnxCircularBufferPop(buffer, Int32(n))
  }

  func size() -> Int {
    return Int(SherpaOnnxCircularBufferSize(buffer))
  }

  func reset() {
    SherpaOnnxCircularBufferReset(buffer)
  }
}

// MARK: - Speech Segment Wrapper

class SherpaOnnxSpeechSegmentWrapper {
  private let p: UnsafePointer<SherpaOnnxSpeechSegment>

  init(p: UnsafePointer<SherpaOnnxSpeechSegment>) {
    self.p = p
  }

  deinit {
    SherpaOnnxDestroySpeechSegment(p)
  }

  var start: Int {
    Int(p.pointee.start)
  }

  var n: Int {
    Int(p.pointee.n)
  }

  lazy var samples: [Float] = {
    Array(UnsafeBufferPointer(start: p.pointee.samples, count: n))
  }()
}

// MARK: - Voice Activity Detector Wrapper

class SherpaOnnxVoiceActivityDetectorWrapper {
  /// A pointer to the underlying counterpart in C
  private let vad: OpaquePointer

  init(config: UnsafePointer<SherpaOnnxVadModelConfig>, buffer_size_in_seconds: Float) {
    guard let vad = SherpaOnnxCreateVoiceActivityDetector(config, buffer_size_in_seconds) else {
      fatalError("SherpaOnnxCreateVoiceActivityDetector returned nil")
    }
    self.vad = vad
  }

  deinit {
    SherpaOnnxDestroyVoiceActivityDetector(vad)
  }

  func acceptWaveform(samples: [Float]) {
    SherpaOnnxVoiceActivityDetectorAcceptWaveform(vad, samples, Int32(samples.count))
  }

  func isEmpty() -> Bool {
    return SherpaOnnxVoiceActivityDetectorEmpty(vad) == 1
  }

  func isSpeechDetected() -> Bool {
    return SherpaOnnxVoiceActivityDetectorDetected(vad) == 1
  }

  func pop() {
    SherpaOnnxVoiceActivityDetectorPop(vad)
  }

  func clear() {
    SherpaOnnxVoiceActivityDetectorClear(vad)
  }

  func front() -> SherpaOnnxSpeechSegmentWrapper {
    guard let p = SherpaOnnxVoiceActivityDetectorFront(vad) else {
      fatalError("SherpaOnnxVoiceActivityDetectorFront returned nil")
    }
    return SherpaOnnxSpeechSegmentWrapper(p: p)
  }

  func reset() {
    SherpaOnnxVoiceActivityDetectorReset(vad)
  }

  func flush() {
    SherpaOnnxVoiceActivityDetectorFlush(vad)
  }
}

// MARK: - Keyword Spotting

class SherpaOnnxKeywordResultWrapper {
  /// A pointer to the underlying counterpart in C
  let result: UnsafePointer<SherpaOnnxKeywordResult>!

  var keyword: String {
    return String(cString: result.pointee.keyword)
  }

  var count: Int32 {
    return result.pointee.count
  }

  var tokens: [String] {
    if let tokensPointer = result.pointee.tokens_arr {
      var tokens: [String] = []
      for index in 0..<count {
        if let tokenPointer = tokensPointer[Int(index)] {
          let token = String(cString: tokenPointer)
          tokens.append(token)
        }
      }
      return tokens
    } else {
      let tokens: [String] = []
      return tokens
    }
  }

  init(result: UnsafePointer<SherpaOnnxKeywordResult>!) {
    self.result = result
  }

  deinit {
    if let result {
      SherpaOnnxDestroyKeywordResult(result)
    }
  }
}

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
) -> SherpaOnnxKeywordSpotterConfig {
  return SherpaOnnxKeywordSpotterConfig(
    feat_config: featConfig,
    model_config: modelConfig,
    max_active_paths: Int32(maxActivePaths),
    num_trailing_blanks: Int32(numTrailingBlanks),
    keywords_score: keywordsScore,
    keywords_threshold: keywordsThreshold,
    keywords_file: toCPointer(keywordsFile),
    keywords_buf: toCPointer(keywordsBuf),
    keywords_buf_size: Int32(keywordsBufSize)
  )
}

class SherpaOnnxKeywordSpotterWrapper {
  /// A pointer to the underlying counterpart in C
  let spotter: OpaquePointer!
  var stream: OpaquePointer!

  init(
    config: UnsafePointer<SherpaOnnxKeywordSpotterConfig>!
  ) {
    spotter = SherpaOnnxCreateKeywordSpotter(config)
    stream = SherpaOnnxCreateKeywordStream(spotter)
  }

  deinit {
    if let stream {
      SherpaOnnxDestroyOnlineStream(stream)
    }

    if let spotter {
      SherpaOnnxDestroyKeywordSpotter(spotter)
    }
  }

  func acceptWaveform(samples: [Float], sampleRate: Int = 16000) {
    SherpaOnnxOnlineStreamAcceptWaveform(stream, Int32(sampleRate), samples, Int32(samples.count))
  }

  func isReady() -> Bool {
    return SherpaOnnxIsKeywordStreamReady(spotter, stream) == 1 ? true : false
  }

  func decode() {
    SherpaOnnxDecodeKeywordStream(spotter, stream)
  }

  func reset() {
    SherpaOnnxResetKeywordStream(spotter, stream)
  }

  func getResult() -> SherpaOnnxKeywordResultWrapper {
    let result: UnsafePointer<SherpaOnnxKeywordResult>? = SherpaOnnxGetKeywordResult(
      spotter, stream)
    return SherpaOnnxKeywordResultWrapper(result: result)
  }

  /// Signal that no more audio samples would be available.
  /// After this call, you cannot call acceptWaveform() any more.
  func inputFinished() {
    SherpaOnnxOnlineStreamInputFinished(stream)
  }
}
