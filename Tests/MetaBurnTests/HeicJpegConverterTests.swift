import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import MetaBurn

@Suite("HeicJpegConverter")
struct HeicJpegConverterTests {
    /// Builds a small HEIC whose left half is fully transparent and right half opaque red.
    private static func makeAlphaHeic(in dir: URL) throws -> URL {
        let width = 8
        let height = 8
        var bytes: [UInt8] = []
        bytes.reserveCapacity(width * height * 4)
        for _ in 0..<height {
            for x in 0..<width {
                if x < width / 2 {
                    bytes += [0, 0, 0, 0]  // transparent
                } else {
                    bytes += [255, 0, 0, 255]  // opaque red
                }
            }
        }
        let data = Data(bytes)
        guard
            let provider = CGDataProvider(data: data as CFData),
            let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        else {
            Issue.record("could not build RGBA CGImage")
            throw NSError(domain: "test", code: 1)
        }
        let url = dir.appendingPathComponent("alpha-src.heic")
        guard
            let dest = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.heic.identifier as CFString, 1, nil)
        else {
            Issue.record("no HEIC destination on this platform")
            throw NSError(domain: "test", code: 2)
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            Issue.record("HEIC encode failed")
            throw NSError(domain: "test", code: 3)
        }
        return url
    }

    /// Decodes the JPEG and returns the RGB of a pixel.
    private static func pixel(_ url: URL, x: Int, y: Int) throws -> (UInt8, UInt8, UInt8) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            Issue.record("could not decode JPEG output")
            throw NSError(domain: "test", code: 4)
        }
        guard
            let ctx = CGContext(
                data: nil,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
        else {
            Issue.record("could not create readback context")
            throw NSError(domain: "test", code: 5)
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let data = ctx.data else {
            Issue.record("no pixel data")
            throw NSError(domain: "test", code: 6)
        }
        let stride = ctx.bytesPerRow
        let offset = y * stride + x * 4
        let buf = data.bindMemory(to: UInt8.self, capacity: stride * image.height)
        return (buf[offset], buf[offset + 1], buf[offset + 2])
    }

    @Test("HEIC alpha composites onto white instead of flattening to black")
    func alphaFlattensToWhite() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("metaburn-heic-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let heic = try Self.makeAlphaHeic(in: dir)

        // If the encoder dropped alpha, the converter has nothing to composite — skip.
        guard
            let checkSource = CGImageSourceCreateWithURL(heic as CFURL, nil),
            let checkImage = CGImageSourceCreateImageAtIndex(checkSource, 0, nil)
        else {
            Issue.record("could not read back generated HEIC")
            return
        }
        guard checkImage.alphaInfo != .none, checkImage.alphaInfo != .noneSkipLast,
            checkImage.alphaInfo != .noneSkipFirst
        else {
            // Environment cannot produce alpha HEIC — nothing to verify here.
            return
        }

        let jpg = dir.appendingPathComponent("alpha-out.jpg")
        guard case .success = HeicJpegConverter.convertAndStrip(from: heic.path, to: jpg) else {
            Issue.record("convertAndStrip failed")
            return
        }

        // Top-left sits in the transparent half: must be near-white, not black.
        let transparentSide = try Self.pixel(jpg, x: 0, y: 0)
        #expect(transparentSide.0 > 230)
        #expect(transparentSide.1 > 230)
        #expect(transparentSide.2 > 230)

        // Top-right is the opaque red half: stays red-ish.
        let opaqueSide = try Self.pixel(jpg, x: 6, y: 0)
        #expect(opaqueSide.0 > 150)
        #expect(opaqueSide.1 < 100)
    }
}
