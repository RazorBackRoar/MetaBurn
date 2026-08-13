import Foundation

public enum SecureRandom: Sendable {
    public static func hexString(length: Int = 32) -> String {
        var generator = SystemRandomNumberGenerator()
        let bytesCount = length / 2
        var bytes = [UInt8](repeating: 0, count: bytesCount)
        for i in 0..<bytesCount {
            bytes[i] = generator.next()
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
