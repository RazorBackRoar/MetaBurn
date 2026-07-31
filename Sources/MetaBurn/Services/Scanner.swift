import Foundation
import MetaBurnCore

struct ScanResult {
    let files: [String]
    let skipped: [(path: String, reason: String)]
    let totalBytes: Int64
}

enum Scanner {
    static func buildFileList(droppedPaths: [String]) async throws -> ScanResult {
        var fileSizes: [String: Int64] = [:]
        var skipped: [(path: String, reason: String)] = []

        for dropped in droppedPaths {
            guard !dropped.isEmpty else { continue }

            let url = URL(fileURLWithPath: dropped)
            if url.lastPathComponent.hasPrefix(".") { continue }
            do {
                let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey, .fileSizeKey])
                if values.isSymbolicLink == true {
                    skipped.append((dropped, "symlink skipped for safety"))
                    continue
                }
                if values.isDirectory == true {
                    let dirSkipped = try walkDirectory(url: url, fileSizes: &fileSizes, skipped: &skipped)
                    skipped.append(contentsOf: dirSkipped)
                } else if values.isRegularFile == true {
                    let size = Int64(values.fileSize ?? 0)
                    classifyAndBucket(url.path, size: size, fileSizes: &fileSizes, skipped: &skipped)
                } else {
                    skipped.append((dropped, "not a regular file or folder"))
                }
            } catch {
                skipped.append((dropped, "could not stat: \(error.localizedDescription)"))
            }
        }

        let deduped = fileSizes.keys.sorted()
        let totalBytes = fileSizes.values.reduce(0, +)
        return ScanResult(files: deduped, skipped: skipped, totalBytes: totalBytes)
    }

    private static func classifyAndBucket(
        _ path: String,
        size: Int64,
        fileSizes: inout [String: Int64],
        skipped: inout [(path: String, reason: String)]
    ) {
        if let reason = SupportedTypes.skipReason(filePath: path) {
            skipped.append((path, reason))
        } else {
            fileSizes[path] = size
        }
    }

    private static func walkDirectory(
        url: URL,
        fileSizes: inout [String: Int64],
        skipped: inout [(path: String, reason: String)]
    ) throws -> [(path: String, reason: String)] {
        var walkSkipped: [(path: String, reason: String)] = []
        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles],
            errorHandler: { url, error in
                walkSkipped.append((url.path, "could not read: \(error.localizedDescription)"))
                return true
            }
        )

        while let item = enumerator?.nextObject() as? URL {
            do {
                let values = try item.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey, .fileSizeKey])
                if values.isSymbolicLink == true {
                    walkSkipped.append((item.path, "symlink skipped for safety"))
                    continue
                }
                if values.isRegularFile == true {
                    let size = Int64(values.fileSize ?? 0)
                    classifyAndBucket(item.path, size: size, fileSizes: &fileSizes, skipped: &skipped)
                }
            } catch {
                walkSkipped.append((item.path, "could not stat: \(error.localizedDescription)"))
            }
        }
        return walkSkipped
    }
}
