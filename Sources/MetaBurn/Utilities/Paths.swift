import Foundation
import MetaBurnCore

/// macOS path helpers aligned with the workspace `razorcore-api-spec.md`.
enum Paths {
    static var appName: String { Brand.displayName }

    static var desktopOutputFolderName: String { OutputNaming.desktopFolderName }

    static func applicationSupportDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(appName, isDirectory: true)
    }

    static func cacheDirectory() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(appName, isDirectory: true)
    }

    static func logsDirectory() -> URL {
        applicationSupportDirectory().appendingPathComponent("logs", isDirectory: true)
    }

    static func desktopDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
    }

    static func picturesDirectory() -> URL {
        FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Pictures", isDirectory: true)
    }

    /// Legacy collected path `~/Pictures/MetaBurn` — never create this folder.
    static func desktopOutputRoot() -> URL {
        picturesDirectory().appendingPathComponent(desktopOutputFolderName, isDirectory: true)
    }

    /// `~/Desktop/MetaBurn` — never create this folder (clutters Desktop next to the DMG).
    static func forbiddenDesktopMetaBurnRoot() -> URL {
        desktopDirectory().appendingPathComponent(desktopOutputFolderName, isDirectory: true)
    }

    /// True for `~/Desktop/MetaBurn` or any path under it. Does not match `MetaBurn & L!bra Test`.
    static func isForbiddenDesktopMetaBurn(_ url: URL) -> Bool {
        isUnderRoot(url, root: forbiddenDesktopMetaBurnRoot())
    }

    /// True for `~/Pictures/MetaBurn` or any path under it.
    static func isForbiddenPicturesMetaBurn(_ url: URL) -> Bool {
        isUnderRoot(url, root: desktopOutputRoot())
    }

    /// Collected dumps that must never be created: `~/Desktop/MetaBurn` and `~/Pictures/MetaBurn`.
    static func isForbiddenCollectedMetaBurn(_ url: URL) -> Bool {
        isForbiddenDesktopMetaBurn(url) || isForbiddenPicturesMetaBurn(url)
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
        guard !isForbiddenCollectedMetaBurn(url) else { return }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
    }

    static func ensureLogsDirectory() {
        ensureDirectory(logsDirectory())
    }

    static func ensureCacheDirectory() {
        ensureDirectory(cacheDirectory())
    }

    /// Unique path under `directory` for `sourcePath`'s filename (`name.ext`, `name-1.ext`, …).
    static func uniqueOutputURL(forSourcePath sourcePath: String, in directory: URL) -> URL {
        OutputNaming.uniqueURL(
            forSourcePath: sourcePath,
            in: directory,
            fileExists: { path in
                FileManager.default.fileExists(atPath: path) || PathSafety.isSymlink(path)
            }
        )
    }

    /// Local cache work file (not on Desktop/iCloud) so cleaning never mid-writes the final path.
    static func workURL(forFinal finalURL: URL) -> URL {
        ensureCacheDirectory()
        let url = OutputNaming.workURL(in: cacheDirectory(), forFinal: finalURL)
        assert(
            !isForbiddenCollectedMetaBurn(url),
            "MetaBurn work files must not live under Pictures/MetaBurn or Desktop/MetaBurn"
        )
        return url
    }

    /// Remove leftover `*.metaburn.tmp*` from cache and any leftover collected folders that already exist.
    /// Never creates `Desktop/MetaBurn`, `Pictures/MetaBurn`, or their children.
    @discardableResult
    static func cleanupOrphanWorkFiles() -> [URL] {
        ensureCacheDirectory()
        var dirs = [cacheDirectory()]
        let fm = FileManager.default
        let leftover = [
            photosOutputDirectory(),
            videosOutputDirectory(),
            skippableOutputDirectory(),
            forbiddenDesktopMetaBurnRoot().appendingPathComponent(OutputNaming.photosFolderName, isDirectory: true),
            forbiddenDesktopMetaBurnRoot().appendingPathComponent(OutputNaming.videosFolderName, isDirectory: true),
            forbiddenDesktopMetaBurnRoot().appendingPathComponent(OutputNaming.skippableFolderName, isDirectory: true)
        ]
        for dir in leftover {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue {
                dirs.append(dir)
            }
        }
        return WorkFileSafety.cleanupOrphanWorkFiles(in: dirs)
    }

    private static func isUnderRoot(_ url: URL, root: URL) -> Bool {
        let banned = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == banned || path.hasPrefix(banned + "/")
    }
}
