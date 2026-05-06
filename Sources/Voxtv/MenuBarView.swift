import SwiftUI

struct MenuBarView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 6) {
                Circle()
                    .fill(appState.daemonRunning ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text(appState.daemonRunning ? "守护进程运行中" : "守护进程未启动")
                    .font(.system(size: 13))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)

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
