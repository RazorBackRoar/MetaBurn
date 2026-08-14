import AppKit
import MetaBurnCore

@MainActor
final class TaskRunner: ObservableObject {
    @Published private(set) var state: RunState = .waiting
    @Published private(set) var counters = Counters()
    @Published private(set) var typeCounts = TypeCounts()
    @Published private(set) var scanSummary: ScanSummary?
    @Published private(set) var message: String?
    @Published private(set) var log: [LogEntry] = []
    @Published private(set) var currentFile: String?
    @Published private(set) var currentFileNumber = 0

    private var activeJob: Task<Void, Never>?
    private var isCancelled = false
    /// Invalidates an in-flight job when Cancel/Reset fires so late completions cannot resume cleaning.
    private var runToken = UUID()

    func start(droppedPaths: [String], muteAudio: Bool) {
        guard activeJob == nil else { return }
        let token = UUID()
        runToken = token
        isCancelled = false
        state = .scanning
        counters = Counters()
        typeCounts = TypeCounts()
        scanSummary = nil
        message = nil
        log = []
        currentFile = nil
        currentFileNumber = 0

        let jobId = UUID().uuidString
        let outputDestination = OutputPreference.stored
        activeJob = Task { [weak self] in
            await self?.run(
                jobId: jobId,
                token: token,
                droppedPaths: droppedPaths,
                muteAudio: muteAudio,
                outputDestination: outputDestination
            )
        }
    }

    func cancel() {
        runToken = UUID()
        isCancelled = true
        activeJob?.cancel()
        // Reflect Cancel immediately in the UI even if a file is mid-clean.
        if state == .scanning || state == .downloading || state == .cleaning {
            state = .cancelled
            message = "Cancelled — in-flight export was stopped."
            currentFile = nil
            currentFileNumber = 0
        }
    }

    func reset() {
        cancel()
        // Keep isCancelled until finish() so a dying job cannot keep cleaning.
        if activeJob == nil {
            isCancelled = false
        }
        state = .waiting
        counters = Counters()
        typeCounts = TypeCounts()
        scanSummary = nil
        message = nil
        log = []
        currentFile = nil
        currentFileNumber = 0
    }

    private func run(
        jobId: String,
        token: UUID,
        droppedPaths: [String],
        muteAudio: Bool,
        outputDestination: OutputDestination
    ) async {
        guard !isStale(token) else {
            finish(token: token)
            return
        }

        Log.shared.info("Starting job \(jobId) for \(droppedPaths.count) dropped path(s)", scope: "taskRunner")
        let removedOrphans = await Task.detached {
            Paths.cleanupOrphanWorkFiles()
        }.value
        if !removedOrphans.isEmpty {
            Log.shared.info(
                "Removed \(removedOrphans.count) leftover work file(s)",
                scope: "taskRunner"
            )
        }

        do {
            await setState(.scanning)
            let scan = try await Scanner.buildFileList(droppedPaths: droppedPaths)

            guard !isStale(token) else {
                await markCancelledIfStillRunning(message: "Cancelled during scan.")
                finish(token: token)
                return
            }

            // Park bypassed files in Skippable only when there are skips (creates that folder on demand).
            _ = try? SkipExporter.export(skipped: scan.skipped, outputDestination: outputDestination)

            var kinds = TypeCounts()
            for file in scan.files {
                kinds.recordTotal(for: file)
            }

            await MainActor.run {
                counters.supported = scan.files.count
                counters.skipped = scan.skipped.count
                typeCounts = kinds
                scanSummary = ScanSummary(fileCount: scan.files.count, totalBytes: scan.totalBytes)
            }

            Log.shared.info(
                "Scan complete: \(scan.files.count) processable, \(scan.skipped.count) skipped, job \(jobId)",
                scope: "taskRunner"
            )

            // Zero-file guard — no phantom cleaning job when the drop had nothing we can burn.
            if scan.files.isEmpty {
                let skipNote: String
                if scan.skipped.isEmpty {
                    skipNote = "Drop photos, videos, or a folder that contains them."
                } else {
                    skipNote =
                        "\(scan.skipped.count) skipped file(s) saved to \(OutputPreference.label(for: outputDestination))/\(OutputNaming.skippableFolderName) (see \(OutputNaming.skippedSummaryFileName))."
                }
                await setState(
                    .done,
                    message: "No supported photos or videos found. \(skipNote)"
                )
                finish(token: token)
                return
            }

            // Mute is video-only; AVFoundation handles strip + mute in-process.
            let muteVideos = muteAudio && kinds.videos > 0

            Log.shared.info(
                "Job \(jobId): \(kinds.images) photo(s), \(kinds.videos) video(s), muteVideos=\(muteVideos), skipped=\(scan.skipped.count), output=\(outputDestination.rawValue)",
                scope: "taskRunner"
            )

            await setState(.cleaning)

            let files = scan.files
            let total = files.count
            let limit = min(Self.cleanConcurrencyLimit, max(1, total))
            var nextIndex = 0
            var inFlight = 0
            var completed = 0
            var sawCancel = false

            await withTaskGroup(of: (index: Int, file: String, result: CleanResult).self) { group in
                func enqueueIfPossible() async {
                    guard !sawCancel, !(await isStale(token)) else { return }
                    while inFlight < limit, nextIndex < total {
                        let index = nextIndex
                        let file = files[index]
                        nextIndex += 1
                        inFlight += 1
                        await noteProgress(file: file, number: min(total, completed + inFlight))
                        let muteThis = muteVideos && SupportedTypes.isVideo(filePath: file)
                        if UbiquityGate.needsDownload(atPath: file) {
                            await setState(.downloading)
                            await logTask(
                                "[icloud-download] \(index + 1)/\(total): \(file)"
                            )
                        }
                        await logTask("[file-start] \(index + 1)/\(total): \(file)")
                        group.addTask {
                            let capturedIndex = index
                            let capturedFile = file
                            let capturedMute = muteThis
                            let capturedDest = outputDestination
                            // Detach so ImageIO / AVFoundation run off the main actor;
                            // forward cancel so in-flight exports still stop.
                            let work = Task.detached(priority: .userInitiated) {
                                await MetadataCleaner.cleanFile(
                                    filePath: capturedFile,
                                    muteAudio: capturedMute,
                                    outputDestination: capturedDest
                                )
                            }
                            let result = await withTaskCancellationHandler {
                                await work.value
                            } onCancel: {
                                work.cancel()
                            }
                            return (capturedIndex, capturedFile, result)
                        }
                    }
                }

                await enqueueIfPossible()

                for await (index, file, result) in group {
                    inFlight -= 1
                    completed += 1

                    let stale = isStale(token)
                    if sawCancel || stale {
                        sawCancel = true
                        if result.reason != "cancelled" {
                            await appendLog(result)
                        }
                        group.cancelAll()
                        continue
                    }

                    let progressNumber = min(total, max(completed + inFlight, 1))
                    noteProgress(file: file, number: progressNumber)
                    if shouldResumeCleaning() {
                        await setState(.cleaning)
                    }
                    logTask(
                        "[file-done] \(index + 1)/\(total): \(file) -> \(result.status.rawValue)"
                    )
                    await appendLog(result)
                    noteProgress(file: file, number: progressNumber)
                    await enqueueIfPossible()
                }
            }

            if isStale(token) {
                await markCancelledIfStillRunning(
                    message: "Cancelled after \(counters.cleaned + counters.partial) file(s)."
                )
                finish(token: token)
                return
            }

            if scan.skipped.count > 0 {
                await setState(
                    .done,
                    message: "\(scan.skipped.count) skipped file(s) saved to \(OutputPreference.label(for: outputDestination))/\(OutputNaming.skippableFolderName)."
                )
            } else {
                await setState(.done)
            }
            finish(token: token)
        } catch {
            if isStale(token) {
                await markCancelledIfStillRunning(message: "Cancelled.")
            } else {
                await setState(.failed, message: error.localizedDescription)
            }
            finish(token: token)
        }
    }

    /// Caps parallel cleans so AVFoundation/ImageIO do not unbounded-contend on the GPU.
    static func boundedCleanConcurrency(processorCount: Int) -> Int {
        min(4, max(2, processorCount / 2))
    }

    private static var cleanConcurrencyLimit: Int {
        boundedCleanConcurrency(processorCount: ProcessInfo.processInfo.activeProcessorCount)
    }

    private func isStale(_ token: UUID) -> Bool {
        Task.isCancelled || isCancelled || token != runToken
    }

    private func noteProgress(file: String, number: Int) {
        currentFile = file
        currentFileNumber = number
    }

    private func shouldResumeCleaning() -> Bool {
        state != .cleaning && state != .cancelled && state != .failed
    }

    private func logTask(_ message: String) {
        Log.shared.info(message, scope: "taskRunner")
    }

    /// Avoid clobbering Waiting/Reset UI when a dying job notices cancel late.
    private func markCancelledIfStillRunning(message: String) async {
        await MainActor.run {
            if state == .scanning || state == .downloading || state == .cleaning {
                state = .cancelled
                self.message = message
                currentFile = nil
                currentFileNumber = 0
            } else if state == .cancelled, self.message == nil || self.message?.isEmpty == true {
                self.message = message
            }
        }
    }

    private func setState(_ newState: RunState, message: String? = nil) async {
        await MainActor.run {
            self.state = newState
            self.message = message
        }
    }

    private func appendLog(_ result: CleanResult) async {
        await MainActor.run {
            switch result.status {
            case .cleaned: counters.cleaned += 1
            case .skipped: counters.skipped += 1
            case .failed: counters.failed += 1
            case .partial: counters.partial += 1
            }
            typeCounts.recordDone(for: result.path)
            log.append(LogEntry(result: result))
            NSApp?.requestUserAttention(.informationalRequest)
        }
    }

    private func finish(token: UUID) {
        guard activeJob != nil else { return }
        // Clear when this token is current, or when Cancel/Reset invalidated it.
        if token == runToken || isCancelled {
            activeJob = nil
            isCancelled = false
            currentFile = nil
            currentFileNumber = 0
        }
    }
}
