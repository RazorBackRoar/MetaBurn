import Foundation

struct ScanResult {
    let files: [String]
    let skipped: [(path: String, reason: String)]
    let totalBytes: Int64
}

enum Scanner {
    static func buildFileList(droppedPaths: [String]) async throws -> ScanResult {
        var files: [String] = []
        var skipped: [(path: String, reason: String)] = []

        for dropped in droppedPaths {
            guard !dropped.isEmpty else { continue }

            let url = URL(fileURLWithPath: dropped)
            if url.lastPathComponent.hasPrefix(".") { continue }
            do {
                let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey])
                if values.isSymbolicLink == true {
                    skipped.append((dropped, "symlink skipped for safety"))
                    continue
                }
                if values.isDirectory == true {
                    let dirSkipped = try walkDirectory(url: url, files: &files)
                    skipped.append(contentsOf: dirSkipped)
                } else if values.isRegularFile == true {
                    files.append(url.path)
                } else {
                    skipped.append((dropped, "not a regular file or folder"))
                }
            } catch {
                skipped.append((dropped, "could not stat: \(error.localizedDescription)"))
            }
        }

        let deduped = Array(Set(files)).sorted()
        let totalBytes = await sumSizes(deduped)
        return ScanResult(files: deduped, skipped: skipped, totalBytes: totalBytes)
    }

    private static func walkDirectory(url: URL, files: inout [String]) throws -> [(path: String, reason: String)] {
        var walkSkipped: [(path: String, reason: String)] = []
        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles],
            errorHandler: { url, error in
                walkSkipped.append((url.path, "could not read: \(error.localizedDescription)"))
                return true
            }
        )

        while let item = enumerator?.nextObject() as? URL {
            do {
                let values = try item.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey])
                if values.isSymbolicLink == true {
                    walkSkipped.append((item.path, "symlink skipped for safety"))
                    continue
                }
                if values.isRegularFile == true {
                    files.append(item.path)
                }
            } catch {
                walkSkipped.append((item.path, "could not stat: \(error.localizedDescription)"))
            }
        }
        return walkSkipped
    }

    private static func sumSizes(_ paths: [String]) async -> Int64 {
        await withTaskGroup(of: Int64.self) { group in
            for path in paths {
                group.addTask { (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0 }
            }
            var total: Int64 = 0
            for await size in group {
                total += size
            }
            return total
        }
    }
}
