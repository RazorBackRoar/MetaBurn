import Foundation
import MetaBurnCore

/// Copies bypassed files into `Desktop/MetaBurn/Skippable` and writes `skipped-summary.txt`.
@MainActor
enum SkipExporter {
    struct Result: Equatable {
        let copiedCount: Int
        let summaryURL: URL
        let folderURL: URL
    }

    static func export(skipped: [(path: String, reason: String)]) throws -> Result? {
        guard !skipped.isEmpty else { return nil }

        Paths.ensureSkippableOutputDirectory()
        let folder = Paths.skippableOutputDirectory()
        let fm = FileManager.default
        var copied = 0

        for entry in skipped {
            // Symlinks / unreadable paths may still appear in the audit log without a copy.
            guard fm.fileExists(atPath: entry.path),
                  (try? URL(fileURLWithPath: entry.path).resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            else { continue }

            let dest = Paths.uniqueOutputURL(forSourcePath: entry.path, in: folder)
            do {
                try fm.copyItem(atPath: entry.path, toPath: dest.path)
                copied += 1
            } catch {
                Log.shared.warn(
                    "Could not copy skipped file \(entry.path): \(error.localizedDescription)",
                    scope: "skipExporter"
                )
            }
        }

        let summaryURL = folder.appendingPathComponent(OutputNaming.skippedSummaryFileName)
        let body = SkipSummary.document(entries: skipped)
        try body.write(to: summaryURL, atomically: true, encoding: .utf8)

        return Result(copiedCount: copied, summaryURL: summaryURL, folderURL: folder)
    }
}
