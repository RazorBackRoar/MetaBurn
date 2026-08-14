import Foundation
import MetaBurnCore
import Testing

@Suite("SecureRandom")
struct SecureRandomTests {
    @Test("hexString generates string of default length 32")
    func defaultLength() {
        let hex = SecureRandom.hexString()
        #expect(hex.count == 32)
    }

    @Test("hexString generates string of specific even lengths")
    func specificLengths() {
        let hex16 = SecureRandom.hexString(length: 16)
        #expect(hex16.count == 16)

        let hex64 = SecureRandom.hexString(length: 64)
        #expect(hex64.count == 64)
    }

    @Test("hexString returns empty string for length 0")
    func zeroLength() {
        let hex = SecureRandom.hexString(length: 0)
        #expect(hex.isEmpty)
    }

    @Test("hexString generates unique values")
    func uniqueness() {
        let hex1 = SecureRandom.hexString()
        let hex2 = SecureRandom.hexString()
        #expect(hex1 != hex2)
    }

    @Test("hexString contains only lowercase hexadecimal characters")
    func validHexCharacters() {
        let hex = SecureRandom.hexString(length: 64)
        let allowedCharacters = CharacterSet(charactersIn: "0123456789abcdef")
        let hexCharacterSet = CharacterSet(charactersIn: hex)

        #expect(allowedCharacters.isSuperset(of: hexCharacterSet))
    }
}
