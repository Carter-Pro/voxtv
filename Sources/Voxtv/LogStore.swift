import Foundation

enum LogLevel: String, Codable, Sendable, Comparable {
    case debug = "debug"
    case info = "info"
    case warn = "warn"
    case error = "error"

    var priority: Int {
        switch self {
        case .debug: return 0
        case .info:  return 1
        case .warn:  return 2
        case .error: return 3
        }
    }

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.priority < rhs.priority
    }
}

struct LogEntry: Codable, Sendable {
    let timestamp: Date
    let level: LogLevel
    let message: String
}

actor LogStore {
    private var entries: [LogEntry]
    private let maxSize: Int

    // MARK: - File logging

    private let logDir: URL = {
        let lib = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        return lib.appendingPathComponent("Logs/Voxtv")
    }()
    private var currentLogFile: URL?
    private var currentFileHandle: FileHandle?
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    init(maxSize: Int = 200) {
        self.maxSize = maxSize
        self.entries = []
    }

    func append(level: LogLevel, message: String) {
        let entry = LogEntry(timestamp: Date(), level: level, message: message)
        entries.append(entry)
        if entries.count > maxSize {
            entries.removeFirst(entries.count - maxSize)
        }
        // Write to persistent file (synchronous — crash-safe)
        writeToFile(entry)
        // Rotate/cleanup on each append (cheap date check)
        cleanupOldLogs()
    }

    func all() -> [LogEntry] {
        entries
    }

    // MARK: - File writing

    private func ensureLogFile() {
        let today = dateFormatter.string(from: Date())
        let fileName = "voxtv-\(today).log"
        let fileURL = logDir.appendingPathComponent(fileName)

        // Same file, no rotation needed
        if currentLogFile == fileURL, currentFileHandle != nil { return }

        // Close old handle
        currentFileHandle?.closeFile()
        currentFileHandle = nil

        // Create directory if needed
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)

        // Open (or create) today's log file
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        currentFileHandle = try? FileHandle(forWritingTo: fileURL)
        currentFileHandle?.seekToEndOfFile()
        currentLogFile = fileURL
    }

    private func writeToFile(_ entry: LogEntry) {
        ensureLogFile()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(entry),
              var line = String(data: data, encoding: .utf8) else { return }
        line += "\n"
        guard let lineData = line.data(using: .utf8) else { return }
        currentFileHandle?.write(lineData)
        try? currentFileHandle?.synchronize() // flush immediately — survive crash
    }

    private func cleanupOldLogs() {
        let maxAge: TimeInterval = 7 * 24 * 60 * 60 // 7 days
        guard let files = try? FileManager.default.contentsOfDirectory(at: logDir, includingPropertiesForKeys: [.creationDateKey]) else { return }
        let cutoff = Date().addingTimeInterval(-maxAge)
        for file in files where file.pathExtension == "log" {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
               let creation = attrs[.creationDate] as? Date,
               creation < cutoff {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}

extension Array where Element == LogEntry {
    func toJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }
}
