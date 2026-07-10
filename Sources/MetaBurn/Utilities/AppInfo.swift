import Foundation

struct AppInfo {
    let name: String
    let version: String
    let license: String
    let copyright: String
    let organization: String
    let architecture: String
}

enum AppInfoProvider {
    static func current() -> AppInfo {
        AppInfo(
            name: Brand.displayName,
            version: resolvedVersion(),
            license: Brand.licenseText,
            copyright: Brand.copyrightFull,
            organization: Brand.organization,
            architecture: Brand.architecture
        )
    }

    private static func resolvedVersion() -> String {
        if let url = Resources.url(forResource: "version", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let version = json["version"] as? String {
            return version
        }
        return "1.0.0"
    }

    static func printStartupInfo() {
        let info = current()
        let banner = """
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
          \(info.name)
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
          Version:  \(info.version)
          License:  \(info.license)
          Arch:     \(info.architecture)
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        """
        print(banner)
    }
}
