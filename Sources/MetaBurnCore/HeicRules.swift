import Foundation

/// Pure HEIC/HEIF detection and JPEG naming helpers (no I/O).
public enum HeicRules: Sendable {
    /// Extensions that MetaBurn auto-converts to JPEG before cleaning.
    public static let convertibleExtensions: Set<String> = [".heic", ".heif"]

    /// Preferred extension for converted stills (lowercase).
    public static let jpegExtension = "jpg"

    /// True when the path's extension is HEIC or HEIF (case-insensitive).
    public static func needsJpegConversion(filePath: String) -> Bool {
        let ext = (filePath as NSString).pathExtension.lowercased()
        guard !ext.isEmpty else { return false }
        return convertibleExtensions.contains(".\(ext)")
    }

    /// Source basename with `.jpg` (or `preferredExtension`) for cleaned output naming.
    public static func jpegOutputFileName(
        forSourcePath sourcePath: String,
        preferredExtension: String = jpegExtension
    ) -> String {
        let base = URL(fileURLWithPath: sourcePath).deletingPathExtension().lastPathComponent
        let ext = preferredExtension.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return ext.isEmpty ? base : "\(base).\(ext)"
    }
}
