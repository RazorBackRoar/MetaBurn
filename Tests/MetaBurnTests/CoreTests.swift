import Foundation
import MetaBurnCore
import Testing

@Suite("SupportedTypes")
struct SupportedTypesTests {
    @Test("classifies common photo extensions")
    func photos() {
        for path in ["a.jpg", "b.JPEG", "c.png", "d.heic", "e.webp", "f.tiff"] {
            let info = SupportedTypes.classify(filePath: path)
            #expect(info.kind == .photo)
            #expect(info.writable)
        }
    }

    @Test("classifies writable and non-writable videos")
    func videos() {
        #expect(SupportedTypes.classify(filePath: "clip.mov").writable)
        #expect(SupportedTypes.classify(filePath: "clip.mp4").writable)
        #expect(SupportedTypes.classify(filePath: "clip.m4v").writable)
        #expect(!SupportedTypes.classify(filePath: "clip.mkv").writable)
        #expect(!SupportedTypes.classify(filePath: "clip.webm").writable)
        #expect(!SupportedTypes.classify(filePath: "clip.avi").writable)
        #expect(SupportedTypes.classify(filePath: "clip.mkv").kind == .video)
    }

    @Test("rejects unsupported types")
    func unsupported() {
        let info = SupportedTypes.classify(filePath: "notes.txt")
        #expect(info.kind == .unsupported)
        #expect(!SupportedTypes.isSupported(filePath: "notes.txt"))
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
