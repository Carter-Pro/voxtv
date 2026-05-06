import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var portText: String = ""
    @State private var deviceIdText: String = ""

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
                Text("语音交互")
                    .font(.headline)

                Picker("提示音类型:", selection: Binding(
                    get: { appState.promptType },
                    set: { appState.savePromptType($0) }
                )) {
                    Text("系统提示音").tag("beep")
                    Text("TTS 语音").tag("tts")
                }
                .pickerStyle(.radioGroup)

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
                Label("语音", systemImage: "waveform")
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
        }
        .frame(width: 380, height: 320)
    }
}
