import Foundation
import MetaBurnCore

/// macOS path helpers aligned with the workspace `razorcore-api-spec.md`.
enum Paths {
    static var appName: String { Brand.displayName }

    /// User-facing cleaned output root: `~/Desktop/MetaBurn`.
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

    static func ensureDirectory(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
    }

    static func ensureLogsDirectory() {
        ensureDirectory(logsDirectory())
    }

    static func ensureCacheDirectory() {
        ensureDirectory(cacheDirectory())
    }

    /// Creates `~/Desktop/MetaBurn/{Photos,Videos}` for cleaned output.
    static func ensureDesktopOutputDirectories() {
        ensureDirectory(photosOutputDirectory())
        ensureDirectory(videosOutputDirectory())
    }

    /// Unique path under `directory` for `sourcePath`'s filename (`name.ext`, `name-1.ext`, …).
    static func uniqueOutputURL(forSourcePath sourcePath: String, in directory: URL) -> URL {
        OutputNaming.uniqueURL(forSourcePath: sourcePath, in: directory)
    }

    /// Hidden work file beside the final destination (never ExifTool's final path).
    static func workURL(forFinal finalURL: URL) -> URL {
        OutputNaming.workURL(forFinal: finalURL)
    }
}
