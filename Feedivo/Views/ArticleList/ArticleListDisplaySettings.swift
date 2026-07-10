import SwiftUI

/// Position des Vorschaubilds in der Artikelliste (Feature 19.1).
enum ArticleListImagePosition: String, CaseIterable, Identifiable {
    case left
    case right
    case hidden

    static let storageKey = "articleList.imagePosition"
    static let defaultPosition = ArticleListImagePosition.left

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .left:
            L10n.articleListImagePositionLeft
        case .right:
            L10n.articleListImagePositionRight
        case .hidden:
            L10n.articleListImagePositionHidden
        }
    }

    static func resolved(from rawValue: String) -> ArticleListImagePosition {
        ArticleListImagePosition(rawValue: rawValue) ?? defaultPosition
    }
}

/// Position der Feedname-Zeile (Favicon + Feedname + Zeitpunkt) relativ zum
/// Artikeltitel (Feature 19.1).
enum ArticleListFeedNamePosition: String, CaseIterable, Identifiable {
    case beforeTitle
    case afterTitle

    static let storageKey = "articleList.feedNamePosition"
    static let defaultPosition = ArticleListFeedNamePosition.afterTitle

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .beforeTitle:
            L10n.articleListFeedNamePositionBeforeTitle
        case .afterTitle:
            L10n.articleListFeedNamePositionAfterTitle
        }
    }

    static func resolved(from rawValue: String) -> ArticleListFeedNamePosition {
        ArticleListFeedNamePosition(rawValue: rawValue) ?? defaultPosition
    }
}

/// Ob der Feedname (und damit auch das Favicon) pro Artikel angezeigt wird.
/// Der Zeitpunkt bleibt unabhängig davon immer sichtbar (siehe `ArticleRowView`).
enum ArticleListFeedNameVisibilitySettings {
    static let showsFeedNameKey = "articleList.showsFeedName"
    static let defaultShowsFeedName = true
}

/// Ob die Artikel-Zusammenfassung in der Artikelliste angezeigt wird (Feature 19.1).
enum ArticleListSummaryVisibilitySettings {
    static let showsSummaryKey = "articleList.showsSummary"
    static let defaultShowsSummary = true
}

/// Anzahl der Vorschautext-Zeilen der Summary in der Artikelliste (Feature 19.1).
/// Nur relevant, wenn `ArticleListSummaryVisibilitySettings.showsSummaryKey` an ist.
enum ArticleListSummaryLineCount {
    static let storageKey = "articleList.summaryLineCount"
    static let defaultValue = 2
    static let allowedRange = 1...3

    /// Fängt ungültige/veraltete gespeicherte Werte ab (z. B. durch manuelle
    /// UserDefaults-Manipulation oder künftige Range-Änderungen).
    static func resolved(from storedValue: Int) -> Int {
        allowedRange.contains(storedValue) ? storedValue : defaultValue
    }
}

/// Anzeigeformat für Artikel-/Feed-Zeitstempel: relativ ("vor 2 Stunden") oder
/// absolut (kurzes Datum, z. B. "23.06.2026"). Wirkt app-weit über
/// `Date.feedivoDisplay(mode:)` (Feature 19.1).
enum ArticleDateDisplayMode: String, CaseIterable, Identifiable {
    case relative
    case absolute

    static let storageKey = "articleList.dateDisplayMode"
    static let defaultMode = ArticleDateDisplayMode.relative

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .relative:
            L10n.articleDateDisplayModeRelative
        case .absolute:
            L10n.articleDateDisplayModeAbsolute
        }
    }

    static func resolved(from rawValue: String) -> ArticleDateDisplayMode {
        ArticleDateDisplayMode(rawValue: rawValue) ?? defaultMode
    }
}
