import Foundation
import MetaBurnCore

/// UserDefaults-backed cleaned-output destination (`desktop` | `adjacent`).
enum OutputPreference {
    static let storageKey = "outputDestination"

    static var stored: OutputDestination {
        OutputDestination(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .desktop
    }

    static func label(for destination: OutputDestination) -> String {
        switch destination {
        case .desktop: return "Pictures/MetaBurn"
        case .adjacent: return "next to originals"
        }
    }
}
