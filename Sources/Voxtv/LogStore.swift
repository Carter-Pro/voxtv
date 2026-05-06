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
    }

    func all() -> [LogEntry] {
        entries
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
