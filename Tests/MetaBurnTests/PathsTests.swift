import Foundation
import Testing
@testable import MetaBurn
import MetaBurnCore

@Suite("Paths")
struct PathsTests {

    @Test("applicationSupportDirectory appends app name correctly")
    func testApplicationSupportDirectory() {
        let url = Paths.applicationSupportDirectory()
        let expectedBase = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let expectedURL = expectedBase.appendingPathComponent(Brand.displayName, isDirectory: true)

        #expect(url == expectedURL)
        #expect(url.lastPathComponent == Brand.displayName)
    }

    @Test("cacheDirectory appends app name correctly")
    func testCacheDirectory() {
        let url = Paths.cacheDirectory()
        let expectedBase = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let expectedURL = expectedBase.appendingPathComponent(Brand.displayName, isDirectory: true)

        #expect(url == expectedURL)
        #expect(url.lastPathComponent == Brand.displayName)
    }

    @Test("logsDirectory resides within applicationSupportDirectory")
    func testLogsDirectory() {
        let url = Paths.logsDirectory()
        let expectedURL = Paths.applicationSupportDirectory().appendingPathComponent("logs", isDirectory: true)

        #expect(url == expectedURL)
        #expect(url.path.contains("logs"))
    }

    @Test("desktopDirectory points to user's Desktop")
    func testDesktopDirectory() {
        let url = Paths.desktopDirectory()
        let expectedURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)

        #expect(url == expectedURL)
    }

    @Test("desktopOutputRoot names the forbidden Pictures/MetaBurn path")
    func testDesktopOutputRoot() {
        let url = Paths.desktopOutputRoot()
        let expectedURL = Paths.picturesDirectory().appendingPathComponent(OutputNaming.desktopFolderName, isDirectory: true)

        #expect(url == expectedURL)
        #expect(url.lastPathComponent == OutputNaming.desktopFolderName)
        #expect(Paths.isForbiddenPicturesMetaBurn(url))
        #expect(!Paths.isForbiddenDesktopMetaBurn(url))
    }

    @Test("photosOutputDirectory uses correct folder name")
    func testPhotosOutputDirectory() {
        let url = Paths.photosOutputDirectory()
        let expectedURL = Paths.desktopOutputRoot().appendingPathComponent(OutputNaming.photosFolderName, isDirectory: true)

        #expect(url == expectedURL)
        #expect(url.lastPathComponent == OutputNaming.photosFolderName)
    }

    @Test("videosOutputDirectory uses correct folder name")
    func testVideosOutputDirectory() {
        let url = Paths.videosOutputDirectory()
        let expectedURL = Paths.desktopOutputRoot().appendingPathComponent(OutputNaming.videosFolderName, isDirectory: true)

        #expect(url == expectedURL)
        #expect(url.lastPathComponent == OutputNaming.videosFolderName)
    }

    @Test("skippableOutputDirectory uses correct folder name")
    func testSkippableOutputDirectory() {
        let url = Paths.skippableOutputDirectory()
        let expectedURL = Paths.desktopOutputRoot().appendingPathComponent(OutputNaming.skippableFolderName, isDirectory: true)

        #expect(url == expectedURL)
        #expect(url.lastPathComponent == OutputNaming.skippableFolderName)
    }

    @Test("uniqueOutputURL forwards to OutputNaming")
    func testUniqueOutputURL() {
        let dir = URL(fileURLWithPath: "/tmp", isDirectory: true)
        let sourcePath = "/path/to/test.jpg"
        let url = Paths.uniqueOutputURL(forSourcePath: sourcePath, in: dir)

        let expectedURL = OutputNaming.uniqueURL(forSourcePath: sourcePath, in: dir)
        #expect(url == expectedURL)
    }

    @Test("workURL generates a safe path in cache directory")
    func testWorkURL() {
        let finalURL = Paths.photosOutputDirectory().appendingPathComponent("test.jpg")
        let url = Paths.workURL(forFinal: finalURL)

        // Assert it's in the cache directory
        #expect(url.path.hasPrefix(Paths.cacheDirectory().path))

        // Assert it's not in the desktop output root
        #expect(!url.path.hasPrefix(Paths.desktopOutputRoot().path))
        #expect(!Paths.isForbiddenDesktopMetaBurn(url))
    }

    @Test("Desktop/MetaBurn and Pictures/MetaBurn are forbidden collected roots")
    func forbiddenCollectedRoots() {
        let bannedRoot = Paths.forbiddenDesktopMetaBurnRoot()
        let bannedPhotos = bannedRoot.appendingPathComponent("Photos", isDirectory: true)
        #expect(Paths.isForbiddenDesktopMetaBurn(bannedRoot))
        #expect(Paths.isForbiddenDesktopMetaBurn(bannedPhotos))
        #expect(Paths.isForbiddenCollectedMetaBurn(bannedPhotos))
        #expect(Paths.isForbiddenPicturesMetaBurn(Paths.desktopOutputRoot()))
        #expect(Paths.isForbiddenPicturesMetaBurn(Paths.photosOutputDirectory()))
        #expect(Paths.isForbiddenCollectedMetaBurn(Paths.photosOutputDirectory()))

        let testMedia = Paths.desktopDirectory().appendingPathComponent("MetaBurn & L!bra Test", isDirectory: true)
        #expect(!Paths.isForbiddenDesktopMetaBurn(testMedia))
        #expect(!Paths.isForbiddenPicturesMetaBurn(testMedia))
        #expect(!Paths.isForbiddenCollectedMetaBurn(testMedia))
    }

    @Test("ensureDirectory never creates Pictures/MetaBurn")
    func ensureDirectorySkipsPicturesMetaBurn() {
        let picturesRoot = Paths.desktopOutputRoot()
        let picturesPhotos = Paths.photosOutputDirectory()
        #expect(!FileManager.default.fileExists(atPath: picturesRoot.path))
        Paths.ensureDirectory(picturesRoot)
        Paths.ensureDirectory(picturesPhotos)
        #expect(!FileManager.default.fileExists(atPath: picturesRoot.path))
        #expect(!FileManager.default.fileExists(atPath: picturesPhotos.path))
    }
}
