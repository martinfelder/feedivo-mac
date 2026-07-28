# Bulk-Aktionen-/Sidebar-Fehleranzeige — Implementierungsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Drei unabhängige Stellen, an denen ein Fehler zwar korrekt erkannt,
aber nie sichtbar gemacht wird, beheben: "Alle als gelesen markieren"
(Finding 1.3), "Alle Feeds aktualisieren" (Finding 1.4) und der
Sidebar-Ladefehler (Finding 1.6).

**Architecture:** Alle drei Fixes folgen demselben, bereits im Projekt
etablierten Muster: ein vorhandenes `errorMessage`/`loadState`-Feld wird bei
einem Fehler korrekt gesetzt, aber (a) im `catch`-Block gar nicht erst
gesetzt (1.3, 1.4) oder (b) gesetzt, aber von keiner View gelesen (1.6).
Fix jeweils minimal: den `catch`-Block auf das bereits existierende
Zustandsfeld umstellen bzw. das Feld an eine sichtbare `Text`-Anzeige binden
— keine neuen Abstraktionen, keine UI-Neuentwürfe.

**Tech Stack:** SwiftUI, GRDB (SQLite), Swift Testing (`@testable import
Feedivo`).

## Global Constraints

- Arbeitsweise für diese Gruppe: Commits direkt auf `main` (Nutzerentscheid
  für diese Gruppe, keine generelle Regel).
- Kommentare im Code auf Deutsch (Projektkonvention laut CLAUDE.md).
- Kein `reload()`/erneuter State-Load im `catch`-Zweig, wenn dadurch der
  gerade gesetzte Fehlerzustand sofort wieder überschrieben würde (siehe
  bereits etabliertes Muster aus Gruppe 1,
  `SQLiteFeedArticleListState.deleteArticle`).
- SwiftUI-View-Structs sind in diesem Projekt nicht direkt unit-testbar
  (private Methoden ohne Test-Harness) — wo eine Task reine View-Verdrahtung
  betrifft, ist die Verifikation ein echter `xcodebuild build`-Lauf statt
  eines neuen Unit-Tests (SourceKit-Diagnosen in der IDE sind laut
  CLAUDE.md-Gotcha unzuverlässig). Wo die Logik in einer testbaren
  `@Observable`/ViewModel-Klasse liegt (Task 2), gilt normales TDD.
- Volle Testsuite hängt (CLAUDE.md-Gotcha) — immer gezielt mit
  `-only-testing:FeedivoTests/<SuiteName>` testen.

---

### Task 1: "Alle als gelesen markieren" surfaced Fehler (Finding 1.3)

**Files:**
- Modify: `Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift:691-708` (`markRowsRead`)

**Interfaces:**
- Consumes: `state.loadState: SQLiteFeedArticleListState.LoadState` (bereits
  `var`, nicht `private(set)` — wird im selben File schon direkt aus
  `requestExportArticle`s `catch`-Block gesetzt, kein neues API nötig).

**Vorher:**
```swift
private func markRowsRead(_ option: ArticleMarkReadOption) {
    guard let database else {
        return
    }

    do {
        _ = try TimelineStore(database: database).markRead(
            scope: scope.timelineScope,
            searchText: debouncedSearchText,
            includeHidden: scope.includeHidden,
            option: option
        )
        SQLiteDataInvalidation.bumpStatusVersion()
        reload()
    } catch {
        reload()
    }
}
```

- [ ] **Step 1: `catch`-Block auf sichtbaren Fehlerzustand umstellen**

In `Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift`, die Funktion
`markRowsRead(_:)` (aktuell Zeilen 691-708) ändern zu:

```swift
    private func markRowsRead(_ option: ArticleMarkReadOption) {
        guard let database else {
            return
        }

        do {
            _ = try TimelineStore(database: database).markRead(
                scope: scope.timelineScope,
                searchText: debouncedSearchText,
                includeHidden: scope.includeHidden,
                option: option
            )
            SQLiteDataInvalidation.bumpStatusVersion()
            reload()
        } catch {
            // Kein reload() hier: das wuerde ueber state.load(...) den
            // gerade gesetzten .failed-Zustand sofort wieder auf .idle/
            // .loaded ueberschreiben (siehe SQLiteFeedArticleListState.
            // deleteArticle fuer denselben, bereits etablierten Grund).
            state.loadState = .failed(error.localizedDescription)
        }
    }
```

- [ ] **Step 2: Build verifizieren**

Run: `xcodebuild build -scheme Feedivo -destination 'platform=macOS'`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Zielgerichteten Regressionstest laufen lassen**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedArticleListStateTests -parallel-testing-enabled NO`
Expected: Alle Tests weiterhin grün (keine Regression im State-Layer, da
diese Task nur den `catch`-Zweig einer View-Methode ändert).

- [ ] **Step 4: Commit**

```bash
git add Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift
git commit -m "Fix: 'Alle als gelesen markieren' zeigt Fehler sichtbar an statt stumm zu scheitern"
```

---

### Task 2: "Alle Feeds aktualisieren" surfaced Fehler (Finding 1.4)

**Files:**
- Modify: `Feedivo/ViewModels/FeedViewModel.swift:306-327` (`refreshAllFeeds(sqliteDatabase:)`)
- Test: `FeedivoTests/FeedViewModelTests.swift`

**Interfaces:**
- Consumes: `SQLiteFeedActionService.refreshSnapshots() throws -> [FeedRefreshSnapshot]`
  (`Feedivo/Services/SQLiteFeedActionService.swift:64`, bereits vorhanden,
  unverändert), `FeedViewModel.errorMessage: String?` (bereits vorhanden).

**Vorher:**
```swift
@MainActor
func refreshAllFeeds(sqliteDatabase: FeedivoDatabase) async {
    guard !isLoading else {
        errorMessage = L10n.feedErrorAlreadyRunning
        return
    }

    let service = sqliteFeedActionService(for: sqliteDatabase)
    let snapshots = (try? service.refreshSnapshots()) ?? []

    guard !snapshots.isEmpty else {
        return
    }

    let ruleSnapshots = sqliteRuleSnapshots(from: sqliteDatabase)

    await refreshAllFeedsWithCoordinator(
        snapshots,
        database: sqliteDatabase,
        ruleSnapshots: ruleSnapshots
    )
}
```

- [ ] **Step 1: Failing Test schreiben**

In `FeedivoTests/FeedViewModelTests.swift`, neuen Test direkt nach
`refreshAllFeedsMitSQLiteDatabaseNutztSQLiteFirstOhneDoppeltenAbruf()`
(endet bei Zeile 320) einfügen:

```swift
@Test func refreshAllFeedsMeldetFehlerWennSnapshotsNichtGeladenWerdenKoennen() async throws {
    let sqliteDatabase = try FeedivoDatabase.inMemoryForTests()
    try sqliteDatabase.write { db in
        try db.execute(sql: "DROP TABLE feeds")
    }
    let viewModel = makeViewModel(
        fetchFeed: { _ in
            Issue.record("Netzwerk-Abruf darf nicht erreicht werden, wenn schon das Laden der Snapshots fehlschlaegt.")
            return ParsedFeed(sourceURL: "", title: "", description: nil, articles: [])
        }
    )

    await viewModel.refreshAllFeeds(sqliteDatabase: sqliteDatabase)

    #expect(viewModel.errorMessage != nil)
    #expect(!viewModel.isLoading)
}
```

- [ ] **Step 2: Test laufen lassen, RED verifizieren**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedViewModelTests/refreshAllFeedsMeldetFehlerWennSnapshotsNichtGeladenWerdenKoennen -parallel-testing-enabled NO`
Expected: FAIL — `viewModel.errorMessage` ist `nil` (die aktuelle
`try?`-Implementierung verschluckt den Fehler und kehrt kommentarlos
zurück).

- [ ] **Step 3: Minimale Implementierung**

In `Feedivo/ViewModels/FeedViewModel.swift`, die Funktion
`refreshAllFeeds(sqliteDatabase:)` (aktuell Zeilen 306-327) ändern zu:

```swift
    @MainActor
    func refreshAllFeeds(sqliteDatabase: FeedivoDatabase) async {
        guard !isLoading else {
            errorMessage = L10n.feedErrorAlreadyRunning
            return
        }

        let service = sqliteFeedActionService(for: sqliteDatabase)

        let snapshots: [FeedRefreshSnapshot]
        do {
            snapshots = try service.refreshSnapshots()
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        guard !snapshots.isEmpty else {
            return
        }

        let ruleSnapshots = sqliteRuleSnapshots(from: sqliteDatabase)

        await refreshAllFeedsWithCoordinator(
            snapshots,
            database: sqliteDatabase,
            ruleSnapshots: ruleSnapshots
        )
    }
```

- [ ] **Step 4: Test laufen lassen, GREEN verifizieren**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedViewModelTests/refreshAllFeedsMeldetFehlerWennSnapshotsNichtGeladenWerdenKoennen -parallel-testing-enabled NO`
Expected: PASS.

- [ ] **Step 5: Volle `FeedViewModelTests`-Suite laufen lassen**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedViewModelTests -parallel-testing-enabled NO`
Expected: Alle Tests PASS — bekannte Ausnahme laut CLAUDE.md-Gotcha: die 2
dauerhaft flaky-unter-Last Tests
(`refreshAllFeedsMitSQLiteDatabaseNutztSQLiteFirstOhneDoppeltenAbruf`,
`refreshAllFeedsMitSQLiteDatabaseMeldetFeedBenachrichtigungen`) dürfen bei
Last vereinzelt fehlschlagen — das ist vorbestehend, keine neue Regression.

- [ ] **Step 6: Commit**

```bash
git add Feedivo/ViewModels/FeedViewModel.swift FeedivoTests/FeedViewModelTests.swift
git commit -m "Fix: FeedViewModel.refreshAllFeeds meldet Fehler beim Laden der Feed-Snapshots statt stumm zurueckzukehren"
```

---

### Task 3: Sidebar-Ladefehler sichtbar machen (Finding 1.6)

**Files:**
- Modify: `Feedivo/Views/Sidebar/SidebarView.swift:51-71` (`body`)

**Interfaces:**
- Consumes: `SQLiteSidebarState.errorMessage: String?` (bereits vorhanden,
  `Feedivo/ViewModels/SQLiteSidebarState.swift:14`, wird in `load(...)`
  bereits korrekt gesetzt — Zeile 81 im Fehlerfall, Zeile 69/32 auf `nil`
  zurückgesetzt).

**Vorher** (`Feedivo/Views/Sidebar/SidebarView.swift:51-71`):
```swift
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    sidebarActionRow
                    defaultSmartFoldersSection(
                        badgeSnapshot: sqliteSidebarState.smartFolderBadgeSnapshot,
                        mixedCountsByDefaultKey: sqliteSidebarState.mixedCountsByDefaultKey
                    )
                    customSmartFoldersSection(
                        badgeSnapshot: sqliteSidebarState.smartFolderBadgeSnapshot,
                        mixedCountsByDefaultKey: sqliteSidebarState.mixedCountsByDefaultKey
                    )
                    tagsSection
                    foldersSection
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .scrollContentBackground(.hidden)
        }
        .background(SidebarStyle.background)
```

- [ ] **Step 1: Sichtbare Fehleranzeige direkt nach `sidebarActionRow` ergänzen**

In `Feedivo/Views/Sidebar/SidebarView.swift`, im `body` (Zeilen 51-71), die
innere `VStack` um eine Fehleranzeige ergänzen — Muster identisch zur
bereits bestehenden Fehleranzeige in `AddFeedSheet` (`SidebarView.swift:835-839`,
`Text(errorMessage).foregroundStyle(.red).font(.callout)`):

```swift
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    sidebarActionRow

                    if let errorMessage = sqliteSidebarState.errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.callout)
                    }

                    defaultSmartFoldersSection(
                        badgeSnapshot: sqliteSidebarState.smartFolderBadgeSnapshot,
                        mixedCountsByDefaultKey: sqliteSidebarState.mixedCountsByDefaultKey
                    )
                    customSmartFoldersSection(
                        badgeSnapshot: sqliteSidebarState.smartFolderBadgeSnapshot,
                        mixedCountsByDefaultKey: sqliteSidebarState.mixedCountsByDefaultKey
                    )
                    tagsSection
                    foldersSection
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .scrollContentBackground(.hidden)
        }
        .background(SidebarStyle.background)
```

(Rest der Funktion bleibt unverändert — nur der neue `if let`-Block wird
eingefügt, alle nachfolgenden Modifier/Sheets/Dialogs bleiben exakt wie
vorher.)

- [ ] **Step 2: Build verifizieren**

Run: `xcodebuild build -scheme Feedivo -destination 'platform=macOS'`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Manuelle Verifikation (Hinweis, nicht automatisierbar)**

Kein computer-use für native macOS-Apps in dieser Umgebung verfügbar (siehe
CLAUDE.md). Der Nutzer sollte bei Gelegenheit manuell prüfen, dass die
Sidebar im Normalfall (keine DB-Fehler) unverändert aussieht — die neue
`if let`-Zeile darf nur bei einem tatsächlichen Ladefehler etwas anzeigen.

- [ ] **Step 4: Commit**

```bash
git add Feedivo/Views/Sidebar/SidebarView.swift
git commit -m "Fix: Sidebar-Ladefehler wird sichtbar angezeigt statt nur berechnet (Finding 1.6)"
```

---

## Abschluss dieser Gruppe

Nach Task 3: finaler Whole-Group-Review über den gesamten Gruppen-Diff, dann
kurze Zusammenfassung für den Nutzer (Commits, Testergebnis), dann
Rückfrage, ob mit Gruppe 3 (Regex-Validierung bei Regeln, Finding 1.5)
fortgefahren werden soll — inklusive erneuter Nachfrage main vs. eigener
Branch für diese nächste Gruppe.
