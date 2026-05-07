import SwiftUI
import AppKit
import ServiceManagement

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
    @Published var kwsRunning: Bool = false
    @Published var beepSoundName: String = "Tink"
    @Published var wakeWord: String = "电视电视"
    @Published var wakeThreshold: Float = 0.25
    @Published var localNetworkAuthorized: Bool = false
    @Published var launchAtLogin: Bool = false {
        didSet {
            if oldValue != launchAtLogin {
                setLoginItem(enabled: launchAtLogin)
            }
        }
    }

    private var dashboard: DashboardServer?
    private var wakePipeline: WakePipeline?
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
        beepSoundName = defaults.string(forKey: "beepSoundName") ?? "Tink"
        wakeWord = defaults.string(forKey: "wakeWord") ?? "电视电视"
        let savedThreshold = defaults.float(forKey: "wakeThreshold")
        if savedThreshold > 0 { wakeThreshold = savedThreshold }
        updateDashboardURL()
        checkLoginItemStatus()
    }

    func bind(_ server: DashboardServer) {
        dashboard = server
        wakePipeline = server.wakePipeline
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

    func saveBeepSoundName(_ name: String) {
        beepSoundName = name
        defaults.set(name, forKey: "beepSoundName")
    }

    func saveWakeWord(_ word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        wakeWord = trimmed
        defaults.set(trimmed, forKey: "wakeWord")
        restartKWSIfRunning()
    }

    func saveWakeThreshold(_ threshold: Float) {
        wakeThreshold = threshold
        defaults.set(threshold, forKey: "wakeThreshold")
        restartKWSIfRunning()
    }

    func startKWS() {
        guard let pipeline = wakePipeline, !kwsRunning else { return }
        let word = wakeWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else {
            print("[Voxtv] KWS start failed: wake word is empty")
            return
        }
        let buf = PinyinTokenizer.keywordsBuf(from: word)
        let threshold = wakeThreshold
        // Dispatch to background — AVAudioEngine.start() must not run on main thread
        // during a menu event, or ObjC exceptions will kill the process silently.
        DispatchQueue.global().async { [weak self] in
            guard let self else { return }
            do {
                try pipeline.start(keywordsBuf: buf, threshold: threshold)
                Task { @MainActor in self.kwsRunning = true }
            } catch {
                print("[Voxtv] KWS start failed: \(error.localizedDescription)")
            }
        }
    }

    func stopKWS() {
        wakePipeline?.stop()
        kwsRunning = false
    }

    private func restartKWSIfRunning() {
        guard kwsRunning else { return }
        stopKWS()
        let word = wakeWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return }
        let buf = PinyinTokenizer.keywordsBuf(from: word)
        let threshold = wakeThreshold
        let pipeline = wakePipeline
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            do {
                try pipeline?.start(keywordsBuf: buf, threshold: threshold)
                Task { @MainActor in self.kwsRunning = true }
            } catch {
                print("[Voxtv] KWS restart failed: \(error.localizedDescription)")
            }
        }
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
        window.setContentSize(NSSize(width: 420, height: 480))
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

    func checkLoginItemStatus() {
        launchAtLogin = (SMAppService.mainApp.status == .enabled)
    }

    /// Trigger local network permission dialog by browsing Bonjour.
    /// macOS shows the permission prompt on first multicast network access.
    func requestLocalNetworkPermission() {
        let browser = NetServiceBrowser()
        let delegate = LocalNetworkPermissionDelegate()
        // Keep delegate alive for the duration of the browse
        browser.delegate = delegate
        // Stash strong ref so delegate outlives this scope
        objc_setAssociatedObject(browser, "lnpd", delegate, .OBJC_ASSOCIATION_RETAIN)
        browser.searchForServices(ofType: "_appletv._tcp.", inDomain: "local.")
        // Stop after 3 seconds — permission dialog has already appeared
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [browser] in
            browser.stop()
        }
        // Mark as authorized — the dialog fires once and persists
        localNetworkAuthorized = true
    }

    /// All required permissions granted?
    var allPermissionsGranted: Bool {
        // Mic + Speech checked by SpeechService; local network is one-shot trigger
        true
    }

    private func setLoginItem(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("[Voxtv] SMAppService error: \(error.localizedDescription)")
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    struct ClearDataResult {
        let logFilesDeleted: Int
        let defaultsCleared: Bool
    }

    func clearAllData() -> ClearDataResult {
        var logCount = 0
        var defaultsCleared = false
        // Clear UserDefaults
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
            defaultsCleared = true
        }
        // Clear log files — count before deleting
        let logDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs/Voxtv")
        if let files = try? FileManager.default.contentsOfDirectory(at: logDir, includingPropertiesForKeys: nil) {
            logCount = files.filter { $0.pathExtension == "log" }.count
        }
        try? FileManager.default.removeItem(at: logDir)
        // Reset local state
        appleTVDeviceId = ""
        beepSoundName = "Tink"
        wakeWord = "电视电视"
        wakeThreshold = 0.25
        recognitionTimeout = 8.0
        cooldownDuration = 3.0
        promptType = "beep"
        promptText = "请说"
        feedbackEnabled = true
        dashboardPort = 8765
        updateDashboardURL()
        return ClearDataResult(logFilesDeleted: logCount, defaultsCleared: defaultsCleared)
    }
}

/// Triggers the macOS local network permission dialog via Bonjour browsing.
private final class LocalNetworkPermissionDelegate: NSObject, NetServiceBrowserDelegate {
    func netServiceBrowserWillSearch(_ browser: NetServiceBrowser) {}
    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {}
    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {}
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {}
    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {}
}
