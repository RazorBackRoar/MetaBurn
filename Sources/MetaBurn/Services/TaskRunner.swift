import Foundation
import AppKit

@MainActor
final class TaskRunner: ObservableObject {
    @Published private(set) var state: RunState = .waiting
    @Published private(set) var counters = Counters()
    @Published private(set) var typeCounts = TypeCounts()
    @Published private(set) var scanSummary: ScanSummary?
    @Published private(set) var message: String?
    @Published private(set) var log: [LogEntry] = []

    private var activeJob: Task<Void, Never>?
    private var isCancelled = false

    func start(droppedPaths: [String], muteAudio: Bool) {
        guard activeJob == nil else { return }
        isCancelled = false
        state = .scanning
        counters = Counters()
        typeCounts = TypeCounts()
        scanSummary = nil
        message = nil
        log = []

        let jobId = UUID().uuidString
        activeJob = Task { [weak self] in
            await self?.run(jobId: jobId, droppedPaths: droppedPaths, muteAudio: muteAudio)
        }
    }

    func cancel() {
        isCancelled = true
        activeJob?.cancel()
    }

    func reset() {
        cancel()
        activeJob = nil
        isCancelled = false
        state = .waiting
        counters = Counters()
        typeCounts = TypeCounts()
        scanSummary = nil
        message = nil
        log = []
    }

    private func run(jobId: String, droppedPaths: [String], muteAudio: Bool) async {
        let ffmpegPath = muteAudio ? await MetadataCleaner.resolveFfmpeg() : nil
        let exiftoolPath = await MetadataCleaner.resolveExiftool()

        guard exiftoolPath != nil else {
            await setState(.exiftoolMissing, message: "ExifTool is required. Install it with: brew install exiftool")
            finish()
            return
        }

        let ffmpegAvailable = ffmpegPath != nil
        Log.shared.info("Starting job \(jobId) for \(droppedPaths.count) dropped path(s) (mute: \(muteAudio))", scope: "taskRunner")

        do {
            await setState(.scanning)
            let scan = try await Scanner.buildFileList(droppedPaths: droppedPaths)

            for skip in scan.skipped {
                await appendLog(CleanResult(path: skip.path, status: .skipped, reason: skip.reason))
            }

            await MainActor.run {
                counters.supported = scan.files.count
                var kinds = TypeCounts()
                for file in scan.files {
                    kinds.recordTotal(for: file)
                }
                typeCounts = kinds
                scanSummary = ScanSummary(fileCount: scan.files.count, totalBytes: scan.totalBytes)
            }

            await setState(.cleaning)

            for file in scan.files {
                if Task.isCancelled || isCancelled {
                    await setState(.cancelled)
                    finish()
                    return
                }
                let result = await MetadataCleaner.cleanFile(filePath: file, muteAudio: muteAudio, ffmpegPath: ffmpegAvailable ? ffmpegPath : nil)
                await appendLog(result)
            }

            await setState(.done)
            finish()
        } catch {
            await setState(.failed, message: error.localizedDescription)
            finish()
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

    private func finish() {
        activeJob = nil
        isCancelled = false
    }
}
