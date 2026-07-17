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
/// Standard-Button aus", kein eigentlicher, umbenennbarer Befehls-Shortcut. „Feed
/// löschen" ist ebenfalls bewusst nicht enthalten — sensible, destruktive Aktion,
/// die keinen versehentlich auslösbaren Shortcut bekommen soll (Nutzerentscheidung
/// 2026-07-16).
enum CustomizableShortcut: String, CaseIterable, Identifiable, Sendable {
    case feedAdd
    case statisticsOpen
    case feedRefreshAll
    case feedRefresh
    case feedImportOPML
    case feedExportOPML
    case feedOrganizerOpen
    case articleSelectPrevious
    case articleSelectNext
    case articleSearch
    case articleToggleRead
    case articleToggleStarred
    case articleToggleArchived
    case articleOpenInWindow
    case articleCopyLink
    case articleOpenOriginal
    case articleShareOriginal
    case articleExport
    case articlePrint
    case readerWebBack
    case readerWebForward

    var id: String { rawValue }

    var category: ShortcutCategory {
        switch self {
        case .feedAdd, .statisticsOpen, .feedRefreshAll, .feedRefresh,
             .feedImportOPML, .feedExportOPML, .feedOrganizerOpen:
            .feed
        case .articleSelectPrevious, .articleSelectNext, .articleSearch,
             .articleToggleRead, .articleToggleStarred, .articleToggleArchived,
             .articleOpenInWindow, .articleCopyLink, .articleOpenOriginal,
             .articleShareOriginal, .articleExport, .articlePrint:
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
        case .feedImportOPML: L10n.shortcutsLabelFeedImportOPML
        case .feedExportOPML: L10n.shortcutsLabelFeedExportOPML
        case .feedOrganizerOpen: L10n.shortcutsLabelFeedOrganizerOpen
        case .articleSelectPrevious: L10n.shortcutsLabelArticleSelectPrevious
        case .articleSelectNext: L10n.shortcutsLabelArticleSelectNext
        case .articleSearch: L10n.shortcutsLabelArticleSearch
        case .articleToggleRead: L10n.shortcutsLabelArticleToggleRead
        case .articleToggleStarred: L10n.shortcutsLabelArticleToggleStarred
        case .articleToggleArchived: L10n.shortcutsLabelArticleToggleArchived
        case .articleOpenInWindow: L10n.shortcutsLabelArticleOpenInWindow
        case .articleCopyLink: L10n.shortcutsLabelArticleCopyLink
        case .articleOpenOriginal: L10n.shortcutsLabelArticleOpenOriginal
        case .articleShareOriginal: L10n.shortcutsLabelArticleShareOriginal
        case .articleExport: L10n.shortcutsLabelArticleExport
        case .articlePrint: L10n.shortcutsLabelArticlePrint
        case .readerWebBack: L10n.shortcutsLabelReaderWebBack
        case .readerWebForward: L10n.shortcutsLabelReaderWebForward
        }
    }

    /// Entspricht 1:1 den bisherigen hartcodierten `.keyboardShortcut(...)`-Werten,
    /// damit sich beim Einführen dieses Features für niemanden etwas ändert, der
    /// noch nichts angepasst hat. `nil` bedeutet „kein Default" — die 8 am
    /// 2026-07-16 ergänzten Fälle hatten vorher überhaupt keinen Shortcut und
    /// erscheinen deshalb in den Einstellungen zunächst als „nicht belegt".
    var defaultSpec: KeyboardShortcutSpec? {
        switch self {
        case .feedAdd:
            KeyboardShortcutSpec(key: "n", modifiers: [.command])
        case .statisticsOpen:
            KeyboardShortcutSpec(key: "s", modifiers: [.command, .shift])
        case .feedRefreshAll:
            KeyboardShortcutSpec(key: "r", modifiers: [.command, .shift])
        case .feedRefresh:
            KeyboardShortcutSpec(key: "r", modifiers: [.command])
        case .feedImportOPML, .feedExportOPML, .feedOrganizerOpen:
            nil
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
        case .articleToggleArchived, .articleCopyLink, .articleOpenOriginal,
             .articleShareOriginal, .articleExport:
            nil
        case .articleOpenInWindow:
            KeyboardShortcutSpec(key: SpecialKey.return.rawValue, modifiers: [.command])
        case .articlePrint:
            KeyboardShortcutSpec(key: "p", modifiers: [.command])
        case .readerWebBack:
            KeyboardShortcutSpec(key: "[", modifiers: [.command])
        case .readerWebForward:
            KeyboardShortcutSpec(key: "]", modifiers: [.command])
        }
    }
}
