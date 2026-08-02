# Artikel-Tabs im Reader-Bereich Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Der Reader-Bereich des Hauptfensters bekommt eine Browser-artige Tab-Leiste, mit der mehrere Artikel gleichzeitig offen gehalten und per Klick/Kontextmenü/Tastenkürzel gewechselt werden können.

**Architecture:** Ein neues, reines `ReaderTabsState`-Modell (`@Observable`) hält die Liste offener Tabs unabhängig von der bestehenden Sidebar-/Artikelliste-Auswahl. Der Reader (`SQLiteReaderView`) zeigt immer den Artikel des aktiven Tabs statt direkt der Listenauswahl. Ein einzelner `.onChange`-Hook in `ContentView` bindet die bestehende Listenauswahl (`selectedSQLiteArticleID`) an den aktiven Tab; explizite "neuer Tab"-Aktionen (Kontextmenü, ⌘-Klick, ⌘T) legen stattdessen einen Hintergrund-Tab an, ohne den aktiven Tab zu ändern.

**Tech Stack:** SwiftUI (macOS), GRDB/SQLite, Swift Testing (kein XCTest), `@Observable`-Macro, `UserDefaults` für Persistenz (kein neues DB-Schema nötig).

## Global Constraints

- Kommentare im Code auf Deutsch (Projektkonvention, siehe CLAUDE.md).
- Keine SwiftData-Patterns, kein `ObservableObject`/`@Published` — nur `@Observable`.
- Artikel-IDs sind intern `String` (GRDB-Primärschlüssel), NICHT `UUID` — nur `ArticleWindowRequest`/`ArticleWindowSettings` (Popout-Fenster) arbeiten mit `UUID`, das ist für dieses Feature NICHT relevant (Tabs bleiben durchgängig bei `String`-IDs).
- Neue `Localizable.xcstrings`-Einträge NIEMALS per `json.load`/`json.dump` roundtripen — nur per Text-Segment-Einfügung direkt nach dem stabilen Anker `"strings" : {`, danach `git diff --stat` prüfen (nur Insertions, keine Deletions).
- Jeder neue `L10n.swift`-Key MUSS zusätzlich einen Katalogeintrag in `Localizable.xcstrings` bekommen — der Auto-Stub-Mechanismus von `xcodebuild build` greift NUR bei direkten String-Literalen, nicht bei indirekten `L10n`-Konstanten. Nach jedem neuen Key: `grep -c "<punktgetrennter-key>" Feedivo/Resources/Localizable.xcstrings` muss > 0 sein.
- Neue Migrationen sind für dieses Feature NICHT nötig (reine UserDefaults-Persistenz, kein neues DB-Schema).
- Volle Testsuite (`xcodebuild test` ohne `-only-testing:`) hängt bekanntermaßen — immer gezielt mit `-only-testing:FeedivoTests/<SuiteName>` und `-parallel-testing-enabled NO` testen.
- Bestehende, dauerhaft vorbestehende Testfehlschläge (17 in `FeedivoAppSceneConfigurationTests.swift`, 2 flaky-unter-Last in `FeedViewModelTests.swift`, 1 flaky-unter-Last `listStateToggeltReadUndAktualisiertRows` in `SQLiteFeedArticleListStateTests.swift`) sind bekannt und keine neue Regression — nicht versuchen zu fixen, aber auch keine neuen Fehlschläge einführen.
- SourceKit-Diagnosen (rote Unterstreichungen in der IDE nach Edits) sind oft veraltet/falsch — nur ein echter `xcodebuild build`-Lauf ist verlässlich.

---

## Task 1: `ReaderTab` + `ReaderTabsState` Kernmodell (reine Logik, TDD)

**Files:**
- Create: `Feedivo/ViewModels/ReaderTabsState.swift`
- Test: `FeedivoTests/ViewModels/ReaderTabsStateTests.swift`

**Interfaces:**
- Produces:
  - `struct ReaderTab: Identifiable, Equatable, Sendable { let id: UUID; var articleID: String }`
  - `@MainActor @Observable final class ReaderTabsState`
    - `private(set) var tabs: [ReaderTab]`
    - `private(set) var activeTabID: ReaderTab.ID?`
    - `var activeArticleID: String? { get }`
    - `func openInActiveTab(articleID: String)`
    - `@discardableResult func openInNewBackgroundTab(articleID: String) -> ReaderTab.ID`
    - `@discardableResult func duplicateActiveTab() -> Bool`
    - `func closeTab(id: ReaderTab.ID)`
    - `func activateTab(id: ReaderTab.ID)`
    - `func activateNextTab()`
    - `func activatePreviousTab()`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import Feedivo

@MainActor
struct ReaderTabsStateTests {
    @Test func openInActiveTabErstelltErstenTabBeiLeererListe() {
        let state = ReaderTabsState()
        state.openInActiveTab(articleID: "article-1")

        #expect(state.tabs.count == 1)
        #expect(state.tabs.first?.articleID == "article-1")
        #expect(state.activeArticleID == "article-1")
    }

    @Test func openInActiveTabAktualisiertBestehendenAktivenTab() {
        let state = ReaderTabsState()
        state.openInActiveTab(articleID: "article-1")
        let firstTabID = state.activeTabID

        state.openInActiveTab(articleID: "article-2")

        #expect(state.tabs.count == 1)
        #expect(state.activeTabID == firstTabID)
        #expect(state.activeArticleID == "article-2")
    }

    @Test func openInNewBackgroundTabLaesstAktivenTabUnveraendert() {
        let state = ReaderTabsState()
        state.openInActiveTab(articleID: "article-1")
        let firstTabID = state.activeTabID

        state.openInNewBackgroundTab(articleID: "article-2")

        #expect(state.tabs.count == 2)
        #expect(state.activeTabID == firstTabID)
        #expect(state.activeArticleID == "article-1")
    }

    @Test func openInNewBackgroundTabWirdAktivWennKeinTabOffenIst() {
        let state = ReaderTabsState()

        let newTabID = state.openInNewBackgroundTab(articleID: "article-1")

        #expect(state.tabs.count == 1)
        #expect(state.activeTabID == newTabID)
    }

    @Test func duplicateActiveTabOeffnetHintergrundTabMitGleicherArtikelID() {
        let state = ReaderTabsState()
        state.openInActiveTab(articleID: "article-1")
        let firstTabID = state.activeTabID

        let didDuplicate = state.duplicateActiveTab()

        #expect(didDuplicate)
        #expect(state.tabs.count == 2)
        #expect(state.activeTabID == firstTabID)
        #expect(state.tabs.map(\.articleID) == ["article-1", "article-1"])
    }

    @Test func duplicateActiveTabLiefertFalseOhneAktivenTab() {
        let state = ReaderTabsState()

        let didDuplicate = state.duplicateActiveTab()

        #expect(!didDuplicate)
        #expect(state.tabs.isEmpty)
    }

    @Test func closeTabAktiviertNachbarTabAnGleicherPosition() {
        let state = ReaderTabsState()
        state.openInActiveTab(articleID: "article-1")
        state.openInNewBackgroundTab(articleID: "article-2")
        state.openInNewBackgroundTab(articleID: "article-3")
        state.activateTab(id: state.tabs[1].id)
        let tabToCloseID = state.tabs[1].id
        let expectedNextActiveID = state.tabs[2].id

        state.closeTab(id: tabToCloseID)

        #expect(state.tabs.count == 2)
        #expect(state.activeTabID == expectedNextActiveID)
    }

    @Test func closeTabAktiviertVorherigenTabWennLetzterTabGeschlossenWird() {
        let state = ReaderTabsState()
        state.openInActiveTab(articleID: "article-1")
        state.openInNewBackgroundTab(articleID: "article-2")
        state.activateTab(id: state.tabs[1].id)
        let firstTabID = state.tabs[0].id

        state.closeTab(id: state.tabs[1].id)

        #expect(state.tabs.count == 1)
        #expect(state.activeTabID == firstTabID)
    }

    @Test func closeLetztenTabLeertAktivenTab() {
        let state = ReaderTabsState()
        state.openInActiveTab(articleID: "article-1")

        state.closeTab(id: state.tabs[0].id)

        #expect(state.tabs.isEmpty)
        #expect(state.activeTabID == nil)
        #expect(state.activeArticleID == nil)
    }

    @Test func schliessenEinesInaktivenTabsAendertAktivenTabNicht() {
        let state = ReaderTabsState()
        state.openInActiveTab(articleID: "article-1")
        state.openInNewBackgroundTab(articleID: "article-2")
        let activeID = state.activeTabID
        let backgroundTabID = state.tabs[1].id

        state.closeTab(id: backgroundTabID)

        #expect(state.tabs.count == 1)
        #expect(state.activeTabID == activeID)
    }

    @Test func activateNextTabWechseltZumFolgendenTabOhneWraparound() {
        let state = ReaderTabsState()
        state.openInActiveTab(articleID: "article-1")
        state.openInNewBackgroundTab(articleID: "article-2")
        let secondTabID = state.tabs[1].id

        state.activateNextTab()
        #expect(state.activeTabID == secondTabID)

        state.activateNextTab()
        #expect(state.activeTabID == secondTabID)
    }

    @Test func activatePreviousTabWechseltZumVorherigenTabOhneWraparound() {
        let state = ReaderTabsState()
        state.openInActiveTab(articleID: "article-1")
        state.openInNewBackgroundTab(articleID: "article-2")
        state.activateTab(id: state.tabs[1].id)
        let firstTabID = state.tabs[0].id

        state.activatePreviousTab()
        #expect(state.activeTabID == firstTabID)

        state.activatePreviousTab()
        #expect(state.activeTabID == firstTabID)
    }

    @Test func activateTabIgnoriertUnbekannteID() {
        let state = ReaderTabsState()
        state.openInActiveTab(articleID: "article-1")
        let activeID = state.activeTabID

        state.activateTab(id: UUID())

        #expect(state.activeTabID == activeID)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ReaderTabsStateTests -parallel-testing-enabled NO`
Expected: FAIL (Compile-Fehler `Cannot find 'ReaderTabsState' in scope`, da die Datei noch nicht existiert)

- [ ] **Step 3: Implementierung schreiben**

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ReaderTabsStateTests -parallel-testing-enabled NO`
Expected: PASS (13/13 Tests grün)

- [ ] **Step 5: Commit**

```bash
git add Feedivo/ViewModels/ReaderTabsState.swift FeedivoTests/ViewModels/ReaderTabsStateTests.swift
git commit -m "feat: ReaderTabsState-Kernmodell für Artikel-Tabs im Reader"
```

---

## Task 2: Persistenz (`ReaderTabsSettings` + Speichern/Wiederherstellen)

**Files:**
- Create: `Feedivo/Services/ReaderTabsSettings.swift`
- Modify: `Feedivo/ViewModels/ReaderTabsState.swift`
- Test: `FeedivoTests/ViewModels/ReaderTabsStateTests.swift` (erweitern)

**Interfaces:**
- Consumes: `ReaderTab`, `ReaderTabsState` aus Task 1
- Produces:
  - `enum ReaderTabsSettings` mit `restoreTabsOnLaunchKey`, `defaultRestoreTabsOnLaunch = false`, `openTabArticleIDsKey`, `activeTabArticleIDKey`, `isRestoreOnLaunchEnabled(defaults:) -> Bool`, `savedArticleIDs(defaults:) -> [String]`, `savedActiveArticleID(defaults:) -> String?`, `save(articleIDs:activeArticleID:defaults:)`, `clear(defaults:)`
  - `ReaderTabsState.init(userDefaults: UserDefaults = .standard)`
  - `ReaderTabsState.restoreIfEnabled()`

- [ ] **Step 1: Write the failing tests**

Ergänze in `FeedivoTests/ViewModels/ReaderTabsStateTests.swift`:

```swift
    @Test func persistiertOffeneTabsBeiAktivierterEinstellung() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defer { defaults.removePersistentDomain(forName: #function) }
        defaults.set(true, forKey: ReaderTabsSettings.restoreTabsOnLaunchKey)
        let state = ReaderTabsState(userDefaults: defaults)

        state.openInActiveTab(articleID: "article-1")
        state.openInNewBackgroundTab(articleID: "article-2")

        #expect(ReaderTabsSettings.savedArticleIDs(defaults: defaults) == ["article-1", "article-2"])
        #expect(ReaderTabsSettings.savedActiveArticleID(defaults: defaults) == "article-1")
    }

    @Test func persistiertNichtsBeiDeaktivierterEinstellung() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defer { defaults.removePersistentDomain(forName: #function) }
        defaults.set(false, forKey: ReaderTabsSettings.restoreTabsOnLaunchKey)
        let state = ReaderTabsState(userDefaults: defaults)

        state.openInActiveTab(articleID: "article-1")

        #expect(ReaderTabsSettings.savedArticleIDs(defaults: defaults).isEmpty)
    }

    @Test func persistiertAuchNachSchliessenDesLetztenTabs() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defer { defaults.removePersistentDomain(forName: #function) }
        defaults.set(true, forKey: ReaderTabsSettings.restoreTabsOnLaunchKey)
        let state = ReaderTabsState(userDefaults: defaults)
        state.openInActiveTab(articleID: "article-1")

        state.closeTab(id: state.tabs[0].id)

        #expect(ReaderTabsSettings.savedArticleIDs(defaults: defaults).isEmpty)
        #expect(ReaderTabsSettings.savedActiveArticleID(defaults: defaults) == nil)
    }

    @Test func restoreIfEnabledStelltGespeicherteTabsUndAktivenTabWiederHer() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defer { defaults.removePersistentDomain(forName: #function) }
        defaults.set(true, forKey: ReaderTabsSettings.restoreTabsOnLaunchKey)
        ReaderTabsSettings.save(articleIDs: ["article-1", "article-2"], activeArticleID: "article-2", defaults: defaults)

        let state = ReaderTabsState(userDefaults: defaults)
        state.restoreIfEnabled()

        #expect(state.tabs.map(\.articleID) == ["article-1", "article-2"])
        #expect(state.activeArticleID == "article-2")
    }

    @Test func restoreIfEnabledTutNichtsBeiDeaktivierterEinstellung() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defer { defaults.removePersistentDomain(forName: #function) }
        defaults.set(false, forKey: ReaderTabsSettings.restoreTabsOnLaunchKey)
        ReaderTabsSettings.save(articleIDs: ["article-1"], activeArticleID: "article-1", defaults: defaults)

        let state = ReaderTabsState(userDefaults: defaults)
        state.restoreIfEnabled()

        #expect(state.tabs.isEmpty)
    }

    @Test func restoreIfEnabledFaelltAufErstenTabZurueckWennGespeicherterAktiverArtikelFehlt() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defer { defaults.removePersistentDomain(forName: #function) }
        defaults.set(true, forKey: ReaderTabsSettings.restoreTabsOnLaunchKey)
        ReaderTabsSettings.save(articleIDs: ["article-1", "article-2"], activeArticleID: "article-unbekannt", defaults: defaults)

        let state = ReaderTabsState(userDefaults: defaults)
        state.restoreIfEnabled()

        #expect(state.activeArticleID == "article-1")
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ReaderTabsStateTests -parallel-testing-enabled NO`
Expected: FAIL (Compile-Fehler `Cannot find 'ReaderTabsSettings' in scope`, `extra argument 'userDefaults' in call`)

- [ ] **Step 3: `ReaderTabsSettings` implementieren**

```swift
import Foundation

/// UserDefaults-Schema für die optionale Persistenz offener Reader-Tabs.
/// Analog zu `ArticleWindowSettings` (Popout-Fenster), aber mit `String`-
/// statt `UUID`-Artikel-IDs, da Tabs direkt mit den internen GRDB-
/// Primärschlüsseln arbeiten.
enum ReaderTabsSettings {
    static let restoreTabsOnLaunchKey = "readerTabs.restoreOnLaunch"
    static let defaultRestoreTabsOnLaunch = false
    static let openTabArticleIDsKey = "readerTabs.openArticleIDs"
    static let activeTabArticleIDKey = "readerTabs.activeArticleID"

    static func isRestoreOnLaunchEnabled(defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: restoreTabsOnLaunchKey) != nil else {
            return defaultRestoreTabsOnLaunch
        }
        return defaults.bool(forKey: restoreTabsOnLaunchKey)
    }

    static func savedArticleIDs(defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: openTabArticleIDsKey) ?? []
    }

    static func savedActiveArticleID(defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: activeTabArticleIDKey)
    }

    static func save(articleIDs: [String], activeArticleID: String?, defaults: UserDefaults = .standard) {
        defaults.set(articleIDs, forKey: openTabArticleIDsKey)
        if let activeArticleID {
            defaults.set(activeArticleID, forKey: activeTabArticleIDKey)
        } else {
            defaults.removeObject(forKey: activeTabArticleIDKey)
        }
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: openTabArticleIDsKey)
        defaults.removeObject(forKey: activeTabArticleIDKey)
    }
}
```

- [ ] **Step 4: `ReaderTabsState` um Persistenz erweitern**

In `Feedivo/ViewModels/ReaderTabsState.swift`: `private(set) var tabs`/`activeTabID`-Deklarationen unverändert lassen, direkt danach ergänzen:

```swift
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }
```

Jede der fünf mutierenden Methoden (`openInActiveTab`, `openInNewBackgroundTab`, `duplicateActiveTab` — indirekt über `openInNewBackgroundTab`, kein doppelter Aufruf nötig —, `closeTab`, `activateTab`, `activateNextTab`, `activatePreviousTab`) bekommt am Ende einen Aufruf von `persistIfEnabled()`. Beispiel für `openInActiveTab`:

```swift
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
```

Analog `persistIfEnabled()` am Ende von `openInNewBackgroundTab` (nach dem `if activeTabID == nil { ... }`-Block, vor `return newTab.id`), `closeTab` (ganz am Ende, auch im `guard wasActive else { return }`-Fall — dort VOR dem `return`, da sich `tabs` durch das Entfernen bereits geändert hat), `activateTab` (nach `activeTabID = id`), `activateNextTab` und `activatePreviousTab` (jeweils nach der Zuweisung von `self.activeTabID`). `duplicateActiveTab` braucht KEINEN eigenen Aufruf — es ruft bereits `openInNewBackgroundTab` auf, das seinerseits persistiert.

Am Ende der Klasse ergänzen:

```swift
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
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ReaderTabsStateTests -parallel-testing-enabled NO`
Expected: PASS (19/19 Tests grün)

- [ ] **Step 6: Commit**

```bash
git add Feedivo/ViewModels/ReaderTabsState.swift Feedivo/Services/ReaderTabsSettings.swift FeedivoTests/ViewModels/ReaderTabsStateTests.swift
git commit -m "feat: Optionale Persistenz offener Reader-Tabs (ReaderTabsSettings)"
```

---

## Task 3: Einstellungen-Schalter "Offene Tabs beim Neustart wiederherstellen"

**Files:**
- Modify: `Feedivo/Views/Settings/SettingsView.swift` (Struktur `ArticleListSettingsView`, um Zeile 602-671)
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `ReaderTabsSettings.restoreTabsOnLaunchKey`, `ReaderTabsSettings.defaultRestoreTabsOnLaunch` aus Task 2
- Produces: `L10n.settingsArticleListRestoreTabsOnLaunchTitle: LocalizedStringKey`

- [ ] **Step 1: L10n-Key ergänzen**

In `Feedivo/Resources/L10n.swift`, direkt bei den übrigen `settingsArticleList*`-Keys (z. B. neben `settingsArticleListFeedJumpNavigationTitle`) ergänzen:

```swift
    static let settingsArticleListRestoreTabsOnLaunchTitle = LocalizedStringKey("settings.articleList.restoreTabsOnLaunch.title")
```

- [ ] **Step 2: Katalogeintrag in `Localizable.xcstrings` ergänzen**

NICHT `json.load`/`json.dump` verwenden. Direkt nach dem Anker `"strings" : {` per Text-Einfügung einen neuen Eintrag ergänzen (Format exakt an bestehende Einträge angleichen, z. B. an `"settings.articleList.feedJumpNavigation.title"` als Vorbild für Einrückung/Anführungszeichen-Stil):

```json
    "settings.articleList.restoreTabsOnLaunch.title" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Offene Tabs beim Neustart wiederherstellen"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Restore open tabs on launch"
          }
        }
      }
    },
```

Danach verifizieren: `grep -c "settings.articleList.restoreTabsOnLaunch.title" Feedivo/Resources/Localizable.xcstrings` muss `1` (oder mehr) liefern.

- [ ] **Step 3: Toggle in `SettingsView.swift` ergänzen**

In `ArticleListSettingsView` (um Zeile 618-619) direkt neben der bestehenden `@AppStorage`-Deklaration für `feedJumpNavigationIsEnabled` ergänzen:

```swift
    @AppStorage(ReaderTabsSettings.restoreTabsOnLaunchKey)
    private var restoreReaderTabsOnLaunch = ReaderTabsSettings.defaultRestoreTabsOnLaunch
```

Direkt nach dem bestehenden Toggle-Block für `feedJumpNavigationIsEnabled` (um Zeile 666-671):

```swift
                Toggle(isOn: $feedJumpNavigationIsEnabled) {
                    Text(L10n.settingsArticleListFeedJumpNavigationTitle).font(.system(size: 13))
                }
                .toggleStyle(.checkbox)
                .tint(Color.settingsBoldAccent)
```

ergänzen:

```swift

                Toggle(isOn: $restoreReaderTabsOnLaunch) {
                    Text(L10n.settingsArticleListRestoreTabsOnLaunchTitle).font(.system(size: 13))
                }
                .toggleStyle(.checkbox)
                .tint(Color.settingsBoldAccent)
```

- [ ] **Step 4: Build verifizieren**

Run: `xcodebuild build -scheme Feedivo -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Views/Settings/SettingsView.swift Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings
git commit -m "feat: Einstellungen-Schalter für Tab-Wiederherstellung beim Neustart"
```

---

## Task 4: `ReaderTabsState` in ContentView verdrahten (Kern-Bridging)

**Files:**
- Modify: `Feedivo/Views/ContentView.swift`

**Interfaces:**
- Consumes: `ReaderTabsState` (Task 1/2)
- Produces: `ContentView.readerTabsState: ReaderTabsState` (für Task 5/6/8 als Ausgangspunkt)

- [ ] **Step 1: State-Objekt hinzufügen**

Direkt neben der bestehenden Deklaration in `ContentView.swift:41`:

```swift
    @State private var selectedSQLiteArticleID: String?
```

ergänzen:

```swift
    @State private var readerTabsState = ReaderTabsState()
```

- [ ] **Step 2: Bridging-`.onChange` ergänzen**

Direkt neben dem bestehenden `.onChange(of: sidebarSelection, handleSidebarSelectionChange)` (Zeile 176) im selben Modifier-Block ergänzen:

```swift
                .onChange(of: selectedSQLiteArticleID) { _, newValue in
                    guard let newValue else { return }
                    if NSEvent.modifierFlags.contains(.command) {
                        readerTabsState.openInNewBackgroundTab(articleID: newValue)
                    } else {
                        readerTabsState.openInActiveTab(articleID: newValue)
                    }
                }
```

Wichtig: dieser Handler feuert bewusst NICHT bei `newValue == nil` — ein Sidebar-/Ordnerwechsel setzt `selectedSQLiteArticleID` über `handleSidebarSelectionChange()` typischerweise auf `nil` zurück, das darf die offenen Tabs nicht berühren (siehe Design-Spec, Abschnitt "Architektur & Datenmodell"). `NSEvent` ist bereits über das bestehende `import AppKit` (Zeile 1) verfügbar.

- [ ] **Step 3: Wiederherstellung beim App-Start**

Finde die bestehende Funktion `handleContentAppear()` (`grep -n "func handleContentAppear" Feedivo/Views/ContentView.swift`) und ergänze `readerTabsState.restoreIfEnabled()` als ALLERERSTEN Schritt der Funktion (vor allen anderen bestehenden Anweisungen dort — Reihenfolge ist hier nicht kritisch, da Tabs komplett unabhängig vom übrigen Start-Ablauf sind, aber ein früher, eindeutiger Platz vermeidet spätere Verwechslungen).

- [ ] **Step 4: Build verifizieren**

Run: `xcodebuild build -scheme Feedivo -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED. Der Reader zeigt an dieser Stelle im Plan noch UNVERÄNDERT `selectedSQLiteArticleID` (Task 5 stellt auf `readerTabsState.activeArticleID` um) — das ist ein bewusster Zwischenzustand: `readerTabsState` wird bereits korrekt befüllt, hat aber noch keine sichtbare Wirkung.

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Views/ContentView.swift
git commit -m "feat: ReaderTabsState in ContentView verdrahten (Bridging von selectedSQLiteArticleID)"
```

---

## Task 5: `ReaderTabBarView` UI + Detail-Spalte umstellen

**Files:**
- Create: `Feedivo/Views/Reader/ReaderTabBarView.swift`
- Modify: `Feedivo/Views/ContentView.swift`
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `ReaderTab`, `ReaderTabsState` (Task 1), `ArticleDatabase.fetchArticles(articleIDs:includeHidden:limit:) throws -> [ArticleListSnapshot]` (bestehend, `Feedivo/Stores/ArticleDatabase.swift`), `CachedRemoteImageView` (bestehend)
- Produces: `ReaderTabBarView` (View), `ContentView.markActiveReaderTabArticleReadIfNeeded()`

- [ ] **Step 1: L10n-Keys ergänzen**

In `Feedivo/Resources/L10n.swift`:

```swift
    static let readerTabNewCommand = LocalizedStringKey("reader.tab.new")
    static let readerTabArticleUnavailable = LocalizedStringKey("reader.tab.articleUnavailable")
```

In `Localizable.xcstrings` (Anker `"strings" : {`, Text-Einfügung, danach `grep -c` verifizieren):

```json
    "reader.tab.new" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Neuer Tab"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "New Tab"
          }
        }
      }
    },
    "reader.tab.articleUnavailable" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Artikel nicht mehr verfügbar"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Article no longer available"
          }
        }
      }
    },
```

- [ ] **Step 2: `ReaderTabBarView` implementieren**

```swift
import SwiftUI
import AppKit

/// Chrome-Register-artige Tab-Leiste über dem Reader-Bereich des
/// Hauptfensters. Rein präsentational — DB-Mutationen (Tab aktivieren,
/// schließen, neu anlegen) laufen ausschließlich über die vom Parent
/// übergebenen Closures, siehe docs/superpowers/specs/2026-08/
/// 2026-08-02-artikel-tabs-design.md.
struct ReaderTabBarView: View {
    let tabs: [ReaderTab]
    let activeTabID: ReaderTab.ID?
    let database: FeedivoDatabase?
    let onActivate: (ReaderTab.ID) -> Void
    let onClose: (ReaderTab.ID) -> Void
    let onNewTab: () -> Void

    @State private var metadataByArticleID: [String: ArticleListSnapshot] = [:]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                tabView(for: tab)
            }

            Button(action: onNewTab) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
            .padding(.bottom, 4)
            .help(L10n.readerTabNewCommand)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.top, 6)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
        .task(id: tabs.map(\.articleID)) {
            await loadMetadata()
        }
    }

    @ViewBuilder
    private func tabView(for tab: ReaderTab) -> some View {
        let metadata = metadataByArticleID[tab.articleID]
        let isActive = tab.id == activeTabID
        let displayTitle = metadata?.title ?? L10n.readerTabArticleUnavailable

        TabRow(
            displayTitle: displayTitle,
            isActive: isActive,
            faviconContent: { faviconView(for: metadata) },
            onActivate: { onActivate(tab.id) },
            onClose: { onClose(tab.id) }
        )
    }

    /// Eigene Zeilen-View statt eines Closures innerhalb von `tabView`, damit
    /// `@State private var isHovering` eine eigene, pro Tab stabile
    /// Identität hat (ein `@State` in einem `@ViewBuilder`-Funktionsergebnis
    /// würde bei jedem Neuaufbau von `tabs` zurückgesetzt).
    private struct TabRow<Favicon: View>: View {
        let displayTitle: String
        let isActive: Bool
        @ViewBuilder let faviconContent: () -> Favicon
        let onActivate: () -> Void
        let onClose: () -> Void

        @State private var isHovering = false

        var body: some View {
            HStack(spacing: 6) {
                faviconContent()
                    .frame(width: 14, height: 14)

                Text(displayTitle)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(.plain)
                .opacity(isActive || isHovering ? 0.6 : 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minWidth: 60, maxWidth: 160)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isActive ? Color(nsColor: .controlBackgroundColor) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isActive ? Color(nsColor: .separatorColor) : Color.clear)
            )
            .contentShape(Rectangle())
            .onTapGesture(perform: onActivate)
            .onHover { isHovering = $0 }
            .help(displayTitle)
        }
    }

    @ViewBuilder
    private func faviconView(for metadata: ArticleListSnapshot?) -> some View {
        if let faviconURLString = metadata?.faviconURL, let url = URL(string: faviconURLString) {
            CachedRemoteImageView(url: url) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                faviconFallback
            }
        } else {
            faviconFallback
        }
    }

    private var faviconFallback: some View {
        Image(systemName: "dot.radiowaves.left.and.right")
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
    }

    /// Lädt Titel/Feed-Favicon für alle offenen Tabs in einem Rutsch. Läuft
    /// per `Task.detached`, da `ArticleDatabase.fetchArticles(...)`
    /// synchron ist und das Projekt `SWIFT_DEFAULT_ACTOR_ISOLATION =
    /// MainActor` setzt (siehe Gotcha in CLAUDE.md) — ein einfaches `Task {}`
    /// würde sonst weiterhin auf dem MainActor blockieren.
    private func loadMetadata() async {
        guard let database else {
            metadataByArticleID = [:]
            return
        }

        let articleIDs = Set(tabs.map(\.articleID))
        guard !articleIDs.isEmpty else {
            metadataByArticleID = [:]
            return
        }

        let snapshots = await Task.detached(priority: .userInitiated) {
            (try? ArticleDatabase(database: database).fetchArticles(articleIDs: articleIDs)) ?? []
        }.value

        metadataByArticleID = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id, $0) })
    }
}
```

Fehlt ein Artikel in den geladenen `snapshots` (z. B. weil er zwischenzeitlich gelöscht wurde), bleibt `metadataByArticleID[tab.articleID]` einfach `nil` — der Tab zeigt dann automatisch `L10n.readerTabArticleUnavailable` mit dem Favicon-Platzhalter. Kein separater Fehlerzustand nötig, da `fetchArticles` bei fehlenden IDs laut bestehendem Verhalten keinen Fehler wirft, sondern nur eine kürzere Liste liefert.

- [ ] **Step 3: Detail-Spalte in `ContentView.swift` umstellen**

`grep -n "@Environment(\\.feedivoDatabase)" Feedivo/Views/ContentView.swift` ausführen, um den exakten Namen der bestehenden Datenbank-Environment-Property zu finden (im Folgenden als `database` angenommen — bei Abweichung den tatsächlichen Namen verwenden).

Den bestehenden Block (Zeile 160-174):

```swift
        } detail: {
            SQLiteReaderView(
                articleID: selectedSQLiteArticleID,
                canSelectPreviousArticle: sqliteArticleNavigationState.previousArticleID != nil,
                canSelectNextArticle: sqliteArticleNavigationState.nextArticleID != nil,
                selectPreviousArticle: selectPreviousArticle,
                selectNextArticle: selectNextArticle,
                onSnapshotChange: handleSQLiteArticleSnapshotChange,
                onCreateRule: requestRuleCreation
            )
        }
```

ersetzen durch:

```swift
        } detail: {
            VStack(spacing: 0) {
                if !readerTabsState.tabs.isEmpty {
                    ReaderTabBarView(
                        tabs: readerTabsState.tabs,
                        activeTabID: readerTabsState.activeTabID,
                        database: database,
                        onActivate: { tabID in
                            readerTabsState.activateTab(id: tabID)
                            markActiveReaderTabArticleReadIfNeeded()
                        },
                        onClose: { tabID in
                            readerTabsState.closeTab(id: tabID)
                        },
                        onNewTab: {
                            readerTabsState.duplicateActiveTab()
                        }
                    )
                }

                SQLiteReaderView(
                    articleID: readerTabsState.activeArticleID,
                    canSelectPreviousArticle: sqliteArticleNavigationState.previousArticleID != nil,
                    canSelectNextArticle: sqliteArticleNavigationState.nextArticleID != nil,
                    selectPreviousArticle: selectPreviousArticle,
                    selectNextArticle: selectNextArticle,
                    onSnapshotChange: handleSQLiteArticleSnapshotChange,
                    onCreateRule: requestRuleCreation
                )
            }
        }
```

- [ ] **Step 4: Gelesen-Markierungs-Helfer für Tab-Aktivierung ergänzen**

Die bestehende, listenbasierte Gelesen-Markierung (`SQLiteFeedArticleListView.markSelectedArticleReadIfNeeded()`) bleibt für den normalen Klick-Fall unverändert bestehen — sie feuert weiterhin korrekt, wenn `selectedSQLiteArticleID` sich durch einen Listenklick ändert. Für den NEUEN Fall (Wechsel zu einem bereits offenen Hintergrund-Tab, dessen Artikel evtl. gar nicht in der aktuell sichtbaren Liste steht) wird ein direkter, listenunabhängiger Aufruf gebraucht. In `ContentView.swift` ergänzen (in der Nähe der übrigen `private func handle...`/`private func mark...`-Hilfsfunktionen):

```swift
    @AppStorage("markArticleReadOnSelection") private var markArticleReadOnSelection = true

    /// Listenunabhängige Gelesen-Markierung für den Fall, dass ein Tab
    /// aktiviert wird, dessen Artikel nicht (mehr) in der aktuell
    /// sichtbaren Artikelliste steht — die bestehende
    /// `markSelectedArticleReadIfNeeded()` in SQLiteFeedArticleListView
    /// bräuchte dafür zwingend eine passende Zeile in `state.rows`, die hier
    /// nicht garantiert ist. Nutzt direkt `ArticleStatusStore`, das
    /// unabhängig von jeder geladenen Liste per Artikel-ID schreibt.
    private func markActiveReaderTabArticleReadIfNeeded() {
        guard markArticleReadOnSelection,
              let database,
              let articleID = readerTabsState.activeArticleID
        else { return }

        do {
            try ArticleStatusStore(database: database).setRead(true, articleID: articleID, at: Date())
        } catch {
            AppLogger.dataAccess.error("Konnte Artikel beim Tab-Wechsel nicht als gelesen markieren: \(error, privacy: .public)")
        }
    }
```

Falls in `ContentView.swift` bereits eine `@AppStorage("markArticleReadOnSelection")`-Deklaration existiert (`grep -n 'AppStorage("markArticleReadOnSelection")' Feedivo/Views/ContentView.swift`), diese wiederverwenden statt eine zweite anzulegen.

- [ ] **Step 5: Bestehende Rechts-/Links-/Return-Tastaturkürzel korrigieren**

Die drei bestehenden `.onKeyPress`-Handler in `ContentView.swift` (Zeilen ~194, ~207, ~219 — Reader-Ansichtswechsel und "Original öffnen") sind aktuell auf `guard selectedSQLiteArticleID != nil, ...` gegatet. Da der Reader jetzt den Artikel des AKTIVEN TABS zeigt (der von `selectedSQLiteArticleID` abweichen kann, sobald der Nutzer zu einem Hintergrund-Tab wechselt, ohne die Listenauswahl zu ändern), muss die Bedingung an allen drei Stellen von `selectedSQLiteArticleID != nil` auf `readerTabsState.activeArticleID != nil` umgestellt werden — sonst würden diese Tastenkürzel nach einem Tab-Wechsel fälschlich deaktiviert bleiben, obwohl der Reader sichtbar einen Artikel zeigt. `grep -n "selectedSQLiteArticleID != nil" Feedivo/Views/ContentView.swift` liefert die exakten Stellen; jedes Vorkommen innerhalb dieser drei `.onKeyPress`-Guards ersetzen (NICHT die Deklaration selbst oder den Bridging-Handler aus Task 4, die bleiben unverändert).

- [ ] **Step 6: Build verifizieren**

Run: `xcodebuild build -scheme Feedivo -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Commit**

```bash
git add Feedivo/Views/Reader/ReaderTabBarView.swift Feedivo/Views/ContentView.swift Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings
git commit -m "feat: Tab-Leiste im Reader-Bereich rendern und verdrahten"
```

---

## Task 6: Kontextmenü "In neuem Tab öffnen"

**Files:**
- Modify: `Feedivo/Views/ArticleList/ArticleRowView.swift`
- Modify: `Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift`
- Modify: `Feedivo/Views/ContentView.swift`
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `ReaderTabsState.openInNewBackgroundTab(articleID:)` (Task 1)
- Produces: `ArticleRowView.onOpenInNewTab: () -> Void`

- [ ] **Step 1: L10n-Key ergänzen**

`Feedivo/Resources/L10n.swift`:

```swift
    static let articleOpenInNewTabCommand = LocalizedStringKey("article.openInNewTab")
```

`Localizable.xcstrings` (Text-Einfügung nach `"strings" : {`, danach `grep -c` verifizieren):

```json
    "article.openInNewTab" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "In neuem Tab öffnen"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Open in New Tab"
          }
        }
      }
    },
```

- [ ] **Step 2: `ArticleRowView` um neuen Callback + Kontextmenü-Eintrag ergänzen**

In `ArticleRowView.swift`, direkt neben der bestehenden Property (Zeile 68):

```swift
    let onOpenInWindow: () -> Void
```

ergänzen:

```swift
    let onOpenInNewTab: () -> Void
```

Im `.contextMenu` (Zeile 152-154), direkt VOR dem bestehenden Eintrag:

```swift
            Button(L10n.articleOpenInWindowCommand) {
                onOpenInWindow()
            }
```

ergänzen:

```swift
            Button(L10n.articleOpenInNewTabCommand) {
                onOpenInNewTab()
            }

            Button(L10n.articleOpenInWindowCommand) {
                onOpenInWindow()
            }
```

- [ ] **Step 3: `SQLiteFeedArticleListView` verdrahten**

`grep -n "readerTabsState\|init(\|onOpenInWindow: {\|ArticleRowView(" Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift` ausführen, um alle Stellen zu finden, die berührt werden müssen:

1. **Neuer Init-Parameter** — in ALLEN VIER `init`-Überladungen (für `feedID:`, `tagID:`, `smartFilter:`, `smartFolder:`, Zeilen 117-177) einen neuen Parameter `readerTabsState: ReaderTabsState` ergänzen (analog zu den bestehenden `Binding`-Parametern, aber als einfacher `let`-Wert, da `ReaderTabsState` selbst `@Observable` ist) und `self.readerTabsState = readerTabsState` im jeweiligen Body setzen. Eine neue gespeicherte Property `private let readerTabsState: ReaderTabsState` auf Klassenebene ergänzen.

2. **Callback bei Zeile 490-495** — den bestehenden Block

```swift
                onOpenInWindow: {
                    guard let articleID = UUID(uuidString: row.id) else { return }
                    openWindow(value: ArticleWindowRequest(articleID: articleID))
                },
```

um einen neuen Parameter direkt davor ergänzen:

```swift
                onOpenInNewTab: {
                    readerTabsState.openInNewBackgroundTab(articleID: row.id)
                },
                onOpenInWindow: {
                    guard let articleID = UUID(uuidString: row.id) else { return }
                    openWindow(value: ArticleWindowRequest(articleID: articleID))
                },
```

- [ ] **Step 4: `readerTabsState` von ContentView bis zur Liste durchreichen**

`grep -n "SQLiteFeedArticleListView(" Feedivo/Views/ContentView.swift` liefert die Aufrufstellen im Content-Bereich der `NavigationSplitView` (ein Aufruf pro Auswahl-Typ: Feed/Tag/SmartFilter/SmartFolder). An JEDER dieser Stellen den neuen Parameter `readerTabsState: readerTabsState` ergänzen (Name identisch zur Property aus Task 4, daher Kurzschreibweise `readerTabsState` statt `readerTabsState: readerTabsState` möglich, je nach Swift-Version — beide Schreibweisen sind funktional gleich).

- [ ] **Step 5: Build verifizieren**

Run: `xcodebuild build -scheme Feedivo -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Views/ArticleList/ArticleRowView.swift Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift Feedivo/Views/ContentView.swift Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings
git commit -m "feat: Kontextmenü-Eintrag \"In neuem Tab öffnen\""
```

---

## Task 7: `CustomizableShortcut` — vier neue Tab-Tastenkürzel (Modell)

**Files:**
- Modify: `Feedivo/Models/CustomizableShortcut.swift`
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`
- Test: `FeedivoTests/Models/CustomizableShortcutTests.swift` (falls noch nicht vorhanden: `grep -rn "struct CustomizableShortcutTests" FeedivoTests/` prüfen, sonst neu anlegen)

**Interfaces:**
- Produces: `CustomizableShortcut.readerNewTab`, `.readerCloseTab`, `.readerNextTab`, `.readerPreviousTab` (neue Enum-Fälle, Kategorie `.reader`, Default ⌘T/⌘W/⌘⇧]/⌘⇧[)

- [ ] **Step 1: Write the failing test**

Falls `FeedivoTests/Models/CustomizableShortcutTests.swift` bereits existiert, folgende Tests dort ergänzen; sonst neu anlegen mit `import Testing` + `@testable import Feedivo` + `struct CustomizableShortcutTests { ... }` nach dem etablierten Suite-Stil (siehe `FeedivoTests/ViewModels/ReaderTabsStateTests.swift` aus Task 1 als Vorbild).

```swift
    @Test func neueTabShortcutsGehoerenZurReaderKategorie() {
        #expect(CustomizableShortcut.readerNewTab.category == .reader)
        #expect(CustomizableShortcut.readerCloseTab.category == .reader)
        #expect(CustomizableShortcut.readerNextTab.category == .reader)
        #expect(CustomizableShortcut.readerPreviousTab.category == .reader)
    }

    @Test func neueTabShortcutsHabenErwarteteDefaults() {
        #expect(CustomizableShortcut.readerNewTab.defaultSpec == KeyboardShortcutSpec(key: "t", modifiers: [.command]))
        #expect(CustomizableShortcut.readerCloseTab.defaultSpec == KeyboardShortcutSpec(key: "w", modifiers: [.command]))
        #expect(CustomizableShortcut.readerNextTab.defaultSpec == KeyboardShortcutSpec(key: "]", modifiers: [.command, .shift]))
        #expect(CustomizableShortcut.readerPreviousTab.defaultSpec == KeyboardShortcutSpec(key: "[", modifiers: [.command, .shift]))
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CustomizableShortcutTests -parallel-testing-enabled NO`
Expected: FAIL (Compile-Fehler `Type 'CustomizableShortcut' has no member 'readerNewTab'`)

- [ ] **Step 3: Vier neue Enum-Fälle ergänzen**

In `Feedivo/Models/CustomizableShortcut.swift`, direkt nach `case readerWebForward` (Zeile 45):

```swift
    case readerWebForward
    case readerNewTab
    case readerCloseTab
    case readerNextTab
    case readerPreviousTab
```

Im `category`-Switch (Zeile 59-60):

```swift
        case .readerWebBack, .readerWebForward:
            .reader
```

ersetzen durch:

```swift
        case .readerWebBack, .readerWebForward, .readerNewTab, .readerCloseTab,
             .readerNextTab, .readerPreviousTab:
            .reader
```

Im `titleKey`-Switch (nach Zeile 93):

```swift
        case .readerWebForward: L10n.shortcutsLabelReaderWebForward
        case .readerNewTab: L10n.shortcutsLabelReaderNewTab
        case .readerCloseTab: L10n.shortcutsLabelReaderCloseTab
        case .readerNextTab: L10n.shortcutsLabelReaderNextTab
        case .readerPreviousTab: L10n.shortcutsLabelReaderPreviousTab
```

Im `defaultSpec`-Switch (nach Zeile 134):

```swift
        case .readerWebForward:
            KeyboardShortcutSpec(key: "]", modifiers: [.command])
        case .readerNewTab:
            KeyboardShortcutSpec(key: "t", modifiers: [.command])
        case .readerCloseTab:
            KeyboardShortcutSpec(key: "w", modifiers: [.command])
        case .readerNextTab:
            KeyboardShortcutSpec(key: "]", modifiers: [.command, .shift])
        case .readerPreviousTab:
            KeyboardShortcutSpec(key: "[", modifiers: [.command, .shift])
```

- [ ] **Step 4: L10n-Keys + Katalogeinträge ergänzen**

`Feedivo/Resources/L10n.swift`, neben `shortcutsLabelReaderWebForward`:

```swift
    static let shortcutsLabelReaderNewTab = LocalizedStringKey("shortcuts.label.readerNewTab")
    static let shortcutsLabelReaderCloseTab = LocalizedStringKey("shortcuts.label.readerCloseTab")
    static let shortcutsLabelReaderNextTab = LocalizedStringKey("shortcuts.label.readerNextTab")
    static let shortcutsLabelReaderPreviousTab = LocalizedStringKey("shortcuts.label.readerPreviousTab")
```

`Localizable.xcstrings`, vier analoge Einträge nach dem Muster aus Task 3/5/6 ergänzen (Keys: `shortcuts.label.readerNewTab` → "Neuer Tab"/"New Tab", `shortcuts.label.readerCloseTab` → "Tab schließen"/"Close Tab", `shortcuts.label.readerNextTab` → "Nächster Tab"/"Next Tab", `shortcuts.label.readerPreviousTab` → "Vorheriger Tab"/"Previous Tab"), danach `grep -c` je Key verifizieren.

- [ ] **Step 5: Run test to verify it passes**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CustomizableShortcutTests -parallel-testing-enabled NO`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Models/CustomizableShortcut.swift Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings FeedivoTests/Models/CustomizableShortcutTests.swift
git commit -m "feat: Vier neue Tastenkürzel-Fälle für Tab-Aktionen (Modell)"
```

---

## Task 8: Menübefehle verdrahten (⌘T / ⌘W / ⌘⇧] / ⌘⇧[)

**Files:**
- Modify: `Feedivo/App/ArticleCommandActions.swift`
- Modify: `Feedivo/App/ArticleCommands.swift`
- Modify: `Feedivo/Views/ContentView.swift`
- Modify: `Feedivo/ViewModels/ReaderTabsState.swift`
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `CustomizableShortcut.readerNewTab/.readerCloseTab/.readerNextTab/.readerPreviousTab` (Task 7), `ReaderTabsState` (Task 1), `markActiveReaderTabArticleReadIfNeeded()` (Task 5)
- Produces: `ArticleCommandActions.newReaderTab/.closeReaderTab/.activateNextReaderTab/.activatePreviousReaderTab: () -> Void`, `.canCloseReaderTab/.canActivateNextReaderTab/.canActivatePreviousReaderTab: Bool`

- [ ] **Step 1: `ReaderTabsState` um zwei Computed Properties ergänzen**

In `Feedivo/ViewModels/ReaderTabsState.swift`, direkt nach `activateNextTab()`/`activatePreviousTab()` ergänzen:

```swift
    var canActivateNextTab: Bool {
        guard let activeTabID, let index = tabs.firstIndex(where: { $0.id == activeTabID }) else { return false }
        return index + 1 < tabs.count
    }

    var canActivatePreviousTab: Bool {
        guard let activeTabID, let index = tabs.firstIndex(where: { $0.id == activeTabID }) else { return false }
        return index > 0
    }
```

- [ ] **Step 2: L10n-Keys ergänzen**

`Feedivo/Resources/L10n.swift`:

```swift
    static let readerTabCloseCommand = LocalizedStringKey("reader.tab.close")
    static let readerTabNextCommand = LocalizedStringKey("reader.tab.next")
    static let readerTabPreviousCommand = LocalizedStringKey("reader.tab.previous")
```

(`L10n.readerTabNewCommand` existiert bereits aus Task 5 und wird für den Menübefehl wiederverwendet.)

`Localizable.xcstrings`: drei analoge Einträge ergänzen (`reader.tab.close` → "Tab schließen"/"Close Tab", `reader.tab.next` → "Nächster Tab"/"Next Tab", `reader.tab.previous` → "Vorheriger Tab"/"Previous Tab"), danach `grep -c` je Key verifizieren.

- [ ] **Step 3: `ArticleCommandActions` erweitern**

In `Feedivo/App/ArticleCommandActions.swift`, dem `struct` direkt nach `let openInArticleWindow: () -> Void` (Zeile 22) ergänzen:

```swift
    let newReaderTab: () -> Void
    let closeReaderTab: () -> Void
    let activateNextReaderTab: () -> Void
    let activatePreviousReaderTab: () -> Void
    let canCloseReaderTab: Bool
    let canActivateNextReaderTab: Bool
    let canActivatePreviousReaderTab: Bool
```

In `static func ==` (Zeile 29-37) die drei neuen Bools ergänzen:

```swift
            && lhs.canSelectNextArticle == rhs.canSelectNextArticle
            && lhs.canCloseReaderTab == rhs.canCloseReaderTab
            && lhs.canActivateNextReaderTab == rhs.canActivateNextReaderTab
            && lhs.canActivatePreviousReaderTab == rhs.canActivatePreviousReaderTab
```

Im `init` (Zeile 39-75), direkt nach `openInArticleWindow: @escaping () -> Void = {},` (Zeile 51) ergänzen:

```swift
        newReaderTab: @escaping () -> Void = {},
        closeReaderTab: @escaping () -> Void = {},
        activateNextReaderTab: @escaping () -> Void = {},
        activatePreviousReaderTab: @escaping () -> Void = {},
        canCloseReaderTab: Bool = false,
        canActivateNextReaderTab: Bool = false,
        canActivatePreviousReaderTab: Bool = false,
```

und im `init`-Body direkt nach `self.openInArticleWindow = openInArticleWindow` (Zeile 69):

```swift
        self.newReaderTab = newReaderTab
        self.closeReaderTab = closeReaderTab
        self.activateNextReaderTab = activateNextReaderTab
        self.activatePreviousReaderTab = activatePreviousReaderTab
        self.canCloseReaderTab = canCloseReaderTab
        self.canActivateNextReaderTab = canActivateNextReaderTab
        self.canActivatePreviousReaderTab = canActivatePreviousReaderTab
```

- [ ] **Step 4: Vier neue Menübefehle in `ArticleCommands.swift`**

Direkt nach dem bestehenden Block (Zeile 57-62):

```swift
                Button(L10n.articleOpenInWindowCommand) {
                    articleCommandActions?.openInArticleWindow()
                }
                .customizableKeyboardShortcut(.articleOpenInWindow, overrides: shortcutOverrides)
                .disabled(articleCommandActions?.canPerformActions != true)
```

ergänzen:

```swift

                Divider()

                Button(L10n.readerTabNewCommand) {
                    articleCommandActions?.newReaderTab()
                }
                .customizableKeyboardShortcut(.readerNewTab, overrides: shortcutOverrides)
                .disabled(articleCommandActions?.canPerformActions != true)

                Button(L10n.readerTabCloseCommand) {
                    articleCommandActions?.closeReaderTab()
                }
                .customizableKeyboardShortcut(.readerCloseTab, overrides: shortcutOverrides)
                .disabled(articleCommandActions?.canCloseReaderTab != true)

                Button(L10n.readerTabNextCommand) {
                    articleCommandActions?.activateNextReaderTab()
                }
                .customizableKeyboardShortcut(.readerNextTab, overrides: shortcutOverrides)
                .disabled(articleCommandActions?.canActivateNextReaderTab != true)

                Button(L10n.readerTabPreviousCommand) {
                    articleCommandActions?.activatePreviousReaderTab()
                }
                .customizableKeyboardShortcut(.readerPreviousTab, overrides: shortcutOverrides)
                .disabled(articleCommandActions?.canActivatePreviousReaderTab != true)
```

`newReaderTab` wird bewusst über dasselbe `canPerformActions`-Gate wie `openInArticleWindow` deaktiviert (kein eigenes Gate nötig — beide bedeuten "es ist gerade ein Artikel im Reader/in der Liste relevant").

- [ ] **Step 5: In `ContentView.swift` verdrahten**

`grep -n "ArticleCommandActions(" Feedivo/Views/ContentView.swift` liefert die Konstruktionsstelle (um Zeile 853). Dort, direkt nach `openInArticleWindow: { ... },` (analoger bestehender Parameter), ergänzen:

```swift
                newReaderTab: {
                    if !readerTabsState.duplicateActiveTab(), let selectedSQLiteArticleID {
                        readerTabsState.openInActiveTab(articleID: selectedSQLiteArticleID)
                    }
                },
                closeReaderTab: {
                    guard let activeTabID = readerTabsState.activeTabID else { return }
                    readerTabsState.closeTab(id: activeTabID)
                },
                activateNextReaderTab: {
                    readerTabsState.activateNextTab()
                    markActiveReaderTabArticleReadIfNeeded()
                },
                activatePreviousReaderTab: {
                    readerTabsState.activatePreviousTab()
                    markActiveReaderTabArticleReadIfNeeded()
                },
                canCloseReaderTab: readerTabsState.activeTabID != nil,
                canActivateNextReaderTab: readerTabsState.canActivateNextTab,
                canActivatePreviousReaderTab: readerTabsState.canActivatePreviousTab,
```

`newReaderTab` implementiert damit exakt die ⌘T-Fallback-Regel aus der Design-Spec: ist ein Tab aktiv, wird er dupliziert; ist keiner aktiv, aber ein Artikel in der Liste ausgewählt, wird dieser als erster Tab geöffnet.

- [ ] **Step 6: Build verifizieren**

Run: `xcodebuild build -scheme Feedivo -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Commit**

```bash
git add Feedivo/App/ArticleCommandActions.swift Feedivo/App/ArticleCommands.swift Feedivo/Views/ContentView.swift Feedivo/ViewModels/ReaderTabsState.swift Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings
git commit -m "feat: Menübefehle für Tab-Aktionen (Neu/Schließen/Wechseln) verdrahten"
```

---

## Task 9: Regressionslauf, Release-Build, Live-Verifikationscheckliste

**Files:**
- Keine Code-Änderungen — reine Verifikation.

- [ ] **Step 1: Gezielten Testlauf über alle neuen/berührten Suiten ausführen**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' \
  -only-testing:FeedivoTests/ReaderTabsStateTests \
  -only-testing:FeedivoTests/CustomizableShortcutTests \
  -parallel-testing-enabled NO
```

Expected: alle Tests grün.

- [ ] **Step 2: Bestehende, potenziell berührte Suiten gezielt mitlaufen lassen**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' \
  -only-testing:FeedivoTests/SQLiteFeedArticleListStateTests \
  -only-testing:FeedivoTests/ArticleStatusStoreTests \
  -parallel-testing-enabled NO
```

Expected: grün, mit Ausnahme des bekannten, vorbestehenden Flaky-Tests `listStateToggeltReadUndAktualisiertRows` (siehe Global Constraints) — kein NEUER Fehlschlag.

- [ ] **Step 3: Release-Build**

```bash
xcodebuild build -scheme Feedivo -configuration Release -destination 'platform=macOS'
```

Expected: BUILD SUCCEEDED

- [ ] **Step 4: `git diff --stat` auf `Localizable.xcstrings` prüfen**

```bash
git diff --stat -- Feedivo/Resources/Localizable.xcstrings
```

Expected: NUR Insertions über alle Commits dieses Plans hinweg (keine/kaum Deletions) — sonst wurde versehentlich doch ein `json.dump`-artiger Roundtrip statt einer chirurgischen Text-Einfügung verwendet (siehe Global Constraints).

- [ ] **Step 5: Manuelle Live-Verifikationscheckliste dokumentieren**

Kein computer-use für native macOS-Apps in dieser Umgebung verfügbar (siehe CLAUDE.md-Konvention) — folgende Punkte müssen vom Nutzer selbst durchgeklickt werden, bevor das Feature als vollständig verifiziert gilt:

1. Artikel anklicken → erscheint im Reader, noch keine Tab-Leiste sichtbar (nur 1 "impliziter" Tab).
2. ⌘-Klick auf einen zweiten Artikel → Tab-Leiste erscheint mit 2 Tabs, Reader zeigt weiterhin den ZUERST geklickten Artikel (Hintergrund-Tab-Verhalten).
3. Kontextmenü „In neuem Tab öffnen" auf einem dritten Artikel → dritter Tab erscheint, Reader-Inhalt bleibt unverändert.
4. Auf einen Hintergrund-Tab klicken → Reader wechselt, Artikel wird als gelesen markiert (Punkt/Fettdruck in der Liste verschwindet, falls der Artikel dort sichtbar ist).
5. ⌘T → aktiver Tab wird dupliziert (neuer Tab mit identischem Artikel, im Hintergrund).
6. ⌘W → aktiver Tab schließt, Reader zeigt den Tab an der freigewordenen Position.
7. ⌘⇧] / ⌘⇧[ → Tab-Wechsel vor/zurück, kein Wraparound an den Rändern (Menübefehl dort deaktiviert).
8. Alle Tabs schließen → Tab-Leiste verschwindet, Reader zeigt den „kein Artikel ausgewählt"-Leerzustand.
9. Rechts-/Links-Pfeil (Reader-Ansichtswechsel nativ/Web) und Eingabetaste (Original öffnen) nach einem Tab-Wechsel testen — müssen weiterhin auf den AKTIVEN Tab wirken, nicht auf die (evtl. abweichende) Listenauswahl.
10. Pfeil-Hoch/-Runter in der Artikelliste bei offenen Tabs → navigiert wie gewohnt, aktualisiert dabei den aktiven Tab (kein neuer Tab).
11. Sidebar-Feed wechseln, während Tabs offen sind → Tabs bleiben unverändert bestehen, nur die Artikelliste wechselt.
12. Artikel eines offenen Tabs per Bereinigung/manuellem Löschen entfernen → Tab bleibt mit „Artikel nicht mehr verfügbar" sichtbar, lässt sich normal schließen.
13. Einstellungen → Artikelliste → „Offene Tabs beim Neustart wiederherstellen" aktivieren, App neu starten → Tabs (inkl. aktivem Tab) sind wieder da. Schalter deaktivieren, neu starten → keine Tabs mehr offen.
14. Bestehendes Popout-Fenster („In neuem Fenster öffnen") weiterhin unverändert testen — muss neben den Tabs unabhängig funktionieren.

Kein Commit in diesem Task (reine Verifikation).
