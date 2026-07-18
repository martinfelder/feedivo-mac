import SwiftUI

/// Registry aller Icons/Controls der Reader-Toolbar, die der Nutzer im
/// Einstellungen-Tab "Toolbar" frei umsortieren und ein-/ausblenden kann
/// (Feature 19.4). Die Deklarationsreihenfolge der Fälle entspricht der
/// heutigen Standard-Anzeigereihenfolge in
/// `SQLiteReaderView.readerToolbarContent` und ist zugleich der
/// Auslieferungszustand von `ReaderToolbarLayout()`.
enum ReaderToolbarItem: String, CaseIterable, Identifiable, Sendable {
    case search
    case openOriginal
    case createRule
    case star
    case archive
    case toggleRead
    case copyLink
    case export
    case webBack
    case webForward
    case print
    case displayModePicker
    case appearance
    case inspector

    var id: String { rawValue }

    /// Neutrales, zustandsunabhängiges Label für die Einstellungen-Liste.
    /// 13 der 14 Fälle nutzen dafür bereits bestehende Shortcuts-/Reader-Labels
    /// (`shortcuts.label.*` sind bereits state-unabhängig formuliert, z. B.
    /// "Stern umschalten" statt "Stern hinzufügen"/"Stern entfernen").
    /// `.createRule` ist der einzige Fall mit einem `String(localized:)`-Key
    /// (`L10n.articleCreateRuleCommand`) statt `LocalizedStringKey` — `Text(String)`
    /// zeigt den bereits aufgelösten String unverändert an, `Text(LocalizedStringKey)`
    /// löst den Schlüssel selbst auf; beide Initializer-Aufrufe sind hier bewusst
    /// gemischt, um für alle 14 Fälle ohne neue xcstrings-Einträge auszukommen.
    var label: Text {
        switch self {
        case .search: Text(L10n.shortcutsLabelArticleSearch)
        case .openOriginal: Text(L10n.shortcutsLabelArticleOpenOriginal)
        case .createRule: Text(L10n.articleCreateRuleCommand)
        case .star: Text(L10n.shortcutsLabelArticleToggleStarred)
        case .archive: Text(L10n.shortcutsLabelArticleToggleArchived)
        case .toggleRead: Text(L10n.shortcutsLabelArticleToggleRead)
        case .copyLink: Text(L10n.shortcutsLabelArticleCopyLink)
        case .export: Text(L10n.shortcutsLabelArticleExport)
        case .webBack: Text(L10n.shortcutsLabelReaderWebBack)
        case .webForward: Text(L10n.shortcutsLabelReaderWebForward)
        case .print: Text(L10n.shortcutsLabelArticlePrint)
        case .displayModePicker: Text(L10n.readerDisplayModePicker)
        case .appearance: Text(L10n.readerAppearanceButton)
        case .inspector: Text(L10n.readerInspectorButton)
        }
    }

    var systemImage: String {
        switch self {
        case .search: "magnifyingglass"
        case .openOriginal: "safari"
        case .createRule: "slider.horizontal.3"
        case .star: "star"
        case .archive: "archivebox"
        case .toggleRead: "circle"
        case .copyLink: "link"
        case .export: "square.and.arrow.up"
        case .webBack: "chevron.backward"
        case .webForward: "chevron.forward"
        case .print: "printer"
        case .displayModePicker: "rectangle.2.swap"
        case .appearance: "textformat"
        case .inspector: "sidebar.right"
        }
    }
}
