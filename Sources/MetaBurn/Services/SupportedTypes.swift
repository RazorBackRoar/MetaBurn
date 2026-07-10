import Foundation

enum SupportedTypes {
    enum FileKind { case photo, video, unsupported }

    struct FileClassification {
        let ext: String
        let kind: FileKind
        let writable: Bool
    }

    private static let photoExts: Set<String> = [".jpg", ".jpeg", ".png", ".heic", ".heif", ".webp", ".tiff"]
    private static let videoExts: Set<String> = [".mov", ".mp4", ".m4v", ".avi", ".mkv", ".webm"]
    private static let nonWritableVideoExts: Set<String> = [".mkv", ".webm", ".avi"]

    static func classify(filePath: String) -> FileClassification {
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

    static func isSupported(filePath: String) -> Bool {
        classify(filePath: filePath).kind != .unsupported
    }

    static func isVideo(filePath: String) -> Bool {
        classify(filePath: filePath).kind == .video
    }
}
