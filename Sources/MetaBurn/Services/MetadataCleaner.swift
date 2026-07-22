import Foundation

@MainActor
enum MetadataCleaner {
    enum CleanStatus: String, Equatable { case cleaned, skipped, failed, partial }

    private static let exiftoolCandidates = ["/opt/homebrew/bin/exiftool", "/usr/local/bin/exiftool"]
    private static let ffmpegCandidates = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
    private static let brewCandidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]

    private static var cachedExiftoolPath: String? = nil
    private static var cachedFfmpegPath: String? = nil

    static func resolveExiftool() async -> String? {
        if let cached = cachedExiftoolPath { return cached }
        cachedExiftoolPath = await resolveBinary(name: "exiftool", candidates: exiftoolCandidates)
        return cachedExiftoolPath
    }

    static func resolveFfmpeg() async -> String? {
        if let cached = cachedFfmpegPath { return cached }
        cachedFfmpegPath = await resolveBinary(name: "ffmpeg", candidates: ffmpegCandidates)
        return cachedFfmpegPath
    }

    static func resolveBrew() async -> String? {
        await resolveBinary(name: "brew", candidates: brewCandidates)
    }

    static func invalidateExiftoolCache() { cachedExiftoolPath = nil }
    static func invalidateFfmpegCache() { cachedFfmpegPath = nil }

    private static func resolveBinary(name: String, candidates: [String]) async -> String? {
        for candidate in candidates {
            if FileManager.default.fileExists(atPath: candidate) && FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        do {
            let output = try await ProcessRunner.runSimple(executablePath: "/usr/bin/which", arguments: [name], timeout: 5)
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        } catch {
            return nil
        }
    }

    static func muteVideo(ffmpegPath: String, filePath: String) async -> (success: Bool, reason: String?) {
        let url = URL(fileURLWithPath: filePath)
        let dir = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        let tempURL = dir.appendingPathComponent(".\(base).muted.tmp.\(ext)")
        let fm = FileManager.default

        do {
            _ = try await ProcessRunner.runSimple(
                executablePath: ffmpegPath,
                arguments: ["-y", "-i", filePath, "-map", "0:v", "-c", "copy", "-an", tempURL.path],
                timeout: 300
            )
            // `moveItem` fails when the destination already exists — replace explicitly.
            if fm.fileExists(atPath: url.path) {
                try fm.removeItem(at: url)
            }
            try fm.moveItem(at: tempURL, to: url)
            return (true, nil)
        } catch {
            try? fm.removeItem(at: tempURL)
            return (false, error.localizedDescription)
        }
    }

    static func cleanFile(filePath: String, muteAudio: Bool, ffmpegPath: String?) async -> CleanResult {
        let info = SupportedTypes.classify(filePath: filePath)

        if info.kind == .unsupported {
            return CleanResult(path: filePath, status: .skipped, reason: "unsupported file type")
        }
        if info.kind == .video && !info.writable {
            return CleanResult(path: filePath, status: .skipped, reason: "container not safely writable by ExifTool")
        }

        guard let exiftoolPath = await resolveExiftool() else {
            return CleanResult(path: filePath, status: .failed, reason: "exiftool not found")
        }

        Paths.ensureDesktopOutputDirectories()
        let outputDir = info.kind == .photo ? Paths.photosOutputDirectory() : Paths.videosOutputDirectory()
        let outputURL = Paths.uniqueOutputURL(forSourcePath: filePath, in: outputDir)
        let workPath = outputURL.path

        do {
            try FileManager.default.copyItem(atPath: filePath, toPath: workPath)
        } catch {
            return CleanResult(
                path: filePath,
                status: .failed,
                reason: "could not copy to Desktop/\(Paths.desktopOutputFolderName): \(error.localizedDescription)"
            )
        }

        let metadataBefore = await readMetadata(exiftoolPath: exiftoolPath, filePath: workPath)

        var muteReason: String? = nil
        if muteAudio && info.kind == .video {
            let resolvedFfmpeg: String?
            if let path = ffmpegPath {
                resolvedFfmpeg = path
            } else {
                resolvedFfmpeg = await resolveFfmpeg()
            }
            if let ffmpeg = resolvedFfmpeg {
                let muted = await muteVideo(ffmpegPath: ffmpeg, filePath: workPath)
                if !muted.success {
                    muteReason = "audio removal failed: \(muted.reason ?? "ffmpeg failed")"
                }
            } else {
                muteReason = "ffmpeg not installed — audio not removed"
            }
        }

        let args = buildArgs(kind: info.kind, filePath: workPath)
        do {
            let output = try await ProcessRunner.run(
                executablePath: exiftoolPath,
                arguments: args,
                timeout: 60
            )
            let metadataAfter = await readMetadata(exiftoolPath: exiftoolPath, filePath: workPath)
            var result = interpretOutput(filePath: workPath, output: "\(output.stdout)\n\(output.stderr)")
            result = verifyResult(result, kind: info.kind, metadataBefore: metadataBefore, metadataAfter: metadataAfter)

            if let reason = muteReason, result.status == .cleaned {
                result = CleanResult(path: workPath, status: .partial, reason: reason, metadataBefore: metadataBefore, metadataAfter: metadataAfter)
            } else if let reason = muteReason, result.status == .partial {
                let combined = [result.reason, reason].compactMap { $0 }.joined(separator: "; ")
                result = CleanResult(path: workPath, status: .partial, reason: combined, metadataBefore: metadataBefore, metadataAfter: metadataAfter)
            }
            return result
        } catch {
            let metadataAfter = await readMetadata(exiftoolPath: exiftoolPath, filePath: workPath)
            return CleanResult(path: workPath, status: .failed, reason: error.localizedDescription, metadataBefore: metadataBefore, metadataAfter: metadataAfter)
        }
    }

    static func installExiftool() async -> (success: Bool, message: String?) {
        guard let brew = await resolveBrew() else {
            return (false, "Homebrew not found. Install ExifTool manually: brew install exiftool")
        }
        do {
            _ = try await ProcessRunner.runSimple(executablePath: brew, arguments: ["install", "exiftool"], timeout: 600)
            invalidateExiftoolCache()
            let found = await resolveExiftool() != nil
            return (found, found ? nil : "exiftool installed but not found on PATH")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    static func installFfmpeg() async -> (success: Bool, message: String?) {
        guard let brew = await resolveBrew() else {
            return (false, "Homebrew not found. Install ffmpeg manually: brew install ffmpeg")
        }
        do {
            _ = try await ProcessRunner.runSimple(executablePath: brew, arguments: ["install", "ffmpeg"], timeout: 600)
            invalidateFfmpegCache()
            let found = await resolveFfmpeg() != nil
            return (found, found ? nil : "ffmpeg installed but not found on PATH")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    private static func buildArgs(kind: SupportedTypes.FileKind, filePath: String) -> [String] {
        if kind == .photo {
            return ["-all=", "-tagsFromFile", "@", "-icc_profile:all", "-overwrite_original", filePath]
        }
        return ["-all=", "-overwrite_original", filePath]
    }

    private static func readMetadata(exiftoolPath: String, filePath: String) async -> [MetadataEntry] {
        do {
            let output = try await ProcessRunner.runSimple(executablePath: exiftoolPath, arguments: ["-G1", "-j", filePath], timeout: 60)
            guard let data = output.data(using: .utf8),
                  let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let record = json.first else { return [] }
            var entries: [MetadataEntry] = []
            let blocklist: Set<String> = [
                "SourceFile", "ExifTool:ExifToolVersion", "System:FileName", "System:Directory",
                "System:FileAccessDate", "System:FileInodeChangeDate", "System:FilePermissions",
                "Warning", "Error"
            ]
            for (key, value) in record {
                if blocklist.contains(key) || value is NSNull { continue }
                let text: String
                if let str = value as? String {
                    text = str
                } else if let arr = value as? [Any] {
                    text = arr.map { String(describing: $0) }.joined(separator: ", ")
                } else {
                    text = String(describing: value)
                }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let parts = key.split(separator: ":", maxSplits: 1)
                let group = parts.count == 2 ? String(parts[0]) : ""
                let tag = parts.count == 2 ? String(parts[1]) : key
                entries.append(MetadataEntry(group: group, tag: tag, value: trimmed))
            }
            return entries.sorted { "\($0.group):\($0.tag)" < "\($1.group):\($1.tag)" }
        } catch {
            return []
        }
    }

    private static func interpretOutput(filePath: String, output: String) -> CleanResult {
        let updatedCount = matchCount(output, pattern: #"(\d+)\s+(?:image\s+)?files?\s+updated"#)
        let unchangedCount = matchCount(output, pattern: #"(\d+)\s+(?:image\s+)?files?\s+unchanged"#)
        let failedCount = matchCount(output, pattern: #"(\d+)\s+files?\s+(?:weren't|were not)\s+updated"#)
        let hasError = output.range(of: #"(^|\n)\s*error[:\s]"#, options: .regularExpression) != nil

        if failedCount > 0 || hasError {
            return CleanResult(path: filePath, status: .failed, reason: firstIssueLine(output) ?? "exiftool reported an error")
        }
        if updatedCount >= 1 {
            return CleanResult(path: filePath, status: .cleaned)
        }
        if unchangedCount >= 1 {
            return CleanResult(path: filePath, status: .cleaned, reason: "already free of removable metadata")
        }
        return CleanResult(path: filePath, status: .failed, reason: firstIssueLine(output) ?? "no changes applied")
    }

    private static func matchCount(_ text: String, pattern: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) else { return 0 }
        guard let range = Range(match.range(at: 1), in: text) else { return 0 }
        return Int(text[range]) ?? 0
    }

    private static func firstIssueLine(_ text: String) -> String? {
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return lines.first { $0.range(of: "error", options: .caseInsensitive) != nil }
            ?? lines.first { $0.range(of: "weren't", options: .caseInsensitive) != nil || $0.range(of: "were not", options: .caseInsensitive) != nil }
            ?? lines.first { $0.range(of: "warning", options: .caseInsensitive) != nil }
            ?? lines.first
    }

    private static func verifyResult(_ result: CleanResult, kind: SupportedTypes.FileKind, metadataBefore: [MetadataEntry], metadataAfter: [MetadataEntry]) -> CleanResult {
        guard result.status != .failed else {
            return CleanResult(path: result.path, status: result.status, reason: result.reason, metadataBefore: metadataBefore, metadataAfter: metadataAfter)
        }

        let beforeRemovable = removableEntries(metadataBefore, kind: kind)
        let afterRemovable = removableEntries(metadataAfter, kind: kind)

        if afterRemovable.isEmpty {
            return CleanResult(path: result.path, status: .cleaned, reason: result.reason, metadataBefore: metadataBefore, metadataAfter: metadataAfter)
        }

        if entriesEqual(beforeRemovable, afterRemovable) {
            return CleanResult(path: result.path, status: .failed, reason: "metadata not removed by exiftool", metadataBefore: metadataBefore, metadataAfter: metadataAfter)
        }

        return CleanResult(path: result.path, status: .partial, reason: "some metadata remains", metadataBefore: metadataBefore, metadataAfter: metadataAfter)
    }

    private static func removableEntries(_ entries: [MetadataEntry], kind: SupportedTypes.FileKind) -> [MetadataEntry] {
        entries.filter { isRemovable($0, kind: kind) }
    }

    private static func entriesEqual(_ lhs: [MetadataEntry], _ rhs: [MetadataEntry]) -> Bool {
        let left = lhs.map { "\($0.group):\($0.tag)=\($0.value)" }.sorted()
        let right = rhs.map { "\($0.group):\($0.tag)=\($0.value)" }.sorted()
        return left == right
    }

    private static let pngStructuralTags: Set<String> = [
        "AnimationFrames", "AnimationPlays", "AppleDataOffsets", "BackgroundColor",
        "BitDepth", "BlueX", "BlueY", "ColorPrimaries", "ColorType", "Compression",
        "DigitalSignature", "Filter", "FractalParameters", "GIFApplicationExtension",
        "GIFGraphicControlExtension", "GIFPlainTextExtension", "GainMapImage", "Gamma",
        "GreenX", "GreenY", "ImageHeight", "ImageOffset", "ImageWidth", "Interlace",
        "MatrixCoefficients", "Palette", "PaletteHistogram", "PixelCalibration",
        "PixelUnits", "PixelsPerUnitX", "PixelsPerUnitY", "ProfileName", "RedX", "RedY",
        "SRGBRendering", "SignificantBits", "StereoMode", "SubjectPixelHeight",
        "SubjectPixelWidth", "SubjectUnits", "SuggestedPalette", "TransferCharacteristics",
        "Transparency", "VideoFullRangeFlag", "VirtualImageHeight", "VirtualImageWidth",
        "VirtualPageUnits", "WhitePointX", "WhitePointY"
    ]

    private static func isRemovable(_ entry: MetadataEntry, kind: SupportedTypes.FileKind) -> Bool {
        let group = entry.group
        if group.hasPrefix("XMP") { return true }
        if group.hasPrefix("ICC") { return kind != .photo }
        switch group {
        case "EXIF", "GPS", "IPTC", "MakerNotes", "Photoshop", "JFIF", "Ducky",
             "PDF", "MIE", "MIELensInfo", "CanonVRD", "FotoStation", "Adobe",
             "XML", "ItemList", "UserData", "Keys", "AudioKeys", "VideoKeys":
            return true
        case "PNG":
            return !pngStructuralTags.contains(entry.tag)
        default:
            return false
        }
    }
}

private extension FileManager {
    func isExecutableFile(atPath path: String) -> Bool {
        guard fileExists(atPath: path) else { return false }
        guard let attributes = try? attributesOfItem(atPath: path),
              let permissions = attributes[.posixPermissions] as? NSNumber else { return false }
        return permissions.int16Value & 0o111 != 0
    }
}
