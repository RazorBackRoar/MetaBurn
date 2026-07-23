import Darwin
import Foundation

/// Guards against the Desktop/iCloud + quarantine stall that left orphan `.metaburn.tmp` work files.
public enum WorkFileSafety: Sendable {
    /// xattrs that have stalled ExifTool / file coordination on synced Desktop paths.
    public static let stallingXattrNames: [String] = [
        "com.apple.quarantine",
        "com.apple.macl",
        "com.apple.FinderInfo"
    ]

    /// True when `workURL` lives under the Desktop output tree (forbidden — use local cache instead).
    public static func isWorkFileOnDesktopOutput(workURL: URL, desktopOutputRoot: URL) -> Bool {
        let work = workURL.standardizedFileURL.path
        let root = desktopOutputRoot.standardizedFileURL.path
        guard !root.isEmpty else { return false }
        return work == root || work.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }

    /// Remove quarantine / MACL / FinderInfo from a work copy before ExifTool touches it.
    @discardableResult
    public static func stripStallingXattrs(atPath path: String) -> [String] {
        var removed: [String] = []
        for name in stallingXattrNames {
            let result = path.withCString { pathPtr in
                name.withCString { namePtr in
                    removexattr(pathPtr, namePtr, 0)
                }
            }
            if result == 0 {
                removed.append(name)
            }
        }
        return removed
    }

    /// Whether the named xattr is currently present on `path`.
    public static func hasXattr(atPath path: String, name: String) -> Bool {
        path.withCString { pathPtr in
            name.withCString { namePtr in
                getxattr(pathPtr, namePtr, nil, 0, 0, 0) >= 0
            }
        }
    }

    /// Set a string xattr (tests / diagnostics). Returns false on failure.
    @discardableResult
    public static func setXattr(atPath path: String, name: String, value: String) -> Bool {
        value.withCString { valuePtr in
            path.withCString { pathPtr in
                name.withCString { namePtr in
                    setxattr(pathPtr, namePtr, valuePtr, strlen(valuePtr), 0, 0) == 0
                }
            }
        }
    }

    /// Delete every `*metaburn.tmp*` entry under the given directories (cache + legacy Desktop orphans).
    @discardableResult
    public static func cleanupOrphanWorkFiles(
        in directories: [URL],
        fileManager: FileManager = .default
    ) -> [URL] {
        var removed: [URL] = []
        for dir in directories {
            guard let names = try? fileManager.contentsOfDirectory(atPath: dir.path) else { continue }
            for name in names where OutputNaming.isWorkFileName(name) {
                let url = dir.appendingPathComponent(name)
                do {
                    try fileManager.removeItem(at: url)
                    removed.append(url)
                } catch {
                    continue
                }
            }
        }
        return removed
    }
}
