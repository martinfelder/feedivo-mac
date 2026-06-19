import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case de
    case en
    case fr
    case it

    var id: String { rawValue }

    var localeIdentifier: String? {
        switch self {
        case .system:
            nil
        case .de:
            "de"
        case .en:
            "en"
        case .fr:
            "fr"
        case .it:
            "it"
        }
    }

    var locale: Locale {
        if let localeIdentifier {
            Locale(identifier: localeIdentifier)
        } else {
            .autoupdatingCurrent
        }
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .system:
            L10n.settingsLanguageSystem
        case .de:
            L10n.settingsLanguageGerman
        case .en:
            L10n.settingsLanguageEnglish
        case .fr:
            L10n.settingsLanguageFrench
        case .it:
            L10n.settingsLanguageItalian
        }
    }

    static func resolved(from rawValue: String) -> AppLanguage {
        AppLanguage(rawValue: rawValue) ?? .system
    }
}
