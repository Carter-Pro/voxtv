@preconcurrency import AVFoundation
import Foundation

// MARK: - KWS State

enum KWSState: String, Sendable {
    case idle
    case listening
}

// MARK: - KWS Error

enum KWSError: Error, LocalizedError, Sendable {
    case alreadyRunning
    case modelNotFound(String)
    case engineStartFailed(String)

    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "Keyword spotter is already running"
        case .modelNotFound(let name):
            return "Model file not found: \(name)"
        case .engineStartFailed(let detail):
            return "Audio engine start failed: \(detail)"
        }
    }
}

// MARK: - KeywordSpotterService

/// Wraps AVAudioEngine + Silero VAD + sherpa-onnx KWS into a single service.
///
/// - `start(keywordsBuf:threshold:score:)` begins listening on the default input
/// - `stop()` tears down the engine and releases models
/// - `onDetection` is called on the audio callback thread when a keyword fires
/// - `onVADStateChange` reports near-real-time voice activity status
final class KeywordSpotterService: @unchecked Sendable {
    private var engine = AVAudioEngine()
    private let modelDir: String
    private let vadModelPath: String
    private let log: (LogLevel, String) -> Void

    private var spotter: SherpaOnnxKeywordSpotterWrapper?
    private var vad: SherpaOnnxVoiceActivityDetectorWrapper?

    /// Current state of the service (`idle` or `listening`).
    private(set) var state: KWSState = .idle

    /// Called on the audio callback thread when a keyword is detected.
    var onDetection: (@Sendable (String) -> Void)?

    /// Called on the audio callback thread after every VAD cycle.
    /// The boolean indicates whether speech is currently detected.
    var onVADStateChange: (@Sendable (Bool) -> Void)?

    // MARK: - Initialization

    init(modelDir: String, vadModel: String, log: @escaping (LogLevel, String) -> Void) {
        self.modelDir = modelDir
        self.vadModelPath = vadModel
        self.log = log
    }

    deinit {
        stop()
    }

    // MARK: - Public API

    /// Start listening for keywords on the default audio input.
    ///
    /// - Parameters:
    ///   - keywordsBuf: Inline tokenised keyword phrases (same format as `keywords.txt`).
    ///   - threshold: Detection threshold (default 0.25). Lower is more sensitive.
    ///   - score: Keyword boosting score (default 1.0).
    func start(keywordsBuf: String, threshold: Float = 0.25, score: Float = 1.0) throws {
        guard state == .idle else {
            throw KWSError.alreadyRunning
        }

        // 1. Find model files
        let encoderPath = try findModelFile(containing: "encoder")
        let decoderPath = try findModelFile(containing: "decoder")
        let joinerPath = try findModelFile(containing: "joiner")
        let tokensPath = (modelDir as NSString).appendingPathComponent("tokens.txt")

        log(.info, "KWS using encoder=\(encoderPath) decoder=\(decoderPath) joiner=\(joinerPath)")

        // 2. Build config structs
        let featureConfig = sherpaOnnxFeatureConfig()

        let transducerConfig = sherpaOnnxOnlineTransducerModelConfig(
            encoder: encoderPath,
            decoder: decoderPath,
            joiner: joinerPath
        )

        let onlineConfig = sherpaOnnxOnlineModelConfig(
            tokens: tokensPath,
            transducer: transducerConfig,
            numThreads: 1,
            provider: "cpu",
            modelingUnit: "cjkchar"
        )

        var kwsConfig = sherpaOnnxKeywordSpotterConfig(
            featConfig: featureConfig,
            modelConfig: onlineConfig,
            keywordsFile: "",
            maxActivePaths: 4,
            numTrailingBlanks: 1,
            keywordsScore: score,
            keywordsThreshold: threshold,
            keywordsBuf: keywordsBuf,
            keywordsBufSize: keywordsBuf.utf8.count
        )

        // 3. Create KWS spotter
        let spotter = SherpaOnnxKeywordSpotterWrapper(config: &kwsConfig)
        self.spotter = spotter

        // 4. Create VAD detector (tuned for short wake words)
        let sileroVadConfig = sherpaOnnxSileroVadModelConfig(
            model: vadModelPath,
            threshold: 0.15,
            minSilenceDuration: 0.15,
            minSpeechDuration: 0.05,
            windowSize: 512,
            maxSpeechDuration: 5.0
        )
        var vadConfig = sherpaOnnxVadModelConfig(
            sileroVad: sileroVadConfig,
            sampleRate: 16000,
            numThreads: 1,
            provider: "cpu"
        )
        let vad = SherpaOnnxVoiceActivityDetectorWrapper(
            config: &vadConfig,
            buffer_size_in_seconds: 30.0
        )
        self.vad = vad

        // 5. Install audio tap on the input node using its native format.
        //    Specifying a custom format (16 kHz) fails on macOS when the
        //    hardware doesn't support it. We tap with nil, then convert
        //    via AVAudioConverter to 16 kHz mono for VAD+KWS.
        let dstFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )!

        let inputFormat = engine.inputNode.inputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            log(.error, "KWS: audio input not available (format=\(inputFormat))")
            throw KWSError.engineStartFailed("No audio input device available")
        }

        engine.inputNode.installTap(onBus: 0, bufferSize: 512, format: nil) { [weak self] buffer, _ in
            guard let self = self else { return }
            // Convert native format → 16 kHz mono
            guard let converted = self.convertTo16kMono(buffer, from: inputFormat, to: dstFormat) else { return }
            let samples = self.extractSamples(converted)
            guard !samples.isEmpty else { return }

            self.vad?.acceptWaveform(samples: samples)
            self.onVADStateChange?(self.vad?.isSpeechDetected() ?? false)
            self.processVADResults()
        }

        // 6. Start engine
        engine.prepare()
        do {
            try engine.start()
        } catch {
            teardown()
            throw KWSError.engineStartFailed(error.localizedDescription)
        }

        state = .listening
        log(.info, "KWS started listening")
    }

    /// Stop listening and release all resources.
    func stop() {
        guard state == .listening else { return }
        teardown()
    }

    // MARK: - Private

    private func teardown() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        engine = AVAudioEngine()  // nil out old, create fresh — stop/start reuse is unreliable
        spotter = nil
        vad = nil
        state = .idle
        log(.info, "KWS stopped")
    }

    /// Convert audio from native hardware format to 16 kHz mono float.
    private func convertTo16kMono(_ src: AVAudioPCMBuffer, from srcFormat: AVAudioFormat, to dstFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: srcFormat, to: dstFormat) else {
            log(.error, "KWS: cannot create audio converter (from \(srcFormat) to \(dstFormat))")
            return nil
        }
        let srcFrames = Int(src.frameLength)
        let dstCapacity = AVAudioFrameCount(Double(srcFrames) * (dstFormat.sampleRate / srcFormat.sampleRate) + 1)
        guard let dstBuf = AVAudioPCMBuffer(pcmFormat: dstFormat, frameCapacity: dstCapacity) else {
            log(.error, "KWS: cannot create destination PCM buffer")
            return nil
        }
        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return src
        }
        converter.convert(to: dstBuf, error: &error, withInputFrom: inputBlock)
        if let error {
            log(.error, "KWS: format conversion failed: \(error.localizedDescription)")
            return nil
        }
        return dstBuf
    }

    /// Process all available VAD speech segments through the KWS spotter.
    private func processVADResults() {
        guard let vad = vad, let spotter = spotter else { return }

        while !vad.isEmpty() {
            let segment = vad.front()
            vad.pop()

            // Feed speech segment to spotter
            spotter.acceptWaveform(samples: segment.samples)

            // Decode after each segment
            while spotter.isReady() {
                spotter.decode()
                let result = spotter.getResult()
                let keyword = result.keyword
                if !keyword.isEmpty {
                    log(.info, "KWS detected: \(keyword)")
                    spotter.reset()
                    let callback = onDetection
                    let kw = keyword
                    DispatchQueue.global().async { callback?(kw) }
                }
            }
        }
    }

    /// Find an ONNX model file in `modelDir` whose filename contains `substr`.
    /// Prefers the `int8` quantized variant when available, but falls back to
    /// the unquantized file.
    private func findModelFile(containing substr: String) throws -> String {
        let files: [String]
        do {
            files = try FileManager.default.contentsOfDirectory(atPath: modelDir)
        } catch {
            throw KWSError.modelNotFound("\(substr) (directory not readable: \(modelDir))")
        }

        // Collect candidates
        var candidates: [String] = []
        for file in files where file.contains(substr) && file.hasSuffix(".onnx") {
            candidates.append(file)
        }

        guard !candidates.isEmpty else {
            throw KWSError.modelNotFound(substr)
        }

        // Prefer int8 quantized variant
        if let preferred = candidates.first(where: { $0.contains(".int8.") }) {
            return (modelDir as NSString).appendingPathComponent(preferred)
        }

        // Fall back to first match
        return (modelDir as NSString).appendingPathComponent(candidates[0])
    }

    /// Extract float audio samples from an `AVAudioPCMBuffer`.
    private func extractSamples(_ buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else { return [] }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return [] }
        return Array(UnsafeBufferPointer(start: channelData.pointee, count: frameCount))
    }
}
