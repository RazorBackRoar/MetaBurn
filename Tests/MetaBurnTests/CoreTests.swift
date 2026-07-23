import Foundation
import MetaBurnCore
import Testing

@Suite("SupportedTypes")
struct SupportedTypesTests {
    @Test("classifies common photo extensions")
    func photos() {
        for path in [
            "a.jpg", "b.JPEG", "c.jpe", "d.jfif", "e.png", "f.heic", "g.heif",
            "h.webp", "i.tiff", "j.tif", "k.bmp", "l.jp2", "m.j2k"
        ] {
            let info = SupportedTypes.classify(filePath: path)
            #expect(info.kind == .photo)
            #expect(info.writable)
        }
    }

    @Test("classifies writable videos; avi/mkv are non-writable videos")
    func videos() {
        #expect(SupportedTypes.classify(filePath: "clip.mov").writable)
        #expect(SupportedTypes.classify(filePath: "clip.mp4").writable)
        #expect(SupportedTypes.classify(filePath: "clip.m4v").writable)
        #expect(!SupportedTypes.classify(filePath: "clip.mkv").writable)
        #expect(!SupportedTypes.classify(filePath: "clip.avi").writable)
        #expect(SupportedTypes.classify(filePath: "clip.mkv").kind == .video)
        #expect(SupportedTypes.skipReason(filePath: "clip.mkv") != nil)
        #expect(SupportedTypes.isProcessable(filePath: "clip.mov"))
    }

    @Test("gif and webm are unsupported and not processable")
    func gifAndWebmUnsupported() {
        #expect(SupportedTypes.classify(filePath: "anim.gif").kind == .unsupported)
        #expect(SupportedTypes.classify(filePath: "clip.webm").kind == .unsupported)
        #expect(!SupportedTypes.isProcessable(filePath: "anim.gif"))
        #expect(!SupportedTypes.isProcessable(filePath: "clip.webm"))
        #expect(SupportedTypes.skipReason(filePath: "anim.gif")?.contains(".gif") == true)
        #expect(SupportedTypes.skipReason(filePath: "clip.webm")?.contains(".webm") == true)
    }

    @Test("rejects unsupported office and script types")
    func unsupported() {
        for path in ["notes.txt", "report.pdf", "memo.doc", "run.sh", "data.xlsx"] {
            #expect(SupportedTypes.classify(filePath: path).kind == .unsupported)
            #expect(!SupportedTypes.isProcessable(filePath: path))
            #expect(SupportedTypes.skipReason(filePath: path) != nil)
        }
    }
}

@Suite("OutputNaming")
struct OutputNamingTests {
    @Test("uniqueURL increments when destination exists")
    func uniqueIncrements() {
        let dir = URL(fileURLWithPath: "/tmp/metaburn-test", isDirectory: true)
        let existing: Set<String> = [
            "/tmp/metaburn-test/shot.jpg",
            "/tmp/metaburn-test/shot-1.jpg"
        ]
        let url = OutputNaming.uniqueURL(
            forSourcePath: "/in/shot.jpg",
            in: dir,
            fileExists: { existing.contains($0) }
        )
        #expect(url.lastPathComponent == "shot-2.jpg")
    }

    @Test("workURL stays in an explicit work directory")
    func workURLInDirectory() {
        let final = URL(fileURLWithPath: "/tmp/metaburn/Photos/img.heic")
        let workDir = URL(fileURLWithPath: "/tmp/metaburn-cache", isDirectory: true)
        let work = OutputNaming.workURL(in: workDir, forFinal: final, uuid: "ABC")
        #expect(work.lastPathComponent == "ABC.metaburn.tmp.heic")
        #expect(work.deletingLastPathComponent() == workDir)
    }

    @Test("legacy sibling workURL stays hidden beside the final file")
    func workURLHiddenSibling() {
        let final = URL(fileURLWithPath: "/tmp/metaburn/Photos/img.heic")
        let work = OutputNaming.workURL(forFinal: final, uuid: "ABC")
        #expect(work.lastPathComponent == ".ABC.metaburn.tmp.heic")
        #expect(work.deletingLastPathComponent() == final.deletingLastPathComponent())
    }

    @Test("uniqueURL second pass increments past existing copies")
    func uniqueSecondPass() {
        let dir = URL(fileURLWithPath: "/tmp/metaburn-test", isDirectory: true)
        let existing: Set<String> = [
            "/tmp/metaburn-test/IMG_2667_plus.JPG",
            "/tmp/metaburn-test/IMG_2667_plus-1.JPG",
            "/tmp/metaburn-test/IMG_2667.jpeg",
            "/tmp/metaburn-test/IMG_2667-1.jpeg"
        ]
        let plus = OutputNaming.uniqueURL(
            forSourcePath: "/in/IMG_2667_plus.JPG",
            in: dir,
            fileExists: { existing.contains($0) }
        )
        #expect(plus.lastPathComponent == "IMG_2667_plus-2.JPG")
    }

    @Test("isWorkFileName detects metaburn temp markers")
    func workFileMarker() {
        #expect(OutputNaming.isWorkFileName("ABC.metaburn.tmp.JPG"))
        #expect(OutputNaming.isWorkFileName(".ABC.metaburn.tmp.jpeg"))
        #expect(!OutputNaming.isWorkFileName("IMG_2667_plus.JPG"))
    }

    @Test("skippable folder and summary names are stable")
    func skippableNames() {
        #expect(OutputNaming.skippableFolderName == "Skippable")
        #expect(OutputNaming.skippedSummaryFileName == "skipped-summary.txt")
    }
}

@Suite("SkipSummary")
struct SkipSummaryTests {
    @Test("lines are numbered with file name and reason")
    func numberedLines() {
        let line = SkipSummary.line(index: 1, filePath: "/in/photo.gif", reason: "unsupported file type (.gif)")
        #expect(line == "1. photo.gif - unsupported file type (.gif)")
    }

    @Test("document lists every bypassed file")
    func documentBody() {
        let body = SkipSummary.document(entries: [
            (path: "/a/photo.gif", reason: "unsupported file type (.gif)"),
            (path: "/a/clip.webm", reason: "unsupported file type (.webm)"),
            (path: "/a/notes.pdf", reason: "unsupported file type (.pdf)")
        ])
        #expect(body.contains("Count: 3"))
        #expect(body.contains("1. photo.gif - unsupported file type (.gif)"))
        #expect(body.contains("2. clip.webm - unsupported file type (.webm)"))
        #expect(body.contains("3. notes.pdf - unsupported file type (.pdf)"))
    }
}

@Suite("WorkFileSafety")
struct WorkFileSafetyTests {
    @Test("work files must not live under Desktop/MetaBurn output")
    func rejectsDesktopWorkPath() {
        let desktop = URL(fileURLWithPath: "/Users/home/Desktop/MetaBurn", isDirectory: true)
        let bad = URL(fileURLWithPath: "/Users/home/Desktop/MetaBurn/Photos/.ABC.metaburn.tmp.JPG")
        let good = URL(fileURLWithPath: "/Users/home/Library/Caches/MetaBurn/ABC.metaburn.tmp.JPG")
        #expect(WorkFileSafety.isWorkFileOnDesktopOutput(workURL: bad, desktopOutputRoot: desktop))
        #expect(!WorkFileSafety.isWorkFileOnDesktopOutput(workURL: good, desktopOutputRoot: desktop))
    }

    @Test("cache workURL is never under the final Desktop photos folder")
    func cacheWorkIsolatedFromFinal() {
        let photos = URL(fileURLWithPath: "/Users/me/Desktop/MetaBurn/Photos", isDirectory: true)
        let cache = URL(fileURLWithPath: "/Users/me/Library/Caches/MetaBurn", isDirectory: true)
        let final = photos.appendingPathComponent("IMG_2667_plus.JPG")
        let work = OutputNaming.workURL(in: cache, forFinal: final, uuid: "DEADBEEF")
        let desktopRoot = URL(fileURLWithPath: "/Users/me/Desktop/MetaBurn", isDirectory: true)
        #expect(work.path.contains("Library/Caches/MetaBurn"))
        #expect(!WorkFileSafety.isWorkFileOnDesktopOutput(workURL: work, desktopOutputRoot: desktopRoot))
        #expect(OutputNaming.isWorkFileName(work.lastPathComponent))
    }

    @Test("stripStallingXattrs removes quarantine like the hung IMG_2667_plus work file")
    func stripsQuarantine() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("metaburn-xattr-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // Reproduce the smoking-gun name pattern from the stalled 4th file.
        let work = dir.appendingPathComponent("647BB6F7-2A12-453D-9058-A36B2172D479.metaburn.tmp.JPG")
        try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: work)

        #expect(WorkFileSafety.setXattr(atPath: work.path, name: "com.apple.quarantine", value: "0081;test"))
        #expect(WorkFileSafety.setXattr(atPath: work.path, name: "com.apple.macl", value: "x"))
        #expect(WorkFileSafety.hasXattr(atPath: work.path, name: "com.apple.quarantine"))
        #expect(WorkFileSafety.hasXattr(atPath: work.path, name: "com.apple.macl"))

        let removed = WorkFileSafety.stripStallingXattrs(atPath: work.path)
        #expect(removed.contains("com.apple.quarantine"))
        #expect(removed.contains("com.apple.macl"))
        #expect(!WorkFileSafety.hasXattr(atPath: work.path, name: "com.apple.quarantine"))
        #expect(!WorkFileSafety.hasXattr(atPath: work.path, name: "com.apple.macl"))
    }

    @Test("cleanupOrphanWorkFiles removes legacy dotted Desktop orphans and cache leftovers")
    func cleansOrphans() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("metaburn-orphan-\(UUID().uuidString)", isDirectory: true)
        let photos = root.appendingPathComponent("Photos", isDirectory: true)
        let cache = root.appendingPathComponent("Cache", isDirectory: true)
        try FileManager.default.createDirectory(at: photos, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let legacy = photos.appendingPathComponent(".647BB6F7.metaburn.tmp.JPG")
        let cached = cache.appendingPathComponent("AABBCC.metaburn.tmp.jpeg")
        let keep = photos.appendingPathComponent("IMG_2667_plus.JPG")
        try Data([1]).write(to: legacy)
        try Data([2]).write(to: cached)
        try Data([3]).write(to: keep)

        let removed = WorkFileSafety.cleanupOrphanWorkFiles(in: [photos, cache])
        #expect(removed.count == 2)
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
        #expect(!FileManager.default.fileExists(atPath: cached.path))
        #expect(FileManager.default.fileExists(atPath: keep.path))
    }
}

@Suite("MetadataRules")
struct MetadataRulesTests {
    @Test("photo args restore ICC after stripping")
    func photoArgs() {
        let args = MetadataRules.buildArgs(kind: .photo, filePath: "/x.jpg")
        #expect(args == ["-all=", "-tagsFromFile", "@", "-icc_profile:all", "-overwrite_original", "/x.jpg"])
    }

    @Test("video args strip all tags")
    func videoArgs() {
        let args = MetadataRules.buildArgs(kind: .video, filePath: "/x.mov")
        #expect(args == ["-all=", "-overwrite_original", "/x.mov"])
    }

    @Test("interpretOutput maps updated/unchanged/error")
    func interpret() {
        let cleaned = MetadataRules.interpretOutput(filePath: "a", output: "1 image files updated")
        #expect(cleaned.outcome == .cleaned)

        let already = MetadataRules.interpretOutput(filePath: "a", output: "1 image files unchanged")
        #expect(already.outcome == .cleaned)
        #expect(already.reason == "already free of removable metadata")

        let failed = MetadataRules.interpretOutput(filePath: "a", output: "Error: something bad\n0 image files updated")
        #expect(failed.outcome == .failed)
    }

    @Test("GPS is removable; PNG dimensions are not")
    func removable() {
        #expect(MetadataRules.isRemovable(group: "GPS", tag: "GPSLatitude", kind: .photo))
        #expect(MetadataRules.isRemovable(group: "EXIF", tag: "Make", kind: .photo))
        #expect(!MetadataRules.isRemovable(group: "PNG", tag: "ImageWidth", kind: .photo))
        #expect(!MetadataRules.isRemovable(group: "ICC", tag: "ProfileDescription", kind: .photo))
        #expect(MetadataRules.isRemovable(group: "ICC", tag: "ProfileDescription", kind: .video))
    }

    @Test("verify marks partial when some removable tags remain")
    func verifyPartial() {
        let before = [
            MetadataRules.Tag(group: "GPS", tag: "GPSLatitude", value: "1"),
            MetadataRules.Tag(group: "EXIF", tag: "Make", value: "Apple")
        ]
        let after = [
            MetadataRules.Tag(group: "GPS", tag: "GPSLatitude", value: "1")
        ]
        let interpreted = MetadataRules.InterpretResult(outcome: .cleaned)
        let result = MetadataRules.verify(interpreted: interpreted, kind: .photo, before: before, after: after)
        #expect(result.outcome == "partial")
    }
}
