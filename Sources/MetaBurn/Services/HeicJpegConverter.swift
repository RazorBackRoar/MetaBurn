import Foundation
import ImageIO
import UniformTypeIdentifiers
import MetaBurnCore

/// Converts HEIC/HEIF stills to max-quality JPEG via Image I/O for the active clean workflow.
/// Originals are never modified; callers write into a local cache work URL.
enum HeicJpegConverter {
    enum ConversionError: Error, Equatable {
        case unreadable
        case notHeif
        case destinationFailed
        case finalizeFailed
    }

    /// Highest practical JPEG quality using public Image I/O APIs (enables Apple’s 4:4:4 path).
    static let compressionQuality: Double = 1.0

    /// True when extension indicates HEIC/HEIF.
    static func shouldConvert(filePath: String) -> Bool {
        HeicRules.needsJpegConversion(filePath: filePath)
    }

    /// Write a JPEG to `destinationURL` from `sourcePath`, preserving metadata when possible.
    static func convert(from sourcePath: String, to destinationURL: URL) -> Result<Void, ConversionError> {
        convert(from: sourcePath, to: destinationURL, stripPrivacyMetadata: false)
    }

    /// Single-pass HEIC/HEIF → max-quality JPEG **without** EXIF/GPS/IPTC/Maker bags (orientation kept).
    static func convertAndStrip(from sourcePath: String, to destinationURL: URL) -> Result<Void, ConversionError> {
        convert(from: sourcePath, to: destinationURL, stripPrivacyMetadata: true)
    }

    // MARK: - Private

    private static func convert(
        from sourcePath: String,
        to destinationURL: URL,
        stripPrivacyMetadata: Bool
    ) -> Result<Void, ConversionError> {
        let sourceURL = URL(fileURLWithPath: sourcePath)
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]

        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, options as CFDictionary),
              CGImageSourceGetCount(source) >= 1
        else {
            return .failure(.unreadable)
        }

        guard isHeifSource(source) || HeicRules.needsJpegConversion(filePath: sourcePath) else {
            return .failure(.notHeif)
        }

        let fm = FileManager.default
        if fm.fileExists(atPath: destinationURL.path) {
            try? fm.removeItem(at: destinationURL)
        }

        if stripPrivacyMetadata {
            if convertStrippedDecoded(source: source, destinationURL: destinationURL, options: options) {
                return .success(())
            }
        } else {
            if convertViaAddFromSource(source: source, destinationURL: destinationURL) {
                return .success(())
            }
            if convertViaDecodedImage(source: source, destinationURL: destinationURL, options: options) {
                return .success(())
            }
        }

        try? fm.removeItem(at: destinationURL)
        return .failure(.finalizeFailed)
    }

    private static func isHeifSource(_ source: CGImageSource) -> Bool {
        guard let type = CGImageSourceGetType(source) as String? else { return false }
        if type == "public.heic" || type == "public.heif" || type == "public.heics" {
            return true
        }
        if let ut = UTType(type) {
            return ut.conforms(to: .heic) || ut.conforms(to: .heif)
        }
        return false
    }

    private static func writeProperties(from source: CGImageSource) -> [CFString: Any] {
        var props: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: compressionQuality
        ]

        if let sourceProps = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {
            for (key, value) in sourceProps {
                props[key as CFString] = value
            }
        }

        props[kCGImageDestinationLossyCompressionQuality] = compressionQuality
        props[kCGImageDestinationPreserveGainMap] = kCFBooleanTrue
        return props
    }

    /// Orientation + quality only (no privacy dictionaries).
    private static func strippedWriteProperties(from source: CGImageSource) -> [CFString: Any] {
        var props: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: compressionQuality
        ]
        if let sourceProps = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
           let orientation = sourceProps[kCGImagePropertyOrientation as String] {
            props[kCGImagePropertyOrientation] = orientation
        }
        return props
    }

    private static func convertViaAddFromSource(
        source: CGImageSource,
        destinationURL: URL
    ) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(
            destinationURL as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return false
        }
        let props = writeProperties(from: source)
        CGImageDestinationAddImageFromSource(destination, source, 0, props as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }

    private static func convertViaDecodedImage(
        source: CGImageSource,
        destinationURL: URL,
        options: [CFString: Any]
    ) -> Bool {
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary) else {
            return false
        }
        guard let destination = CGImageDestinationCreateWithURL(
            destinationURL as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return false
        }

        var props = writeProperties(from: source)
        if let sourceProps = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
           let orientation = sourceProps[kCGImagePropertyOrientation as String] {
            props[kCGImagePropertyOrientation] = orientation
        }

        CGImageDestinationAddImage(destination, image, props as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }

    private static func convertStrippedDecoded(
        source: CGImageSource,
        destinationURL: URL,
        options: [CFString: Any]
    ) -> Bool {
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary) else {
            return false
        }
        guard let destination = CGImageDestinationCreateWithURL(
            destinationURL as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return false
        }
        let props = strippedWriteProperties(from: source)
        CGImageDestinationAddImage(destination, image, props as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }
}
