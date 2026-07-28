# Automatischer Feed-Sprung Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pfeil-Runter am Ende der ungelesenen Artikel eines ausgewählten Feeds springt
automatisch zum nächsten Feed mit ungelesenen Artikeln (Sidebar-Reihenfolge) und wählt dort
den ersten ungelesenen Artikel; Pfeil-Hoch symmetrisch rückwärts.

**Architecture:** Reine, isoliert testbare Nachschlage-Logik (`SidebarFeedOrder`) liefert die
Feeds in sichtbarer Sidebar-Reihenfolge und findet darin den nächsten/vorherigen Feed mit
`unreadCount > 0`. `ContentView.swift` lädt zusätzlich die Ordnerliste, verdrahtet zwei neue
`.onKeyPress`-Handler an derselben Stelle wie die bestehende Rechts-/Links-/Eingabetaste-
Navigation, und löst ein bestehendes Race zwischen Sidebar-Auswahlwechsel und
Artikel-Auswahl über einen "pending"-State-Wert.

**Tech Stack:** SwiftUI (macOS 14+, `.onKeyPress` API), GRDB (`FeedFolderStore`,
`ArticleDatabase`), Swift Testing für die reine Logik.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-17-naechster-feed-mit-ungelesenen-design.md` — bei
  Widersprüchen zwischen Plan und Spec gilt die Spec.
- Kommentare im Code auf Deutsch (Projektkonvention).
- `xcodebuild build` muss nach jedem Task grün sein: `xcodebuild build -project Feedivo.xcodeproj
  -scheme Feedivo -destination 'platform=macOS'`.
- Tests laufen gezielt: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo
  -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoTests
  -parallel-testing-enabled NO`.
- Gilt NUR bei Einzel-Feed-Auswahl (`sidebarSelection == .feed(...)`) — kein Feed-Sprung bei
  Smart Foldern/Tags.
- Kein Wraparound am Ende/Anfang aller Feeds — kein weiterer/vorheriger Feed mit
  ungelesenen Artikeln bedeutet: Taste tut nichts.
- Keine Anpassbarkeit über die Shortcuts-Einstellungen — fest eingebaut, analog zur
  bestehenden Pfeiltasten-Navigation (Rechts/Links/Eingabetaste).
- Bekanntes technisches Risiko (aus der Spec): natives `List`-Verhalten konsumiert
  Pfeil-Hoch/-Runter unter Umständen auch am Rand der Liste, bevor ein
  `.onKeyPress`-Handler an einer Vorfahren-View das Ereignis überhaupt sieht. Der in diesem
  Plan gebaute Ansatz ist der in der Spec dokumentierte Primäransatz; ob er live tatsächlich
  funktioniert, ist NICHT Teil dieses Plans zu verifizieren (steht in der manuellen
  Live-Checkliste am Ende von Task 2) — falls er scheitert, ist der in der Spec beschriebene
  `NSEvent`-Monitor-Fallback ein separater Folge-Task, kein Teil dieses Plans.

---

## Task 1: Reine Feed-Reihenfolge- und Nachschlage-Logik (`SidebarFeedOrder`)

**Files:**
- Create: `Feedivo/Views/Sidebar/SidebarFeedOrder.swift`
- Test: `FeedivoTests/FeedivoTests.swift` (direkt vor der schließenden `}` der
  `FeedivoTests`-Struct)

**Interfaces:**
- Produces: `enum SidebarFeedOrder` mit
  `static func orderedFeeds(from snapshots: [FeedSidebarSnapshot], folders: [FeedFolderRecord]) -> [FeedSidebarSnapshot]`,
  `static func nextFeedWithUnread(after feedID: String, in orderedFeeds: [FeedSidebarSnapshot]) -> FeedSidebarSnapshot?`,
  `static func previousFeedWithUnread(before feedID: String, in orderedFeeds: [FeedSidebarSnapshot]) -> FeedSidebarSnapshot?`.
- Consumes: bereits bestehende `FeedFolderOrganizer.feedsWithoutFolder(from:)` und
  `.feedsByFolderName(in:folders:)` (`Feedivo/Views/Sidebar/FeedFolderOrganizer.swift`),
  `FeedSidebarSnapshot` (`Feedivo/Snapshots/FeedSidebarSnapshot.swift`: `id: String`,
  `title: String`, `url: String`, `faviconURL: String?`, `folderName: String?`,
  `sortIndex: Int = 0`, `unreadCount: Int`, `hasRecentError: Bool`), `FeedFolderRecord`
  (`Feedivo/Database/Records/FeedFolderRecord.swift`: `init(id: String = UUID().uuidString,
  name: String, sortIndex: Int = 0, createdAt: Date = Date(), updatedAt: Date = Date())`).

- [ ] **Step 1: Failing Test schreiben**

In `FeedivoTests/FeedivoTests.swift`, direkt vor der schließenden `}` der `FeedivoTests`-Struct
einfügen:

```swift

    @Test func sidebarFeedOrderOrdnetUnfolderteFeedsVorOrdnernEin() {
        let unfoldered = FeedSidebarSnapshot(
            id: "u1", title: "Unfoldered", url: "https://u1", faviconURL: nil,
            folderName: nil, sortIndex: 0, unreadCount: 0, hasRecentError: false
        )
        let foldered = FeedSidebarSnapshot(
            id: "f1", title: "Foldered", url: "https://f1", faviconURL: nil,
            folderName: "Ordner A", sortIndex: 0, unreadCount: 0, hasRecentError: false
        )
        let folders = [FeedFolderRecord(name: "Ordner A", sortIndex: 0)]

        let ordered = SidebarFeedOrder.orderedFeeds(from: [foldered, unfoldered], folders: folders)

        #expect(ordered.map(\.id) == ["u1", "f1"])
    }

    @Test func sidebarFeedOrderRespektiertOrdnerReihenfolge() {
        let feedInB = FeedSidebarSnapshot(
            id: "b1", title: "In B", url: "https://b1", faviconURL: nil,
            folderName: "Ordner B", sortIndex: 0, unreadCount: 0, hasRecentError: false
        )
        let feedInA = FeedSidebarSnapshot(
            id: "a1", title: "In A", url: "https://a1", faviconURL: nil,
            folderName: "Ordner A", sortIndex: 0, unreadCount: 0, hasRecentError: false
        )
        let folders = [
            FeedFolderRecord(name: "Ordner B", sortIndex: 0),
            FeedFolderRecord(name: "Ordner A", sortIndex: 1)
        ]

        let ordered = SidebarFeedOrder.orderedFeeds(from: [feedInA, feedInB], folders: folders)

        #expect(ordered.map(\.id) == ["b1", "a1"])
    }

    @Test func sidebarFeedOrderNextFeedWithUnreadUeberspringtFeedsOhneUngelesene() {
        let feeds = [
            FeedSidebarSnapshot(id: "1", title: "A", url: "https://1", faviconURL: nil, folderName: nil, sortIndex: 0, unreadCount: 0, hasRecentError: false),
            FeedSidebarSnapshot(id: "2", title: "B", url: "https://2", faviconURL: nil, folderName: nil, sortIndex: 1, unreadCount: 0, hasRecentError: false),
            FeedSidebarSnapshot(id: "3", title: "C", url: "https://3", faviconURL: nil, folderName: nil, sortIndex: 2, unreadCount: 5, hasRecentError: false)
        ]

        let next = SidebarFeedOrder.nextFeedWithUnread(after: "1", in: feeds)

        #expect(next?.id == "3")
    }

    @Test func sidebarFeedOrderNextFeedWithUnreadLiefertNilAmEnde() {
        let feeds = [
            FeedSidebarSnapshot(id: "1", title: "A", url: "https://1", faviconURL: nil, folderName: nil, sortIndex: 0, unreadCount: 3, hasRecentError: false)
        ]

        let next = SidebarFeedOrder.nextFeedWithUnread(after: "1", in: feeds)

        #expect(next == nil)
    }

    @Test func sidebarFeedOrderPreviousFeedWithUnreadUeberspringtFeedsOhneUngelesene() {
        let feeds = [
            FeedSidebarSnapshot(id: "1", title: "A", url: "https://1", faviconURL: nil, folderName: nil, sortIndex: 0, unreadCount: 5, hasRecentError: false),
            FeedSidebarSnapshot(id: "2", title: "B", url: "https://2", faviconURL: nil, folderName: nil, sortIndex: 1, unreadCount: 0, hasRecentError: false),
            FeedSidebarSnapshot(id: "3", title: "C", url: "https://3", faviconURL: nil, folderName: nil, sortIndex: 2, unreadCount: 0, hasRecentError: false)
        ]

        let previous = SidebarFeedOrder.previousFeedWithUnread(before: "3", in: feeds)

        #expect(previous?.id == "1")
    }

    @Test func sidebarFeedOrderPreviousFeedWithUnreadLiefertNilAmAnfang() {
        let feeds = [
            FeedSidebarSnapshot(id: "1", title: "A", url: "https://1", faviconURL: nil, folderName: nil, sortIndex: 0, unreadCount: 3, hasRecentError: false)
        ]

        let previous = SidebarFeedOrder.previousFeedWithUnread(before: "1", in: feeds)

        #expect(previous == nil)
    }
```

- [ ] **Step 2: Test ausführen, Fehlschlag verifizieren**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoTests/sidebarFeedOrderOrdnetUnfolderteFeedsVorOrdnernEin -parallel-testing-enabled NO`
Expected: FAIL — Compile-Fehler, `SidebarFeedOrder` existiert noch nicht.

- [ ] **Step 3: `SidebarFeedOrder.swift` anlegen**

Neue Datei `Feedivo/Views/Sidebar/SidebarFeedOrder.swift`:

```swift
import Foundation

/// Reine Nachschlage-Logik für den automatischen Feed-Sprung am Ende/Anfang
/// der Artikelliste: liefert die exakt sichtbare Sidebar-Reihenfolge aller
/// Feeds (nicht-einsortierte Feeds zuerst, dann Ordner der Reihe nach) und
/// findet darin den nächsten/vorherigen Feed mit ungelesenen Artikeln. Nutzt
/// dieselben Bausteine (`FeedFolderOrganizer`), die auch die eigentliche
/// Sidebar-Baumstruktur (`SidebarOutlineNode.buildTree`) verwendet — keine
/// AppKit-/NSOutlineView-Abhängigkeit.
enum SidebarFeedOrder {
    static func orderedFeeds(
        from snapshots: [FeedSidebarSnapshot],
        folders: [FeedFolderRecord]
    ) -> [FeedSidebarSnapshot] {
        let unfoldered = FeedFolderOrganizer.feedsWithoutFolder(from: snapshots)
        let foldered = FeedFolderOrganizer.feedsByFolderName(in: snapshots, folders: folders)
            .flatMap(\.snapshots)
        return unfoldered + foldered
    }

    static func nextFeedWithUnread(
        after feedID: String,
        in orderedFeeds: [FeedSidebarSnapshot]
    ) -> FeedSidebarSnapshot? {
        guard let currentIndex = orderedFeeds.firstIndex(where: { $0.id == feedID }) else {
            return nil
        }

        return orderedFeeds[orderedFeeds.index(after: currentIndex)...].first { $0.unreadCount > 0 }
    }

    static func previousFeedWithUnread(
        before feedID: String,
        in orderedFeeds: [FeedSidebarSnapshot]
    ) -> FeedSidebarSnapshot? {
        guard let currentIndex = orderedFeeds.firstIndex(where: { $0.id == feedID }) else {
            return nil
        }

        return orderedFeeds[..<currentIndex].reversed().first { $0.unreadCount > 0 }
    }
}
```

- [ ] **Step 4: Test ausführen, Erfolg verifizieren**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoTests/sidebarFeedOrderOrdnetUnfolderteFeedsVorOrdnernEin -parallel-testing-enabled NO`
Expected: PASS

- [ ] **Step 5: Verbleibende neue Tests + Regressionscheck**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoTests -parallel-testing-enabled NO`
Expected: PASS (alle Tests der Datei, inkl. der 6 neuen)

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Views/Sidebar/SidebarFeedOrder.swift FeedivoTests/FeedivoTests.swift
git commit -m "Feature: Reine Feed-Reihenfolge- und Ungelesen-Nachschlage-Logik (SidebarFeedOrder)"
```

---

## Task 2: Verdrahtung in `ContentView.swift`

**Files:**
- Modify: `Feedivo/Views/ContentView.swift`

**Interfaces:**
- Consumes: `SidebarFeedOrder.orderedFeeds(from:folders:)` / `.nextFeedWithUnread(after:in:)` /
  `.previousFeedWithUnread(before:in:)` aus Task 1; bestehende `FeedFolderStore(database:).folders()
  throws -> [FeedFolderRecord]` (`Feedivo/Stores/FeedFolderStore.swift`); bestehende
  `ArticleDatabase(database:).fetchUnreadArticles(feedIDs: Set<String>, includeHidden: Bool = false,
  limit: Int = 500) throws -> [ArticleListSnapshot]` (`Feedivo/Stores/ArticleDatabase.swift:148-159`,
  `ArticleListSnapshot.id: String`); bestehende `sqliteArticleNavigationState:
  SQLiteArticleNavigationState` (`.previousArticleID`/`.nextArticleID: String?`); bestehende
  `selectedFeedID: String?` Computed Property (`ContentView.swift:663-669`).
- Produces: sichtbares Endverhalten, keine neuen öffentlichen Interfaces für spätere Tasks
  (letzter Task des Plans).

**Wichtiger technischer Hinweis (nicht in der Spec explizit ausformuliert, aber zwingend
für korrekte Funktion):** `handleSidebarSelectionChange()` (`ContentView.swift:414-418`) setzt
`selectedSQLiteArticleID` bei JEDER Änderung von `sidebarSelection` bedingungslos auf `nil`
zurück. Würde der Feed-Sprung `sidebarSelection` und `selectedSQLiteArticleID` direkt
nacheinander setzen, würde der durch die `sidebarSelection`-Änderung ausgelöste
`.onChange`-Handler die gerade gesetzte Artikel-Auswahl wieder überschreiben — dasselbe
Race-Muster, das dieses Projekt bereits einmal bei `AddFeedSheet` gefunden und behoben hat
(siehe Kommentar bei `ContentView.swift:44-53`: „zwei getrennte @State-Properties... Race").
Dieser Plan verhindert das über einen neuen `pendingArticleIDAfterFeedJump`-State-Wert, den
`handleSidebarSelectionChange()` selbst konsumiert, statt blind zu überschreiben (Step 3
unten) — deterministisch, ohne Reihenfolge-Annahmen über SwiftUIs Update-Zyklus.

**Hinweis:** Reine SwiftUI-`.onKeyPress`-Verdrahtung ist im Projekt nicht isoliert
unit-testbar (kein ViewInspector) — Verifikation über Build + die in Step 9 dokumentierte
manuelle Live-Checkliste.

- [ ] **Step 1: Neue `@State`-Properties ergänzen**

In `Feedivo/Views/ContentView.swift`, direkt nach der bestehenden Zeile
`@State private var feedSnapshots: [FeedSidebarSnapshot] = []` (Zeile 23) einfügen:

```swift
    @State private var feedFolders: [FeedFolderRecord] = []
```

Direkt nach der bestehenden Zeile
`@State private var sqliteArticleNavigationState = SQLiteArticleNavigationState.empty`
(Zeile 41) einfügen:

```swift
    // Feature "Automatischer Feed-Sprung": handleSidebarSelectionChange()
    // konsumiert diesen Wert, statt selectedSQLiteArticleID beim Feed-Wechsel
    // bedingungslos zu nullen — vermeidet ein Race zwischen dem Setzen von
    // sidebarSelection und selectedSQLiteArticleID (analog zum bereits
    // dokumentierten AddFeedSheet-Race weiter oben in dieser Datei).
    @State private var pendingArticleIDAfterFeedJump: String?
```

- [ ] **Step 2: `reloadFeedSnapshots()` um Ordner-Ladung erweitern**

In `Feedivo/Views/ContentView.swift`, den bestehenden `reloadFeedSnapshots()`-Funktionskörper
(Zeilen 449-463) ersetzen durch:

```swift
    @MainActor
    private func reloadFeedSnapshots() async {
        guard let database = feedivoDatabase else {
            feedSnapshots = []
            feedFolders = []
            return
        }
        feedSnapshots = (try? FeedStore(database: database).sidebarFeeds()) ?? []
        feedFolders = (try? FeedFolderStore(database: database).folders()) ?? []
        if !feedSnapshots.isEmpty {
            FirstRunWizardState.markHadFeeds(&hasHadFeedsForFirstRunWizard)
        }
    }
```

- [ ] **Step 3: `handleSidebarSelectionChange()` anpassen**

In `Feedivo/Views/ContentView.swift`, die bestehende Funktion (Zeilen 414-418) ersetzen durch:

```swift
    private func handleSidebarSelectionChange() {
        selectedSQLiteArticleID = pendingArticleIDAfterFeedJump
        pendingArticleIDAfterFeedJump = nil
        selectedSQLiteArticleSnapshot = nil
        sqliteArticleNavigationState = .empty
    }
```

- [ ] **Step 4: Neue private Funktionen für den Feed-Sprung ergänzen**

In `Feedivo/Views/ContentView.swift`, direkt nach der bestehenden Funktion `selectNextArticle()`
(endet nach Zeile 661) einfügen:

```swift

    /// Feed-Sprung am Ende der Artikelliste (Feature: automatischer Wechsel
    /// zum nächsten Feed mit ungelesenen Artikeln). Setzt bewusst
    /// pendingArticleIDAfterFeedJump statt direkt selectedSQLiteArticleID —
    /// siehe Kommentar bei handleSidebarSelectionChange().
    private func selectNextFeedWithUnread() {
        guard let feedID = selectedFeedID, let database = feedivoDatabase else {
            return
        }

        let orderedFeeds = SidebarFeedOrder.orderedFeeds(from: feedSnapshots, folders: feedFolders)
        guard let targetFeed = SidebarFeedOrder.nextFeedWithUnread(after: feedID, in: orderedFeeds) else {
            return
        }

        let unreadArticles = (try? ArticleDatabase(database: database).fetchUnreadArticles(feedIDs: [targetFeed.id])) ?? []
        guard let firstUnreadArticleID = unreadArticles.first?.id else {
            return
        }

        pendingArticleIDAfterFeedJump = firstUnreadArticleID
        sidebarSelection = .feed(targetFeed.id)
    }

    private func selectPreviousFeedWithUnread() {
        guard let feedID = selectedFeedID, let database = feedivoDatabase else {
            return
        }

        let orderedFeeds = SidebarFeedOrder.orderedFeeds(from: feedSnapshots, folders: feedFolders)
        guard let targetFeed = SidebarFeedOrder.previousFeedWithUnread(before: feedID, in: orderedFeeds) else {
            return
        }

        let unreadArticles = (try? ArticleDatabase(database: database).fetchUnreadArticles(feedIDs: [targetFeed.id])) ?? []
        guard let lastUnreadArticleID = unreadArticles.last?.id else {
            return
        }

        pendingArticleIDAfterFeedJump = lastUnreadArticleID
        sidebarSelection = .feed(targetFeed.id)
    }
```

- [ ] **Step 5: Neue `.onKeyPress`-Handler ergänzen**

In `Feedivo/Views/ContentView.swift`, direkt nach dem bestehenden `.onKeyPress(.return) { ... }`-
Block (endet mit `}` vor `.onAppear(perform: handleContentAppear)`) einfügen:

```swift
        // Automatischer Feed-Sprung: Pfeil-Runter am Ende der ungelesenen
        // Artikel eines Feeds springt zum nächsten Feed mit ungelesenen
        // Artikeln (Sidebar-Reihenfolge), Pfeil-Hoch symmetrisch rückwärts.
        // Nur bei Einzel-Feed-Auswahl relevant (selectedFeedID != nil) — bei
        // Smart Foldern/Tags gibt es kein "nächster Feed"-Konzept. Zusätzliche
        // Bedingung selectedSQLiteArticleID != nil verhindert einen Sprung,
        // wenn noch gar kein Artikel ausgewählt wurde (dort ist
        // nextArticleID/previousArticleID ebenfalls nil, aber aus einem
        // anderen Grund).
        .onKeyPress(.downArrow) {
            guard selectedFeedID != nil,
                  selectedSQLiteArticleID != nil,
                  sqliteArticleNavigationState.nextArticleID == nil
            else {
                return .ignored
            }

            selectNextFeedWithUnread()
            return .handled
        }
        .onKeyPress(.upArrow) {
            guard selectedFeedID != nil,
                  selectedSQLiteArticleID != nil,
                  sqliteArticleNavigationState.previousArticleID == nil
            else {
                return .ignored
            }

            selectPreviousFeedWithUnread()
            return .handled
        }
```

- [ ] **Step 6: Build ausführen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Regressionscheck der gesamten Testsuite**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoTests -parallel-testing-enabled NO`
Expected: PASS (unverändert gegenüber Task 1, da Task 2 keine testbare Logik hinzufügt —
reine UI-Verdrahtung)

- [ ] **Step 8: Commit**

```bash
git add Feedivo/Views/ContentView.swift
git commit -m "Feature: Automatischer Feed-Sprung zum naechsten Feed mit ungelesenen Artikeln"
```

- [ ] **Step 9: Manuelle Live-Verifikationscheckliste dokumentieren (nicht automatisierbar)**

Kein computer-use-Zugriff auf native macOS-Apps in dieser Umgebung verfügbar. Folgende Punkte
bleiben für den Nutzer als manuelle Checkliste offen und sollten in `CLAUDE.md` unter
„Aktuell in Arbeit" als ausstehend vermerkt werden, sobald dieser Plan abgeschlossen ist:

1. Feed mit genau einem ungelesenen Artikel auswählen, diesen lesen, dann nochmal
   Pfeil-Runter drücken — springt zum nächsten Feed mit ungelesenen Artikeln in
   Sidebar-Reihenfolge, Sidebar-Auswahl wechselt sichtbar, erster ungelesener Artikel dort ist
   ausgewählt.
2. **Entscheidender Test für das dokumentierte technische Risiko:** Falls Schritt 1 NICHT
   funktioniert (Pfeiltaste bleibt wirkungslos, kein Feed-Sprung), ist das der Auslöser für
   den in der Spec beschriebenen `NSEvent`-Monitor-Fallback (eigener Folge-Task, nicht Teil
   dieses Plans) — nicht stillschweigend als „geht halt nicht" hinnehmen.
3. Symmetrisch mit Pfeil-Hoch am Anfang der Liste — springt zum vorherigen Feed mit
   ungelesenen Artikeln, letzter ungelesener Artikel dort ausgewählt.
4. Feed mit mehreren ungelesenen Artikeln: normales Durchnavigieren mit Pfeil-Runter
   innerhalb des Feeds bleibt unverändert (kein vorzeitiger Sprung).
5. Letzter Feed mit ungelesenen Artikeln in der Sidebar-Reihenfolge: Pfeil-Runter am Ende
   tut nichts (kein Wraparound).
6. Feed-Sprung funktioniert unabhängig davon, ob der Ziel-Feed einsortiert oder in einem
   Ordner liegt, und respektiert die Ordner-Reihenfolge (nicht nur alphabetisch).
7. Smart Folder/Tag-Auswahl: Pfeil-Runter am Ende bleibt unverändert wirkungslos (kein
   Feed-Sprung außerhalb von Einzel-Feed-Auswahl).

---

## Self-Review-Notiz für den Plan-Autor (nicht Teil der Ausführung)

- Spec-Abdeckung: Alle Entscheidungen der Spec (nur Einzel-Feed-Auswahl, Auto-Auswahl des
  ersten/letzten ungelesenen Artikels, sichtbare Sidebar-Reihenfolge inkl. Ordner, kein
  Wraparound, Pfeil-Hoch-Symmetrie) sind auf Tasks 1-2 abgebildet. Das in der Spec
  dokumentierte technische Risiko ist als Global Constraint übernommen und in der
  Live-Checkliste priorisiert, der Fallback bewusst als Folge-Task ausgeklammert (nicht Teil
  dieses Plans, da erst nach Live-Test-Befund zu entscheiden).
- Platzhalter-Scan: keine TBD/TODO-Stellen; jeder Code-Block ist vollständig ausgeschrieben.
- Typkonsistenz geprüft: `SidebarFeedOrder`-Funktionssignaturen (Task 1) werden in Task 2
  identisch aufgerufen; `pendingArticleIDAfterFeedJump` wird in Task 2 Step 1 deklariert,
  in Step 3 (`handleSidebarSelectionChange`) konsumiert und in Step 4 (beide neuen
  Sprung-Funktionen) gesetzt — konsistent durchgängig verwendet, kein verwaister Name.
- Race-Bedingung explizit dokumentiert und mit einer deterministischen Lösung (statt einer
  Zeitablauf-Annahme wie `DispatchQueue.main.async`) versehen — vermeidet einen bereits im
  Projekt einmal aufgetretenen Bug-Typ (AddFeedSheet-Race).
