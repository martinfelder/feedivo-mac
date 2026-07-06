# "Neu"-Zähler nur für kürzlich veröffentlichte Artikel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Der "X neu"-Zähler (Status-Pill, System-Benachrichtigungen, Log-Einträge) zählt künftig nur Artikel, deren `publishedAt` innerhalb der letzten 48 Stunden liegt, statt jeden neu in die lokale Datenbank eingefügten Artikel.

**Architecture:** Ein neuer, gezielter `ArticleStore`-Query zählt "kürzlich veröffentlichte" Artikel aus einer Liste von IDs. `SQLiteFeedRefreshService` berechnet diesen Wert zusätzlich zu (nicht anstelle von) `insertedArticleIDs` und trägt ihn in ein neues Feld `newArticleCount` seines Ergebnistyps ein. `SQLiteFeedRefreshCoordinator` liest dieses Feld statt `insertedArticleIDs.count` — dadurch profitieren Status-Pill, Benachrichtigungen und Logs von einer einzigen Änderung.

**Tech Stack:** Swift, GRDB (SQLite), Swift Testing (`@Test`/`#expect`).

## Global Constraints

- `insertedArticleIDs` bleibt unverändert und wird weiterhin vollständig für Regelanwendung und Ungelesen-Zählung genutzt — nur die Anzeige-Zählung ändert sich.
- Zeitfenster: 48 Stunden, fest codiert, kein neues Nutzer-Setting.
- Ein Artikel ohne `publishedAt` (NULL) zählt nicht als "neu".
- Betroffen ist ausschließlich der aktive SQLite-Refresh-Pfad (`SQLiteFeedRefreshService`, `SQLiteFeedRefreshCoordinator`) — `FeedBackgroundRefreshService` (Legacy) bleibt unangetastet.

---

### Task 1: `ArticleStore.recentlyPublishedCount(articleIDs:since:)`

**Files:**
- Modify: `Feedivo/Stores/ArticleStore.swift` (neue Methode, direkt nach `ruleSnapshots(articleIDs:feedTitle:)`, aktuell endend bei Zeile 182)
- Test: `FeedivoTests/SQLiteArticleStoreTests.swift`

**Interfaces:**
- Produces: `ArticleStore.recentlyPublishedCount(articleIDs: [String], since: Date) throws -> Int` — von Task 2 konsumiert.

- [ ] **Step 1: Fehlschlagenden Test schreiben**

An das Ende von `FeedivoTests/SQLiteArticleStoreTests.swift` (nach der letzten bestehenden `@Test func`, innerhalb der `struct SQLiteArticleStoreTests { ... }`) einfügen:

```swift
    @Test func recentlyPublishedCountCountsOnlyArticlesWithinWindowAndIgnoresUndated() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let since = now.addingTimeInterval(-48 * 60 * 60)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))

        let recentID = try articleStore.upsert(ArticleUpsertInput(
            feedID: "feed-1",
            sourceID: "recent",
            title: "Kuerzlich veroeffentlicht",
            publishedAt: now.addingTimeInterval(-60),
            arrivedAt: now
        ))
        let oldID = try articleStore.upsert(ArticleUpsertInput(
            feedID: "feed-1",
            sourceID: "old",
            title: "Alt veroeffentlicht",
            publishedAt: since.addingTimeInterval(-60),
            arrivedAt: now
        ))
        let undatedID = try articleStore.upsert(ArticleUpsertInput(
            feedID: "feed-1",
            sourceID: "undated",
            title: "Ohne Datum",
            publishedAt: nil,
            arrivedAt: now
        ))

        let count = try articleStore.recentlyPublishedCount(
            articleIDs: [recentID, oldID, undatedID],
            since: since
        )

        #expect(count == 1)
    }

    @Test func recentlyPublishedCountReturnsZeroForEmptyIDs() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let articleStore = ArticleStore(database: database)

        let count = try articleStore.recentlyPublishedCount(articleIDs: [], since: Date())

        #expect(count == 0)
    }
```

- [ ] **Step 2: Test ausführen, Fehlschlag bestätigen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteArticleStoreTests`
Expected: FAIL — Compile-Fehler "value of type 'ArticleStore' has no member 'recentlyPublishedCount'"

- [ ] **Step 3: Methode implementieren**

In `Feedivo/Stores/ArticleStore.swift` direkt nach dem Ende von `ruleSnapshots(articleIDs:feedTitle:)` (nach der schließenden `}` bei aktuell Zeile 182, vor `private func latestArticleForFeed`) einfügen:

```swift
    func recentlyPublishedCount(articleIDs: [String], since: Date) throws -> Int {
        guard !articleIDs.isEmpty else {
            return 0
        }

        return try database.read { db in
            let placeholders = Array(repeating: "?", count: articleIDs.count).joined(separator: ", ")
            let arguments = StatementArguments(articleIDs) + StatementArguments([since])
            return try Int.fetchOne(db, sql: """
                SELECT COUNT(*)
                FROM articles
                WHERE id IN (\(placeholders))
                    AND publishedAt IS NOT NULL
                    AND publishedAt >= ?
                """, arguments: arguments) ?? 0
        }
    }
```

- [ ] **Step 4: Test ausführen, Erfolg bestätigen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteArticleStoreTests`
Expected: `** TEST SUCCEEDED **`, beide neuen Tests grün, keine bestehenden Tests in dieser Datei gebrochen.

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Stores/ArticleStore.swift FeedivoTests/SQLiteArticleStoreTests.swift
git commit -m "ArticleStore: recentlyPublishedCount fuer Artikel innerhalb eines Zeitfensters"
```

---

### Task 2: `newArticleCount` in `SQLiteFeedRefreshService`/`SQLiteFeedRefreshCoordinator` verdrahten

**Files:**
- Modify: `Feedivo/Services/SQLiteFeedRefreshService.swift` (`SQLiteFeedRefreshResult`-Struct, `refresh(feedID:)`-Methode)
- Modify: `Feedivo/Services/SQLiteFeedRefreshCoordinator.swift:92-100` (Konstruktion von `FeedRefreshNotificationResult`)
- Test: `FeedivoTests/SQLiteFeedRefreshServiceTests.swift`

**Interfaces:**
- Consumes: `ArticleStore.recentlyPublishedCount(articleIDs:since:) throws -> Int` (aus Task 1)
- Produces: `SQLiteFeedRefreshResult.newArticleCount: Int` (neues Feld) — von `SQLiteFeedRefreshCoordinator` konsumiert.

- [ ] **Step 1: Fehlschlagenden Test schreiben — nur kuerzlich veroeffentlichte Artikel zaehlen als neu**

An das Ende von `FeedivoTests/SQLiteFeedRefreshServiceTests.swift` (innerhalb `struct SQLiteFeedRefreshServiceTests { ... }`, nach der letzten bestehenden `@Test func`) einfügen:

```swift
    @Test func refreshCountsOnlyRecentlyPublishedArticlesAsNew() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let logStore = FeedLogStore(database: database)
        let refreshedAt = Date(timeIntervalSince1970: 1_000_000)
        let longAgo = refreshedAt.addingTimeInterval(-30 * 24 * 60 * 60)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Old"))

        let service = SQLiteFeedRefreshService(database: database, now: { refreshedAt }) { url, _ in
            .updated(
                ParsedFeed(
                    sourceURL: url,
                    title: "Example",
                    description: nil,
                    siteURL: nil,
                    articles: [
                        ParsedArticle(
                            title: "Frischer Artikel",
                            sourceID: "fresh",
                            link: "https://example.com/fresh",
                            summary: nil,
                            content: nil,
                            publishedAt: refreshedAt.addingTimeInterval(-60),
                            imageURL: nil
                        ),
                        ParsedArticle(
                            title: "Archiv-Artikel",
                            sourceID: "archive",
                            link: "https://example.com/archive",
                            summary: nil,
                            content: nil,
                            publishedAt: longAgo,
                            imageURL: nil
                        )
                    ]
                ),
                FeedHTTPValidators(lastStatusCode: 200)
            )
        }

        let result = try await service.refresh(feedID: "feed-1")
        let logs = try logStore.logs(feedID: "feed-1", limit: 5)

        #expect(result.insertedArticleIDs.count == 2)
        #expect(result.newArticleCount == 1)
        #expect(logs.first?.newArticleCount == 1)
    }
```

- [ ] **Step 2: Test ausführen, Fehlschlag bestätigen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedRefreshServiceTests/refreshCountsOnlyRecentlyPublishedArticlesAsNew`
Expected: FAIL — Compile-Fehler "value of type 'SQLiteFeedRefreshResult' has no member 'newArticleCount'"

- [ ] **Step 3: `SQLiteFeedRefreshResult` um `newArticleCount` erweitern**

In `Feedivo/Services/SQLiteFeedRefreshService.swift` den Struct ersetzen:

```swift
struct SQLiteFeedRefreshResult: Equatable, Sendable {
    var feedID: String
    var feedTitle: String
    var insertedArticleIDs: [String]
    var updatedArticleIDs: [String]
    var unreadCount: Int
    var isNotModified: Bool
    var ruleNotifications: [RuleNotificationResult] = []
}
```

durch:

```swift
struct SQLiteFeedRefreshResult: Equatable, Sendable {
    var feedID: String
    var feedTitle: String
    var insertedArticleIDs: [String]
    var updatedArticleIDs: [String]
    var unreadCount: Int
    var isNotModified: Bool
    var ruleNotifications: [RuleNotificationResult] = []
    var newArticleCount: Int = 0
}
```

- [ ] **Step 4: `refresh(feedID:)` — `newArticleCount` berechnen und verwenden**

Im `.notModified`-Zweig von `refresh(feedID:)` das bestehende `return SQLiteFeedRefreshResult(...)` ersetzen:

```swift
                return SQLiteFeedRefreshResult(
                    feedID: feedID,
                    feedTitle: feed.title,
                    insertedArticleIDs: [],
                    updatedArticleIDs: [],
                    unreadCount: unreadCount,
                    isNotModified: true
                )
```

durch (ergänzt nur `newArticleCount: 0`, da bei "nicht geändert" nie neue Artikel eingefügt werden):

```swift
                return SQLiteFeedRefreshResult(
                    feedID: feedID,
                    feedTitle: feed.title,
                    insertedArticleIDs: [],
                    updatedArticleIDs: [],
                    unreadCount: unreadCount,
                    isNotModified: true,
                    newArticleCount: 0
                )
```

Im `.updated`-Zweig, direkt nach der Zeile `let upsertResult = try articleStore.upsert(inputs)` einfügen:

```swift
                let recentCutoff = now().addingTimeInterval(-48 * 60 * 60)
                let recentNewArticleCount = try articleStore.recentlyPublishedCount(
                    articleIDs: upsertResult.insertedArticleIDs,
                    since: recentCutoff
                )
```

Die bestehende `FeedLogRecord`-Konstruktion:

```swift
                try logStore.append(FeedLogRecord(
                    feedID: feedID,
                    createdAt: refreshedAt,
                    level: "info",
                    message: "Aktualisiert",
                    httpStatusCode: updatedValidators.lastStatusCode,
                    newArticleCount: upsertResult.insertedArticleIDs.count
                ))
```

ersetzen durch:

```swift
                try logStore.append(FeedLogRecord(
                    feedID: feedID,
                    createdAt: refreshedAt,
                    level: "info",
                    message: "Aktualisiert",
                    httpStatusCode: updatedValidators.lastStatusCode,
                    newArticleCount: recentNewArticleCount
                ))
```

Den abschließenden `return SQLiteFeedRefreshResult(...)` des `.updated`-Zweigs:

```swift
                return SQLiteFeedRefreshResult(
                    feedID: feedID,
                    feedTitle: refreshedTitle,
                    insertedArticleIDs: upsertResult.insertedArticleIDs,
                    updatedArticleIDs: upsertResult.updatedArticleIDs,
                    unreadCount: unreadCount,
                    isNotModified: false,
                    ruleNotifications: ruleResult.notifications
                )
```

ersetzen durch:

```swift
                return SQLiteFeedRefreshResult(
                    feedID: feedID,
                    feedTitle: refreshedTitle,
                    insertedArticleIDs: upsertResult.insertedArticleIDs,
                    updatedArticleIDs: upsertResult.updatedArticleIDs,
                    unreadCount: unreadCount,
                    isNotModified: false,
                    ruleNotifications: ruleResult.notifications,
                    newArticleCount: recentNewArticleCount
                )
```

- [ ] **Step 5: Test ausführen, Erfolg bestätigen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedRefreshServiceTests`
Expected: `** TEST SUCCEEDED **`, der neue Test grün, alle bestehenden Tests in dieser Datei weiterhin grün (insbesondere `refreshInsertsParsedArticlesAndUpdatesUnreadCount`, dessen `logs.first?.newArticleCount == 2`-Assertion mit Testdaten arbeitet, die alle innerhalb von wenigen Stunden um `refreshedAt` liegen und damit unter dem neuen 48h-Fenster weiterhin als "neu" zählen).

- [ ] **Step 6: `SQLiteFeedRefreshCoordinator` auf das neue Feld umstellen**

In `Feedivo/Services/SQLiteFeedRefreshCoordinator.swift` die Zeile (aktuell Zeile 96):

```swift
                                    newArticleCount: result.insertedArticleIDs.count,
```

ersetzen durch:

```swift
                                    newArticleCount: result.newArticleCount,
```

- [ ] **Step 7: Bauen und Coordinator-Tests laufen lassen**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -configuration Debug -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedRefreshCoordinatorTests`
Expected: `** TEST SUCCEEDED **` (bestehende Coordinator-Tests decken `newArticleCount` nicht explizit auf Alt-vs-Neu-Daten ab, sollten also unverändert grün bleiben; falls ein Test dort direkt `insertedArticleIDs.count` mit `newArticleCount` vergleicht und mit weit auseinanderliegenden Testdaten fehlschlägt, das Testdatum wie in Task 2 Step 1 auf einen enger beieinanderliegenden Zeitraum um das injizierte `now` anpassen — nicht die neue Logik verwässern).

- [ ] **Step 8: Manuell verifizieren**

App bauen und starten, "Alle Feeds aktualisieren" auslösen. Der Status-Pill sollte jetzt nur Artikel zählen, deren Veröffentlichungsdatum innerhalb der letzten 48 Stunden liegt — bei Feeds mit großen historischen Archiven (z. B. dem eingangs beobachteten "Microsoft Support"-Feed) sollte die Zahl deutlich kleiner ausfallen als vor dieser Änderung.

- [ ] **Step 9: Commit**

```bash
git add Feedivo/Services/SQLiteFeedRefreshService.swift Feedivo/Services/SQLiteFeedRefreshCoordinator.swift FeedivoTests/SQLiteFeedRefreshServiceTests.swift
git commit -m "SQLiteFeedRefreshService/Coordinator: newArticleCount nur fuer kuerzlich veroeffentlichte Artikel"
```

---

## Self-Review

**Spec coverage:** Die Spec fordert (1) `insertedArticleIDs` bleibt für Regeln/Ungelesen-Zählung unverändert, (2) neuer 48h-gefilterter Zähler, (3) Anwendung an allen drei Anzeigeorten (Status-Pill, Benachrichtigungen, Logs) über einen einzigen Änderungspunkt, (4) NULL-`publishedAt` zählt nicht als neu, (5) `FeedBackgroundRefreshService` bleibt unangetastet. Task 1 liefert (2)+(4) isoliert testbar; Task 2 verdrahtet (1)+(3) — `insertedArticleIDs` wird an keiner Stelle verändert oder ersetzt, nur `newArticleCount` kommt als zusätzliches Feld hinzu. (5) ist durch Nicht-Anfassen erfüllt — keine Aufgabe berührt `FeedBackgroundRefreshService.swift`.

**Placeholder-Scan:** Keine TBD/TODO, vollständiger Code in jedem Schritt.

**Typ-Konsistenz:** `ArticleStore.recentlyPublishedCount(articleIDs: [String], since: Date) throws -> Int` (Task 1) wird in Task 2 exakt mit dieser Signatur aufgerufen (`try articleStore.recentlyPublishedCount(articleIDs: upsertResult.insertedArticleIDs, since: recentCutoff)`). `SQLiteFeedRefreshResult.newArticleCount: Int` (Task 2) wird in `SQLiteFeedRefreshCoordinator` als `result.newArticleCount` gelesen — Feld- und Typname stimmen überein.
