import Foundation
import MetaBurnCore

/// macOS path helpers aligned with the workspace `razorcore-api-spec.md`.
enum Paths {
    static var appName: String { Brand.displayName }

    /// User-facing cleaned output root: `~/Desktop/MetaBurn` (created only when first needed).
    static var desktopOutputFolderName: String { OutputNaming.desktopFolderName }

    static func applicationSupportDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(appName, isDirectory: true)
    }

    static func cacheDirectory() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(appName, isDirectory: true)
    }

    static func logsDirectory() -> URL {
        applicationSupportDirectory().appendingPathComponent("logs", isDirectory: true)
    }

    static func desktopDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
    }

    static func desktopOutputRoot() -> URL {
        desktopDirectory().appendingPathComponent(desktopOutputFolderName, isDirectory: true)
    }

    static func photosOutputDirectory() -> URL {
        desktopOutputRoot().appendingPathComponent(OutputNaming.photosFolderName, isDirectory: true)
    }

    static func videosOutputDirectory() -> URL {
        desktopOutputRoot().appendingPathComponent(OutputNaming.videosFolderName, isDirectory: true)
    }

    static func skippableOutputDirectory() -> URL {
        desktopOutputRoot().appendingPathComponent(OutputNaming.skippableFolderName, isDirectory: true)
    }

    static func ensureDirectory(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
    }

    static func ensureLogsDirectory() {
        ensureDirectory(logsDirectory())
    }

    static func ensureCacheDirectory() {
        ensureDirectory(cacheDirectory())
    }

    /// Create only the Photos output folder (and `Desktop/MetaBurn` if needed).
    static func ensurePhotosOutputDirectory() {
        ensureDirectory(photosOutputDirectory())
    }

    /// Create only the Videos output folder (and `Desktop/MetaBurn` if needed).
    static func ensureVideosOutputDirectory() {
        ensureDirectory(videosOutputDirectory())
    }

    /// Create only the Skippable output folder (and `Desktop/MetaBurn` if needed).
    static func ensureSkippableOutputDirectory() {
        ensureDirectory(skippableOutputDirectory())
    }

    /// Unique path under `directory` for `sourcePath`'s filename (`name.ext`, `name-1.ext`, …).
    static func uniqueOutputURL(forSourcePath sourcePath: String, in directory: URL) -> URL {
        OutputNaming.uniqueURL(forSourcePath: sourcePath, in: directory)
    }

    /// Local cache work file (not on Desktop/iCloud) so ExifTool never mid-writes the final path.
    static func workURL(forFinal finalURL: URL) -> URL {
        ensureCacheDirectory()
        let url = OutputNaming.workURL(in: cacheDirectory(), forFinal: finalURL)
        assert(
            !WorkFileSafety.isWorkFileOnDesktopOutput(workURL: url, desktopOutputRoot: desktopOutputRoot()),
            "MetaBurn work files must not live under Desktop/MetaBurn"
        )
        return url
    }

    /// Remove leftover `*.metaburn.tmp*` from cache and any Desktop output folders that already exist.
    /// Never creates `Desktop/MetaBurn` or its children.
    @discardableResult
    static func cleanupOrphanWorkFiles() -> [URL] {
        ensureCacheDirectory()
        var dirs = [cacheDirectory()]
        let fm = FileManager.default
        for dir in [photosOutputDirectory(), videosOutputDirectory(), skippableOutputDirectory()] {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue {
                dirs.append(dir)
            }
        }
        return WorkFileSafety.cleanupOrphanWorkFiles(in: dirs)
    }
}
