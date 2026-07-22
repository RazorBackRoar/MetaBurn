import Foundation

struct ProcessOutput {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

enum ProcessRunnerError: Error, Equatable {
    case timeout
    case launchFailure(String)
}

final class ProcessRunner {
    private init() {}

    static func run(
        executablePath: String,
        arguments: [String],
        timeout: TimeInterval = 60
    ) async throws -> ProcessOutput {
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

        do {
            try process.run()
        } catch {
            throw ProcessRunnerError.launchFailure(error.localizedDescription)
        }

        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            if process.isRunning {
                timedOut.set()
                process.terminate()
                // ExifTool can hang on some HEIC/media files after SIGTERM; escalate.
                try await Task.sleep(nanoseconds: 2_000_000_000)
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
            }
        }

        do {
            let stdoutData = try await readDataToEnd(from: stdoutHandle)
            let stderrData = try await readDataToEnd(from: stderrHandle)
            process.waitUntilExit()
            timeoutTask.cancel()

            if timedOut.value {
                throw ProcessRunnerError.timeout
            }

            let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""
            return ProcessOutput(stdout: stdout, stderr: stderr, exitCode: process.terminationStatus)
        } catch let error as ProcessRunnerError {
            timeoutTask.cancel()
            throw error
        } catch {
            timeoutTask.cancel()
            if timedOut.value {
                throw ProcessRunnerError.timeout
            }
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

    private static func readDataToEnd(from handle: FileHandle) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let data = handle.readDataToEndOfFile()
                handle.closeFile()
                continuation.resume(returning: data)
            }
        }
    }

    struct ProcessError: Error {
        let message: String
        var localizedDescription: String { message }
    }
}

/// Tiny lock for timeout flag shared with the timeout Task.
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
