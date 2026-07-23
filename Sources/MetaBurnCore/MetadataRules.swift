import Foundation

/// Pure ExifTool argument / output / removable-tag rules (no process I/O).
public enum MetadataRules: Sendable {
    public enum Outcome: String, Sendable {
        case cleaned, failed
    }

    public struct InterpretResult: Sendable, Equatable {
        public let outcome: Outcome
        public let reason: String?

        public init(outcome: Outcome, reason: String? = nil) {
            self.outcome = outcome
            self.reason = reason
        }
    }

    public struct Tag: Sendable, Equatable {
        public let group: String
        public let tag: String
        public let value: String

        public init(group: String, tag: String, value: String) {
            self.group = group
            self.tag = tag
            self.value = value
        }
    }

    public static func buildArgs(kind: SupportedTypes.FileKind, filePath: String) -> [String] {
        if kind == .photo {
            return ["-all=", "-tagsFromFile", "@", "-icc_profile:all", "-overwrite_original", filePath]
        }
        return ["-all=", "-overwrite_original", filePath]
    }

    public static func interpretOutput(filePath _: String, output: String) -> InterpretResult {
        let updatedCount = matchCount(output, pattern: #"(\d+)\s+(?:image\s+)?files?\s+updated"#)
        let unchangedCount = matchCount(output, pattern: #"(\d+)\s+(?:image\s+)?files?\s+unchanged"#)
        let failedCount = matchCount(output, pattern: #"(\d+)\s+files?\s+(?:weren't|were not)\s+updated"#)
        let hasError = output.range(of: #"(^|\n)\s*error[:\s]"#, options: .regularExpression) != nil

        if failedCount > 0 || hasError {
            return InterpretResult(outcome: .failed, reason: firstIssueLine(output) ?? "exiftool reported an error")
        }
        if updatedCount >= 1 {
            return InterpretResult(outcome: .cleaned)
        }
        if unchangedCount >= 1 {
            return InterpretResult(outcome: .cleaned, reason: "already free of removable metadata")
        }
        return InterpretResult(outcome: .failed, reason: firstIssueLine(output) ?? "no changes applied")
    }

    public static func isRemovable(group: String, tag: String, kind: SupportedTypes.FileKind) -> Bool {
        if group.hasPrefix("XMP") { return true }
        if group.hasPrefix("ICC") { return kind != .photo }
        switch group {
        case "EXIF", "GPS", "IPTC", "MakerNotes", "MakerApple", "Photoshop", "JFIF", "Ducky",
             "PDF", "MIE", "MIELensInfo", "CanonVRD", "FotoStation", "Adobe",
             "XML", "ItemList", "UserData", "Keys", "AudioKeys", "VideoKeys":
            return true
        case "PNG":
            return !pngStructuralTags.contains(tag)
        default:
            return false
        }
    }

    public static func removableTags(_ tags: [Tag], kind: SupportedTypes.FileKind) -> [Tag] {
        tags.filter { isRemovable(group: $0.group, tag: $0.tag, kind: kind) }
    }

    public static func verify(
        interpreted: InterpretResult,
        kind: SupportedTypes.FileKind,
        before: [Tag],
        after: [Tag]
    ) -> (outcome: String, reason: String?) {
        if interpreted.outcome == .failed {
            return ("failed", interpreted.reason)
        }
        let beforeRemovable = removableTags(before, kind: kind)
        let afterRemovable = removableTags(after, kind: kind)
        if afterRemovable.isEmpty {
            return ("cleaned", interpreted.reason)
        }
        if tagsEqual(beforeRemovable, afterRemovable) {
            return ("failed", "metadata was not removed")
        }
        return ("partial", "some removable metadata remains after cleaning")
    }

    private static func tagsEqual(_ lhs: [Tag], _ rhs: [Tag]) -> Bool {
        let left = lhs.map { "\($0.group):\($0.tag)=\($0.value)" }.sorted()
        let right = rhs.map { "\($0.group):\($0.tag)=\($0.value)" }.sorted()
        return left == right
    }

    private static func matchCount(_ text: String, pattern: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return 0 }
        return Int(text[range]) ?? 0
    }

    private static func firstIssueLine(_ text: String) -> String? {
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return lines.first { $0.range(of: "error", options: .caseInsensitive) != nil }
            ?? lines.first { $0.range(of: "weren't", options: .caseInsensitive) != nil || $0.range(of: "were not", options: .caseInsensitive) != nil }
            ?? lines.first { $0.range(of: "warning", options: .caseInsensitive) != nil }
            ?? lines.first
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
}
