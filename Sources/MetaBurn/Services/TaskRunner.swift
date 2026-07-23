import Foundation
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
        activeJob = Task { [weak self] in
            await self?.run(jobId: jobId, token: token, droppedPaths: droppedPaths, muteAudio: muteAudio)
        }
    }

    func cancel() {
        runToken = UUID()
        isCancelled = true
        ProcessRunner.cancelAll()
        activeJob?.cancel()
        // Reflect Cancel immediately in the UI even if a file is mid-clean.
        if state == .scanning || state == .cleaning {
            state = .cancelled
            message = "Cancelled — in-flight tools were stopped."
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

    private func run(jobId: String, token: UUID, droppedPaths: [String], muteAudio: Bool) async {
        let exiftoolPath = await MetadataCleaner.resolveExiftool()

        guard !isStale(token) else {
            finish(token: token)
            return
        }

        Log.shared.info("Starting job \(jobId) for \(droppedPaths.count) dropped path(s)", scope: "taskRunner")
        Paths.cleanupOrphanWorkFiles()

        do {
            await setState(.scanning)
            let scan = try await Scanner.buildFileList(droppedPaths: droppedPaths)

            guard !isStale(token) else {
                await markCancelledIfStillRunning(message: "Cancelled during scan.")
                finish(token: token)
                return
            }

            // Park bypassed files in Skippable only when there are skips (creates that folder on demand).
            _ = try? SkipExporter.export(skipped: scan.skipped)

            var kinds = TypeCounts()
            for file in scan.files {
                kinds.recordTotal(for: file)
            }

            // Videos still need ExifTool; photo-only jobs can run on native ImageIO alone.
            if kinds.videos > 0, exiftoolPath == nil {
                await setState(.exiftoolMissing, message: "ExifTool is required for videos. Install it with: brew install exiftool")
                finish(token: token)
                return
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
                if scan.skipped.count > 0 {
                    skipNote =
                        "\(scan.skipped.count) skipped file(s) saved to Desktop/MetaBurn/\(OutputNaming.skippableFolderName) (see \(OutputNaming.skippedSummaryFileName))."
                } else if scan.skipped.isEmpty {
                    skipNote = "Drop photos, videos, or a folder that contains them."
                } else {
                    skipNote = "\(scan.skipped.count) file(s) were skipped."
                }
                await setState(
                    .done,
                    message: "No supported photos or videos found. \(skipNote)"
                )
                finish(token: token)
                return
            }

            // Mute is video-only; AVFoundation handles it in-process (no ffmpeg).
            let muteVideos = muteAudio && kinds.videos > 0

            Log.shared.info(
                "Job \(jobId): \(kinds.images) photo(s), \(kinds.videos) video(s), muteVideos=\(muteVideos), skipped=\(scan.skipped.count)",
                scope: "taskRunner"
            )

            await setState(.cleaning)

            for (index, file) in scan.files.enumerated() {
                if isStale(token) {
                    await markCancelledIfStillRunning(
                        message: "Cancelled after \(counters.cleaned + counters.partial) file(s)."
                    )
                    finish(token: token)
                    return
                }
                currentFile = file
                currentFileNumber = index + 1
                Log.shared.info("[file-start] \(index + 1)/\(scan.files.count): \(file)", scope: "taskRunner")
                let isVideo = SupportedTypes.isVideo(filePath: file)
                let result = await MetadataCleaner.cleanFile(
                    filePath: file,
                    muteAudio: muteVideos && isVideo
                )
                if isStale(token) {
                    // Don't count a cancelled mid-file as a normal failure in the log.
                    if result.reason != "cancelled" {
                        await appendLog(result)
                    }
                    await markCancelledIfStillRunning(
                        message: "Cancelled after \(counters.cleaned + counters.partial) file(s)."
                    )
                    finish(token: token)
                    return
                }
                Log.shared.info("[file-done] \(index + 1)/\(scan.files.count): \(file) -> \(result.status.rawValue)", scope: "taskRunner")
                await appendLog(result)
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
                    message: "\(scan.skipped.count) skipped file(s) saved to Desktop/MetaBurn/\(OutputNaming.skippableFolderName)."
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

    private func isStale(_ token: UUID) -> Bool {
        Task.isCancelled || isCancelled || token != runToken
    }

    /// Avoid clobbering Waiting/Reset UI when a dying job notices cancel late.
    private func markCancelledIfStillRunning(message: String) async {
        await MainActor.run {
            if state == .scanning || state == .cleaning {
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
            currentFile = nil
            currentFileNumber = 0
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
