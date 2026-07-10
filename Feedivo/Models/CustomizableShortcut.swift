import SwiftUI

enum ShortcutCategory: CaseIterable, Hashable, Sendable {
    case feed
    case article
    case reader

    var titleKey: LocalizedStringKey {
        switch self {
        case .feed: L10n.shortcutsCategoryFeed
        case .article: L10n.shortcutsCategoryArticle
        case .reader: L10n.shortcutsCategoryReader
        }
    }
}

/// Registry aller nutzerdefinierbar gemachten Tastenkombinationen. Bewusst NICHT
/// enthalten: `.keyboardShortcut(.defaultAction)`-Stellen in Dialogen (Export-Sheet,
/// Regel-Assistent, Tag-Manager, …) — das ist die macOS-Konvention "Enter löst den
/// Standard-Button aus", kein eigentlicher, umbenennbarer Befehls-Shortcut.
enum CustomizableShortcut: String, CaseIterable, Identifiable, Sendable {
    case feedAdd
    case statisticsOpen
    case feedRefreshAll
    case feedRefresh
    case articleSelectPrevious
    case articleSelectNext
    case articleSearch
    case articleToggleRead
    case articleToggleStarred
    case articleOpenInWindow
    case readerWebBack
    case readerWebForward

    var id: String { rawValue }

    var category: ShortcutCategory {
        switch self {
        case .feedAdd, .statisticsOpen, .feedRefreshAll, .feedRefresh:
            .feed
        case .articleSelectPrevious, .articleSelectNext, .articleSearch,
             .articleToggleRead, .articleToggleStarred, .articleOpenInWindow:
            .article
        case .readerWebBack, .readerWebForward:
            .reader
        }
    }

    /// Aufgelöster Klartext für Stellen, die keinen `Text`/`LocalizedStringKey`-Kontext
    /// haben (z. B. die Konflikt-Meldung "Bereits belegt durch: %@"). Nutzt denselben
    /// xcstrings-Key wie `titleKey`, nur zur Laufzeit statt SwiftUI-deklarativ aufgelöst.
    var resolvedLabel: String {
        String(localized: "shortcuts.label.\(rawValue)")
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .feedAdd: L10n.shortcutsLabelFeedAdd
        case .statisticsOpen: L10n.shortcutsLabelStatisticsOpen
        case .feedRefreshAll: L10n.shortcutsLabelFeedRefreshAll
        case .feedRefresh: L10n.shortcutsLabelFeedRefresh
        case .articleSelectPrevious: L10n.shortcutsLabelArticleSelectPrevious
        case .articleSelectNext: L10n.shortcutsLabelArticleSelectNext
        case .articleSearch: L10n.shortcutsLabelArticleSearch
        case .articleToggleRead: L10n.shortcutsLabelArticleToggleRead
        case .articleToggleStarred: L10n.shortcutsLabelArticleToggleStarred
        case .articleOpenInWindow: L10n.shortcutsLabelArticleOpenInWindow
        case .readerWebBack: L10n.shortcutsLabelReaderWebBack
        case .readerWebForward: L10n.shortcutsLabelReaderWebForward
        }
    }

    /// Entspricht 1:1 den bisherigen hartcodierten `.keyboardShortcut(...)`-Werten,
    /// damit sich beim Einführen dieses Features für niemanden etwas ändert, der
    /// noch nichts angepasst hat.
    var defaultSpec: KeyboardShortcutSpec {
        switch self {
        case .feedAdd:
            KeyboardShortcutSpec(key: "n", modifiers: [.command])
        case .statisticsOpen:
            KeyboardShortcutSpec(key: "s", modifiers: [.command, .shift])
        case .feedRefreshAll:
            KeyboardShortcutSpec(key: "r", modifiers: [.command, .shift])
        case .feedRefresh:
            KeyboardShortcutSpec(key: "r", modifiers: [.command])
        case .articleSelectPrevious:
            KeyboardShortcutSpec(key: SpecialKey.upArrow.rawValue, modifiers: [.command])
        case .articleSelectNext:
            KeyboardShortcutSpec(key: SpecialKey.downArrow.rawValue, modifiers: [.command])
        case .articleSearch:
            KeyboardShortcutSpec(key: "f", modifiers: [.command])
        case .articleToggleRead:
            KeyboardShortcutSpec(key: "u", modifiers: [.command, .shift])
        case .articleToggleStarred:
            KeyboardShortcutSpec(key: "d", modifiers: [.command])
        case .articleOpenInWindow:
            KeyboardShortcutSpec(key: SpecialKey.return.rawValue, modifiers: [.command])
        case .readerWebBack:
            KeyboardShortcutSpec(key: "[", modifiers: [.command])
        case .readerWebForward:
            KeyboardShortcutSpec(key: "]", modifiers: [.command])
        }
    }
}
