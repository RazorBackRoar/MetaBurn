import Foundation

/// Deterministic output naming for cleaned copies (no filesystem side effects beyond existence checks).
public enum OutputNaming: Sendable {
    public static let desktopFolderName = "MetaBurn"
    public static let photosFolderName = "Photos"
    public static let videosFolderName = "Videos"
    public static let skippableFolderName = "Skippable"
    public static let skippedSummaryFileName = "skipped-summary.txt"
    public static let workFileMarker = "metaburn.tmp"
    /// NativeImageIO atomic-replace temp files (hidden siblings of the work file).
    public static let nativeWorkFileMarker = "metaburn.native.tmp"
    /// NativeVideoClean remux temp files (hidden siblings of the work file).
    public static let videoWorkFileMarker = "metaburn.video.tmp"
    /// Every marker an orphaned work/temp file can carry — the sweep must cover all of them.
    public static let workFileMarkers: [String] = [
        workFileMarker, nativeWorkFileMarker, videoWorkFileMarker,
    ]

    /// Unique path under `directory` (`name.ext`, then `name-001.ext`, `name-002.ext`, …).
    /// Pass `replacingExtension` (e.g. `"jpg"`) to rewrite the extension — used when HEIC/HEIF
    /// is converted to JPEG before cleaning.
    public static func uniqueURL(
        forSourcePath sourcePath: String,
        in directory: URL,
        replacingExtension: String? = nil,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> URL {
        let sourceURL = URL(fileURLWithPath: sourcePath)
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let ext: String
        if let replacingExtension {
            ext = replacingExtension.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        } else {
            ext = sourceURL.pathExtension
        }
        let firstName = ext.isEmpty ? baseName : "\(baseName).\(ext)"
        var candidate = directory.appendingPathComponent(firstName)
        var index = 1
        while fileExists(candidate.path) {
            let padded = String(format: "%03d", index)
            let suffix = ext.isEmpty ? "\(baseName)-\(padded)" : "\(baseName)-\(padded).\(ext)"
            candidate = directory.appendingPathComponent(suffix)
            index += 1
        }
        return candidate
    }

    /// Work-file name for a final destination (kept out of the Desktop output folder by Paths).
    public static func workFileName(forFinal finalURL: URL, uuid: String = SecureRandom.hexString())
        -> String
    {
        let ext = finalURL.pathExtension
        return ext.isEmpty ? "\(uuid).\(workFileMarker)" : "\(uuid).\(workFileMarker).\(ext)"
    }

    /// Hidden sibling work file next to the final path (legacy layout; prefer cache-based Paths.workURL).
    public static func workURL(forFinal finalURL: URL, uuid: String = SecureRandom.hexString())
        -> URL
    {
        let name = workFileName(forFinal: finalURL, uuid: uuid)
        return finalURL.deletingLastPathComponent().appendingPathComponent(".\(name)")
    }

    /// Work file under an explicit directory (Application Support cache — avoids iCloud Desktop stalls).
    public static func workURL(
        in directory: URL,
        forFinal finalURL: URL,
        uuid: String = SecureRandom.hexString()
    ) -> URL {
        directory.appendingPathComponent(workFileName(forFinal: finalURL, uuid: uuid))
    }

    public static func isWorkFileName(_ name: String) -> Bool {
        // Marker must appear as a dotted component (`uuid.metaburn.tmp.jpg`) or as the
        // final suffix (`uuid.metaburn.tmp`) — a bare substring match would also flag
        // user files like `notes-metaburn.tmp-backup.txt`. All three producer markers
        // (cache work files, ImageIO native temps, video remux temps) are covered.
        workFileMarkers.contains { marker in
            name.contains(".\(marker).") || name.hasSuffix(".\(marker)")
        }
    }
}
