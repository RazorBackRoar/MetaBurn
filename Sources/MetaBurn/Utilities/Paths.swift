import Foundation
import MetaBurnCore

/// macOS path helpers aligned with the workspace `razorcore-api-spec.md`.
enum Paths {
    static var appName: String { Brand.displayName }

    /// Collected output root: `~/Pictures/MetaBurn` (never `~/Desktop/MetaBurn`).
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

    /// Collected cleaned copies: `~/Pictures/MetaBurn`.
    static func desktopOutputRoot() -> URL {
        picturesDirectory().appendingPathComponent(desktopOutputFolderName, isDirectory: true)
    }

    /// `~/Desktop/MetaBurn` — never create this folder (clutters Desktop next to the DMG).
    static func forbiddenDesktopMetaBurnRoot() -> URL {
        desktopDirectory().appendingPathComponent(desktopOutputFolderName, isDirectory: true)
    }

    /// True for `~/Desktop/MetaBurn` or any path under it. Does not match `MetaBurn & L!bra Test`.
    static func isForbiddenDesktopMetaBurn(_ url: URL) -> Bool {
        let banned = forbiddenDesktopMetaBurnRoot().standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == banned || path.hasPrefix(banned + "/")
    }

    /// If `url` would land in `~/Desktop/MetaBurn`, rewrite it under `~/Pictures/MetaBurn`.
    static func relocatingOffDesktopMetaBurn(_ url: URL) -> URL {
        guard isForbiddenDesktopMetaBurn(url) else { return url }
        let banned = forbiddenDesktopMetaBurnRoot().standardizedFileURL
        let path = url.standardizedFileURL.path
        let rest = String(path.dropFirst(banned.path.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if rest.isEmpty {
            return desktopOutputRoot()
        }
        return desktopOutputRoot().appendingPathComponent(rest, isDirectory: url.hasDirectoryPath)
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
        let target = relocatingOffDesktopMetaBurn(url)
        guard !isForbiddenDesktopMetaBurn(target) else { return }
        try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true, attributes: nil)
    }

    static func ensureLogsDirectory() {
        ensureDirectory(logsDirectory())
    }

    static func ensureCacheDirectory() {
        ensureDirectory(cacheDirectory())
    }

    /// Create only the Photos output folder (and `Pictures/MetaBurn` if needed).
    static func ensurePhotosOutputDirectory() {
        ensureDirectory(photosOutputDirectory())
    }

    /// Create only the Videos output folder (and `Pictures/MetaBurn` if needed).
    static func ensureVideosOutputDirectory() {
        ensureDirectory(videosOutputDirectory())
    }

    /// Create only the Skippable output folder (and `Pictures/MetaBurn` if needed).
    static func ensureSkippableOutputDirectory() {
        ensureDirectory(skippableOutputDirectory())
    }

    /// Unique path under `directory` for `sourcePath`'s filename (`name.ext`, `name-1.ext`, …).
    static func uniqueOutputURL(forSourcePath sourcePath: String, in directory: URL) -> URL {
        OutputNaming.uniqueURL(forSourcePath: sourcePath, in: directory)
    }

    /// Local cache work file (not on Desktop/iCloud) so cleaning never mid-writes the final path.
    static func workURL(forFinal finalURL: URL) -> URL {
        ensureCacheDirectory()
        let url = OutputNaming.workURL(in: cacheDirectory(), forFinal: finalURL)
        assert(
            !WorkFileSafety.isWorkFileOnDesktopOutput(workURL: url, desktopOutputRoot: desktopOutputRoot()),
            "MetaBurn work files must not live under Pictures/MetaBurn"
        )
        return url
    }

    /// Remove leftover `*.metaburn.tmp*` from cache and any collected output folders that already exist.
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
