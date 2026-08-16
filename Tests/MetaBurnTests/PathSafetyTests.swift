import Foundation
import MetaBurnCore
import Testing

@Suite("PathSafety")
struct PathSafetyTests {
    @Test("ensureDirectoryNoFollow refuses a symlink output folder")
    func refusesSymlinkOutputFolder() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let outside = dir.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let link = dir.appendingPathComponent("MetaBurn", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

        let photos = link.appendingPathComponent("Photos", isDirectory: true)
        #expect(throws: PathSafetyError.self) {
            try PathSafety.ensureDirectoryNoFollow(photos, within: dir.path)
        }
        let outsideItems = try FileManager.default.contentsOfDirectory(atPath: outside.path)
        #expect(outsideItems.isEmpty)
    }

    @Test("copyNoFollow does not follow a source symlink")
    func copyDoesNotFollowSourceSymlink() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let real = dir.appendingPathComponent("real.jpg")
        try Data("keep".utf8).write(to: real)
        let link = dir.appendingPathComponent("alias.jpg")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let dest = dir.appendingPathComponent("copy.jpg")

        #expect(throws: PathSafetyError.symlink(link.path)) {
            try PathSafety.copyNoFollow(from: link.path, to: dest)
        }
        #expect(!FileManager.default.fileExists(atPath: dest.path))
    }
}
