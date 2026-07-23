import Foundation

/// Deterministic output naming for cleaned copies (no filesystem side effects beyond existence checks).
public enum OutputNaming: Sendable {
    public static let desktopFolderName = "MetaBurn"
    public static let photosFolderName = "Photos"
    public static let videosFolderName = "Videos"

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

    /// Hidden sibling work file used so ExifTool never mid-writes the final destination.
    public static func workURL(forFinal finalURL: URL, uuid: String = UUID().uuidString) -> URL {
        let ext = finalURL.pathExtension
        let name = ext.isEmpty ? ".\(uuid).metaburn.tmp" : ".\(uuid).metaburn.tmp.\(ext)"
        return finalURL.deletingLastPathComponent().appendingPathComponent(name)
    }
}
