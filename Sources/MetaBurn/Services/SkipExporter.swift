import Foundation
import MetaBurnCore

/// Copies bypassed files into Skippable and writes `skipped-summary.txt`.
@MainActor
enum SkipExporter {
    struct Result: Equatable {
        let copiedCount: Int
        let summaryURL: URL
        let folderURL: URL
    }

    static func export(
        skipped: [(path: String, reason: String)],
        outputDestination: OutputDestination = OutputPreference.stored
    ) throws -> Result? {
        guard !skipped.isEmpty else { return nil }

        let fm = FileManager.default
        var copied = 0
        var lastFolder: URL?

        // Group by skippable folder so adjacent mode can place files next to each source.
        var groups: [String: [(path: String, reason: String)]] = [:]
        for entry in skipped {
            let folder = OutputRootResolver.skippableDirectory(
                forSourcePath: entry.path,
                destination: outputDestination
            )
            groups[folder.path, default: []].append(entry)
        }

        var primarySummary: URL?
        var primaryFolder: URL?

        for (folderPath, entries) in groups {
            let folder = URL(fileURLWithPath: folderPath, isDirectory: true)
            Paths.ensureDirectory(folder)
            lastFolder = folder
            if primaryFolder == nil { primaryFolder = folder }

            for entry in entries {
                guard fm.fileExists(atPath: entry.path),
                      (try? URL(fileURLWithPath: entry.path).resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
                else { continue }

                // Best-effort: pull iCloud placeholders before copy.
                if UbiquityGate.needsDownload(atPath: entry.path) {
                    try? FileManager.default.startDownloadingUbiquitousItem(at: URL(fileURLWithPath: entry.path))
                }

                let dest = Paths.uniqueOutputURL(forSourcePath: entry.path, in: folder)
                do {
                    if UbiquityGate.isUbiquitous(atPath: entry.path) {
                        try awaitableMaterializeSync(from: entry.path, to: dest)
                    } else {
                        try fm.copyItem(atPath: entry.path, toPath: dest.path)
                    }
                    copied += 1
                } catch {
                    Log.shared.warn(
                        "Could not copy skipped file \(entry.path): \(error.localizedDescription)",
                        scope: "skipExporter"
                    )
                }
            }

            // Per-folder summary lists only that folder's entries; also write a combined note if multiple.
            let summaryURL = try writeSummary(entries: entries, in: folder)
            if primarySummary == nil { primarySummary = summaryURL }
        }

        // When multiple adjacent folders exist, also write a combined summary under the first folder.
        if groups.count > 1, let primaryFolder {
            primarySummary = try writeSummary(entries: skipped, in: primaryFolder)
        }

        let folderURL = primaryFolder ?? lastFolder ?? Paths.skippableOutputDirectory()
        let summaryURL = primarySummary
            ?? folderURL.appendingPathComponent(OutputNaming.skippedSummaryFileName)
        return Result(copiedCount: copied, summaryURL: summaryURL, folderURL: folderURL)
    }

    private static func writeSummary(entries: [(path: String, reason: String)], in folder: URL) throws -> URL {
        let summaryURL = folder.appendingPathComponent(OutputNaming.skippedSummaryFileName)
        let body = SkipSummary.document(entries: entries)
        do {
            try body.write(to: summaryURL, atomically: true, encoding: .utf8)
            Log.shared.info("Wrote skip summary to: \(summaryURL.path)", scope: "skipExporter")
        } catch {
            Log.shared.error("Failed to write skip summary: \(error.localizedDescription)", scope: "skipExporter")
            throw error
        }
        return summaryURL
    }

    /// SkipExporter is sync-throwing; bridge materialize with a short coordinated copy.
    private static func awaitableMaterializeSync(from path: String, to dest: URL) throws {
        let sourceURL = URL(fileURLWithPath: path)
        var coordinatorError: NSError?
        var copyError: Error?
        let coordinator = NSFileCoordinator()
        let fm = FileManager.default
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        coordinator.coordinate(readingItemAt: sourceURL, options: [], error: &coordinatorError) { readURL in
            do {
                try fm.copyItem(at: readURL, to: dest)
            } catch {
                copyError = error
            }
        }
        if let coordinatorError { throw coordinatorError }
        if let copyError { throw copyError }
    }
}
