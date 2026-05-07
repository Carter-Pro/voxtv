import SwiftUI

@main
struct VoxtvApp: App {
    private let dashboard = DashboardServer()
    private let menuBarIconImage: NSImage = {
        if let url = Bundle.module.url(forResource: "MenuBarIcon", withExtension: "png") {
            let img = NSImage(contentsOf: url) ?? NSImage()
            img.isTemplate = true
            img.size = NSSize(width: 18, height: 18)
            return img
        }
        return NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil) ?? NSImage()
    }()

    init() {
        let appState = AppState.shared
        do {
            try dashboard.start()
            appState.serverRunning = true
            appState.daemonRunning = true
            print("[Voxtv] Dashboard started on port \(dashboard.port)")
        } catch {
            print("[Voxtv] Dashboard failed: \(error)")
        }
        dashboard.appleTVBridge = AppleTVBridge(deviceId: appState.appleTVDeviceId)
        let logStore = LogStore(maxSize: 200)
        dashboard.logStore = logStore

        let speechSvc = SpeechService()
        speechSvc.onLog = { message in
            Task { await logStore.append(level: .debug, message: message) }
        }
        dashboard.speechService = speechSvc

        // Request speech recognition permission at startup (mic already requested by KWS)
        Task {
            let (mic, speech) = await speechSvc.requestPermissions()
            print("[Voxtv] Permissions — mic: \(mic), speech: \(speech)")
        }

        Task { await logStore.append(level: .info, message: "Voxtv App started") }
        // Create KeywordSpotterService for keyword wake-up
        func resolveModelPath(_ rel: String) -> String {
            if FileManager.default.fileExists(atPath: rel) { return rel }
            if let rp = Bundle.main.resourcePath {
                let fp = (rp as NSString).appendingPathComponent(rel)
                if FileManager.default.fileExists(atPath: fp) { return fp }
            }
            return rel
        }
        let kwsModelDir = resolveModelPath("Resources/kws/sherpa-onnx-kws-zipformer-wenetspeech-3.3M-2024-01-01-mobile")
        let kwsVadModel = resolveModelPath("Resources/vad/silero_vad.onnx")
        let kwSpotter = KeywordSpotterService(
            modelDir: kwsModelDir,
            vadModel: kwsVadModel,
            log: { level, msg in
                Task { await logStore.append(level: level, message: msg) }
            }
        )
        let dash = dashboard
        kwSpotter.onDetection = { keyword in
            Task { await logStore.append(level: .info, message: "KWS detected: \(keyword)") }
            dash.recordKWSDetection(keyword)
        }
        dashboard.keywordSpotter = kwSpotter

        // Create pipeline components
        let promptPlayer = PromptPlayer()
        promptPlayer.onLog = { message in
            Task { await logStore.append(level: .debug, message: message) }
        }
        let feedbackSpeaker = FeedbackSpeaker()
        let commandDispatcher = CommandDispatcher()

        // Create wake pipeline
        let wakePipeline = WakePipeline(
            spotter: kwSpotter,
            speech: dashboard.speechService,
            bridge: dashboard.appleTVBridge,
            dispatcher: commandDispatcher,
            prompt: promptPlayer,
            feedback: feedbackSpeaker
        )

        // Mirror AppState config to pipeline
        wakePipeline.promptType = appState.promptType
        wakePipeline.promptText = appState.promptText
        wakePipeline.feedbackEnabled = appState.feedbackEnabled
        wakePipeline.recognitionTimeout = appState.recognitionTimeout
        wakePipeline.cooldownDuration = appState.cooldownDuration

        // Log pipeline state changes and debug events
        let store = logStore
        wakePipeline.onStateChange = { state in
            Task { await store.append(level: .info, message: "Pipeline state: \(state.rawValue)") }
            // Sync kwsRunning to menu bar
            let running = (state == .kwsListening)
            DispatchQueue.main.async {
                AppState.shared.kwsRunning = running
            }
        }
        wakePipeline.onLog = { message in
            Task { await store.append(level: .debug, message: message) }
            // If pipeline stopped for any reason, sync state
            if message.contains("pipeline stopped") {
                DispatchQueue.main.async {
                    AppState.shared.kwsRunning = false
                }
            }
        }

        dashboard.wakePipeline = wakePipeline
        dashboard.promptPlayer = promptPlayer
        dashboard.feedbackSpeaker = feedbackSpeaker

        appState.bind(dashboard)
    }

    var body: some Scene {
        MenuBarExtra(isInserted: .constant(true), content: {
            MenuBarView(appState: AppState.shared)
        }, label: {
            Image(nsImage: menuBarIconImage)
        })
        .menuBarExtraStyle(.menu)

        WindowGroup("Voxtv 设置", id: "settings") {
            SettingsView(appState: AppState.shared)
        }
        .windowResizability(.contentSize)
    }
}
