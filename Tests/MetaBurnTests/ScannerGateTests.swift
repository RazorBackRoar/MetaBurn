import Foundation
import Testing

@testable import MetaBurn

@Suite("Scanner format gate")
struct ScannerGateTests {
    @Test("image formats with no ImageIO writer are skipped at scan, not queued")
    func nonWritableImagesSkippedAtScan() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("metaburn-scan-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // Scan-time gating depends only on extension/UTI — content is not decoded here.
        let webp = dir.appendingPathComponent("photo.webp")
        try Data("fake-webp".utf8).write(to: webp)

        let scan = try await Scanner.buildFileList(droppedPaths: [webp.path])
        #expect(scan.files.isEmpty)
        #expect(scan.skipped.count == 1)
        #expect(scan.skipped.first?.reason.contains(".webp") == true)
    }

    @Test("writable photos still queue normally")
    func writablePhotosQueue() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("metaburn-scan-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let jpg = dir.appendingPathComponent("photo.jpg")
        try Data("fake-jpg".utf8).write(to: jpg)

        let scan = try await Scanner.buildFileList(droppedPaths: [jpg.path])
        #expect(scan.files == [jpg.path])
        #expect(scan.skipped.isEmpty)
    }
}
