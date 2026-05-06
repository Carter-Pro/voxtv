import SwiftUI

@main
struct VoxtvApp: App {
    private let dashboard = DashboardServer()

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
        dashboard.speechService = SpeechService()
        let logStore = LogStore(maxSize: 200)
        dashboard.logStore = logStore
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
            dash.recordKWSDetection(keyword)
        }
        dashboard.keywordSpotter = kwSpotter
        appState.bind(dashboard)
    }

    var body: some Scene {
        MenuBarExtra("Voxtv", systemImage: "mic.fill") {
            MenuBarView(appState: AppState.shared)
        }
        .menuBarExtraStyle(.menu)

        Window("Voxtv 设置", id: "settings") {
            SettingsView(appState: AppState.shared)
        }
        .windowResizability(.contentSize)
    }
}
