import Foundation

/// Deterministic output naming for cleaned copies (no filesystem side effects beyond existence checks).
public enum OutputNaming: Sendable {
    public static let desktopFolderName = "MetaBurn"
    public static let photosFolderName = "Photos"
    public static let videosFolderName = "Videos"
    public static let skippableFolderName = "Skippable"
    public static let skippedSummaryFileName = "skipped-summary.txt"
    public static let workFileMarker = "metaburn.tmp"

    /// Unique path under `directory` for `sourcePath`'s filename (`name.ext`, `name-1.ext`, …).
    public static func uniqueURL(
        forSourcePath sourcePath: String,
        in directory: URL,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> URL {
        let sourceURL = URL(fileURLWithPath: sourcePath)
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let ext = sourceURL.pathExtension
        var candidate = directory.appendingPathComponent(sourceURL.lastPathComponent)
        var index = 1
        while fileExists(candidate.path) {
            let suffix = ext.isEmpty ? "\(baseName)-\(index)" : "\(baseName)-\(index).\(ext)"
            candidate = directory.appendingPathComponent(suffix)
            index += 1
        }
        return candidate
    }

    /// Work-file name for a final destination (kept out of the Desktop output folder by Paths).
    public static func workFileName(forFinal finalURL: URL, uuid: String = UUID().uuidString) -> String {
        let ext = finalURL.pathExtension
        return ext.isEmpty ? "\(uuid).\(workFileMarker)" : "\(uuid).\(workFileMarker).\(ext)"
    }

    /// Hidden sibling work file next to the final path (legacy layout; prefer cache-based Paths.workURL).
    public static func workURL(forFinal finalURL: URL, uuid: String = UUID().uuidString) -> URL {
        let name = workFileName(forFinal: finalURL, uuid: uuid)
        return finalURL.deletingLastPathComponent().appendingPathComponent(".\(name)")
    }

    /// Work file under an explicit directory (Application Support cache — avoids iCloud Desktop stalls).
    public static func workURL(
        in directory: URL,
        forFinal finalURL: URL,
        uuid: String = UUID().uuidString
    ) -> URL {
        directory.appendingPathComponent(workFileName(forFinal: finalURL, uuid: uuid))
    }

    public static func isWorkFileName(_ name: String) -> Bool {
        name.contains(workFileMarker)
    }
}
