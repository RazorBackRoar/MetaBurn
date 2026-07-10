import Foundation

/// Resource bundle resolver that works for `swift run` (debug/release) and packaged `.app` bundles.
enum Resources {
    static var bundle: Bundle {
        let candidates = [
            // Packaged .app: resources in Contents/Resources
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources"),
            // Swift run / .app: SwiftPM resource bundle next to the executable
            Bundle.main.bundleURL.appendingPathComponent("MetaBurn_MetaBurn.bundle"),
            // Swift run / .app: SwiftPM resource bundle inside Contents/Resources
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/MetaBurn_MetaBurn.bundle"),
        ]

        for url in candidates {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("version.json").path) {
                return Bundle(url: url) ?? Bundle.main
            }
        }
        return Bundle.main
    }

    static func url(forResource name: String, withExtension ext: String) -> URL? {
        bundle.url(forResource: name, withExtension: ext)
    }
}
