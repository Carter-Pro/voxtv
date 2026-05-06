import SwiftUI
import AppKit

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var daemonRunning = false
    @Published var dashboardPort: UInt16 = 8765
    @Published var dashboardURL: String = "http://localhost:8765"
    @Published var serverRunning = false
    @Published var appleTVDeviceId: String = ""

    // Wake word pipeline config
    @Published var promptType: String = "beep"
    @Published var promptText: String = "请说"
    @Published var feedbackEnabled: Bool = true
    @Published var recognitionTimeout: Double = 8.0
    @Published var cooldownDuration: Double = 3.0

    private var dashboard: DashboardServer?
    private let defaults = UserDefaults.standard
    private var settingsWindow: NSWindow?
    private var settingsCloseObserver: (any NSObjectProtocol)?

    private init() {
        let saved = defaults.integer(forKey: "dashboardPort")
        if saved > 0 && saved <= 65535 {
            dashboardPort = UInt16(saved)
        }
        appleTVDeviceId = defaults.string(forKey: "appleTVDeviceId") ?? ""
        promptType = defaults.string(forKey: "promptType") ?? "beep"
        promptText = defaults.string(forKey: "promptText") ?? "请说"
        if defaults.object(forKey: "feedbackEnabled") != nil {
            feedbackEnabled = defaults.bool(forKey: "feedbackEnabled")
        }
        let savedTimeout = defaults.double(forKey: "recognitionTimeout")
        if savedTimeout > 0 { recognitionTimeout = savedTimeout }
        let savedCooldown = defaults.double(forKey: "cooldownDuration")
        if savedCooldown > 0 { cooldownDuration = savedCooldown }
        updateDashboardURL()
    }

    func bind(_ server: DashboardServer) {
        dashboard = server
    }

    func updateDashboardURL() {
        dashboardURL = "http://localhost:\(dashboardPort)"
    }

    func applyPort(_ port: UInt16) {
        guard port > 0, port != dashboardPort else { return }
        dashboardPort = port
        updateDashboardURL()
        defaults.set(Int(port), forKey: "dashboardPort")

        do {
            try dashboard?.restart(with: port)
            serverRunning = true
            daemonRunning = true
            print("[Voxtv] Dashboard restarted on port \(port)")
        } catch {
            serverRunning = false
            daemonRunning = false
            print("[Voxtv] Dashboard restart failed: \(error)")
        }
    }

    func saveDeviceId(_ id: String) {
        appleTVDeviceId = id.trimmingCharacters(in: .whitespacesAndNewlines)
        defaults.set(appleTVDeviceId, forKey: "appleTVDeviceId")
    }

    func savePromptType(_ type: String) {
        promptType = type
        defaults.set(type, forKey: "promptType")
    }

    func savePromptText(_ text: String) {
        promptText = text
        defaults.set(text, forKey: "promptText")
    }

    func saveFeedbackEnabled(_ enabled: Bool) {
        feedbackEnabled = enabled
        defaults.set(enabled, forKey: "feedbackEnabled")
    }

    func saveRecognitionTimeout(_ timeout: Double) {
        recognitionTimeout = timeout
        defaults.set(timeout, forKey: "recognitionTimeout")
    }

    func saveCooldownDuration(_ duration: Double) {
        cooldownDuration = duration
        defaults.set(duration, forKey: "cooldownDuration")
    }

    var deviceConfigured: Bool {
        !appleTVDeviceId.isEmpty
    }

    func openSettings() {
        if let existing = settingsWindow {
            if existing.isMiniaturized {
                existing.deminiaturize(nil)
            }
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = SettingsView(appState: self)
        let hosting = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Voxtv 设置"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 400, height: 380))
        window.center()
        window.isReleasedWhenClosed = false

        // Standard macOS menu bar app pattern: temporarily show Dock icon
        // so the window can become key and receive keyboard focus
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Hide Dock icon again when settings window closes
        settingsCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                NSApp.setActivationPolicy(.accessory)
                if let obs = self?.settingsCloseObserver {
                    NotificationCenter.default.removeObserver(obs)
                }
            }
        }

        settingsWindow = window
    }
}
