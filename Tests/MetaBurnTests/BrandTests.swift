import Testing
@testable import MetaBurn

@Suite("Brand")
struct BrandTests {

    @Test("Brand constants have expected values")
    func brandConstants() {
        #expect(Brand.displayName == "MetaBurn")
        #expect(Brand.githubRepo == "MetaBurn")
        #expect(Brand.githubOrg == "RazorBackRoar")
        #expect(Brand.npmPackageName == "metaburn")
        #expect(Brand.appId == "com.razorbackroar.metaburn")
        #expect(Brand.organization == "RazorBackRoar")
        #expect(Brand.licenseText == "2026 RazorBackRoar")
        #expect(Brand.copyrightFull == "© 2026 RazorBackRoar. All rights reserved.")
        #expect(Brand.architecture == "ARM64 (Apple Silicon)")
    }

    @Test("Brand constants are not empty")
    func brandConstantsNotEmpty() {
        #expect(!Brand.displayName.isEmpty)
        #expect(!Brand.githubRepo.isEmpty)
        #expect(!Brand.githubOrg.isEmpty)
        #expect(!Brand.npmPackageName.isEmpty)
        #expect(!Brand.appId.isEmpty)
        #expect(!Brand.organization.isEmpty)
        #expect(!Brand.licenseText.isEmpty)
        #expect(!Brand.copyrightFull.isEmpty)
        #expect(!Brand.architecture.isEmpty)
    }
}
