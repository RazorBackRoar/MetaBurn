import Foundation

struct UpdateResult {
    let currentVersion: String
    let latestVersion: String
    let updateAvailable: Bool
    let downloadURL: String?
    let releaseNotes: String?
    let releaseDate: String?
    let error: String?
}

final class Updates {
    private static let cacheDuration: TimeInterval = 3600
    private static let userAgent = "metaburn-update-checker/1.0"

    private static func cacheURL() -> URL {
        Paths.ensureCacheDirectory()
        return Paths.cacheDirectory().appendingPathComponent("update_check.json")
    }

    static func checkForUpdates(currentVersion: String) async -> UpdateResult {
        if let cached = readCache(currentVersion: currentVersion) {
            return cached
        }

        let url = URL(string: "https://api.github.com/repos/\(Brand.githubOrg)/\(Brand.githubRepo)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue(Brand.githubRepo + "-update-checker/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
                return UpdateResult(
                    currentVersion: currentVersion,
                    latestVersion: currentVersion,
                    updateAvailable: false,
                    downloadURL: nil,
                    releaseNotes: nil,
                    releaseDate: nil,
                    error: "GitHub returned HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)"
                )
            }
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            let tag = (json["tag_name"] as? String ?? "").replacingOccurrences(of: "^v", with: "", options: .regularExpression)
            let htmlURL = json["html_url"] as? String
            let body = json["body"] as? String
            let publishedAt = json["published_at"] as? String

            writeCache(latestVersion: tag, downloadURL: htmlURL, releaseNotes: body, releaseDate: publishedAt)

            return UpdateResult(
                currentVersion: currentVersion,
                latestVersion: tag,
                updateAvailable: compareVersions(currentVersion, tag) < 0,
                downloadURL: htmlURL,
                releaseNotes: body,
                releaseDate: publishedAt,
                error: nil
            )
        } catch {
            return UpdateResult(
                currentVersion: currentVersion,
                latestVersion: currentVersion,
                updateAvailable: false,
                downloadURL: nil,
                releaseNotes: nil,
                releaseDate: nil,
                error: error.localizedDescription
            )
        }
    }

    private static func readCache(currentVersion: String) -> UpdateResult? {
        let url = cacheURL()
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let timestamp = json["timestamp"] as? TimeInterval,
              Date().timeIntervalSince1970 - timestamp < cacheDuration,
              let latest = json["latest_version"] as? String else { return nil }

        return UpdateResult(
            currentVersion: currentVersion,
            latestVersion: latest,
            updateAvailable: compareVersions(currentVersion, latest) < 0,
            downloadURL: json["download_url"] as? String,
            releaseNotes: json["release_notes"] as? String,
            releaseDate: json["release_date"] as? String,
            error: nil
        )
    }

    private static func writeCache(latestVersion: String, downloadURL: String?, releaseNotes: String?, releaseDate: String?) {
        let payload: [String: Any] = [
            "timestamp": Date().timeIntervalSince1970,
            "latest_version": latestVersion,
            "download_url": downloadURL ?? NSNull(),
            "release_notes": releaseNotes ?? NSNull(),
            "release_date": releaseDate ?? NSNull()
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted) {
            try? data.write(to: cacheURL(), options: .atomic)
        }
    }

    static func compareVersions(_ a: String, _ b: String) -> Int {
        let parse: (String) -> [Int] = { version in
            version.replacingOccurrences(of: "^v", with: "", options: .regularExpression)
                .split(separator: ".")
                .compactMap { Int($0) }
        }
        let pa = parse(a), pb = parse(b)
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x < y { return -1 }
            if x > y { return 1 }
        }
        return 0
    }
}
