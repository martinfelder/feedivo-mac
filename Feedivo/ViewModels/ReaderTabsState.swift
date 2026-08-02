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

    var activeArticleID: String? {
        tabs.first(where: { $0.id == activeTabID })?.articleID
    }

    /// Einzelklick auf einen Artikel in der Liste: aktualisiert den Inhalt
    /// des aktiven Tabs (wie Link-Navigation im selben Browser-Tab). Ist noch
    /// kein Tab offen, wird dieser Artikel als erster Tab angelegt.
    func openInActiveTab(articleID: String) {
        guard let activeTabID, let index = tabs.firstIndex(where: { $0.id == activeTabID }) else {
            let newTab = ReaderTab(articleID: articleID)
            tabs.append(newTab)
            self.activeTabID = newTab.id
            return
        }
        tabs[index].articleID = articleID
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

        guard wasActive else { return }

        if tabs.isEmpty {
            activeTabID = nil
        } else if index < tabs.count {
            activeTabID = tabs[index].id
        } else {
            activeTabID = tabs[tabs.count - 1].id
        }
    }

    func activateTab(id: ReaderTab.ID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabID = id
    }

    /// Kein Wraparound am Ende — konsistent mit der bestehenden
    /// "kein Wraparound"-Konvention des automatischen Feed-Sprungs.
    func activateNextTab() {
        guard let activeTabID, let index = tabs.firstIndex(where: { $0.id == activeTabID }) else { return }
        let nextIndex = index + 1
        guard nextIndex < tabs.count else { return }
        self.activeTabID = tabs[nextIndex].id
    }

    func activatePreviousTab() {
        guard let activeTabID, let index = tabs.firstIndex(where: { $0.id == activeTabID }) else { return }
        let previousIndex = index - 1
        guard previousIndex >= 0 else { return }
        self.activeTabID = tabs[previousIndex].id
    }
}
