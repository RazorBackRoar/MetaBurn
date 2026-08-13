import Foundation
import Testing
@testable import MetaBurn

@Suite("AppInfoProvider")
struct AppInfoProviderTests {

    @Test("current() returns valid AppInfo with expected Brand values")
    func currentAppInfo() {
        let info = AppInfoProvider.current()

        // Assert non-empty strings
        #expect(!info.name.isEmpty)
        #expect(!info.version.isEmpty)
        #expect(!info.license.isEmpty)
        #expect(!info.copyright.isEmpty)
        #expect(!info.organization.isEmpty)
        #expect(!info.architecture.isEmpty)

        // Assert matches Brand constants
        #expect(info.name == Brand.displayName)
        #expect(info.license == Brand.licenseText)
        #expect(info.copyright == Brand.copyrightFull)
        #expect(info.organization == Brand.organization)
        #expect(info.architecture == Brand.architecture)

        // Ensure version parses correctly (not empty and likely has a digit)
        #expect(info.version.contains(where: { $0.isNumber }), "Version should contain at least one digit")
    }
}
