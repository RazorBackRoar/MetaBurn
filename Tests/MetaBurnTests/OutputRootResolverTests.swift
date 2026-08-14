import Foundation
import Testing
@testable import MetaBurn
import MetaBurnCore

@Suite("OutputRootResolver")
struct OutputRootResolverTests {

    let sampleSourcePath = "/Users/test/Documents/sample.jpg"

    @Test("photosDirectory returns correct URL for desktop destination")
    func testPhotosDirectoryDesktop() {
        let result = OutputRootResolver.photosDirectory(forSourcePath: sampleSourcePath, destination: .desktop)
        #expect(result == Paths.photosOutputDirectory())
    }

    @Test("photosDirectory returns correct URL for adjacent destination")
    func testPhotosDirectoryAdjacent() {
        let result = OutputRootResolver.photosDirectory(forSourcePath: sampleSourcePath, destination: .adjacent)
        #expect(result == AdjacentOutput.photosDirectory(forSourcePath: sampleSourcePath))
    }

    @Test("videosDirectory returns correct URL for desktop destination")
    func testVideosDirectoryDesktop() {
        let result = OutputRootResolver.videosDirectory(forSourcePath: sampleSourcePath, destination: .desktop)
        #expect(result == Paths.videosOutputDirectory())
    }

    @Test("videosDirectory returns correct URL for adjacent destination")
    func testVideosDirectoryAdjacent() {
        let result = OutputRootResolver.videosDirectory(forSourcePath: sampleSourcePath, destination: .adjacent)
        #expect(result == AdjacentOutput.videosDirectory(forSourcePath: sampleSourcePath))
    }

    @Test("skippableDirectory returns correct URL for desktop destination")
    func testSkippableDirectoryDesktop() {
        let result = OutputRootResolver.skippableDirectory(forSourcePath: sampleSourcePath, destination: .desktop)
        #expect(result == Paths.skippableOutputDirectory())
    }

    @Test("skippableDirectory returns correct URL for adjacent destination")
    func testSkippableDirectoryAdjacent() {
        let result = OutputRootResolver.skippableDirectory(forSourcePath: sampleSourcePath, destination: .adjacent)
        #expect(result == AdjacentOutput.skippableDirectory(forSourcePath: sampleSourcePath))
    }

    @Test("Desktop sources do not resolve under Desktop/MetaBurn")
    func desktopSourcesLeaveTheDesktop() {
        let source = Paths.desktopDirectory().appendingPathComponent("Screenshot.png").path
        let photos = OutputRootResolver.photosDirectory(forSourcePath: source, destination: .adjacent)
        let collected = OutputRootResolver.photosDirectory(forSourcePath: source, destination: .desktop)
        #expect(!Paths.isForbiddenDesktopMetaBurn(photos))
        #expect(!Paths.isForbiddenDesktopMetaBurn(collected))
        #expect(photos == Paths.photosOutputDirectory())
        #expect(collected == Paths.photosOutputDirectory())
    }

    @Test("pathLooksLikeICloud returns true for iCloud Drive paths")
    func testPathLooksLikeICloudTrue() {
        let path1 = URL(fileURLWithPath: "/Users/test/Library/Mobile Documents/com~apple~CloudDocs/photo.jpg")
        let path2 = URL(fileURLWithPath: "/Users/test/Library/Mobile Documents/somefolder/video.mp4")
        let path3 = URL(fileURLWithPath: "/var/folders/Mobile Documents/file.txt")

        #expect(OutputRootResolver.pathLooksLikeICloud(path1))
        #expect(OutputRootResolver.pathLooksLikeICloud(path2))
        #expect(OutputRootResolver.pathLooksLikeICloud(path3))
    }

    @Test("pathLooksLikeICloud returns false for regular paths")
    func testPathLooksLikeICloudFalse() {
        let path1 = URL(fileURLWithPath: "/Users/test/Desktop/photo.jpg")
        let path2 = URL(fileURLWithPath: "/Users/test/Downloads/MobileDocuments/video.mp4") // close but not exact
        let path3 = URL(fileURLWithPath: "/Users/test/Library/Documents/file.txt")

        #expect(!OutputRootResolver.pathLooksLikeICloud(path1))
        #expect(!OutputRootResolver.pathLooksLikeICloud(path2))
        #expect(!OutputRootResolver.pathLooksLikeICloud(path3))
    }

    @Test("ensure*Directory methods create directories successfully")
    func testEnsureDirectories() throws {
        // Use a temporary directory as the source to avoid writing to user space
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tempSourcePath = tempDir.appendingPathComponent("test.jpg").path

        // We test with .adjacent so it writes inside our tempDir instead of the user's Desktop
        let expectedPhotosURL = AdjacentOutput.photosDirectory(forSourcePath: tempSourcePath)
        let expectedVideosURL = AdjacentOutput.videosDirectory(forSourcePath: tempSourcePath)
        let expectedSkippableURL = AdjacentOutput.skippableDirectory(forSourcePath: tempSourcePath)

        // Ensure directories don't exist yet
        #expect(!FileManager.default.fileExists(atPath: expectedPhotosURL.path))
        #expect(!FileManager.default.fileExists(atPath: expectedVideosURL.path))
        #expect(!FileManager.default.fileExists(atPath: expectedSkippableURL.path))

        OutputRootResolver.ensurePhotosDirectory(forSourcePath: tempSourcePath, destination: .adjacent)
        OutputRootResolver.ensureVideosDirectory(forSourcePath: tempSourcePath, destination: .adjacent)
        OutputRootResolver.ensureSkippableDirectory(forSourcePath: tempSourcePath, destination: .adjacent)

        var isDir: ObjCBool = false

        #expect(FileManager.default.fileExists(atPath: expectedPhotosURL.path, isDirectory: &isDir))
        #expect(isDir.boolValue)

        #expect(FileManager.default.fileExists(atPath: expectedVideosURL.path, isDirectory: &isDir))
        #expect(isDir.boolValue)

        #expect(FileManager.default.fileExists(atPath: expectedSkippableURL.path, isDirectory: &isDir))
        #expect(isDir.boolValue)
    }
}
