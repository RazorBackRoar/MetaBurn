import Foundation
import Testing
@testable import MetaBurn

@Suite("OutputRootResolver")
struct OutputRootResolverTests {

    @Test("pathLooksLikeICloud detects Mobile Documents paths")
    func testPathLooksLikeICloud() {
        let icloudURL = URL(fileURLWithPath: "/Users/me/Library/Mobile Documents/com~apple~CloudDocs/photo.jpg")
        let mobileURL = URL(fileURLWithPath: "/Users/me/Mobile Documents/photo.jpg")
        let localURL = URL(fileURLWithPath: "/Users/me/Desktop/photo.jpg")

        #expect(OutputRootResolver.pathLooksLikeICloud(icloudURL))
        #expect(OutputRootResolver.pathLooksLikeICloud(mobileURL))
        #expect(!OutputRootResolver.pathLooksLikeICloud(localURL))
    }
}
