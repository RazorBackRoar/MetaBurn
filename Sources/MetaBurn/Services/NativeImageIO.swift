import Foundation
import ImageIO
import UniformTypeIdentifiers
import MetaBurnCore

/// Native ImageIO metadata read/strip for photos — avoids ExifTool hangs (esp. HEIC) and external deps.
enum NativeImageIO {
    /// Strip EXIF/GPS/TIFF/IPTC/XMP without re-encoding pixels when the container allows it.
    /// JPEG uses a lossless marker rewrite; PNG/TIFF/HEIC use `CGImageDestinationCopyImageSource`.
    /// Orientation is kept so the picture does not appear rotated.
    static func stripMetadata(atPath path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        if let data = try? Data(contentsOf: url), JpegLosslessStrip.isJpeg(data) {
            if let stripped = try? JpegLosslessStrip.strip(data), replaceFile(at: url, with: stripped) {
                return true
            }
        }

        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary),
              CGImageSourceGetCount(source) >= 1,
              let uti = CGImageSourceGetType(source) else {
            return false
        }

        if copyImageSourceStripped(from: source, uti: uti, replacing: url) {
            return true
        }

        return decodeAndWriteLossless(source: source, uti: uti, options: options, replacing: url)
    }

    private static func replaceFile(at url: URL, with data: Data) -> Bool {
        let tempURL = url.deletingLastPathComponent()
            .appendingPathComponent(".\(SecureRandom.hexString()).metaburn.native.tmp.\(url.pathExtension)")
        do {
            try data.write(to: tempURL, options: .atomic)
            let fm = FileManager.default
            if fm.fileExists(atPath: url.path) {
                try fm.removeItem(at: url)
            }
            try fm.moveItem(at: tempURL, to: url)
            return true
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            return false
        }
    }

    /// Same-container copy of compressed samples with empty metadata (QA1895).
    private static func copyImageSourceStripped(
        from source: CGImageSource,
        uti: CFString,
        replacing url: URL
    ) -> Bool {
        let tempURL = url.deletingLastPathComponent()
            .appendingPathComponent(".\(SecureRandom.hexString()).metaburn.native.tmp.\(url.pathExtension)")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        guard let destination = CGImageDestinationCreateWithURL(tempURL as CFURL, uti, 1, nil) else {
            return false
        }

        let metadata = CGImageMetadataCreateMutable()
        var options: [CFString: Any] = [
            kCGImageDestinationMetadata: metadata,
            kCGImageDestinationMergeMetadata: false,
            kCGImageMetadataShouldExcludeGPS: true
        ]
        if let sourceProps = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
           let orientation = sourceProps[kCGImagePropertyOrientation as String] {
            options[kCGImageDestinationOrientation] = orientation
        }

        var copyError: Unmanaged<CFError>?
        let copied = CGImageDestinationCopyImageSource(destination, source, options as CFDictionary, &copyError)
        if let copyError {
            _ = copyError.takeRetainedValue()
        }
        guard copied, CGImageDestinationFinalize(destination) else {
            return false
        }
        return moveTemp(tempURL, over: url)
    }

    /// PNG/TIFF stay lossless when Image I/O rewrites the container; used only if CopyImageSource fails.
    private static func decodeAndWriteLossless(
        source: CGImageSource,
        uti: CFString,
        options: [CFString: Any],
        replacing url: URL
    ) -> Bool {
        let tempURL = url.deletingLastPathComponent()
            .appendingPathComponent(".\(SecureRandom.hexString()).metaburn.native.tmp.\(url.pathExtension)")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        guard let destination = CGImageDestinationCreateWithURL(tempURL as CFURL, uti, 1, nil) else {
            return false
        }

        var writeProps: [CFString: Any] = [:]
        if let sourceProps = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
           let orientation = sourceProps[kCGImagePropertyOrientation as String] {
            writeProps[kCGImagePropertyOrientation] = orientation
        }

        if let image = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary) {
            CGImageDestinationAddImage(destination, image, writeProps as CFDictionary)
        } else if !addImageFromSourceStripped(destination: destination, source: source) {
            return false
        }

        guard CGImageDestinationFinalize(destination) else {
            return false
        }
        return moveTemp(tempURL, over: url)
    }

    private static func moveTemp(_ tempURL: URL, over url: URL) -> Bool {
        let fm = FileManager.default
        do {
            if fm.fileExists(atPath: url.path) {
                try fm.removeItem(at: url)
            }
            try fm.moveItem(at: tempURL, to: url)
            return true
        } catch {
            return false
        }
    }

    /// Fallback when decode fails: copy frame but explicitly null metadata dictionaries.
    private static func addImageFromSourceStripped(
        destination: CGImageDestination,
        source: CGImageSource
    ) -> Bool {
        var props = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]) ?? [:]
        let removable: [CFString] = [
            kCGImagePropertyExifDictionary,
            kCGImagePropertyGPSDictionary,
            kCGImagePropertyTIFFDictionary,
            kCGImagePropertyIPTCDictionary,
            kCGImagePropertyMakerAppleDictionary,
            kCGImageProperty8BIMDictionary,
            kCGImagePropertyDNGDictionary,
            kCGImagePropertyCIFFDictionary,
            kCGImagePropertyMakerCanonDictionary,
            kCGImagePropertyMakerNikonDictionary,
            kCGImagePropertyMakerMinoltaDictionary,
            kCGImagePropertyMakerFujiDictionary,
            kCGImagePropertyMakerOlympusDictionary,
            kCGImagePropertyMakerPentaxDictionary
        ]
        for key in removable {
            props[key as String] = kCFNull
        }
        // XMP key varies by SDK; clear common string forms when present.
        props["{XMP}"] = kCFNull
        props[kCGImagePropertyExifAuxDictionary as String] = kCFNull
        CGImageDestinationAddImageFromSource(destination, source, 0, props as CFDictionary)
        return true
    }

    static func readEntries(atPath path: String) -> [MetadataEntry] {
        let url = URL(fileURLWithPath: path)
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return fileSystemEntries(atPath: path)
        }

        var entries: [MetadataEntry] = []
        entries.append(contentsOf: fileSystemEntries(atPath: path))

        if let w = props[kCGImagePropertyPixelWidth as String] as? NSNumber {
            entries.append(MetadataEntry(group: "Image", tag: "ImageWidth", value: w.stringValue))
        }
        if let h = props[kCGImagePropertyPixelHeight as String] as? NSNumber {
            entries.append(MetadataEntry(group: "Image", tag: "ImageHeight", value: h.stringValue))
        }
        if let w = props[kCGImagePropertyPixelWidth as String] as? NSNumber,
           let h = props[kCGImagePropertyPixelHeight as String] as? NSNumber {
            entries.append(MetadataEntry(group: "Image", tag: "ImageSize", value: "\(w.intValue)x\(h.intValue)"))
        }

        let tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        let exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        let gps = props[kCGImagePropertyGPSDictionary as String] as? [String: Any] ?? [:]
        let iptc = props[kCGImagePropertyIPTCDictionary as String] as? [String: Any] ?? [:]

        append(tiff[kCGImagePropertyTIFFMake as String], group: "EXIF", tag: "Make", into: &entries)
        append(tiff[kCGImagePropertyTIFFModel as String], group: "EXIF", tag: "Model", into: &entries)
        append(tiff[kCGImagePropertyTIFFSoftware as String], group: "EXIF", tag: "Software", into: &entries)
        append(exif[kCGImagePropertyExifLensModel as String], group: "EXIF", tag: "LensModel", into: &entries)
        append(exif[kCGImagePropertyExifDateTimeOriginal as String], group: "EXIF", tag: "DateTimeOriginal", into: &entries)
        append(exif[kCGImagePropertyExifDateTimeDigitized as String], group: "EXIF", tag: "CreateDate", into: &entries)
        append(tiff[kCGImagePropertyTIFFDateTime as String], group: "EXIF", tag: "ModifyDate", into: &entries)
        append(iptc["Caption/Abstract"], group: "IPTC", tag: "Caption", into: &entries)
        append(iptc[kCGImagePropertyIPTCCaptionAbstract as String], group: "IPTC", tag: "Description", into: &entries)

        let lat = gps[kCGImagePropertyGPSLatitude as String]
        let lon = gps[kCGImagePropertyGPSLongitude as String]
        let latRef = gps[kCGImagePropertyGPSLatitudeRef as String] as? String
        let lonRef = gps[kCGImagePropertyGPSLongitudeRef as String] as? String
        if let latNum = coordinate(lat), let lonNum = coordinate(lon) {
            let latSigned = (latRef == "S") ? -latNum : latNum
            let lonSigned = (lonRef == "W") ? -lonNum : lonNum
            let text = String(format: "%.6f, %.6f", latSigned, lonSigned)
            entries.append(MetadataEntry(group: "GPS", tag: "GPSPosition", value: text))
            entries.append(MetadataEntry(group: "GPS", tag: "GPSLatitude", value: String(latSigned)))
            entries.append(MetadataEntry(group: "GPS", tag: "GPSLongitude", value: String(lonSigned)))
        }

        let ext = (path as NSString).pathExtension.uppercased()
        if !ext.isEmpty {
            entries.append(MetadataEntry(group: "File", tag: "FileType", value: ext))
        }
        if let type = CGImageSourceGetType(source) as String? {
            entries.append(MetadataEntry(group: "File", tag: "MIMEType", value: type))
        }

        return entries
    }

    static func canHandle(filePath: String) -> Bool {
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        return CGImageSourceCreateWithURL(
            URL(fileURLWithPath: filePath) as CFURL,
            options as CFDictionary
        ) != nil
    }

    @preconcurrency private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter
    }()

    private static func fileSystemEntries(atPath path: String) -> [MetadataEntry] {
        var entries: [MetadataEntry] = []
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path) {
            if let size = attrs[.size] as? NSNumber {
                entries.append(MetadataEntry(group: "File", tag: "FileSize", value: byteString(size.int64Value)))
            }
            if let date = attrs[.modificationDate] as? Date {
                entries.append(MetadataEntry(group: "File", tag: "FileModifyDate", value: dateFormatter.string(from: date)))
            }
            if let date = attrs[.creationDate] as? Date {
                entries.append(MetadataEntry(group: "File", tag: "FileCreateDate", value: dateFormatter.string(from: date)))
            }
        }
        return entries
    }

    private static func append(_ value: Any?, group: String, tag: String, into entries: inout [MetadataEntry]) {
        guard let value else { return }
        let text = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text != "<null>" else { return }
        entries.append(MetadataEntry(group: group, tag: tag, value: text))
    }

    private static func coordinate(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let d = value as? Double { return d }
        if let s = value as? String { return Double(s) }
        return nil
    }

    @preconcurrency private static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter
    }()

    private static func byteString(_ bytes: Int64) -> String {
        return byteCountFormatter.string(fromByteCount: bytes)
    }
}
