import Foundation
import Testing

@testable import MetaBurn

@Suite("Output collision handling")
struct OutputRaceTests {
    @Test("a claimed output name retries to the next unique name without overwriting")
    func collisionFallsBackWithoutOverwrite() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("metaburn-race-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer {
            Paths.releaseOutputURL(dir.appendingPathComponent("same.jpg"))
            try? FileManager.default.removeItem(at: dir)
        }

        // The cleaned work product waiting to be published.
        let work = dir.appendingPathComponent("worker.metaburn.tmp.jpg")
        try Data("loser-cleaned-bytes".utf8).write(to: work)

        // The racer wins the intended name first.
        let claimed = dir.appendingPathComponent("same.jpg")
        try Data("winner-bytes".utf8).write(to: claimed)

        let used = try MetadataCleaner.promoteWithCollisionRetry(
            workURL: work,
            finalURL: claimed,
            sourcePath: "/input/same.jpg"
        )

        // Loser lands on a sibling name; the winner's bytes are untouched.
        #expect(used != claimed)
        #expect(used.deletingLastPathComponent() == claimed.deletingLastPathComponent())
        #expect(try String(contentsOf: claimed, encoding: .utf8) == "winner-bytes")
        #expect(try String(contentsOf: used, encoding: .utf8) == "loser-cleaned-bytes")
        #expect(!FileManager.default.fileExists(atPath: work.path))
    }

    @Test("a free output name is used directly")
    func freeNameUsedDirectly() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("metaburn-race-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer {
            Paths.releaseOutputURL(dir.appendingPathComponent("free.jpg"))
            try? FileManager.default.removeItem(at: dir)
        }

        let work = dir.appendingPathComponent("worker.metaburn.tmp.jpg")
        try Data("cleaned".utf8).write(to: work)
        let final = dir.appendingPathComponent("free.jpg")

        let used = try MetadataCleaner.promoteWithCollisionRetry(
            workURL: work,
            finalURL: final,
            sourcePath: "/input/free.jpg"
        )
        #expect(used == final)
        #expect(try String(contentsOf: final, encoding: .utf8) == "cleaned")
    }
}
