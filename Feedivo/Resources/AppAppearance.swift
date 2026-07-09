import Foundation
import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "appAppearance"
    static let defaultMode = AppAppearance.system

    var id: String { rawValue }

    // nil lässt SwiftUI/macOS die Systemeinstellung entscheiden (folgt
    // automatisch, wenn der Nutzer zwischen Hell/Dunkel wechselt).
    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .system:
            L10n.settingsAppearanceModeSystem
        case .light:
            L10n.settingsAppearanceModeLight
        case .dark:
            L10n.settingsAppearanceModeDark
        }
    }

    static func resolved(from rawValue: String) -> AppAppearance {
        AppAppearance(rawValue: rawValue) ?? defaultMode
    }
}
