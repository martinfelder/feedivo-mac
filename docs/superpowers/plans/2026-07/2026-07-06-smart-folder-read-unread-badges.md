# Gelesen/Ungelesen-Anzeige für Alle-Artikel und Heute Smart Folder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Die Smart Folder "Alle Artikel" und "Heute" zeigen in der Sidebar zusätzlich zur bisherigen (aktuell fehlenden) Anzahl sowohl die gelesene als auch die ungelesene Artikelanzahl an, während alle anderen Smart Folder unverändert bleiben.

**Architecture:** Eine neue Methode `TimelineStore.readUnreadCounts(scope:includeHidden:)` nutzt den bestehenden, von `markRead`/`count` bereits verwendeten SQL-WHERE-Klausel-Baustein (`appendScopeWhereClause`), um für einen Smart-Folder-Scope exakt dieselbe Filterlogik wie die echte Artikelliste anzuwenden, und liefert `(read, unread)` per einer `SUM(CASE...)`-Abfrage. `SQLiteSidebarState` ruft diese Methode beim Sidebar-Refresh für die Ordner mit `defaultKey == "all"`/`"today"` auf und stellt das Ergebnis als `mixedCountsByDefaultKey` bereit. `SidebarView` rendert für diese zwei Ordner zwei Zahlen statt der bisherigen Einzel-Badge.

**Tech Stack:** Swift, GRDB (SQLite), SwiftUI, Swift Testing (`@Test`/`#expect`).

## Global Constraints

- Nur die zwei Default-Smart-Folder mit `defaultKey == "all"` und `defaultKey == "today"` bekommen die neue Anzeige — alle anderen Smart Folder bleiben bei ihrer bestehenden Einzel-Badge-Logik unverändert.
- Die Zählung muss exakt dieselbe WHERE-Klausel wie die echte Artikelliste des Ordners verwenden (Wiederverwendung von `appendScopeWhereClause`), damit Badge-Zahl und Ordner-Inhalt nie auseinanderlaufen.
- Gelesen-Zahl: schlichter Text ohne Kapsel-Hintergrund (`SidebarStyle.secondaryText`). Ungelesen-Zahl: wie bisher als Kapsel (`SidebarStyle.activeSelection` + `Capsule()`). Beide in `11pt, semibold, monospacedDigit`.
- Ist eine der beiden Zahlen 0, wird nur das jeweils andere Element angezeigt (kein leeres Badge).
- Kein neues Nutzer-Setting, keine Änderung an `FeedBackgroundRefreshService` oder der Legacy-SwiftData-Badge-Logik.

---

### Task 1: `SmartFolderMixedCounts` und `TimelineStore.readUnreadCounts(scope:includeHidden:)`

**Files:**
- Create: `Feedivo/Snapshots/SmartFolderMixedCounts.swift`
- Modify: `Feedivo/Stores/TimelineStore.swift` (neue Methode nach `count(scope:includeRead:includeHidden:)`, aktuell endend bei Zeile 278)
- Test: `FeedivoTests/SQLiteTimelineStoreTests.swift`

**Interfaces:**
- Produces: `SmartFolderMixedCounts: Equatable, Sendable { let read: Int; let unread: Int }` und `TimelineStore.readUnreadCounts(scope: TimelineScope, includeHidden: Bool) throws -> SmartFolderMixedCounts` — von Task 2 konsumiert.

- [ ] **Step 1: `SmartFolderMixedCounts` anlegen**

Neue Datei `Feedivo/Snapshots/SmartFolderMixedCounts.swift`:

```swift
import Foundation
import GRDB

struct SmartFolderMixedCounts: Equatable, Sendable {
    let read: Int
    let unread: Int

    static let empty = SmartFolderMixedCounts(read: 0, unread: 0)
}

extension SmartFolderMixedCounts: FetchableRecord {
    init(row: Row) throws {
        read = row["read"]
        unread = row["unread"]
    }
}
```

- [ ] **Step 2: Fehlschlagenden Test schreiben**

An das Ende von `FeedivoTests/SQLiteTimelineStoreTests.swift` (innerhalb `struct SQLiteTimelineStoreTests { ... }`, nach der letzten bestehenden `@Test func`) einfügen:

```swift
    @Test func readUnreadCountsSplitsSmartFolderScopeByReadStatusAndExcludesHidden() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)
        let timelineStore = TimelineStore(database: database)
        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))

        let readID = try articleStore.upsert(
            ArticleUpsertInput(feedID: "feed-1", sourceID: "read", title: "Gelesen")
        )
        _ = try articleStore.upsert(
            ArticleUpsertInput(feedID: "feed-1", sourceID: "unread", title: "Ungelesen")
        )
        let hiddenID = try articleStore.upsert(
            ArticleUpsertInput(feedID: "feed-1", sourceID: "hidden", title: "Versteckt")
        )
        try statusStore.setRead(true, articleID: readID, at: Date(timeIntervalSince1970: 100))
        try statusStore.setHidden(true, articleID: hiddenID, at: Date(timeIntervalSince1970: 100))

        let folder = SQLiteSmartFolderSnapshot(
            id: "smart-empty",
            name: "Alle Artikel",
            matchMode: .all,
            conditions: []
        )

        let counts = try timelineStore.readUnreadCounts(
            scope: .smartFolder(folder),
            includeHidden: false
        )

        #expect(counts.read == 1)
        #expect(counts.unread == 1)
    }
```

- [ ] **Step 3: Test ausführen, Fehlschlag bestätigen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteTimelineStoreTests/readUnreadCountsSplitsSmartFolderScopeByReadStatusAndExcludesHidden`
Expected: FAIL — Compile-Fehler "value of type 'TimelineStore' has no member 'readUnreadCounts'"

- [ ] **Step 4: Methode implementieren**

In `Feedivo/Stores/TimelineStore.swift` direkt nach dem Ende von `count(scope:includeRead:includeHidden:)` (nach der schließenden `}` bei aktuell Zeile 278, vor `private func appendScopeWhereClause`) einfügen:

```swift
    func readUnreadCounts(
        scope: TimelineScope,
        includeHidden: Bool
    ) throws -> SmartFolderMixedCounts {
        var whereClauses: [String] = []
        var arguments = StatementArguments()
        appendScopeWhereClause(
            scope,
            whereClauses: &whereClauses,
            arguments: &arguments
        )

        if !includeHidden {
            whereClauses.append("s.isHidden = 0")
        }

        let whereSQL = whereClauses.isEmpty ? "" : "WHERE \(whereClauses.joined(separator: " AND "))"

        return try database.read { db in
            try SmartFolderMixedCounts.fetchOne(db, sql: """
                SELECT
                    COALESCE(SUM(CASE WHEN s.isRead = 1 THEN 1 ELSE 0 END), 0) AS read,
                    COALESCE(SUM(CASE WHEN s.isRead = 0 THEN 1 ELSE 0 END), 0) AS unread
                FROM articles a
                JOIN feeds f ON f.id = a.feedID
                JOIN article_statuses s ON s.articleID = a.id
                \(whereSQL)
                """, arguments: arguments) ?? .empty
        }
    }
```

- [ ] **Step 5: Test ausführen, Erfolg bestätigen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteTimelineStoreTests/readUnreadCountsSplitsSmartFolderScopeByReadStatusAndExcludesHidden`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 6: Vollen Testsuite-Ausschnitt laufen lassen, keine Regression**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteTimelineStoreTests`
Expected: `** TEST SUCCEEDED **`, alle bestehenden Tests dieser Datei weiterhin grün.

- [ ] **Step 7: Commit**

```bash
git add Feedivo/Snapshots/SmartFolderMixedCounts.swift Feedivo/Stores/TimelineStore.swift FeedivoTests/SQLiteTimelineStoreTests.swift
git commit -m "TimelineStore: readUnreadCounts fuer Smart-Folder-Scope mit Hidden-Ausschluss"
```

---

### Task 2: `SQLiteSidebarState.mixedCountsByDefaultKey`

**Files:**
- Modify: `Feedivo/ViewModels/SQLiteSidebarState.swift`
- Test: `FeedivoTests/SQLiteSidebarStateTests.swift`

**Interfaces:**
- Consumes: `TimelineStore.readUnreadCounts(scope:includeHidden:) throws -> SmartFolderMixedCounts` (aus Task 1), `SQLiteSmartFolderSnapshot.defaultKey: String?` und `SQLiteSmartFolderSnapshot.includesHiddenArticles: Bool` (bestehend).
- Produces: `SQLiteSidebarState.mixedCountsByDefaultKey: [String: SmartFolderMixedCounts]` — von Task 3 konsumiert.

- [ ] **Step 1: Fehlschlagenden Test schreiben**

An das Ende von `FeedivoTests/SQLiteSidebarStateTests.swift` (innerhalb `struct SQLiteSidebarStateTests { ... }`, nach der letzten bestehenden `@Test func`) einfügen:

```swift
    @MainActor
    @Test func loadComputesMixedCountsForAllArticlesAndTodayDefaultFolders() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)
        let smartFolderStore = SQLiteSmartFolderStore(database: database)
        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))

        try smartFolderStore.save(
            SmartFolderRecord(id: "smart-all", name: "Alle Artikel", defaultKey: "all"),
            conditions: []
        )
        try smartFolderStore.save(
            SmartFolderRecord(id: "smart-today", name: "Heute", defaultKey: "today"),
            conditions: [
                SmartFolderConditionRecord(
                    id: "condition-today",
                    smartFolderID: "smart-today",
                    field: SmartFolderConditionField.date.rawValue,
                    conditionOperator: SmartFolderConditionOperator.is.rawValue,
                    value: SmartFolderDateValue.today.rawValue
                )
            ]
        )

        let now = Date()
        let longAgo = now.addingTimeInterval(-10 * 24 * 60 * 60)
        let readTodayID = try articleStore.upsert(
            ArticleUpsertInput(feedID: "feed-1", sourceID: "read-today", title: "Gelesen heute", publishedAt: now, arrivedAt: now)
        )
        _ = try articleStore.upsert(
            ArticleUpsertInput(feedID: "feed-1", sourceID: "unread-today", title: "Ungelesen heute", publishedAt: now, arrivedAt: now)
        )
        let oldID = try articleStore.upsert(
            ArticleUpsertInput(feedID: "feed-1", sourceID: "old", title: "Alt", publishedAt: longAgo, arrivedAt: now)
        )
        try statusStore.setRead(true, articleID: readTodayID, at: now)
        try statusStore.setRead(true, articleID: oldID, at: now)

        let state = SQLiteSidebarState()

        state.load(database: database, showsReadFeeds: true)

        #expect(state.mixedCountsByDefaultKey["all"]?.read == 2)
        #expect(state.mixedCountsByDefaultKey["all"]?.unread == 1)
        #expect(state.mixedCountsByDefaultKey["today"]?.read == 1)
        #expect(state.mixedCountsByDefaultKey["today"]?.unread == 1)
    }
```

- [ ] **Step 2: Test ausführen, Fehlschlag bestätigen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteSidebarStateTests/loadComputesMixedCountsForAllArticlesAndTodayDefaultFolders`
Expected: FAIL — Compile-Fehler "value of type 'SQLiteSidebarState' has no member 'mixedCountsByDefaultKey'"

- [ ] **Step 3: Property ergänzen und in `load` befüllen**

In `Feedivo/ViewModels/SQLiteSidebarState.swift` das bestehende Property

```swift
    private(set) var smartFolderBadgeSnapshot = SmartFolderSidebarBadgeSnapshot.empty
```

ersetzen durch:

```swift
    private(set) var smartFolderBadgeSnapshot = SmartFolderSidebarBadgeSnapshot.empty
    private(set) var mixedCountsByDefaultKey: [String: SmartFolderMixedCounts] = [:]
```

Die Reset-Zweige (im `guard let database else { ... }`-Block und im `catch`-Block) jeweils um eine Zeile ergänzen. Aus:

```swift
            smartFolderSnapshots = []
            smartFolderBadgeSnapshot = .empty
```

wird an BEIDEN Stellen (Guard-Block und Catch-Block):

```swift
            smartFolderSnapshots = []
            smartFolderBadgeSnapshot = .empty
            mixedCountsByDefaultKey = [:]
```

Im Erfolgspfad die Zeile

```swift
            let loadedSmartFolderSnapshots = try smartFolderStore.sidebarSnapshots()
            let loadedSmartFolderBadgeSnapshot = try unreadCountService.sidebarSmartFolderBadgeSnapshot()
            snapshots = loadedSnapshots
```

ersetzen durch:

```swift
            let loadedSmartFolderSnapshots = try smartFolderStore.sidebarSnapshots()
            let loadedSmartFolderBadgeSnapshot = try unreadCountService.sidebarSmartFolderBadgeSnapshot()
            let timelineStore = TimelineStore(database: database)
            var loadedMixedCounts: [String: SmartFolderMixedCounts] = [:]
            for defaultKey in ["all", "today"] {
                guard let folder = loadedSmartFolderSnapshots.first(where: { $0.defaultKey == defaultKey }) else {
                    continue
                }

                loadedMixedCounts[defaultKey] = try timelineStore.readUnreadCounts(
                    scope: .smartFolder(folder),
                    includeHidden: folder.includesHiddenArticles
                )
            }
            snapshots = loadedSnapshots
```

Direkt nach der bestehenden Zeile `smartFolderBadgeSnapshot = loadedSmartFolderBadgeSnapshot` eine neue Zeile ergänzen:

```swift
            smartFolderBadgeSnapshot = loadedSmartFolderBadgeSnapshot
            mixedCountsByDefaultKey = loadedMixedCounts
```

- [ ] **Step 4: Test ausführen, Erfolg bestätigen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteSidebarStateTests`
Expected: `** TEST SUCCEEDED **`, der neue Test grün, alle bestehenden Tests dieser Datei weiterhin grün.

- [ ] **Step 5: Commit**

```bash
git add Feedivo/ViewModels/SQLiteSidebarState.swift FeedivoTests/SQLiteSidebarStateTests.swift
git commit -m "SQLiteSidebarState: mixedCountsByDefaultKey fuer Alle-Artikel und Heute"
```

---

### Task 3: Zwei Badges in `SmartFolderSidebarRow`

**Files:**
- Modify: `Feedivo/Views/Sidebar/SidebarView.swift`

**Interfaces:**
- Consumes: `SQLiteSidebarState.mixedCountsByDefaultKey: [String: SmartFolderMixedCounts]` (aus Task 2), `SQLiteSmartFolderSnapshot.defaultKey: String?` (bestehend).

- [ ] **Step 1: `smartFoldersSection` erhält die neuen Zählungen**

In `Feedivo/Views/Sidebar/SidebarView.swift` den Aufruf

```swift
                    smartFoldersSection(badgeSnapshot: sqliteSidebarState.smartFolderBadgeSnapshot)
```

ersetzen durch:

```swift
                    smartFoldersSection(
                        badgeSnapshot: sqliteSidebarState.smartFolderBadgeSnapshot,
                        mixedCountsByDefaultKey: sqliteSidebarState.mixedCountsByDefaultKey
                    )
```

Die Funktionssignatur

```swift
    private func smartFoldersSection(badgeSnapshot: SmartFolderSidebarBadgeSnapshot) -> some View {
```

ersetzen durch:

```swift
    private func smartFoldersSection(
        badgeSnapshot: SmartFolderSidebarBadgeSnapshot,
        mixedCountsByDefaultKey: [String: SmartFolderMixedCounts]
    ) -> some View {
```

Die Instanziierung

```swift
                        SmartFolderSidebarRow(
                            smartFolder: smartFolder,
                            badgeSnapshot: badgeSnapshot
                        )
```

ersetzen durch:

```swift
                        SmartFolderSidebarRow(
                            smartFolder: smartFolder,
                            badgeSnapshot: badgeSnapshot,
                            mixedCounts: smartFolder.defaultKey.flatMap { mixedCountsByDefaultKey[$0] }
                        )
```

- [ ] **Step 2: `SmartFolderSidebarRow` um zwei Badges erweitern**

Den bestehenden Struct

```swift
private struct SmartFolderSidebarRow: View {
    @Environment(\.interfaceTextSize) private var interfaceTextSize

    let smartFolder: SQLiteSmartFolderSnapshot
    let badgeSnapshot: SmartFolderSidebarBadgeSnapshot

    // Badge bewusst aus dem SQLite-Snapshot berechnen: Die Sidebar muss dafür
    // keine Artikel-Query und keine SwiftData-Relationships beobachten.
    private var badgeText: String? {
        SmartFolderSidebarBadge.badgeText(for: smartFolder, snapshot: badgeSnapshot)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: smartFolder.iconName ?? SmartFolderAppearance.defaultIconName)
                .font(interfaceTextSize.font(size: 14, weight: .semibold))
                .foregroundStyle(TagColorPalette.color(for: smartFolder.colorHex ?? SmartFolderAppearance.defaultColorHex).opacity(SidebarStyle.iconOpacity))
                .frame(width: interfaceTextSize.scaled(20))

            Text(smartFolder.name)
                .font(interfaceTextSize.font(size: 13, weight: .semibold))
                .lineLimit(1)

            Spacer(minLength: 8)

            if let badgeText {
                Text(badgeText)
                    .font(interfaceTextSize.font(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(SidebarStyle.secondaryText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(SidebarStyle.activeSelection, in: Capsule())
            }
        }
    }
}
```

ersetzen durch:

```swift
private struct SmartFolderSidebarRow: View {
    @Environment(\.interfaceTextSize) private var interfaceTextSize

    let smartFolder: SQLiteSmartFolderSnapshot
    let badgeSnapshot: SmartFolderSidebarBadgeSnapshot
    let mixedCounts: SmartFolderMixedCounts?

    // Badge bewusst aus dem SQLite-Snapshot berechnen: Die Sidebar muss dafür
    // keine Artikel-Query und keine SwiftData-Relationships beobachten.
    private var badgeText: String? {
        SmartFolderSidebarBadge.badgeText(for: smartFolder, snapshot: badgeSnapshot)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: smartFolder.iconName ?? SmartFolderAppearance.defaultIconName)
                .font(interfaceTextSize.font(size: 14, weight: .semibold))
                .foregroundStyle(TagColorPalette.color(for: smartFolder.colorHex ?? SmartFolderAppearance.defaultColorHex).opacity(SidebarStyle.iconOpacity))
                .frame(width: interfaceTextSize.scaled(20))

            Text(smartFolder.name)
                .font(interfaceTextSize.font(size: 13, weight: .semibold))
                .lineLimit(1)

            Spacer(minLength: 8)

            if let mixedCounts {
                if mixedCounts.read > 0 {
                    Text("\(mixedCounts.read)")
                        .font(interfaceTextSize.font(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(SidebarStyle.secondaryText)
                }

                if mixedCounts.unread > 0 {
                    Text("\(mixedCounts.unread)")
                        .font(interfaceTextSize.font(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(SidebarStyle.secondaryText)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(SidebarStyle.activeSelection, in: Capsule())
                }
            } else if let badgeText {
                Text(badgeText)
                    .font(interfaceTextSize.font(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(SidebarStyle.secondaryText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(SidebarStyle.activeSelection, in: Capsule())
            }
        }
    }
}
```

- [ ] **Step 3: Bauen**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -configuration Debug -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Manuell verifizieren**

App starten. In der Sidebar bei "Alle Artikel" und "Heute" müssen jetzt zwei Zahlen erscheinen (dezente Gelesen-Zahl links, hervorgehobene Ungelesen-Kapsel rechts), während "Ungelesen", "Mit Stern", "Ausgeblendet" und "Archiviert" unverändert nur ihre bisherige einzelne Kapsel zeigen.

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Views/Sidebar/SidebarView.swift
git commit -m "SidebarView: Gelesen/Ungelesen-Badges fuer Alle-Artikel und Heute Smart Folder"
```

---

## Self-Review

**Spec coverage:** Die Spec fordert (1) neue Zählmethode auf Basis der bestehenden WHERE-Klausel-Logik (Task 1, wiederverwendet `appendScopeWhereClause`), (2) Berechnung beim Sidebar-Refresh für genau die zwei `defaultKey`-Ordner (Task 2), (3) zwei Badges mit Gelesen dezent/Ungelesen hervorgehoben, nur bei Wert > 0 sichtbar (Task 3), (4) keine Änderung an anderen Ordnern (Task 3 behält den `else if let badgeText`-Zweig unverändert bei), (5) Hidden-Exklusion je nach `includesHiddenArticles` (Task 1 Parameter `includeHidden`, Task 2 übergibt `folder.includesHiddenArticles`). Alle Punkte sind abgedeckt.

**Placeholder-Scan:** Keine TBD/TODO, vollständiger Code in jedem Schritt.

**Typ-Konsistenz:** `TimelineStore.readUnreadCounts(scope: TimelineScope, includeHidden: Bool) throws -> SmartFolderMixedCounts` (Task 1) wird in Task 2 exakt mit dieser Signatur aufgerufen. `SQLiteSidebarState.mixedCountsByDefaultKey: [String: SmartFolderMixedCounts]` (Task 2) wird in Task 3 exakt mit diesem Namen und Typ gelesen und in `SmartFolderSidebarRow.mixedCounts: SmartFolderMixedCounts?` weitergereicht.
