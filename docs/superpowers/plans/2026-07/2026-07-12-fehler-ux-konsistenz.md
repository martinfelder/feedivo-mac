# Fehler-UX-Konsistenz (Findings 2.1 + 2.2 + 2.4, volles Feature 20.1/20.2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Feed-Fehler in der App sichtbar und behebbar machen: Warn-Badge in der
Sidebar, "Erneut versuchen"/"Feed aktualisieren"-Buttons in den bisher toten
Fehler-/Leerzuständen der Artikelliste, ein Inline-Banner bei fehlgeschlagenem
Refresh trotz vorhandener Artikel, und eine dokumentierte Alert-vs-Inline-Regel.

**Architecture:** Siehe `docs/superpowers/specs/2026-07-12-fehler-ux-konsistenz-design.md`
(vom Nutzer freigegeben) für die vollständige Architektur-Begründung. Kernidee: der
jüngste `feed_logs`-Eintrag pro Feed (`level: "info"`/`"error"`, bei JEDEM Refresh
frisch geschrieben) ist ein zuverlässiges, migrationsfreies Fehler-Signal — via
korrelierter SQL-Subquery abgeleitet, analog zum bestehenden `unreadCount`-Muster in
`FeedStore.sidebarFeeds()`. Ein neuer `onRetryFeed`-Closure-Parameter auf
`SQLiteFeedArticleListView` (nur im `.feed`-Scope) ruft dieselbe, bereits bestehende
`feedViewModel.refreshFeed(feedID:sqliteDatabase:)`-Methode auf, die auch der
bestehende "Feed aktualisieren"-Menüpunkt nutzt — kein neuer Refresh-Code-Pfad.

**Tech Stack:** Swift, SwiftUI, GRDB (SQLite), Swift Testing.

## Global Constraints

- Zielumgebung: `xcodebuild test -scheme Feedivo -destination 'platform=macOS'
  -only-testing:FeedivoTests/<SuiteName> -parallel-testing-enabled NO` und
  `xcodebuild build -scheme Feedivo -destination 'platform=macOS'`.
- **TDD gilt für Task 1** (reine Store-/SQL-Logik, real testbar über
  `FeedivoDatabase.inMemoryForTests()`). **Tasks 2-6 sind SwiftUI-View-Verdrahtung
  ohne UI-Testing-Framework in diesem Projekt** — dort ist die Verifikation
  `xcodebuild build` Erfolg + manuelle Code-Reviewer-Prüfung, keine automatisierten
  Red/Green-Zyklen (bereits im freigegebenen Spec-Dokument so festgehalten,
  Abschnitt „Testing"). Kein Widerspruch zum Prozess — dokumentierte, bewusste
  Abweichung wie bei Gruppe 5.
- `Localizable.xcstrings` NIEMALS per Skript/`json.dump` komplett neu schreiben —
  bekannter Gotcha. Neue Einträge ausschließlich per gezieltem `Edit`-Aufruf an der
  per `grep` verifizierten Ankerzeile einfügen.
- SourceKit/IDE-Diagnosen nach Edits sind oft veraltet/falsch (CLAUDE.md-Gotcha) —
  nur echte `xcodebuild`-Läufe sind verlässlich.
- Kommentare im Code auf Deutsch, nur wo eine nicht offensichtliche Begründung
  nötig ist (Projekt-Konvention).
- **Explizit außerhalb des Scopes** (siehe Spec-Dokument, Abschnitt
  „Scope-Entscheidungen"): kein globaler Top-Banner (bestehende
  `NetworkConnectionStatusIndicator`-Kapsel bleibt unverändert), keine
  Reaktivierung des stillgelegten Offline-Artikel-Download-Features, keine
  vollständige Alert-vs-Inline-Überarbeitung aller Fehlerpfade der App.
- Alle Commits laufen direkt auf `main` (etablierte Praxis dieser Session).

---

### Task 1: `FeedStore` — Fehler-Signal aus `feed_logs` ableiten (Finding 2.1, Datenschicht)

**Files:**
- Modify: `Feedivo/Snapshots/FeedSidebarSnapshot.swift`
- Modify: `Feedivo/Stores/FeedStore.swift`
- Test: `FeedivoTests/SQLiteFeedStoreTests.swift`

**Interfaces:**
- Produces: `FeedSidebarSnapshot.hasRecentError: Bool`, `FeedStore.hasRecentError(feedID: String) throws -> Bool`
  — werden in Task 2 (Badge) bzw. Task 5 (Inline-Banner) konsumiert.

- [ ] **Step 1: Fehlschlagende Tests schreiben**

Füge in `FeedivoTests/SQLiteFeedStoreTests.swift` nach der letzten bestehenden
`@Test func` (Datei-Ende) ein:

```swift

    @Test func sidebarSnapshotsMarkenFeedMitJuengstemErrorLogAlsFehlerhaft() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = FeedStore(database: database)
        let logStore = FeedLogStore(database: database)

        try store.save(FeedRecord(id: "feed-a", url: "https://a.example/feed.xml", title: "A"))
        try store.save(FeedRecord(id: "feed-b", url: "https://b.example/feed.xml", title: "B"))

        try logStore.append(FeedLogRecord(
            feedID: "feed-a",
            createdAt: Date(timeIntervalSince1970: 100),
            level: "error",
            message: "Netzwerkfehler"
        ))
        try logStore.append(FeedLogRecord(
            feedID: "feed-b",
            createdAt: Date(timeIntervalSince1970: 100),
            level: "info",
            message: "3 neue Artikel"
        ))

        let snapshots = try store.sidebarFeeds()

        #expect(snapshots.first { $0.id == "feed-a" }?.hasRecentError == true)
        #expect(snapshots.first { $0.id == "feed-b" }?.hasRecentError == false)
    }

    @Test func sidebarSnapshotsLoeschenFehlerstatusNachErfolgreichemFolgeRefresh() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = FeedStore(database: database)
        let logStore = FeedLogStore(database: database)

        try store.save(FeedRecord(id: "feed-a", url: "https://a.example/feed.xml", title: "A"))

        try logStore.append(FeedLogRecord(
            feedID: "feed-a",
            createdAt: Date(timeIntervalSince1970: 100),
            level: "error",
            message: "Netzwerkfehler"
        ))
        try logStore.append(FeedLogRecord(
            feedID: "feed-a",
            createdAt: Date(timeIntervalSince1970: 200),
            level: "info",
            message: "2 neue Artikel"
        ))

        let snapshots = try store.sidebarFeeds()

        #expect(snapshots.first { $0.id == "feed-a" }?.hasRecentError == false)
    }

    @Test func sidebarSnapshotsOhneLogEintraegeSindNichtFehlerhaft() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = FeedStore(database: database)

        try store.save(FeedRecord(id: "feed-a", url: "https://a.example/feed.xml", title: "A"))

        let snapshots = try store.sidebarFeeds()

        #expect(snapshots.first { $0.id == "feed-a" }?.hasRecentError == false)
    }

    @Test func hasRecentErrorLiefertStatusFuerEinzelnenFeed() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = FeedStore(database: database)
        let logStore = FeedLogStore(database: database)

        try store.save(FeedRecord(id: "feed-a", url: "https://a.example/feed.xml", title: "A"))
        try logStore.append(FeedLogRecord(
            feedID: "feed-a",
            createdAt: Date(timeIntervalSince1970: 100),
            level: "error",
            message: "Netzwerkfehler"
        ))

        #expect(try store.hasRecentError(feedID: "feed-a") == true)
    }

    @Test func hasRecentErrorLiefertFalseFuerUnbekannteFeedID() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = FeedStore(database: database)

        #expect(try store.hasRecentError(feedID: "unbekannt") == false)
    }
```

- [ ] **Step 2: Tests laufen lassen, RED bestätigen**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedStoreTests -parallel-testing-enabled NO`
Expected: FAIL (Build-Fehler: "value of type 'FeedSidebarSnapshot' has no member
'hasRecentError'" / "value of type 'FeedStore' has no member 'hasRecentError'" — beide
existieren noch nicht).

- [ ] **Step 3: `FeedSidebarSnapshot.hasRecentError` ergänzen**

Ersetze in `Feedivo/Snapshots/FeedSidebarSnapshot.swift`:

```swift
import Foundation

struct FeedSidebarSnapshot: Equatable, Identifiable, Sendable {
    var id: String
    var title: String
    var url: String
    var faviconURL: String?
    var folderName: String?
    var unreadCount: Int
}
```

durch:

```swift
import Foundation

struct FeedSidebarSnapshot: Equatable, Identifiable, Sendable {
    var id: String
    var title: String
    var url: String
    var faviconURL: String?
    var folderName: String?
    var unreadCount: Int
    var hasRecentError: Bool
}
```

- [ ] **Step 4: `FeedStore.sidebarFeeds()` SQL erweitern**

In `Feedivo/Stores/FeedStore.swift`, ersetze die `sidebarFeeds()`-Query (aktuell
Zeilen ~250-269):

```swift
    func sidebarFeeds() throws -> [FeedSidebarSnapshot] {
        try database.read { db in
            let snapshots = try FeedSidebarSnapshot.fetchAll(db, sql: """
                SELECT
                    f.id,
                    f.title,
                    f.url,
                    f.faviconURL,
                    f.folderName,
                    (
                        SELECT COUNT(*)
                        FROM articles a
                        JOIN article_statuses s ON s.articleID = a.id
                        WHERE a.feedID = f.id
                            AND s.isRead = 0
                            AND s.isHidden = 0
                    ) AS unreadCount
                FROM feeds f
                ORDER BY f.title COLLATE NOCASE, f.id COLLATE NOCASE
                """)
            return snapshots.sorted {
                let titleOrder = $0.title.localizedStandardCompare($1.title)
                if titleOrder != .orderedSame {
                    return titleOrder == .orderedAscending
                }

                return $0.id.localizedStandardCompare($1.id) == .orderedAscending
            }
        }
    }
```

durch:

```swift
    func sidebarFeeds() throws -> [FeedSidebarSnapshot] {
        try database.read { db in
            let snapshots = try FeedSidebarSnapshot.fetchAll(db, sql: """
                SELECT
                    f.id,
                    f.title,
                    f.url,
                    f.faviconURL,
                    f.folderName,
                    (
                        SELECT COUNT(*)
                        FROM articles a
                        JOIN article_statuses s ON s.articleID = a.id
                        WHERE a.feedID = f.id
                            AND s.isRead = 0
                            AND s.isHidden = 0
                    ) AS unreadCount,
                    COALESCE(
                        (
                            SELECT level = 'error'
                            FROM feed_logs
                            WHERE feedID = f.id
                            ORDER BY createdAt DESC
                            LIMIT 1
                        ),
                        0
                    ) AS hasRecentError
                FROM feeds f
                ORDER BY f.title COLLATE NOCASE, f.id COLLATE NOCASE
                """)
            return snapshots.sorted {
                let titleOrder = $0.title.localizedStandardCompare($1.title)
                if titleOrder != .orderedSame {
                    return titleOrder == .orderedAscending
                }

                return $0.id.localizedStandardCompare($1.id) == .orderedAscending
            }
        }
    }

    /// Einzelfeed-Variante derselben Fehler-Ableitung wie `sidebarFeeds()` — für
    /// `SQLiteFeedArticleListView`s Inline-Fehlerbanner, wo kein vollständiger
    /// `FeedSidebarSnapshot` verfügbar ist (Finding 2.1/Feature 20.1, Gruppe 6).
    func hasRecentError(feedID: String) throws -> Bool {
        try database.read { db in
            try Bool.fetchOne(db, sql: """
                SELECT level = 'error'
                FROM feed_logs
                WHERE feedID = ?
                ORDER BY createdAt DESC
                LIMIT 1
                """, arguments: [feedID]) ?? false
        }
    }
```

- [ ] **Step 5: `FetchableRecord`-Init um `hasRecentError` ergänzen**

Ersetze in derselben Datei (aktuell Zeilen ~342-351):

```swift
extension FeedSidebarSnapshot: FetchableRecord {
    init(row: Row) throws {
        id = row["id"]
        title = row["title"]
        url = row["url"]
        faviconURL = row["faviconURL"]
        folderName = row["folderName"]
        unreadCount = row["unreadCount"]
    }
}
```

durch:

```swift
extension FeedSidebarSnapshot: FetchableRecord {
    init(row: Row) throws {
        id = row["id"]
        title = row["title"]
        url = row["url"]
        faviconURL = row["faviconURL"]
        folderName = row["folderName"]
        unreadCount = row["unreadCount"]
        hasRecentError = row["hasRecentError"]
    }
}
```

- [ ] **Step 6: Tests laufen lassen, GREEN bestätigen**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedStoreTests -parallel-testing-enabled NO`
Expected: PASS (alle bestehenden Tests + die 5 neuen)

- [ ] **Step 7: Committen**

```bash
git add Feedivo/Snapshots/FeedSidebarSnapshot.swift Feedivo/Stores/FeedStore.swift FeedivoTests/SQLiteFeedStoreTests.swift
git commit -m "$(cat <<'EOF'
Feature: FeedStore leitet Feed-Fehlerstatus aus juengstem feed_logs-Eintrag ab (Finding 2.1, Datenschicht)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: `FeedRowView` — Fehler-Badge in der Sidebar (Finding 2.1, UI-Schicht)

**Files:**
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`
- Modify: `Feedivo/Views/Sidebar/FeedRowView.swift`

**Interfaces:**
- Consumes: `FeedSidebarSnapshot.hasRecentError` (Task 1)

Keine automatisierten Tests für diesen Task (reine SwiftUI-View-Änderung, siehe
Global Constraints) — Verifikation ist `xcodebuild build` Erfolg.

- [ ] **Step 1: L10n-Key für den Badge-Tooltip ergänzen**

In `Feedivo/Resources/L10n.swift`, direkt nach Zeile
`static let feedRefreshCommand = String(localized: "feed.refresh.command")` einfügen:

```swift
    static let feedErrorBadgeTooltip = String(localized: "feed.error.badge.tooltip")
```

- [ ] **Step 2: xcstrings-Eintrag einfügen**

Verifiziere Ankerzeile: `grep -n '"feed.error.duplicate"' Feedivo/Resources/Localizable.xcstrings`

Füge direkt VOR dieser Zeile ein:

```json
    "feed.error.badge.tooltip" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Feed nicht erreichbar — Details in den Feed-Eigenschaften"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Feed unreachable — see Feed Properties for details"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Flux inaccessible — voir les propriétés du flux pour plus de détails"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Feed non raggiungibile — vedi le proprietà del feed per i dettagli"
          }
        }
      }
    },
```

- [ ] **Step 3: Badge in `FeedRowView` einfügen**

Ersetze in `Feedivo/Views/Sidebar/FeedRowView.swift` den `body` (aktuell Zeilen ~42-72):

```swift
    var body: some View {
        HStack(spacing: displayStyle.horizontalSpacing) {
            faviconView
                .frame(
                    width: interfaceTextSize.scaled(displayStyle.iconSize),
                    height: interfaceTextSize.scaled(displayStyle.iconSize)
                )

            Text(displayTitle)
```

durch:

```swift
    var body: some View {
        HStack(spacing: displayStyle.horizontalSpacing) {
            faviconView
                .frame(
                    width: interfaceTextSize.scaled(displayStyle.iconSize),
                    height: interfaceTextSize.scaled(displayStyle.iconSize)
                )

            if snapshot.hasRecentError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(interfaceTextSize.font(size: 11, weight: .semibold))
                    .foregroundStyle(.orange)
                    .help(L10n.feedErrorBadgeTooltip)
                    .accessibilityLabel(Text(L10n.feedErrorBadgeTooltip))
            }

            Text(displayTitle)
```

(Der Rest des `body` — `.font(...)`, `.lineLimit(1)`, `Spacer(minLength: 8)`, der
Ungelesen-Badge-Block, die schließende `}` — bleibt unverändert.)

- [ ] **Step 4: Build ausführen, Erfolg bestätigen**

Run: `xcodebuild build -scheme Feedivo -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Committen**

```bash
git add Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings Feedivo/Views/Sidebar/FeedRowView.swift
git commit -m "$(cat <<'EOF'
Feature: Fehler-Badge in der Sidebar bei nicht erreichbarem Feed (Finding 2.1, UI-Schicht)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: "Erneut versuchen"-Button im Fehler-Ladezustand der Artikelliste (Finding 2.2, Teil 1)

**Files:**
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`
- Modify: `Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift`
- Modify: `Feedivo/Views/ContentView.swift`

**Interfaces:**
- Produces: `SQLiteFeedArticleListView.onRetryFeed: (() -> Void)?` (neuer, nur im
  `.feed`-Init verfügbarer Parameter) — wird in Task 4 und Task 5 weiterverwendet.

Keine automatisierten Tests (SwiftUI-View-Verdrahtung) — Verifikation ist
`xcodebuild build` Erfolg.

- [ ] **Step 1: L10n-Key für den Retry-Button ergänzen**

In `Feedivo/Resources/L10n.swift`, direkt nach der in Task 2 eingefügten Zeile
`static let feedErrorBadgeTooltip = String(localized: "feed.error.badge.tooltip")`
einfügen:

```swift
    static let feedErrorRetryButton = String(localized: "feed.error.retry.button")
```

- [ ] **Step 2: xcstrings-Eintrag einfügen**

Verifiziere Ankerzeile: `grep -n '"feed.exportOPML.command"' Feedivo/Resources/Localizable.xcstrings`

Füge direkt VOR dieser Zeile ein:

```json
    "feed.error.retry.button" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Erneut versuchen"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Try Again"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Réessayer"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Riprova"
          }
        }
      }
    },
```

- [ ] **Step 3: `onRetryFeed`-Property + Init-Parameter ergänzen**

In `Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift`, ersetze die
Property-Deklaration und alle 4 Inits (aktuell Zeilen ~46-120):

```swift
    private let scope: Scope
    @Binding var selectedArticleID: String?
    @Binding var navigationState: SQLiteArticleNavigationState
    @Binding var searchText: String
```

durch:

```swift
    private let scope: Scope
    let onRetryFeed: (() -> Void)?
    @Binding var selectedArticleID: String?
    @Binding var navigationState: SQLiteArticleNavigationState
    @Binding var searchText: String
```

Ersetze den `.feed`-Init:

```swift
    init(
        feedID: String,
        title: String,
        selectedArticleID: Binding<String?>,
        navigationState: Binding<SQLiteArticleNavigationState>,
        searchText: Binding<String>
    ) {
        self.scope = .feed(feedID: feedID, title: title)
        self._selectedArticleID = selectedArticleID
        self._navigationState = navigationState
        self._searchText = searchText
    }
```

durch:

```swift
    init(
        feedID: String,
        title: String,
        selectedArticleID: Binding<String?>,
        navigationState: Binding<SQLiteArticleNavigationState>,
        searchText: Binding<String>,
        onRetryFeed: (() -> Void)? = nil
    ) {
        self.scope = .feed(feedID: feedID, title: title)
        self.onRetryFeed = onRetryFeed
        self._selectedArticleID = selectedArticleID
        self._navigationState = navigationState
        self._searchText = searchText
    }
```

Ersetze die restlichen 3 Inits (`tagID`, `smartFilter`, `smartFolder`) — jeweils nur
eine Zeile `self.onRetryFeed = nil` direkt nach der `self.scope = ...`-Zeile ergänzen:

```swift
    init(
        tagID: String,
        selectedArticleID: Binding<String?>,
        navigationState: Binding<SQLiteArticleNavigationState>,
        searchText: Binding<String>
    ) {
        self.scope = .tagID(tagID)
        self.onRetryFeed = nil
        self._selectedArticleID = selectedArticleID
        self._navigationState = navigationState
        self._searchText = searchText
    }

    init(
        smartFilter: SmartFilter,
        selectedArticleID: Binding<String?>,
        navigationState: Binding<SQLiteArticleNavigationState>,
        searchText: Binding<String>
    ) {
        self.scope = .smartFilter(smartFilter)
        self.onRetryFeed = nil
        self._selectedArticleID = selectedArticleID
        self._navigationState = navigationState
        self._searchText = searchText
    }

    init(
        smartFolder: SQLiteSmartFolderSnapshot,
        selectedArticleID: Binding<String?>,
        navigationState: Binding<SQLiteArticleNavigationState>,
        searchText: Binding<String>
    ) {
        self.scope = .smartFolder(smartFolder)
        self.onRetryFeed = nil
        self._selectedArticleID = selectedArticleID
        self._navigationState = navigationState
        self._searchText = searchText
    }
```

- [ ] **Step 4: `.failed`-Zustand um Retry-Button erweitern**

Ersetze in derselben Datei (aktuell in `articleContent`):

```swift
            case .failed(let message):
                ContentUnavailableView(
                    L10n.articleListLoadFailedTitle,
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
```

durch:

```swift
            case .failed(let message):
                ContentUnavailableView {
                    Label(L10n.articleListLoadFailedTitle, systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    if let onRetryFeed {
                        Button(L10n.feedErrorRetryButton, action: onRetryFeed)
                    }
                }
```

- [ ] **Step 5: `onRetryFeed` in `ContentView.swift` verdrahten**

Ersetze in `Feedivo/Views/ContentView.swift` die `.feed`-Scope-Instanziierung
(aktuell Zeilen ~94-102):

```swift
            } else if let feedID = selectedFeedID {
                SQLiteFeedArticleListView(
                    feedID: feedID,
                    title: selectedFeed?.title ?? "",
                    selectedArticleID: $selectedSQLiteArticleID,
                    navigationState: $sqliteArticleNavigationState,
                    searchText: .constant("")
                )
                    .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
```

durch:

```swift
            } else if let feedID = selectedFeedID {
                SQLiteFeedArticleListView(
                    feedID: feedID,
                    title: selectedFeed?.title ?? "",
                    selectedArticleID: $selectedSQLiteArticleID,
                    navigationState: $sqliteArticleNavigationState,
                    searchText: .constant(""),
                    onRetryFeed: {
                        Task {
                            await feedViewModel.refreshFeed(
                                feedID: feedID,
                                sqliteDatabase: feedivoDatabase
                            )
                        }
                    }
                )
                    .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
```

- [ ] **Step 6: Build ausführen, Erfolg bestätigen**

Run: `xcodebuild build -scheme Feedivo -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Committen**

```bash
git add Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift Feedivo/Views/ContentView.swift
git commit -m "$(cat <<'EOF'
Feature: 'Erneut versuchen'-Button im Fehler-Ladezustand der Artikelliste (Finding 2.2, Teil 1)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: "Feed aktualisieren"-Button im leeren Feed-Zustand (Finding 2.2, Teil 2 + Feature 20.2)

**Files:**
- Modify: `Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift`

**Interfaces:**
- Consumes: `onRetryFeed` (Task 3), `L10n.feedRefreshCommand` (bereits vorhanden,
  `Feedivo/Resources/L10n.swift:571`, deutscher Text bereits "Feed aktualisieren" —
  exakter Wortlaut aus Feature 20.2, kein neuer Key nötig).

Keine automatisierten Tests (SwiftUI-View-Verdrahtung) — Verifikation ist
`xcodebuild build` Erfolg.

- [ ] **Step 1: Retry-Button im leeren-Zustand ergänzen**

Ersetze in `Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift` (aktuell in
`articleContent`):

```swift
            case .loaded where state.rows.isEmpty:
                articleListContainer {
                    ContentUnavailableView(
                        emptyTitle,
                        systemImage: emptySystemImage,
                        description: Text(emptyDescription)
                    )
                }
```

durch:

```swift
            case .loaded where state.rows.isEmpty:
                articleListContainer {
                    ContentUnavailableView {
                        Label(emptyTitle, systemImage: emptySystemImage)
                    } description: {
                        Text(emptyDescription)
                    } actions: {
                        if case .feed = scope, let onRetryFeed {
                            Button(L10n.feedRefreshCommand, action: onRetryFeed)
                        }
                    }
                }
```

- [ ] **Step 2: Build ausführen, Erfolg bestätigen**

Run: `xcodebuild build -scheme Feedivo -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Committen**

```bash
git add Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift
git commit -m "$(cat <<'EOF'
Feature: 'Feed aktualisieren'-Button bei leerem Feed (Finding 2.2 Teil 2, Feature 20.2)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Inline-Fehlerbanner in der Artikelliste bei fehlgeschlagenem Refresh (Feature 20.1, zweite Hälfte)

**Files:**
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`
- Modify: `Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift`

**Interfaces:**
- Consumes: `FeedStore.hasRecentError(feedID:)` (Task 1), `onRetryFeed` (Task 3),
  `L10n.feedErrorRetryButton` (Task 3)

Keine automatisierten Tests für die View-Verdrahtung (SwiftUI, siehe Global
Constraints) — die zugrunde liegende `FeedStore.hasRecentError(feedID:)`-Logik ist
bereits in Task 1 vollständig getestet. Verifikation hier ist `xcodebuild build`
Erfolg.

- [ ] **Step 1: L10n-Key für die Banner-Nachricht ergänzen**

In `Feedivo/Resources/L10n.swift`, direkt nach der in Task 3 eingefügten Zeile
`static let feedErrorRetryButton = String(localized: "feed.error.retry.button")`
einfügen:

```swift
    static let feedErrorBannerMessage = String(localized: "feed.error.banner.message")
```

- [ ] **Step 2: xcstrings-Eintrag einfügen**

Verifiziere Ankerzeile: `grep -n '"feed.error.duplicate"' Feedivo/Resources/Localizable.xcstrings`
(Diese Zeile hat sich seit Task 2 um einen Block verschoben, da
`feed.error.badge.tooltip` direkt davor eingefügt wurde — erneut per `grep`
verifizieren, nicht die alte Zeilennummer aus Task 2 wiederverwenden.)

Füge direkt VOR dieser Zeile ein (alphabetisch zwischen `badge.tooltip` und
`duplicate`):

```json
    "feed.error.banner.message" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Der letzte Aktualisierungsversuch ist fehlgeschlagen."
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "The last refresh attempt failed."
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "La dernière tentative d'actualisation a échoué."
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "L'ultimo tentativo di aggiornamento non è riuscito."
          }
        }
      }
    },
```

- [ ] **Step 3: `feedHasRecentError`-State + Reload-Logik ergänzen**

In `Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift`, füge bei den
bestehenden `@State`-Properties (aktuell Zeilen ~51-58, nach
`@State private var state = SQLiteFeedArticleListState()`) eine neue Zeile ein:

```swift
    @State private var state = SQLiteFeedArticleListState()
    @State private var feedHasRecentError = false
```

Ersetze in `reload()` (aktuell Zeilen ~464-472) den `.feed`-Fall:

```swift
        switch scope {
        case let .feed(feedID, _):
            state.load(
                feedID: feedID,
                searchText: debouncedSearchText,
                database: database,
                selectedArticleID: selectedArticleID
            )
```

durch:

```swift
        switch scope {
        case let .feed(feedID, _):
            state.load(
                feedID: feedID,
                searchText: debouncedSearchText,
                database: database,
                selectedArticleID: selectedArticleID
            )
            if let database {
                feedHasRecentError = (try? FeedStore(database: database).hasRecentError(feedID: feedID)) ?? false
            } else {
                feedHasRecentError = false
            }
```

- [ ] **Step 4: Banner in `articleListContainer` ergänzen**

Ersetze in derselben Datei (aktuell Zeilen ~224-233):

```swift
    private func articleListContainer<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            articleListHeader
            Divider()
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
```

durch:

```swift
    private func articleListContainer<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            articleListHeader
            if feedHasRecentError, !state.rows.isEmpty, case .feed = scope, let onRetryFeed {
                feedErrorBanner(retry: onRetryFeed)
            }
            Divider()
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func feedErrorBanner(retry: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(L10n.feedErrorBannerMessage)
                .font(interfaceTextSize.font(size: 12))
            Spacer()
            Button(L10n.feedErrorRetryButton, action: retry)
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.12))
    }
```

- [ ] **Step 5: Build ausführen, Erfolg bestätigen**

Run: `xcodebuild build -scheme Feedivo -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Committen**

```bash
git add Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift
git commit -m "$(cat <<'EOF'
Feature: Inline-Fehlerbanner in der Artikelliste bei fehlgeschlagenem Feed-Refresh (Feature 20.1)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Alert-vs-Inline-Regel dokumentieren + `SidebarView`-Fälle prüfen (Finding 2.4)

**Files:**
- Modify: `Feedivo/Views/ContentView.swift`
- Verify (kein Code-Fix erwartet): `Feedivo/Views/Sidebar/SidebarView.swift`

**Interfaces:** Keine — reine Dokumentation + Verifikation.

Keine automatisierten Tests (Dokumentations-Kommentar) — Verifikation ist
`xcodebuild build` Erfolg (stellt sicher, dass der Kommentar syntaktisch korrekt
eingefügt wurde) + die manuelle Prüfung in Step 2.

- [ ] **Step 1: Regel-Kommentar bei `ContentView.swift`s erster `.alert(`-Stelle ergänzen**

Finde die Stelle mit: `grep -n '\.alert(item: \$opmlAlert)' Feedivo/Views/ContentView.swift`
(aktuell Zeile ~214).

Füge direkt davor ein (Einrückung an die umgebende Modifier-Kette anpassen):

```swift
        // Fehler-UX-Regel (Finding 2.4, Gruppe 6): Modal-Alert nur für
        // App-blockierende Zustände (z. B. DB-Init-Fehler) oder destruktive
        // Bestätigungen. Formular-/Validierungsfehler (z. B. Feed-Hinzufügen,
        // Ordner-Name-Duplikat in SidebarView.swift) bleiben bewusst inline neben
        // dem betroffenen Feld — kein Modal, das den Bearbeitungsfluss unterbricht.
        .alert(item: $opmlAlert) { alert in
```

- [ ] **Step 2: Die 2 im Review genannten `SidebarView.swift`-Fälle gegen die Regel prüfen**

Lies `Feedivo/Views/Sidebar/SidebarView.swift` um die Zeilen ~842-843 (Feed-
Hinzufügen-Fehler, `discoveryErrorMessage ?? viewModel.errorMessage` via
`Text(errorMessage)`) und ~1155-1218 (Ordner-Hinzufügen-Sheet, `errorMessage`
inkl. `L10n.sidebarAddFolderDuplicateError`). Beide sind Formular-lokale
Validierungsfehler in einem Sheet/einer Inline-Sektion, kein App-blockierender oder
destruktiver Zustand — beide entsprechen der in Step 1 dokumentierten Regel bereits
korrekt. **Kein Code-Fix an diesen beiden Stellen.** Falls die Prüfung entgegen
dieser Erwartung doch eine echte Inkonsistenz zeigt (z. B. ein Fall, der laut Regel
eigentlich ein Modal bräuchte oder umgekehrt fälschlich modal ist), diese Abweichung
im Task-Report festhalten statt sie stillschweigend zu übergehen — der Task-Reviewer
entscheidet dann, ob das ein Nachbesserungs-Fund für den Whole-Branch-Review ist.

- [ ] **Step 3: Build ausführen, Erfolg bestätigen**

Run: `xcodebuild build -scheme Feedivo -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Committen**

```bash
git add Feedivo/Views/ContentView.swift
git commit -m "$(cat <<'EOF'
Docs: Alert-vs-Inline-Fehler-UX-Regel dokumentiert, SidebarView-Faelle als konform verifiziert (Finding 2.4)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Self-Review (vom Autor dieses Plans durchgeführt)

**1. Spec-Abdeckung:** Alle 5 Architektur-Komponenten aus dem freigegebenen
Spec-Dokument (`docs/superpowers/specs/2026-07-12-fehler-ux-konsistenz-design.md`)
sind auf die 6 Tasks abgebildet: Komponente 1 → Task 1+2, Komponente 2 → Task 3,
Komponente 3 → Task 4, Komponente 4 → Task 5, Komponente 5 → Task 6. Die im Spec als
„Out of Scope" markierten Punkte (Top-Banner, Offline-Download-Reaktivierung,
vollständige Alert-Überarbeitung) haben bewusst keinen Task.

**2. Placeholder-Scan:** Keine "TBD"/"implement later"-Platzhalter. Task 6 Step 2
formuliert explizit, was zu tun ist, falls die erwartete Konformität nicht zutrifft
(Report-Eintrag statt stillschweigendes Ignorieren) — das ist eine bewusste
Verzweigung, keine Lücke.

**3. Typ-Konsistenz:** `onRetryFeed: (() -> Void)?` wird in Task 3 eingeführt und in
Task 4/5 identisch referenziert. `FeedStore.hasRecentError(feedID:)` (Task 1) und
`FeedSidebarSnapshot.hasRecentError` (Task 1) werden in Task 2 bzw. Task 5 korrekt
konsumiert. `L10n.feedErrorRetryButton` (Task 3) wird in Task 5 wiederverwendet,
`L10n.feedRefreshCommand` (bereits vorhanden) in Task 4 — keine doppelten Keys für
denselben Zweck.
