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
