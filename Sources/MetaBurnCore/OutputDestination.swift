import Foundation

/// Where cleaned copies are written. Originals are never overwritten.
public enum OutputDestination: String, Sendable, CaseIterable {
    /// `~/Desktop/MetaBurn/{Photos,Videos,Skippable}` (default).
    case desktop
    /// `dirname(source)/MetaBurn/{Photos,Videos,Skippable}` — next to the originals.
    case adjacent
}

/// Pure path layout for adjacent (source-relative) output roots.
public enum AdjacentOutput: Sendable {
    public static func root(forSourcePath sourcePath: String) -> URL {
        URL(fileURLWithPath: sourcePath)
            .deletingLastPathComponent()
            .appendingPathComponent(OutputNaming.desktopFolderName, isDirectory: true)
    }

    public static func photosDirectory(forSourcePath sourcePath: String) -> URL {
        root(forSourcePath: sourcePath)
            .appendingPathComponent(OutputNaming.photosFolderName, isDirectory: true)
    }

    public static func videosDirectory(forSourcePath sourcePath: String) -> URL {
        root(forSourcePath: sourcePath)
            .appendingPathComponent(OutputNaming.videosFolderName, isDirectory: true)
    }

    public static func skippableDirectory(forSourcePath sourcePath: String) -> URL {
        root(forSourcePath: sourcePath)
            .appendingPathComponent(OutputNaming.skippableFolderName, isDirectory: true)
    }
}
