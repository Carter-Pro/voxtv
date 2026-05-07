import Foundation

struct AppleTVBridgeResult {
    let success: Bool
    let stdout: String
    let stderr: String
}

final class AppleTVBridge {
    let deviceId: String

    init(deviceId: String) {
        self.deviceId = deviceId
    }

    func buildCommand(text: String) -> [String] {
        ["atvremote", "--id", deviceId, "text_set=\(text)"]
    }

    func findAtvremotePath() -> String? {
        // 1. Bundled in .app (for future PyInstaller build)
        if let execPath = Bundle.main.executablePath {
            let dir = (execPath as NSString).deletingLastPathComponent
            let path = (dir as NSString).appendingPathComponent("atvremote")
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        // 2. Known pipx / pip user install paths
        let knownPaths = [
            "\(NSHomeDirectory())/.local/bin/atvremote",
            "\(NSHomeDirectory())/Library/Python/3.9/bin/atvremote",
            "\(NSHomeDirectory())/Library/Python/3.10/bin/atvremote",
            "\(NSHomeDirectory())/Library/Python/3.11/bin/atvremote",
            "\(NSHomeDirectory())/Library/Python/3.12/bin/atvremote",
            "\(NSHomeDirectory())/Library/Python/3.13/bin/atvremote",
            "\(NSHomeDirectory())/Library/Python/3.14/bin/atvremote",
            "/usr/local/bin/atvremote",
        ]
        for path in knownPaths where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        // 3. PATH search (works in terminal, fails in .app)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["which", "atvremote"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.isEmpty ? nil : path
    }

    func send(text: String) -> AppleTVBridgeResult {
        guard let atvPath = findAtvremotePath() else {
            return AppleTVBridgeResult(
                success: false,
                stdout: "",
                stderr: "atvremote not found in PATH. Install with: pipx install pyatv"
            )
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: atvPath)
        task.arguments = ["--id", deviceId, "text_set=\(text)"]
        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return AppleTVBridgeResult(
                success: false,
                stdout: "",
                stderr: error.localizedDescription
            )
        }

        let stdout = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(),
                            encoding: .utf8) ?? ""
        let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                            encoding: .utf8) ?? ""

        return AppleTVBridgeResult(
            success: task.terminationStatus == 0,
            stdout: stdout.trimmingCharacters(in: .whitespacesAndNewlines),
            stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
