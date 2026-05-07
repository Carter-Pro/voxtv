import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var portText: String = ""
    @State private var deviceIdText: String = ""
    @State private var showClearConfirmation = false
    @State private var showClearResult = false
    @State private var clearResultMessage = ""

    private let systemSoundNames = [
        "Basso", "Blow", "Bottle", "Frog", "Funk",
        "Glass", "Hero", "Morse", "Ping", "Pop",
        "Purr", "Sosumi", "Submarine", "Tink"
    ]

    var body: some View {
        TabView {
            VStack(spacing: 12) {
                Text("守护进程状态")
                    .font(.headline)

                HStack {
                    Image(systemName: appState.daemonRunning ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundColor(appState.daemonRunning ? .green : .red)
                    Text(appState.daemonRunning ? "运行中" : "未启动")
                }

                Text("语音识别、Apple TV 控制等功能将在后续版本实现。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .tabItem {
                Label("状态", systemImage: "info.circle")
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Apple TV 配置")
                    .font(.headline)

                HStack {
                    Text("Device ID:")
                    TextField("例如: AABBCCDDEEFF@192.168.1.100", text: $deviceIdText)
                        .frame(width: 220)
                        .onAppear {
                            deviceIdText = appState.appleTVDeviceId
                        }
                    Button("保存") {
                        appState.saveDeviceId(deviceIdText)
                    }
                }

                if appState.appleTVDeviceId.isEmpty {
                    Text("未配置。运行 atvremote scan 获取 device ID。")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text("已配置: \(appState.appleTVDeviceId)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .tabItem {
                Label("Apple TV", systemImage: "tv")
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("提示音")
                    .font(.headline)

                Picker("提示音类型:", selection: Binding(
                    get: { appState.promptType },
                    set: { appState.savePromptType($0) }
                )) {
                    Text("系统提示音").tag("beep")
                    Text("TTS 语音").tag("tts")
                }
                .pickerStyle(.radioGroup)

                if appState.promptType == "beep" {
                    HStack {
                        Text("系统声音:")
                        Picker("", selection: Binding(
                            get: { appState.beepSoundName },
                            set: { appState.saveBeepSoundName($0) }
                        )) {
                            ForEach(systemSoundNames, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                        .frame(width: 120)

                        Button("试听") {
                            if let sound = NSSound(named: appState.beepSoundName) {
                                sound.play()
                            }
                        }
                    }
                }

                if appState.promptType == "tts" {
                    HStack {
                        Text("提示文案:")
                        TextField("请说", text: Binding(
                            get: { appState.promptText },
                            set: { appState.savePromptText($0) }
                        ))
                        .frame(width: 150)
                    }
                }

                Divider()

                Text("唤醒词")
                    .font(.headline)

                HStack {
                    Text("唤醒词:")
                    TextField("例如: 电视电视", text: Binding(
                        get: { appState.wakeWord },
                        set: { appState.saveWakeWord($0) }
                    ))
                    .frame(width: 120)
                    Text("(拼音自动生成)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("阈值:")
                    Slider(value: Binding(
                        get: { Double(appState.wakeThreshold) },
                        set: { appState.saveWakeThreshold(Float($0)) }
                    ), in: 0.05...0.95, step: 0.05)
                    .frame(width: 120)
                    Text(String(format: "%.2f", appState.wakeThreshold))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 35)
                }

                Divider()

                HStack {
                    Text("识别超时:")
                    Picker("", selection: Binding(
                        get: { Int(appState.recognitionTimeout) },
                        set: { appState.saveRecognitionTimeout(Double($0)) }
                    )) {
                        Text("5 秒").tag(5)
                        Text("8 秒").tag(8)
                        Text("10 秒").tag(10)
                        Text("15 秒").tag(15)
                    }
                    .frame(width: 80)
                }

                HStack {
                    Text("唤醒冷却:")
                    Picker("", selection: Binding(
                        get: { Int(appState.cooldownDuration) },
                        set: { appState.saveCooldownDuration(Double($0)) }
                    )) {
                        Text("2 秒").tag(2)
                        Text("3 秒").tag(3)
                        Text("5 秒").tag(5)
                    }
                    .frame(width: 80)
                }

                Toggle("语音反馈播报", isOn: Binding(
                    get: { appState.feedbackEnabled },
                    set: { appState.saveFeedbackEnabled($0) }
                ))
            }
            .padding()
            .tabItem {
                Label("唤醒词", systemImage: "waveform")
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Dashboard")
                    .font(.headline)

                HStack {
                    Text("端口:")
                    TextField("8765", text: $portText)
                        .frame(width: 80)
                        .onAppear {
                            portText = String(appState.dashboardPort)
                        }
                    Button("应用") {
                        if let port = UInt16(portText), port > 0 {
                            appState.applyPort(port)
                        }
                    }
                }

                Text("当前地址: \(appState.dashboardURL)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .tabItem {
                Label("Dashboard", systemImage: "globe")
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("高级")
                    .font(.headline)

                Toggle("开机自动启动", isOn: Binding(
                    get: { appState.launchAtLogin },
                    set: { appState.launchAtLogin = $0 }
                ))

                Text("登录时自动在后台启动 Voxtv，无需手动打开。")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Divider()

                Text("数据管理")
                    .font(.headline)

                Text("清除所有 Voxtv 数据：日志文件、配置信息将被永久删除。应用将保留在系统中。")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button("清除所有数据", role: .destructive) {
                    showClearConfirmation = true
                }
            }
            .padding()
            .tabItem {
                Label("高级", systemImage: "gearshape.2")
            }
            .alert("确定要清除所有数据吗？", isPresented: $showClearConfirmation) {
                Button("取消", role: .cancel) {}
                Button("清除", role: .destructive) {
                    let result = appState.clearAllData()
                    clearResultMessage = "已删除 \(result.logFilesDeleted) 个日志文件\(result.defaultsCleared ? "，配置已重置为默认值。" : "。")"
                    showClearResult = true
                }
            } message: {
                Text("此操作将永久删除所有日志文件和配置信息，应用将恢复为初始状态。此操作不可撤销。")
            }
            .alert("数据清理完成", isPresented: $showClearResult) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(clearResultMessage)
            }
        }
        .frame(width: 400, height: 420)
    }
}
