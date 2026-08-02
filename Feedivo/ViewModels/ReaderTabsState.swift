import SwiftUI

/// Ein einzelner offener Artikel-Tab im Reader-Bereich des Hauptfensters.
/// Die `id` bleibt über den gesamten Lebenszyklus des Tabs stabil, auch wenn
/// sich der angezeigte Artikel (z. B. durch normale Listennavigation im
/// aktiven Tab) ändert.
struct ReaderTab: Identifiable, Equatable, Sendable {
    let id: UUID
    var articleID: String

    init(id: UUID = UUID(), articleID: String) {
        self.id = id
        self.articleID = articleID
    }
}

/// Hält die im Hauptfenster-Reader offenen Artikel-Tabs. Bewusst unabhängig
/// von der Sidebar-/Artikellisten-Auswahl (`selectedSQLiteArticleID` in
/// ContentView) — ein Wechsel des Feeds/Ordners in der Sidebar ändert nur die
/// Artikelliste, nie die offenen Tabs. Siehe
/// docs/superpowers/specs/2026-08/2026-08-02-artikel-tabs-design.md.
@MainActor
@Observable
final class ReaderTabsState {
    private(set) var tabs: [ReaderTab] = []
    private(set) var activeTabID: ReaderTab.ID?
    private let userDefaults: UserDefaults

    var activeArticleID: String? {
        tabs.first(where: { $0.id == activeTabID })?.articleID
    }

    /// Von ContentViews selectPreviousArticle()/selectNextArticle() (⌘↓/⌘↑)
    /// gesetzt, bevor sie selectedSQLiteArticleID mutieren. Unterscheidet eine
    /// durch Tastenkürzel ausgelöste Artikelnavigation von einem echten
    /// ⌘-Klick mit der Maus — beide setzen NSEvent.modifierFlags.contains(.command)
    /// auf true, müssen aber unterschiedlich behandelt werden: Tastenkürzel
    /// navigiert normal im aktiven Tab weiter, ⌘-Klick öffnet einen neuen
    /// Hintergrund-Tab und markiert den Artikel noch nicht als gelesen.
    private(set) var isArticleKeyboardNavigationInProgress = false

    func markArticleKeyboardNavigationInProgress() {
        isArticleKeyboardNavigationInProgress = true
    }

    func clearArticleKeyboardNavigationInProgress() {
        isArticleKeyboardNavigationInProgress = false
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    /// Einzelklick auf einen Artikel in der Liste: aktualisiert den Inhalt
    /// des aktiven Tabs (wie Link-Navigation im selben Browser-Tab). Ist noch
    /// kein Tab offen, wird dieser Artikel als erster Tab angelegt.
    func openInActiveTab(articleID: String) {
        guard let activeTabID, let index = tabs.firstIndex(where: { $0.id == activeTabID }) else {
            let newTab = ReaderTab(articleID: articleID)
            tabs.append(newTab)
            self.activeTabID = newTab.id
            persistIfEnabled()
            return
        }
        tabs[index].articleID = articleID
        persistIfEnabled()
    }

    /// ⌘-Klick / Kontextmenü "In neuem Tab öffnen": legt einen neuen Tab an,
    /// ohne den aktiven Tab zu wechseln — außer es war noch gar kein Tab
    /// offen, dann wird der neue Tab zwangsläufig zum aktiven Tab.
    @discardableResult
    func openInNewBackgroundTab(articleID: String) -> ReaderTab.ID {
        let newTab = ReaderTab(articleID: articleID)
        tabs.append(newTab)
        if activeTabID == nil {
            activeTabID = newTab.id
        }
        persistIfEnabled()
        return newTab.id
    }

    /// ⌘T-Semantik: dupliziert den aktiven Tab als neuen Hintergrund-Tab.
    /// Liefert `false`, wenn kein Tab aktiv ist (Aufrufer entscheidet dann
    /// selbst über einen Fallback, z. B. den aktuell in der Liste
    /// ausgewählten Artikel als ersten Tab zu öffnen).
    @discardableResult
    func duplicateActiveTab() -> Bool {
        guard let activeArticleID else { return false }
        openInNewBackgroundTab(articleID: activeArticleID)
        return true
    }

    /// Schließt einen Tab. War er aktiv, wird der Tab an derselben Position
    /// aktiv (der vorher rechts daneben lag) — existiert der nicht mehr (war
    /// der letzte Tab), wird stattdessen der neue letzte Tab aktiv. Bleibt
    /// kein Tab mehr übrig, wird `activeTabID` `nil`.
    func closeTab(id: ReaderTab.ID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let wasActive = activeTabID == id
        tabs.remove(at: index)

        guard wasActive else {
            persistIfEnabled()
            return
        }

        if tabs.isEmpty {
            activeTabID = nil
        } else if index < tabs.count {
            activeTabID = tabs[index].id
        } else {
            activeTabID = tabs[tabs.count - 1].id
        }
        persistIfEnabled()
    }

    func activateTab(id: ReaderTab.ID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabID = id
        persistIfEnabled()
    }

    /// Kein Wraparound am Ende — konsistent mit der bestehenden
    /// "kein Wraparound"-Konvention des automatischen Feed-Sprungs.
    func activateNextTab() {
        guard let activeTabID, let index = tabs.firstIndex(where: { $0.id == activeTabID }) else { return }
        let nextIndex = index + 1
        guard nextIndex < tabs.count else { return }
        self.activeTabID = tabs[nextIndex].id
        persistIfEnabled()
    }

    func activatePreviousTab() {
        guard let activeTabID, let index = tabs.firstIndex(where: { $0.id == activeTabID }) else { return }
        let previousIndex = index - 1
        guard previousIndex >= 0 else { return }
        self.activeTabID = tabs[previousIndex].id
        persistIfEnabled()
    }

    var canActivateNextTab: Bool {
        guard let activeTabID, let index = tabs.firstIndex(where: { $0.id == activeTabID }) else { return false }
        return index + 1 < tabs.count
    }

    var canActivatePreviousTab: Bool {
        guard let activeTabID, let index = tabs.firstIndex(where: { $0.id == activeTabID }) else { return false }
        return index > 0
    }

    private func persistIfEnabled() {
        guard ReaderTabsSettings.isRestoreOnLaunchEnabled(defaults: userDefaults) else { return }
        ReaderTabsSettings.save(
            articleIDs: tabs.map(\.articleID),
            activeArticleID: activeArticleID,
            defaults: userDefaults
        )
    }

    /// Beim App-Start aufzurufen (ContentView), stellt gespeicherte Tabs
    /// wieder her, falls die Einstellung aktiv ist. Ist der gespeicherte
    /// aktive Artikel nicht mehr unter den wiederhergestellten Tabs (z. B.
    /// durch eine zwischenzeitliche Schema-Änderung), fällt es auf den
    /// ersten Tab zurück.
    func restoreIfEnabled() {
        guard ReaderTabsSettings.isRestoreOnLaunchEnabled(defaults: userDefaults) else { return }
        let savedIDs = ReaderTabsSettings.savedArticleIDs(defaults: userDefaults)
        guard !savedIDs.isEmpty else { return }

        let restoredTabs = savedIDs.map { ReaderTab(articleID: $0) }
        tabs = restoredTabs

        let savedActiveArticleID = ReaderTabsSettings.savedActiveArticleID(defaults: userDefaults)
        if let savedActiveArticleID, let matchingTab = restoredTabs.first(where: { $0.articleID == savedActiveArticleID }) {
            activeTabID = matchingTab.id
        } else {
            activeTabID = restoredTabs.first?.id
        }
    }
}
