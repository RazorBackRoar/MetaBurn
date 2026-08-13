import Foundation
import os.log

/// Handles asynchronous file writing for logs to avoid blocking the main thread.
private actor AsyncFileLogger {
    private let fileURL: URL
    private var fileHandle: FileHandle?

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func write(_ data: Data) {
        if fileHandle == nil {
            Paths.ensureLogsDirectory()
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                FileManager.default.createFile(atPath: fileURL.path, contents: nil, attributes: nil)
            }
            do {
                fileHandle = try FileHandle(forWritingTo: fileURL)
                fileHandle?.seekToEndOfFile()
            } catch {
                return
            }
        }

        fileHandle?.write(data)
    }

    deinit {
        try? fileHandle?.close()
    }
}

/// Unified console + file logger.
@MainActor
final class Log {
    static let shared = Log()

    private let osLog = Logger(subsystem: Brand.appId, category: "app")
    private let fileLogger: AsyncFileLogger
    private var hasSetup = false
    @preconcurrency private static let dateFormatter = ISO8601DateFormatter()

    private init() {
        Paths.ensureLogsDirectory()
        let logURL = Paths.logsDirectory().appendingPathComponent("metaburn.log")
        self.fileLogger = AsyncFileLogger(fileURL: logURL)
    }

    func setup() {
        hasSetup = true
    }

    private func write(level: String, message: String, scope: String) {
        let timestamp = Self.dateFormatter.string(from: Date())
        let line = "[\(timestamp)] [\(level.uppercased())] [\(scope)] \(message)"
        osLog.log(level: level, "\(line)")

        guard hasSetup else { return }
        if let data = (line + "\n").data(using: .utf8) {
            Task.detached { [fileLogger] in
                await fileLogger.write(data)
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
