import Foundation
import os.log

/// Unified console + file logger.
@MainActor
final class Log {
    static let shared = Log()

    private let fileURL: URL
    private let osLog = Logger(subsystem: Brand.appId, category: "app")
    private var hasSetup = false

    private init() {
        Paths.ensureLogsDirectory()
        fileURL = Paths.logsDirectory().appendingPathComponent("metaburn.log")
    }

    func setup() {
        hasSetup = true
    }

    private func write(level: String, message: String, scope: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] [\(level.uppercased())] [\(scope)] \(message)"
        osLog.log(level: level, "\(line)")

        guard hasSetup else { return }
        Paths.ensureLogsDirectory()
        if let data = (line + "\n").data(using: .utf8) {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                if let handle = try? FileHandle(forWritingTo: fileURL) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.close()
                }
            } else {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }

    func debug(_ message: String, scope: String = "app") { write(level: "debug", message: message, scope: scope) }
    func info(_ message: String, scope: String = "app") { write(level: "info", message: message, scope: scope) }
    func warn(_ message: String, scope: String = "app") { write(level: "warn", message: message, scope: scope) }
    func error(_ message: String, scope: String = "app") { write(level: "error", message: message, scope: scope) }
}

private extension Logger {
    func log(level: String, _ message: String) {
        switch level {
        case "debug": self.debug("\(message)")
        case "warn": self.warning("\(message)")
        case "error": self.error("\(message)")
        default: self.info("\(message)")
        }
    }
}
