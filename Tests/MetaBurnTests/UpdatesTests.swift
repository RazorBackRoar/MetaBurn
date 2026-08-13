import Foundation
import Testing
@testable import MetaBurn

@Suite("Updates")
struct UpdatesTests {

    @Test("compareVersions correctly compares equal versions")
    func testCompareVersionsEqual() {
        #expect(Updates.compareVersions("1.0.0", "1.0.0") == 0)
        #expect(Updates.compareVersions("v1.0.0", "1.0.0") == 0)
        #expect(Updates.compareVersions("1.0", "1.0.0") == 0)
        #expect(Updates.compareVersions("2", "2.0.0") == 0)
    }

    @Test("compareVersions correctly identifies older versions")
    func testCompareVersionsOlder() {
        #expect(Updates.compareVersions("1.0.0", "1.0.1") == -1)
        #expect(Updates.compareVersions("1.0.9", "1.1.0") == -1)
        #expect(Updates.compareVersions("1.2.3", "2.0.0") == -1)
        #expect(Updates.compareVersions("v1.2", "1.2.1") == -1)
        #expect(Updates.compareVersions("0.9.9", "1.0") == -1)
    }

    @Test("compareVersions correctly identifies newer versions")
    func testCompareVersionsNewer() {
        #expect(Updates.compareVersions("1.0.1", "1.0.0") == 1)
        #expect(Updates.compareVersions("1.1.0", "1.0.9") == 1)
        #expect(Updates.compareVersions("2.0.0", "1.2.3") == 1)
        #expect(Updates.compareVersions("v1.2.1", "1.2") == 1)
        #expect(Updates.compareVersions("1.0", "0.9.9") == 1)
    }

    @Test("Cache writes and reads successfully")
    func testCacheReadWrite() throws {
        // Clear cache first if it exists
        let url = Updates.cacheURL()
        try? FileManager.default.removeItem(at: url)

        let latestVersion = "2.0.0"
        let downloadURL = "https://example.com/download"
        let releaseNotes = "Big update!"
        let releaseDate = "2023-10-27T10:00:00Z"

        Updates.writeCache(latestVersion: latestVersion, downloadURL: downloadURL, releaseNotes: releaseNotes, releaseDate: releaseDate)

        // Cache should now exist
        #expect(FileManager.default.fileExists(atPath: url.path))

        // Read cache
        let currentVersion = "1.5.0"
        let result = Updates.readCache(currentVersion: currentVersion)

        #expect(result != nil)
        #expect(result?.currentVersion == currentVersion)
        #expect(result?.latestVersion == latestVersion)
        #expect(result?.updateAvailable == true)
        #expect(result?.downloadURL == downloadURL)
        #expect(result?.releaseNotes == releaseNotes)
        #expect(result?.releaseDate == releaseDate)
        #expect(result?.error == nil)

        // Clean up
        try? FileManager.default.removeItem(at: url)
    }

    @Test("Cache is ignored if expired")
    func testExpiredCache() throws {
        // Clear cache first if it exists
        let url = Updates.cacheURL()
        try? FileManager.default.removeItem(at: url)

        // Write standard cache
        Updates.writeCache(latestVersion: "2.0.0", downloadURL: nil, releaseNotes: nil, releaseDate: nil)

        // Read the file and modify the timestamp to make it expired
        guard let data = try? Data(contentsOf: url),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Issue.record("Failed to read cache file")
            return
        }

        // Set timestamp to past (older than cache duration)
        json["timestamp"] = Date().timeIntervalSince1970 - Updates.cacheDuration - 100

        let modifiedData = try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
        try modifiedData.write(to: url, options: .atomic)

        // Read cache - should be nil because it's expired
        let result = Updates.readCache(currentVersion: "1.0.0")

        #expect(result == nil)

        // Clean up
        try? FileManager.default.removeItem(at: url)
    }
}
