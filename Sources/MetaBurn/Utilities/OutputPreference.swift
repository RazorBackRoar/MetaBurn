import Foundation
import MetaBurnCore

/// UserDefaults-backed cleaned-output destination (`desktop` | `adjacent`).
/// Stored `desktop` is treated as adjacent so collected home folders are never used.
enum OutputPreference {
    static let storageKey = "outputDestination"

    static var stored: OutputDestination {
        .adjacent
    }

    static func label(for destination: OutputDestination) -> String {
        switch destination {
        case .desktop, .adjacent:
            return "next to originals"
        }
    }
}
