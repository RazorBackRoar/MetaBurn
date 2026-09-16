import Foundation
import ImageIO
import MetaBurnCore
import UniformTypeIdentifiers

/// Converts HEIC/HEIF stills to max-quality JPEG via Image I/O for the active clean workflow.
/// Originals are never modified; callers write into a local cache work URL.
enum HeicJpegConverter {
    enum ConversionError: Error, Equatable {
        case unreadable
        case notHeif
        case destinationFailed
        case finalizeFailed
    }

    /// Facts about the source that matter to the caller's result note.
    struct ConversionInfo: Sendable {
        let imageCount: Int
        let flattenedAlpha: Bool
    }

    /// Highest practical JPEG quality using public Image I/O APIs (enables Apple’s 4:4:4 path).
    static let compressionQuality: Double = 1.0

    /// True when extension indicates HEIC/HEIF.
    static func shouldConvert(filePath: String) -> Bool {
        HeicRules.needsJpegConversion(filePath: filePath)
    }

    /// Write a JPEG to `destinationURL` from `sourcePath`, preserving metadata when possible.
    static func convert(from sourcePath: String, to destinationURL: URL) -> Result<
        ConversionInfo, ConversionError
    > {
        convert(from: sourcePath, to: destinationURL, stripPrivacyMetadata: false)
    }

    /// Single-pass HEIC/HEIF → max-quality JPEG **without** EXIF/GPS/IPTC/Maker bags (orientation kept).
    static func convertAndStrip(from sourcePath: String, to destinationURL: URL) -> Result<
        ConversionInfo, ConversionError
    > {
        convert(from: sourcePath, to: destinationURL, stripPrivacyMetadata: true)
    }

    // MARK: - Private

    private static func convert(
        from sourcePath: String,
        to destinationURL: URL,
        stripPrivacyMetadata: Bool
    ) -> Result<ConversionInfo, ConversionError> {
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

        let imageCount = CGImageSourceGetCount(source)
        if imageCount > 1 {
            logWarn(
                "HEIC contains \(imageCount) images — only the primary frame is written to JPEG: \(sourcePath)"
            )
        }

        let fm = FileManager.default
        if fm.fileExists(atPath: destinationURL.path) {
            try? fm.removeItem(at: destinationURL)
        }

        if stripPrivacyMetadata {
            if let flattenedAlpha = convertStrippedDecoded(
                source: source, destinationURL: destinationURL, options: options)
            {
                return .success(
                    ConversionInfo(imageCount: imageCount, flattenedAlpha: flattenedAlpha))
            }
        } else {
            // Alpha cannot survive into JPEG — route through the decoded path, which
            // composites onto white, instead of the pixel-preserving addFromSource path.
            let frameZeroHasAlpha =
                CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary)
                .map(Self.imageHasAlpha) ?? false
            if !frameZeroHasAlpha,
                convertViaAddFromSource(source: source, destinationURL: destinationURL)
            {
                return .success(ConversionInfo(imageCount: imageCount, flattenedAlpha: false))
            }
            if let flattenedAlpha = convertViaDecodedImage(
                source: source, destinationURL: destinationURL, options: options)
            {
                return .success(
                    ConversionInfo(imageCount: imageCount, flattenedAlpha: flattenedAlpha))
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
            let orientation = sourceProps[kCGImagePropertyOrientation as String]
        {
            props[kCGImagePropertyOrientation] = orientation
        }
        return props
    }

    private static func convertViaAddFromSource(
        source: CGImageSource,
        destinationURL: URL
    ) -> Bool {
        guard
            let destination = CGImageDestinationCreateWithURL(
                destinationURL as CFURL,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            )
        else {
            return false
        }
        let props = writeProperties(from: source)
        CGImageDestinationAddImageFromSource(destination, source, 0, props as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }

    /// Returns whether frame zero had real alpha, or nil when conversion failed.
    private static func convertViaDecodedImage(
        source: CGImageSource,
        destinationURL: URL,
        options: [CFString: Any]
    ) -> Bool? {
        guard let decoded = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary)
        else {
            return nil
        }
        let flattenedAlpha = imageHasAlpha(decoded)
        let image = compositeOntoWhiteIfNeeded(decoded, sourcePath: nil)
        guard
            let destination = CGImageDestinationCreateWithURL(
                destinationURL as CFURL,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            )
        else {
            return nil
        }

        var props = writeProperties(from: source)
        if let sourceProps = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
            let orientation = sourceProps[kCGImagePropertyOrientation as String]
        {
            props[kCGImagePropertyOrientation] = orientation
        }

        CGImageDestinationAddImage(destination, image, props as CFDictionary)
        return CGImageDestinationFinalize(destination) ? flattenedAlpha : nil
    }

    /// Returns whether frame zero had real alpha, or nil when conversion failed.
    private static func convertStrippedDecoded(
        source: CGImageSource,
        destinationURL: URL,
        options: [CFString: Any]
    ) -> Bool? {
        guard let decoded = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary)
        else {
            return nil
        }
        let flattenedAlpha = imageHasAlpha(decoded)
        let image = compositeOntoWhiteIfNeeded(decoded, sourcePath: nil)
        guard
            let destination = CGImageDestinationCreateWithURL(
                destinationURL as CFURL,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            )
        else {
            return nil
        }
        let props = strippedWriteProperties(from: source)
        CGImageDestinationAddImage(destination, image, props as CFDictionary)
        return CGImageDestinationFinalize(destination) ? flattenedAlpha : nil
    }

    /// True when the image carries real transparency (not just an ignorable alpha byte).
    private static func imageHasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipLast, .noneSkipFirst:
            return false
        case .last, .first, .premultipliedLast, .premultipliedFirst, .alphaOnly:
            return true
        @unknown default:
            return false
        }
    }

    /// JPEG has no alpha channel — composite transparent regions onto white so they
    /// do not render as black in the cleaned output.
    private static func compositeOntoWhiteIfNeeded(_ image: CGImage, sourcePath: String?) -> CGImage
    {
        guard imageHasAlpha(image) else { return image }
        if let sourcePath {
            logWarn("HEIC has an alpha channel — flattening onto white for JPEG: \(sourcePath)")
        } else {
            logWarn("HEIC has an alpha channel — flattening onto white for JPEG")
        }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard
            let context = CGContext(
                data: nil,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
        else {
            return image
        }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage() ?? image
    }

    private static func logWarn(_ message: String) {
        Task { @MainActor in Log.shared.warn(message, scope: "cleaner") }
    }
}
