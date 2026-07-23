import Foundation

/// Pure classification of media paths by extension (no I/O).
public enum SupportedTypes: Sendable {
    public enum FileKind: Sendable {
        case photo, video, unsupported
    }

    public struct FileClassification: Sendable {
        public let ext: String
        public let kind: FileKind
        public let writable: Bool

        public init(ext: String, kind: FileKind, writable: Bool) {
            self.ext = ext
            self.kind = kind
            self.writable = writable
        }
    }

    /// Standard still-image formats cleaned via ImageIO (with ExifTool fallback).
    private static let photoExts: Set<String> = [
        ".jpg", ".jpeg", ".jpe", ".jfif",
        ".png",
        ".heic", ".heif",
        ".webp",
        ".tif", ".tiff",
        ".bmp",
        ".jp2", ".j2k"
    ]
    /// Writable video containers ExifTool can clean safely.
    private static let videoExts: Set<String> = [".mov", ".mp4", ".m4v"]
    /// Known video-like types we refuse to rewrite (routed to Skippable).
    private static let nonWritableVideoExts: Set<String> = [".avi", ".mkv"]
    /// Explicitly unsupported — always Skippable (never queued for cleaning).
    private static let alwaysUnsupportedExts: Set<String> = [".gif", ".webm"]

    public static func classify(filePath: String) -> FileClassification {
        let ext = (filePath as NSString).pathExtension.lowercased()
        let dotted = ext.isEmpty ? "" : ".\(ext)"

        if alwaysUnsupportedExts.contains(dotted) {
            return FileClassification(ext: dotted, kind: .unsupported, writable: false)
        }
        if photoExts.contains(dotted) {
            return FileClassification(ext: dotted, kind: .photo, writable: true)
        }
        if videoExts.contains(dotted) {
            return FileClassification(ext: dotted, kind: .video, writable: true)
        }
        if nonWritableVideoExts.contains(dotted) {
            return FileClassification(ext: dotted, kind: .video, writable: false)
        }
        return FileClassification(ext: dotted, kind: .unsupported, writable: false)
    }

    public static func isSupported(filePath: String) -> Bool {
        classify(filePath: filePath).kind != .unsupported
    }

    public static func isVideo(filePath: String) -> Bool {
        classify(filePath: filePath).kind == .video
    }

    public static func isPhoto(filePath: String) -> Bool {
        classify(filePath: filePath).kind == .photo
    }

    /// Processable = photo/video we can safely clean. `nil` means queue for cleaning.
    public static func skipReason(filePath: String) -> String? {
        let info = classify(filePath: filePath)
        let label = info.ext.isEmpty ? "unknown type" : info.ext
        switch info.kind {
        case .unsupported:
            return "unsupported file type (\(label))"
        case .video where !info.writable:
            return "video container not safely writable (\(label))"
        case .photo, .video:
            return nil
        }
    }

    public static func isProcessable(filePath: String) -> Bool {
        skipReason(filePath: filePath) == nil
    }
}
