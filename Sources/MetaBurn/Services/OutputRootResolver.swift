import Foundation
import MetaBurnCore

/// Resolves Photos / Videos / Skippable output directories for a job.
/// Cleaned copies go next to the originals. Never creates `~/Pictures/MetaBurn` or `~/Desktop/MetaBurn`.
enum OutputRootResolver {
    static func photosDirectory(forSourcePath sourcePath: String, destination: OutputDestination) -> URL {
        resolved(AdjacentOutput.photosDirectory(forSourcePath: sourcePath), sourcePath: sourcePath, destination: destination)
    }

    static func videosDirectory(forSourcePath sourcePath: String, destination: OutputDestination) -> URL {
        resolved(AdjacentOutput.videosDirectory(forSourcePath: sourcePath), sourcePath: sourcePath, destination: destination)
    }

    static func skippableDirectory(forSourcePath sourcePath: String, destination: OutputDestination) -> URL {
        resolved(AdjacentOutput.skippableDirectory(forSourcePath: sourcePath), sourcePath: sourcePath, destination: destination)
    }

    static func ensurePhotosDirectory(forSourcePath sourcePath: String, destination: OutputDestination) {
        Paths.ensureDirectory(photosDirectory(forSourcePath: sourcePath, destination: destination))
    }

    static func ensureVideosDirectory(forSourcePath sourcePath: String, destination: OutputDestination) {
        Paths.ensureDirectory(videosDirectory(forSourcePath: sourcePath, destination: destination))
    }

    static func ensureSkippableDirectory(forSourcePath sourcePath: String, destination: OutputDestination) {
        Paths.ensureDirectory(skippableDirectory(forSourcePath: sourcePath, destination: destination))
    }

    /// Heuristic: path lives under iCloud Drive / Mobile Documents.
    static func pathLooksLikeICloud(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return path.contains("/Library/Mobile Documents/") || path.contains("/Mobile Documents/")
    }

    /// Adjacent `MetaBurn/{Photos,Videos,Skippable}` beside the source, unless that would
    /// create `~/Desktop/MetaBurn` or `~/Pictures/MetaBurn` — then write in the source's folder.
    private static func resolved(_ adjacent: URL, sourcePath: String, destination: OutputDestination) -> URL {
        switch destination {
        case .desktop, .adjacent:
            if Paths.isForbiddenCollectedMetaBurn(adjacent) {
                return URL(fileURLWithPath: sourcePath).deletingLastPathComponent()
            }
            return adjacent
        }
    }
}
