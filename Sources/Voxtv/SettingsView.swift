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
        .frame(width: 360, height: 200)
    }
}
