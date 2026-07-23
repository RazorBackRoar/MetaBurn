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

        // Detached so a blocked waitUntilExit can never starve the timeout.
        let timeoutTask = Task.detached(priority: .utility) {
            do {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            } catch {
                return
            }
            if process.isRunning {
                timedOut.set()
                process.terminate()
                // ExifTool can hang on some HEIC/media files after SIGTERM; escalate.
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
            }
        }

        do {
            // Concurrent reads avoid classic pipe-fill deadlock (stderr fills while awaiting stdout).
            async let stdoutData = readDataToEnd(from: stdoutHandle)
            async let stderrData = readDataToEnd(from: stderrHandle)
            let out = try await stdoutData
            let err = try await stderrData

            try await waitForExit(process)
            timeoutTask.cancel()

            if timedOut.value {
                throw ProcessRunnerError.timeout
            }

            let stdout = String(data: out, encoding: .utf8) ?? ""
            let stderr = String(data: err, encoding: .utf8) ?? ""
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
