import AppKit
import SwiftUI

/// Shared theme preference (`UserDefaults` key `themeSource`).
enum ThemePreference {
    static let storageKey = "themeSource"

    static var stored: String {
        UserDefaults.standard.string(forKey: storageKey) ?? "system"
    }

    static func colorScheme(for source: String) -> ColorScheme? {
        switch source {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    static func applyAppAppearance(for source: String = stored) {
        let appearance: NSAppearance?
        switch source {
        case "light":
            appearance = NSAppearance(named: .aqua)
        case "dark":
            appearance = NSAppearance(named: .darkAqua)
        default:
            appearance = nil
        }
        NSApp?.appearance = appearance
        for window in NSApp?.windows ?? [] {
            window.backgroundColor = .windowBackgroundColor
        }
    }
}
