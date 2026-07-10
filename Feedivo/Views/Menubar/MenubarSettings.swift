import SwiftUI

/// Ob das Menubar-Icon aktiv ist (Feature 21.1). Default aus, damit
/// Bestandsnutzer keinen Verhaltenssprung erleben.
enum MenubarSettings {
    static let isEnabledKey = "menubar.isEnabled"
    static let defaultIsEnabled = false

    static let articleCountKey = "menubar.articleCount"
    static let defaultArticleCount = 5
    static let allowedArticleCountRange = 3...10

    static let hidesDockIconKey = "menubar.hidesDockIcon"
    static let defaultHidesDockIcon = false

    /// Fängt ungültige/veraltete gespeicherte Werte ab.
    static func resolvedArticleCount(from storedValue: Int) -> Int {
        allowedArticleCountRange.contains(storedValue) ? storedValue : defaultArticleCount
    }
}

/// Verhalten beim Klick auf einen Artikel im Menubar-Dropdown (Feature 21.1).
enum MenubarArticleClickBehavior: String, CaseIterable, Identifiable {
    case inFeedivo
    case inBrowser

    static let storageKey = "menubar.articleClickBehavior"
    static let defaultBehavior = MenubarArticleClickBehavior.inFeedivo

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .inFeedivo:
            L10n.menubarArticleClickBehaviorInFeedivo
        case .inBrowser:
            L10n.menubarArticleClickBehaviorInBrowser
        }
    }

    static func resolved(from rawValue: String) -> MenubarArticleClickBehavior {
        MenubarArticleClickBehavior(rawValue: rawValue) ?? defaultBehavior
    }
}
