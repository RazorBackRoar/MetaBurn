import Foundation
import Security

public enum SecureRandom: Sendable {
    public static func hexString(length: Int = 32) -> String {
        let bytesCount = length / 2
        var bytes = [UInt8](repeating: 0, count: bytesCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytesCount, &bytes)
        guard status == errSecSuccess else {
            fatalError("Failed to generate secure random bytes: \(status)")
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
