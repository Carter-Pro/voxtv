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
        // Request permissions at startup so dialogs appear once
        if let speech = dashboard.speechService {
            Task {
                _ = await speech.requestPermissions()
            }
        }
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
