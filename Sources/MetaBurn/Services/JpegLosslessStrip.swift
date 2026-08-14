import Foundation
import ImageIO

/// Strip JPEG APPn/COM metadata by copying Huffman-coded scans unchanged.
/// Orientation is preserved with a minimal EXIF APP1 when it is not identity.
/// ICC (`APP2` / `ICC_PROFILE`) and Adobe `APP14` stay so color is not altered.
enum JpegLosslessStrip {
    enum StripError: Error {
        case notJpeg
        case truncated
        case missingScan
    }

    static func isJpeg(_ data: Data) -> Bool {
        data.count >= 4 && data[data.startIndex] == 0xFF && data[data.startIndex + 1] == 0xD8
    }

    static func strip(_ data: Data) throws -> Data {
        guard isJpeg(data) else { throw StripError.notJpeg }

        let orientation = readOrientation(from: data)
        var output = Data()
        output.append(contentsOf: [0xFF, 0xD8])
        if orientation != 1 {
            output.append(minimalExifAPP1(orientation: orientation))
        }

        var i = data.startIndex + 2
        let end = data.endIndex
        var copiedScan = false

        while i + 1 < end {
            guard data[i] == 0xFF else { throw StripError.truncated }
            var j = i
            while j < end && data[j] == 0xFF {
                j += 1
            }
            guard j < end else { throw StripError.truncated }
            let marker = data[j]
            i = j + 1

            if marker == 0x00 {
                throw StripError.truncated
            }

            if marker == 0xD9 {
                output.append(contentsOf: [0xFF, 0xD9])
                break
            }

            if marker == 0xDA {
                output.append(contentsOf: data[(j - 1)..<end])
                copiedScan = true
                break
            }

            if marker >= 0xD0 && marker <= 0xD7 {
                continue
            }

            guard i + 1 < end else { throw StripError.truncated }
            let length = (Int(data[i]) << 8) | Int(data[i + 1])
            guard length >= 2, i + length <= end else { throw StripError.truncated }
            let payload = data[i..<(i + length)]
            i += length

            if shouldKeep(marker: marker, lengthPayload: payload) {
                output.append(contentsOf: [0xFF, marker])
                output.append(payload)
            }
        }

        guard copiedScan else { throw StripError.missingScan }
        return output
    }

    private static func shouldKeep(marker: UInt8, lengthPayload: Data) -> Bool {
        switch marker {
        case 0xE2:
            return payloadASCII(lengthPayload, skipLengthBytes: 2).hasPrefix("ICC_PROFILE")
        case 0xEE:
            return true
        case 0xC0...0xCF where marker != 0xC4 && marker != 0xC8 && marker != 0xCC:
            return true
        case 0xC4, 0xDB, 0xDD:
            return true
        case 0xE0...0xEF, 0xFE:
            return false
        default:
            return marker < 0xE0 || marker > 0xEF
        }
    }

    private static func payloadASCII(_ payload: Data, skipLengthBytes: Int) -> String {
        let bytes = payload.dropFirst(skipLengthBytes)
        let prefix = bytes.prefix(16)
        return String(decoding: prefix, as: UTF8.self)
    }

    private static func readOrientation(from data: Data) -> Int {
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let orientation = props[kCGImagePropertyOrientation as String] as? Int,
              (1...8).contains(orientation) else {
            return 1
        }
        return orientation
    }

    /// Minimal big-endian TIFF EXIF containing only `Orientation`.
    private static func minimalExifAPP1(orientation: Int) -> Data {
        let value = UInt16(clamping: orientation)
        var payload = Data()
        payload.append(contentsOf: [0x45, 0x78, 0x69, 0x66, 0x00, 0x00])
        payload.append(contentsOf: [0x4D, 0x4D, 0x00, 0x2A, 0x00, 0x00, 0x00, 0x08])
        payload.append(contentsOf: [0x00, 0x01])
        payload.append(contentsOf: [0x01, 0x12, 0x00, 0x03, 0x00, 0x00, 0x00, 0x01])
        payload.append(contentsOf: [UInt8(value >> 8), UInt8(value & 0xFF), 0x00, 0x00])
        payload.append(contentsOf: [0x00, 0x00, 0x00, 0x00])

        let length = UInt16(payload.count + 2)
        var app1 = Data([0xFF, 0xE1, UInt8(length >> 8), UInt8(length & 0xFF)])
        app1.append(payload)
        return app1
    }
}
