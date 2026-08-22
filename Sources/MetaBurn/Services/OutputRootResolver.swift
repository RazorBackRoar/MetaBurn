import Foundation
import MetaBurnCore

/// Resolves Photos / Videos / Skippable output directories for a job.
/// Active jobs use MetaBurn's private Application Support workspace; legacy destinations remain compatible.
enum OutputRootResolver {
    static func photosDirectory(forSourcePath sourcePath: String, destination: OutputDestination) -> URL {
        switch destination {
        case .workspace:
            return Paths.workspacePhotosDirectory()
        case .desktop, .adjacent:
            return resolved(AdjacentOutput.photosDirectory(forSourcePath: sourcePath), sourcePath: sourcePath)
        }
    }

    static func videosDirectory(forSourcePath sourcePath: String, destination: OutputDestination) -> URL {
        switch destination {
        case .workspace:
            return Paths.workspaceVideosDirectory()
        case .desktop, .adjacent:
            return resolved(AdjacentOutput.videosDirectory(forSourcePath: sourcePath), sourcePath: sourcePath)
        }
    }

    static func skippableDirectory(forSourcePath sourcePath: String, destination: OutputDestination) -> URL {
        switch destination {
        case .workspace:
            return Paths.cacheDirectory().appendingPathComponent(OutputNaming.skippableFolderName, isDirectory: true)
        case .desktop, .adjacent:
            return resolved(AdjacentOutput.skippableDirectory(forSourcePath: sourcePath), sourcePath: sourcePath)
        }
    }

    static func ensurePhotosDirectory(forSourcePath sourcePath: String, destination: OutputDestination) throws {
        try ensure(
            photosDirectory(forSourcePath: sourcePath, destination: destination),
            sourcePath: sourcePath,
            destination: destination
        )
    }

    static func ensureVideosDirectory(forSourcePath sourcePath: String, destination: OutputDestination) throws {
        try ensure(
            videosDirectory(forSourcePath: sourcePath, destination: destination),
            sourcePath: sourcePath,
            destination: destination
        )
    }

    static func ensureSkippableDirectory(forSourcePath sourcePath: String, destination: OutputDestination) throws {
        try ensure(
            skippableDirectory(forSourcePath: sourcePath, destination: destination),
            sourcePath: sourcePath,
            destination: destination
        )
    }

    static func allowedRoot(forSourcePath sourcePath: String, destination: OutputDestination) -> URL {
        switch destination {
        case .workspace:
            return Paths.workspaceDirectory()
        case .desktop, .adjacent:
            return URL(fileURLWithPath: sourcePath).deletingLastPathComponent()
        }
    }

    /// Heuristic: path lives under iCloud Drive / Mobile Documents.
    static func pathLooksLikeICloud(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return path.contains("/Library/Mobile Documents/") || path.contains("/Mobile Documents/")
    }

    private static func ensure(_ url: URL, sourcePath: String, destination: OutputDestination) throws {
        let ancestor: URL
        switch destination {
        case .workspace:
            Paths.ensureDirectory(Paths.applicationSupportDirectory())
            ancestor = Paths.applicationSupportDirectory()
        case .desktop, .adjacent:
            ancestor = URL(fileURLWithPath: sourcePath).deletingLastPathComponent()
        }
        try PathSafety.ensureDirectoryNoFollow(url, within: ancestor.path)
    }

    private static func resolved(_ adjacent: URL, sourcePath: String) -> URL {
        if Paths.isForbiddenCollectedMetaBurn(adjacent) {
            return URL(fileURLWithPath: sourcePath).deletingLastPathComponent()
        }
        return adjacent
    }
}
