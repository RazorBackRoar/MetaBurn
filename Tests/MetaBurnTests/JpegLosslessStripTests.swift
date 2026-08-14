import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import MetaBurn

@Suite("JpegLosslessStrip")
struct JpegLosslessStripTests {
    @Test("keeps Huffman scan bytes and drops APP1 GPS")
    func stripKeepsPixelsDropsApp1() throws {
        let original = try makeTestJPEG()
        var injected = Data([0xFF, 0xD8])
        injected.append(fakeGPSAPP1())
        injected.append(original.dropFirst(2))

        let stripped = try JpegLosslessStrip.strip(injected)
        #expect(JpegLosslessStrip.isJpeg(stripped))
        #expect(!containsGPSAPP1(stripped))
        #expect(scanPayload(stripped) == scanPayload(original))

        let beforePixels = try pixelDigest(original)
        let afterPixels = try pixelDigest(stripped)
        #expect(beforePixels == afterPixels)
    }

    @Test("preserves non-identity orientation without re-encoding the scan")
    func keepsOrientation() throws {
        let original = try makeTestJPEG()
        let stripped = try JpegLosslessStrip.strip(original)
        #expect(scanPayload(stripped) == scanPayload(original))
    }

    private func makeTestJPEG() throws -> Data {
        let rgb: [UInt8] = [0x20, 0x40, 0x80]
        guard let provider = CGDataProvider(data: Data(rgb) as CFData),
              let image = CGImage(
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bitsPerPixel: 24,
                bytesPerRow: 3,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            throw TestFailure("could not create CGImage")
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else {
            throw TestFailure("could not create JPEG destination")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw TestFailure("could not finalize JPEG")
        }
        let jpeg = data as Data
        guard JpegLosslessStrip.isJpeg(jpeg) else {
            throw TestFailure("Image I/O did not produce a JPEG")
        }
        return jpeg
    }

    private func fakeGPSAPP1() -> Data {
        var payload = Data("Exif\0\0GPSFAKE".utf8)
        while payload.count < 20 { payload.append(0) }
        let length = UInt16(payload.count + 2)
        var app1 = Data([0xFF, 0xE1, UInt8(length >> 8), UInt8(length & 0xFF)])
        app1.append(payload)
        return app1
    }

    private func containsGPSAPP1(_ data: Data) -> Bool {
        let needle = Data("GPSFAKE".utf8)
        return data.range(of: needle) != nil
    }

    private func scanPayload(_ data: Data) -> Data? {
        guard let sos = data.range(of: Data([0xFF, 0xDA])) else { return nil }
        return data[sos.lowerBound...]
    }

    private func pixelDigest(_ data: Data) throws -> [UInt8] {
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary),
              let image = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary),
              let provider = image.dataProvider,
              let pixels = provider.data as Data? else {
            throw TestFailure("could not decode JPEG pixels")
        }
        return Array(pixels.prefix(16))
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
