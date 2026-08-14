import Foundation
import Testing
@testable import MetaBurn

@Suite("GitHub certificate pinning")
struct GithubPinningDelegateTests {
    @Test("pin mismatch rejects the protection space instead of cancelling the challenge")
    func pinFailureRejectsProtectionSpace() {
        #expect(GithubPinningDelegate.pinFailureDisposition == .rejectProtectionSpace)
        #expect(GithubPinningDelegate.pinFailureDisposition != .cancelAuthenticationChallenge)
    }
}
