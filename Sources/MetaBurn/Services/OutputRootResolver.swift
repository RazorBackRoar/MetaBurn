import Foundation
import MetaBurnCore

/// Resolves Photos / Videos / Skippable output directories for a job.
enum OutputRootResolver {
    static func photosDirectory(forSourcePath sourcePath: String, destination: OutputDestination) -> URL {
        switch destination {
        case .desktop:
            return Paths.photosOutputDirectory()
        case .adjacent:
            return AdjacentOutput.photosDirectory(forSourcePath: sourcePath)
        }
    }

    static func videosDirectory(forSourcePath sourcePath: String, destination: OutputDestination) -> URL {
        switch destination {
        case .desktop:
            return Paths.videosOutputDirectory()
        case .adjacent:
            return AdjacentOutput.videosDirectory(forSourcePath: sourcePath)
        }
    }

    static func skippableDirectory(forSourcePath sourcePath: String, destination: OutputDestination) -> URL {
        switch destination {
        case .desktop:
            return Paths.skippableOutputDirectory()
        case .adjacent:
            return AdjacentOutput.skippableDirectory(forSourcePath: sourcePath)
        }
    }

    static func ensurePhotosDirectory(forSourcePath sourcePath: String, destination: OutputDestination) {
        let url = photosDirectory(forSourcePath: sourcePath, destination: destination)
        Paths.ensureDirectory(url)
    }

    static func ensureVideosDirectory(forSourcePath sourcePath: String, destination: OutputDestination) {
        let url = videosDirectory(forSourcePath: sourcePath, destination: destination)
        Paths.ensureDirectory(url)
    }

    static func ensureSkippableDirectory(forSourcePath sourcePath: String, destination: OutputDestination) {
        let url = skippableDirectory(forSourcePath: sourcePath, destination: destination)
        Paths.ensureDirectory(url)
    }

    /// Heuristic: path lives under iCloud Drive / Mobile Documents.
    static func pathLooksLikeICloud(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return path.contains("/Library/Mobile Documents/") || path.contains("/Mobile Documents/")
    }
}
