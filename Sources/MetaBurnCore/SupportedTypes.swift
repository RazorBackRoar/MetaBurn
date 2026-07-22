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

    private static let photoExts: Set<String> = [".jpg", ".jpeg", ".png", ".heic", ".heif", ".webp", ".tiff"]
    private static let videoExts: Set<String> = [".mov", ".mp4", ".m4v", ".avi", ".mkv", ".webm"]
    private static let nonWritableVideoExts: Set<String> = [".avi", ".mkv", ".webm"]

    public static func classify(filePath: String) -> FileClassification {
        let ext = (filePath as NSString).pathExtension.lowercased()
        let dotted = ext.isEmpty ? "" : ".\(ext)"

        if photoExts.contains(dotted) {
            return FileClassification(ext: dotted, kind: .photo, writable: true)
        }
        if videoExts.contains(dotted) {
            return FileClassification(ext: dotted, kind: .video, writable: !nonWritableVideoExts.contains(dotted))
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
}
