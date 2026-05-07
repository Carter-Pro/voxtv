import SwiftUI

struct MenuBarView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 6) {
                Circle()
                    .fill(appState.kwsRunning ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text(appState.kwsRunning ? "监听中" : "未监听")
                    .font(.system(size: 13))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)

            Divider()

            Button(appState.kwsRunning ? "停止监听" : "开始监听") {
                if appState.kwsRunning {
                    appState.stopKWS()
                } else {
                    appState.startKWS()
                }
            }

            Divider()

            Button("打开 Dashboard") {
                if let url = URL(string: appState.dashboardURL) {
                    NSWorkspace.shared.open(url)
                }
            }

            Divider()

            Button("设置...") {
                // Defer to next runloop so NSMenu dismisses before window opens
                DispatchQueue.main.async {
                    appState.openSettings()
                }
            }

            Divider()

            Button("退出 Voxtv") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .frame(minWidth: 200)
    }
}
