import Foundation

struct ProcessOutput {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

enum ProcessRunnerError: Error, Equatable {
    case timeout
    case launchFailure(String)
    case cancelled
}

/// Runs external tools with hard cancel + timeout so Cancel always kills ExifTool.
enum ProcessRunner {
    private static let lock = NSLock()
    private static var active: [ObjectIdentifier: Process] = [:]

    /// Kill every in-flight child process (Cancel button).
    static func cancelAll() {
        lock.lock()
        let procs = Array(active.values)
        lock.unlock()
        for process in procs {
            terminate(process)
        }
    }

    static func run(
        executablePath: String,
        arguments: [String],
        timeout: TimeInterval = 60
    ) async throws -> ProcessOutput {
        try Task.checkCancellation()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading
        let timedOut = LockedFlag()
        let id = ObjectIdentifier(process)

        do {
            try process.run()
        } catch {
            throw ProcessRunnerError.launchFailure(error.localizedDescription)
        }

        register(process, id: id)
        defer { unregister(id) }

        let timeoutTask = Task.detached(priority: .utility) {
            do {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            } catch {
                return
            }
            if process.isRunning {
                timedOut.set()
                terminate(process)
            }
        }

        do {
            return try await withTaskCancellationHandler {
                async let stdoutData = readDataToEnd(from: stdoutHandle)
                async let stderrData = readDataToEnd(from: stderrHandle)
                let out = try await stdoutData
                let err = try await stderrData
                try await waitForExit(process)
                timeoutTask.cancel()

                try Task.checkCancellation()
                if timedOut.value {
                    throw ProcessRunnerError.timeout
                }
                if Task.isCancelled {
                    throw ProcessRunnerError.cancelled
                }

                return ProcessOutput(
                    stdout: String(data: out, encoding: .utf8) ?? "",
                    stderr: String(data: err, encoding: .utf8) ?? "",
                    exitCode: process.terminationStatus
                )
            } onCancel: {
                terminate(process)
            }
        } catch is CancellationError {
            timeoutTask.cancel()
            terminate(process)
            throw ProcessRunnerError.cancelled
        } catch let error as ProcessRunnerError {
            timeoutTask.cancel()
            throw error
        } catch {
            timeoutTask.cancel()
            if timedOut.value { throw ProcessRunnerError.timeout }
            if Task.isCancelled { throw ProcessRunnerError.cancelled }
            throw error
        }
    }

    static func runSimple(
        executablePath: String,
        arguments: [String],
        timeout: TimeInterval = 60
    ) async throws -> String {
        let output = try await run(executablePath: executablePath, arguments: arguments, timeout: timeout)
        if output.exitCode != 0 {
            let combined = (output.stdout + "\n" + output.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
            throw ProcessError(message: combined.isEmpty ? "process exited with \(output.exitCode)" : combined)
        }
        return output.stdout
    }

    private static func register(_ process: Process, id: ObjectIdentifier) {
        lock.lock()
        active[id] = process
        lock.unlock()
    }

    private static func unregister(_ id: ObjectIdentifier) {
        lock.lock()
        active.removeValue(forKey: id)
        lock.unlock()
    }

    private static func terminate(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        // ExifTool can ignore SIGTERM on HEIC — escalate quickly.
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.4) {
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }

    private static func readDataToEnd(from handle: FileHandle) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let data = handle.readDataToEndOfFile()
                handle.closeFile()
                continuation.resume(returning: data)
            }
        }
    }

    private static func waitForExit(_ process: Process) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                process.waitUntilExit()
                continuation.resume()
            }
        }
    }

    struct ProcessError: Error {
        let message: String
        var localizedDescription: String { message }
    }
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func set() {
        lock.lock()
        _value = true
        lock.unlock()
    }
}
