# Refresh-Throttling + zwei Perf-Nachzügler Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Drei verbleibende Punkte aus dem NetNewsWire-Performance-Vergleich vom
2026-07-27 umsetzen — Mindestabstand pro Feed beim Refresh-All, eine gruppierte
CTE für `rebuildAllFeedUnreadCounts()`, und Favicon-Single-Flight-Dedup.

**Architecture:** Drei unabhängige, jeweils klein gehaltene Bausteine. Das
Throttling nutzt die bereits vorhandene `feed_logs`-Tabelle als
Attempt-Zeitstempel-Quelle (keine neue Migration). Der Unread-Count-Fix
ersetzt N korrelierte Subqueries durch eine gruppierte Query (dasselbe Muster
wie der bereits gemergte `sidebarFeeds()`-Fix). Favicon-Dedup ist ein neuer,
separater `actor`, der über den bereits bestehenden `discoverFaviconURL`-
Konstruktorparameter von `SQLiteFeedRefreshService` eingehängt wird — keine
Änderung an `FaviconService` selbst.

**Tech Stack:** Swift, GRDB (SQLite), Swift Testing (`@Test`/`#expect`), Swift
Concurrency (`actor`, `TaskGroup`).

## Global Constraints

- Kommentare im Code auf Deutsch (Projektkonvention, siehe CLAUDE.md).
- TDD: jeder Schritt beginnt mit einem fehlschlagenden Test, außer explizit als
  reiner Refactor mit bestehendem Regressionstest markiert (Task 4).
- Throttling gilt **nur** für `SQLiteFeedRefreshCoordinator.refreshAllFeeds`
  (automatisch + manuell), **nicht** für gezieltes Einzel-Feed-Refresh über
  `SQLiteFeedRefreshService.refresh(feedID:)` direkt.
- Schwellwert fest 9 Minuten (`9 * 60` Sekunden), kein neuer
  Einstellungen-Eintrag.
- Keine Host-Blockliste umsetzen (YAGNI, siehe Design-Spec „Nicht-Ziele").
- `FeedRecord.lastRefreshedAt` bleibt unangetastet für Throttling-Zwecke (wird
  nur bei Erfolg gesetzt und in der UI als „Zuletzt aktualisiert" angezeigt) —
  `feed_logs.createdAt` ist die Quelle für „letzter Versuch".
- Kein Langzeit-Cache für Favicon-Discovery — nur Dedup gleichzeitig laufender
  Anfragen innerhalb eines Batches.
- Kein Wechsel auf `DatabasePool`/WAL (bereits in Commit `e789eb6` begründet
  entschieden).
- Nach jedem Task: gezielter `xcodebuild test -only-testing:` für die
  betroffene(n) Suite(n), volles `xcodebuild build` erst am Ende aller Tasks.

Referenz-Design: `docs/superpowers/specs/2026-07-27-refresh-throttling-perf-nachzuegler-design.md`

---

### Task 1: `FeedRefreshThrottle` — reine Entscheidungsfunktion

**Files:**
- Create: `Feedivo/Services/FeedRefreshThrottle.swift`
- Test: `FeedivoTests/FeedRefreshThrottleTests.swift`

**Interfaces:**
- Produces: `FeedRefreshThrottle.shouldSkip(lastAttemptAt: Date?, now: Date, minimumInterval: TimeInterval = 9 * 60) -> Bool` — wird von Task 3 verwendet.

- [ ] **Step 1: Write the failing test**

Neue Datei `FeedivoTests/FeedRefreshThrottleTests.swift`:

```swift
import Foundation
import Testing
@testable import Feedivo

struct FeedRefreshThrottleTests {
    @Test func shouldSkipIstFalseWennNieVersucht() {
        let result = FeedRefreshThrottle.shouldSkip(
            lastAttemptAt: nil,
            now: Date(timeIntervalSince1970: 1_000)
        )

        #expect(result == false)
    }

    @Test func shouldSkipIstTrueInnerhalbDesMindestabstands() {
        let lastAttemptAt = Date(timeIntervalSince1970: 1_000)
        let now = lastAttemptAt.addingTimeInterval(5 * 60)

        let result = FeedRefreshThrottle.shouldSkip(
            lastAttemptAt: lastAttemptAt,
            now: now,
            minimumInterval: 9 * 60
        )

        #expect(result == true)
    }

    @Test func shouldSkipIstFalseNachAblaufDesMindestabstands() {
        let lastAttemptAt = Date(timeIntervalSince1970: 1_000)
        let now = lastAttemptAt.addingTimeInterval(10 * 60)

        let result = FeedRefreshThrottle.shouldSkip(
            lastAttemptAt: lastAttemptAt,
            now: now,
            minimumInterval: 9 * 60
        )

        #expect(result == false)
    }

    @Test func shouldSkipIstFalseGenauAnDerSchwelle() {
        let lastAttemptAt = Date(timeIntervalSince1970: 1_000)
        let now = lastAttemptAt.addingTimeInterval(9 * 60)

        let result = FeedRefreshThrottle.shouldSkip(
            lastAttemptAt: lastAttemptAt,
            now: now,
            minimumInterval: 9 * 60
        )

        #expect(result == false)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:'FeedivoTests/FeedRefreshThrottleTests'`
Expected: FAIL — `Cannot find 'FeedRefreshThrottle' in scope` (Typ existiert noch nicht).

- [ ] **Step 3: Write minimal implementation**

Neue Datei `Feedivo/Services/FeedRefreshThrottle.swift`:

```swift
import Foundation

/// Verhindert zu häufiges Refreshen desselben Feeds beim Refresh-All
/// (NetNewsWire-Vergleich, 2026-07-27) — analog NetNewsWires eigenem
/// `minimumTimeBetweenChecks` in `LocalAccountRefresher.swift`. Reine,
/// isoliert testbare Entscheidungsfunktion, analog
/// `BackgroundRefreshService.isPrematureTick`.
enum FeedRefreshThrottle {
    static func shouldSkip(
        lastAttemptAt: Date?,
        now: Date,
        minimumInterval: TimeInterval = 9 * 60
    ) -> Bool {
        guard let lastAttemptAt else {
            return false
        }
        return now.timeIntervalSince(lastAttemptAt) < minimumInterval
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:'FeedivoTests/FeedRefreshThrottleTests'`
Expected: PASS (4/4 Tests grün).

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Services/FeedRefreshThrottle.swift FeedivoTests/FeedRefreshThrottleTests.swift
git commit -m "Feature: FeedRefreshThrottle als reine Mindestabstand-Entscheidungsfunktion"
```

---

### Task 2: `FeedLogStore.latestAttemptTimes()`

**Files:**
- Modify: `Feedivo/Stores/FeedLogStore.swift`
- Test: `FeedivoTests/SQLiteFeedLogStoreTests.swift`

**Interfaces:**
- Consumes: nichts Neues (nutzt bestehende `feed_logs`-Tabelle über `database.read`).
- Produces: `FeedLogStore.latestAttemptTimes() throws -> [String: Date]` — wird von Task 3 verwendet.

- [ ] **Step 1: Write the failing test**

In `FeedivoTests/SQLiteFeedLogStoreTests.swift`, neuen Testfall am Ende der
`struct SQLiteFeedLogStoreTests { ... }` (vor der schließenden `}`) ergänzen:

```swift
    @Test func latestAttemptTimesLiefertNeuestenZeitstempelJeFeed() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let logStore = FeedLogStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://one.example/feed.xml", title: "One"))
        try feedStore.save(FeedRecord(id: "feed-2", url: "https://two.example/feed.xml", title: "Two"))
        try feedStore.save(FeedRecord(id: "feed-3", url: "https://three.example/feed.xml", title: "Three"))

        try logStore.append(FeedLogRecord(
            feedID: "feed-1",
            createdAt: Date(timeIntervalSince1970: 1_000),
            level: "info",
            message: "Alt"
        ))
        try logStore.append(FeedLogRecord(
            feedID: "feed-1",
            createdAt: Date(timeIntervalSince1970: 2_000),
            level: "error",
            message: "Neu, aber fehlgeschlagen"
        ))
        try logStore.append(FeedLogRecord(
            feedID: "feed-2",
            createdAt: Date(timeIntervalSince1970: 500),
            level: "info",
            message: "Einziger Versuch"
        ))

        let attemptTimes = try logStore.latestAttemptTimes()

        #expect(attemptTimes["feed-1"] == Date(timeIntervalSince1970: 2_000))
        #expect(attemptTimes["feed-2"] == Date(timeIntervalSince1970: 500))
        #expect(attemptTimes["feed-3"] == nil)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:'FeedivoTests/SQLiteFeedLogStoreTests/latestAttemptTimesLiefertNeuestenZeitstempelJeFeed()'`
Expected: FAIL — `value of type 'FeedLogStore' has no member 'latestAttemptTimes'`.

- [ ] **Step 3: Write minimal implementation**

In `Feedivo/Stores/FeedLogStore.swift`, neue Methode nach `func logs(feedID:limit:)` ergänzen:

```swift
    /// Letzter Abrufversuch je Feed — unabhängig vom Ergebnis (Erfolg, „Nicht
    /// geändert" ODER Fehler), da `SQLiteFeedRefreshService.refresh` in allen
    /// drei Fällen einen `FeedLogRecord` schreibt. Grundlage für
    /// `FeedRefreshThrottle` in `SQLiteFeedRefreshCoordinator` — eine
    /// gruppierte Query statt einer Einzelabfrage pro Feed (analog der
    /// `latest_feed_logs`-CTE in `FeedStore.sidebarFeeds()`).
    func latestAttemptTimes() throws -> [String: Date] {
        try database.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT feedID, MAX(createdAt) AS lastAttemptAt
                FROM feed_logs
                GROUP BY feedID
                """)
            var result: [String: Date] = [:]
            for row in rows {
                guard let feedID = row["feedID"] as String?,
                      let lastAttemptAt = row["lastAttemptAt"] as Date? else {
                    continue
                }
                result[feedID] = lastAttemptAt
            }
            return result
        }
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:'FeedivoTests/SQLiteFeedLogStoreTests'`
Expected: PASS (alle Tests der Suite grün, inkl. der drei bestehenden).

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Stores/FeedLogStore.swift FeedivoTests/SQLiteFeedLogStoreTests.swift
git commit -m "Feature: FeedLogStore.latestAttemptTimes() für Refresh-Throttling"
```

---

### Task 3: Throttle in `SQLiteFeedRefreshCoordinator.refreshAllFeeds` verdrahten

**Files:**
- Modify: `Feedivo/Services/SQLiteFeedRefreshCoordinator.swift`
- Test: `FeedivoTests/SQLiteFeedRefreshCoordinatorTests.swift`

**Interfaces:**
- Consumes: `FeedRefreshThrottle.shouldSkip(lastAttemptAt:now:minimumInterval:)` (Task 1), `FeedLogStore.latestAttemptTimes()` (Task 2).
- Produces: neues Feld `SQLiteFeedRefreshCoordinatorSummary.skippedFeedIDs: [UUID]` (Default `[]`), neue `init`-Parameter `now: @escaping () -> Date = Date.init` und `minimumRefreshInterval: TimeInterval = 9 * 60` auf `SQLiteFeedRefreshCoordinator`.

- [ ] **Step 1: Write the failing test**

In `FeedivoTests/SQLiteFeedRefreshCoordinatorTests.swift`, neuen Testfall vor
der schließenden `}` der `struct SQLiteFeedRefreshCoordinatorTests { ... }`
ergänzen (nach der bestehenden `private func feedStoreTest(...)`-Hilfsfunktion):

```swift
    @MainActor
    @Test func refreshAllFeedsUeberspringtFeedMitZuKurzZurueckliegendemVersuch() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let logStore = FeedLogStore(database: database)
        let recentlyAttemptedFeedID = UUID().uuidString
        let staleAttemptFeedID = UUID().uuidString
        let neverAttemptedFeedID = UUID().uuidString
        let now = Date(timeIntervalSince1970: 100_000)

        try feedStore.save(FeedRecord(id: recentlyAttemptedFeedID, url: "https://example.com/recent.xml", title: "Recent"))
        try feedStore.save(FeedRecord(id: staleAttemptFeedID, url: "https://example.com/stale.xml", title: "Stale"))
        try feedStore.save(FeedRecord(id: neverAttemptedFeedID, url: "https://example.com/never.xml", title: "Never"))

        try logStore.append(FeedLogRecord(
            feedID: recentlyAttemptedFeedID,
            createdAt: now.addingTimeInterval(-5 * 60),
            level: "info",
            message: "Nicht geändert"
        ))
        try logStore.append(FeedLogRecord(
            feedID: staleAttemptFeedID,
            createdAt: now.addingTimeInterval(-10 * 60),
            level: "info",
            message: "Nicht geändert"
        ))

        let coordinator = SQLiteFeedRefreshCoordinator(
            database: database,
            now: { now },
            fetcher: { _, _ in .notModified(FeedHTTPValidators(lastStatusCode: 304)) }
        )

        let summary = await coordinator.refreshAllFeeds([
            FeedRefreshSnapshot(id: UUID(uuidString: recentlyAttemptedFeedID) ?? UUID(), title: "Recent", url: "https://example.com/recent.xml"),
            FeedRefreshSnapshot(id: UUID(uuidString: staleAttemptFeedID) ?? UUID(), title: "Stale", url: "https://example.com/stale.xml"),
            FeedRefreshSnapshot(id: UUID(uuidString: neverAttemptedFeedID) ?? UUID(), title: "Never", url: "https://example.com/never.xml")
        ])

        #expect(summary.skippedFeedIDs == [UUID(uuidString: recentlyAttemptedFeedID)])
        #expect(summary.succeededFeedIDs.count == 2)
        #expect(try logStore.logs(feedID: recentlyAttemptedFeedID, limit: 10).count == 1)
        #expect(try logStore.logs(feedID: staleAttemptFeedID, limit: 10).count == 2)
        #expect(try logStore.logs(feedID: neverAttemptedFeedID, limit: 10).count == 1)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:'FeedivoTests/SQLiteFeedRefreshCoordinatorTests/refreshAllFeedsUeberspringtFeedMitZuKurzZurueckliegendemVersuch()'`
Expected: FAIL — Compile-Fehler `incorrect argument label in call (have 'database:now:fetcher:', expected 'database:batchSize:ruleSnapshots:enrichArticleImages:fetcher:')` (Parameter `now:` existiert noch nicht) bzw. nach Anpassen des Aufrufs `value of type 'SQLiteFeedRefreshCoordinatorSummary' has no member 'skippedFeedIDs'`.

- [ ] **Step 3: Write minimal implementation**

In `Feedivo/Services/SQLiteFeedRefreshCoordinator.swift`:

Summary-Struct erweitern:

```swift
struct SQLiteFeedRefreshCoordinatorSummary: Equatable {
    var notificationResults: [FeedRefreshNotificationResult]
    var ruleNotificationResults: [RuleNotificationResult]
    var failedFeedTitles: [String]
    var failedFeedIDs: [UUID]
    var succeededFeedIDs: [UUID]
    var skippedFeedIDs: [UUID] = []
}
```

`init` um `now`/`minimumRefreshInterval` erweitern (VOR `enrichArticleImages`
einfügen — `fetcher` muss laut bestehendem Kommentar der letzte Parameter
bleiben):

```swift
struct SQLiteFeedRefreshCoordinator {
    private let database: FeedivoDatabase
    private let ruleSnapshots: [RuleEngine.RuleSnapshot]
    private let batchSize: Int
    private let now: () -> Date
    private let minimumRefreshInterval: TimeInterval
    private let fetcher: SQLiteFeedRefreshService.Fetcher
    private let enrichArticleImages: SQLiteFeedRefreshService.ArticleImageEnricher

    init(
        database: FeedivoDatabase,
        batchSize: Int = FeedViewModel.maxConcurrentFeedRefreshes,
        ruleSnapshots: [RuleEngine.RuleSnapshot] = [],
        now: @escaping () -> Date = Date.init,
        minimumRefreshInterval: TimeInterval = 9 * 60,
        // Standard bewusst ein No-Op — dieselbe Begründung wie in
        // SQLiteFeedRefreshService: schützt SQLiteFeedRefreshCoordinatorTests
        // vor unbeabsichtigten echten Netzwerkaufrufen. Der produktive Aufrufer
        // (SQLiteFeedActionService) setzt den echten Wert explizit.
        //
        // WICHTIG: steht bewusst VOR `fetcher` — `fetcher` muss der letzte
        // Parameter bleiben, weil bestehende Tests ihn per Trailing-Closure
        // setzen. Siehe ausführliche Begründung in SQLiteFeedRefreshService.swift.
        enrichArticleImages: @escaping SQLiteFeedRefreshService.ArticleImageEnricher = { $0 },
        fetcher: @escaping SQLiteFeedRefreshService.Fetcher = { urlString, validators in
            switch try await FeedService.fetchFeedConditionally(urlString: urlString, validators: validators) {
            case .updated(let feed, let validators):
                return .updated(feed, validators)
            case .notModified(let validators):
                return .notModified(validators)
            }
        }
    ) {
        self.database = database
        self.ruleSnapshots = ruleSnapshots
        self.batchSize = batchSize
        self.now = now
        self.minimumRefreshInterval = minimumRefreshInterval
        self.fetcher = fetcher
        self.enrichArticleImages = enrichArticleImages
    }
```

`refreshAllFeeds` um die Throttle-Filterung erweitern (direkt nach der
bestehenden `guard !snapshots.isEmpty else { ... }`-Zeile, vor der
Deklaration von `notificationResults`):

```swift
    func refreshAllFeeds(
        _ snapshots: [FeedRefreshSnapshot]
    ) async -> SQLiteFeedRefreshCoordinatorSummary {
        guard !snapshots.isEmpty else {
            return SQLiteFeedRefreshCoordinatorSummary(
                notificationResults: [],
                ruleNotificationResults: [],
                failedFeedTitles: [],
                failedFeedIDs: [],
                succeededFeedIDs: []
            )
        }

        // Mindestabstand pro Feed (NetNewsWire-Vergleich, 2026-07-27):
        // feed_logs wird bei JEDEM Abrufversuch geschrieben (Erfolg, „Nicht
        // geändert" UND Fehler) — im Unterschied zu feeds.lastRefreshedAt,
        // das nur bei Erfolg gesetzt wird und in der UI als „Zuletzt
        // aktualisiert" erscheint. Ein Lesefehler hier führt bewusst NICHT
        // dazu, dass gar nicht refresht wird (fail open) — refreshAllFeeds
        // selbst hat keine throws-Signatur.
        let lastAttemptTimes = (try? FeedLogStore(database: database).latestAttemptTimes()) ?? [:]
        let currentDate = now()
        var eligibleSnapshots: [FeedRefreshSnapshot] = []
        var skippedFeedIDs: [UUID] = []
        for snapshot in snapshots {
            let lastAttemptAt = lastAttemptTimes[snapshot.id.uuidString]
            if FeedRefreshThrottle.shouldSkip(
                lastAttemptAt: lastAttemptAt,
                now: currentDate,
                minimumInterval: minimumRefreshInterval
            ) {
                skippedFeedIDs.append(snapshot.id)
            } else {
                eligibleSnapshots.append(snapshot)
            }
        }

        guard !eligibleSnapshots.isEmpty else {
            return SQLiteFeedRefreshCoordinatorSummary(
                notificationResults: [],
                ruleNotificationResults: [],
                failedFeedTitles: [],
                failedFeedIDs: [],
                succeededFeedIDs: [],
                skippedFeedIDs: skippedFeedIDs
            )
        }

        var notificationResults: [FeedRefreshNotificationResult] = []
        var ruleNotificationResults: [RuleNotificationResult] = []
        var failedFeedTitles: [String] = []
        var failedFeedIDs: [UUID] = []
        var succeededFeedIDs: [UUID] = []

        for batch in batches(eligibleSnapshots, size: batchSize) {
```

(Der Rest der Batch-Schleife bleibt unverändert — nur `snapshots` in der
`for batch in batches(snapshots, size: batchSize)`-Zeile wird zu
`eligibleSnapshots`, siehe oben.)

Der finale `return`-Aufruf am Ende der Funktion bekommt zusätzlich
`skippedFeedIDs: skippedFeedIDs`:

```swift
        return SQLiteFeedRefreshCoordinatorSummary(
            notificationResults: notificationResults,
            ruleNotificationResults: ruleNotificationResults,
            failedFeedTitles: failedFeedTitles,
            failedFeedIDs: failedFeedIDs,
            succeededFeedIDs: succeededFeedIDs,
            skippedFeedIDs: skippedFeedIDs
        )
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:'FeedivoTests/SQLiteFeedRefreshCoordinatorTests'`
Expected: PASS (alle drei Tests der Suite grün, inkl. der zwei bestehenden —
diese dürfen sich nicht ändern, da `now`/`minimumRefreshInterval` Defaults
haben und die dort verwendeten Feeds keine `feed_logs`-Einträge vor dem Aufruf
haben, also nie gedrosselt werden).

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Services/SQLiteFeedRefreshCoordinator.swift FeedivoTests/SQLiteFeedRefreshCoordinatorTests.swift
git commit -m "Feature: Mindestabstand pro Feed beim Refresh-All (FeedRefreshThrottle verdrahtet)"
```

---

### Task 4: `rebuildAllFeedUnreadCounts()` auf gruppierte CTE umstellen

**Files:**
- Modify: `Feedivo/Services/SQLiteUnreadCountService.swift`
- Test: `FeedivoTests/SQLiteUnreadCountServiceTests.swift` (kein neuer Test —
  reiner Refactor, bestehender Test `rebuildAllFeedUnreadCountsKorrigiertAlleFeedZaehler`
  ist der Regressions-Nachweis)

**Interfaces:**
- Consumes: nichts Neues.
- Produces: keine Signaturänderung — `rebuildAllFeedUnreadCounts() throws -> [String: Int]` bleibt exakt gleich, nur die interne Query-Strategie ändert sich.

- [ ] **Step 1: Baseline — bestehenden Test grün laufen lassen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:'FeedivoTests/SQLiteUnreadCountServiceTests'`
Expected: PASS (alle 5 bestehenden Tests grün — das ist die Baseline vor dem Refactor).

- [ ] **Step 2: Refactor durchführen**

In `Feedivo/Services/SQLiteUnreadCountService.swift` die bestehende
`rebuildAllFeedUnreadCounts()`-Methode ersetzen:

```swift
    @discardableResult
    func rebuildAllFeedUnreadCounts() throws -> [String: Int] {
        try database.write { db in
            let feedIDs = try String.fetchAll(db, sql: "SELECT id FROM feeds ORDER BY id COLLATE NOCASE")
            let groupedCounts = try Self.groupedUnreadCounts(db: db)
            var counts: [String: Int] = [:]
            for feedID in feedIDs {
                let unreadCount = groupedCounts[feedID] ?? 0
                try db.execute(
                    sql: """
                        UPDATE feeds
                        SET unreadCount = ?, updatedAt = ?
                        WHERE id = ?
                        """,
                    arguments: [unreadCount, Date(), feedID]
                )
                counts[feedID] = unreadCount
            }
            return counts
        }
    }
```

Direkt danach (als neue private static Methode, z. B. vor `rebuildFeedUnreadCount(feedID:db:)`) ergänzen:

```swift
    /// Ungelesen-Zähler für ALLE Feeds in einer einzigen gruppierten Query
    /// statt einer korrelierten Subquery pro Feed — dasselbe Muster wie die
    /// `unread_counts`-CTE in `FeedStore.sidebarFeeds()` (Fix vom
    /// 2026-07-16, 10,9s auf ~2ms bei 500 Feeds gesenkt). Feeds ohne
    /// ungelesene Artikel tauchen hier NICHT auf — der Aufrufer muss für sie
    /// selbst auf 0 zurückfallen.
    private static func groupedUnreadCounts(db: Database) throws -> [String: Int] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT a.feedID AS feedID, COUNT(*) AS unreadCount
            FROM article_statuses s
            JOIN articles a ON a.id = s.articleID
            WHERE s.isRead = 0 AND s.isHidden = 0
            GROUP BY a.feedID
            """)
        var result: [String: Int] = [:]
        for row in rows {
            guard let feedID = row["feedID"] as String? else { continue }
            result[feedID] = row["unreadCount"] as Int? ?? 0
        }
        return result
    }
```

- [ ] **Step 3: Run test to verify it still passes**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:'FeedivoTests/SQLiteUnreadCountServiceTests'`
Expected: PASS (alle 5 Tests weiterhin grün — insbesondere
`rebuildAllFeedUnreadCountsKorrigiertAlleFeedZaehler`, die exakt das
Zwei-Feeds-mit-unterschiedlichen-Zählern-Szenario abdeckt).

- [ ] **Step 4: Commit**

```bash
git add Feedivo/Services/SQLiteUnreadCountService.swift
git commit -m "Perf: rebuildAllFeedUnreadCounts() nutzt gruppierte CTE statt N Subqueries"
```

---

### Task 5: `FaviconDiscoveryCoordinator` — Single-Flight-Dedup-Actor

**Files:**
- Create: `Feedivo/Services/FaviconDiscoveryCoordinator.swift`
- Test: `FeedivoTests/FaviconDiscoveryCoordinatorTests.swift`

**Interfaces:**
- Produces: `actor FaviconDiscoveryCoordinator` mit `func discover(siteURL: URL, using discover: @escaping @Sendable (URL) async -> String? = { url in await FaviconService.discoverFaviconURL(siteURL: url) }) async -> String?` — wird von Task 6 verwendet.

- [ ] **Step 1: Write the failing test**

Neue Datei `FeedivoTests/FaviconDiscoveryCoordinatorTests.swift`:

```swift
import Foundation
import Testing
@testable import Feedivo

struct FaviconDiscoveryCoordinatorTests {
    @Test func discoverDedupliziertGleichzeitigeAnfragenFuerDieselbeSiteURL() async throws {
        let coordinator = FaviconDiscoveryCoordinator()
        let callCounter = FaviconDiscoveryCallCounter()
        let siteURL = try #require(URL(string: "https://example.com"))

        async let first: String? = coordinator.discover(siteURL: siteURL) { _ in
            await callCounter.increment()
            try? await Task.sleep(nanoseconds: 50_000_000)
            return "https://example.com/favicon.ico"
        }
        async let second: String? = coordinator.discover(siteURL: siteURL) { _ in
            await callCounter.increment()
            return "https://example.com/favicon.ico"
        }

        let results = await [first, second]

        #expect(results == ["https://example.com/favicon.ico", "https://example.com/favicon.ico"])
        #expect(await callCounter.count == 1)
    }

    @Test func discoverBehandeltVerschiedeneSiteURLsUnabhaengig() async throws {
        let coordinator = FaviconDiscoveryCoordinator()
        let callCounter = FaviconDiscoveryCallCounter()
        let firstSiteURL = try #require(URL(string: "https://one.example"))
        let secondSiteURL = try #require(URL(string: "https://two.example"))

        async let first: String? = coordinator.discover(siteURL: firstSiteURL) { _ in
            await callCounter.increment()
            return "https://one.example/favicon.ico"
        }
        async let second: String? = coordinator.discover(siteURL: secondSiteURL) { _ in
            await callCounter.increment()
            return "https://two.example/favicon.ico"
        }

        _ = await [first, second]

        #expect(await callCounter.count == 2)
    }
}

private actor FaviconDiscoveryCallCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:'FeedivoTests/FaviconDiscoveryCoordinatorTests'`
Expected: FAIL — `Cannot find 'FaviconDiscoveryCoordinator' in scope`.

- [ ] **Step 3: Write minimal implementation**

Neue Datei `Feedivo/Services/FaviconDiscoveryCoordinator.swift`:

```swift
import Foundation

/// Dedupliziert GLEICHZEITIG laufende Favicon-Discovery-Anfragen für dieselbe
/// siteURL (NetNewsWire-Vergleich, 2026-07-27) — z. B. wenn mehrere Feeds im
/// selben Refresh-All-Batch dieselbe Blog-Plattform teilen. Kein
/// Langzeit-Cache: Einträge werden direkt nach Abschluss entfernt, ein
/// späterer Aufruf löst wieder eine echte Anfrage aus. `FaviconService`
/// selbst bleibt bewusst zustandslos — dieser Actor ist der einzige
/// stateful Baustein für die Deduplizierung.
actor FaviconDiscoveryCoordinator {
    private var inFlight: [String: Task<String?, Never>] = [:]

    func discover(
        siteURL: URL,
        using discover: @escaping @Sendable (URL) async -> String? = { url in
            await FaviconService.discoverFaviconURL(siteURL: url)
        }
    ) async -> String? {
        let key = siteURL.absoluteString
        if let existingTask = inFlight[key] {
            return await existingTask.value
        }

        let task = Task { await discover(siteURL) }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        return result
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:'FeedivoTests/FaviconDiscoveryCoordinatorTests'`
Expected: PASS (2/2 Tests grün).

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Services/FaviconDiscoveryCoordinator.swift FeedivoTests/FaviconDiscoveryCoordinatorTests.swift
git commit -m "Feature: FaviconDiscoveryCoordinator dedupliziert gleichzeitige Favicon-Anfragen"
```

---

### Task 6: Favicon-Dedup in `SQLiteFeedRefreshCoordinator` verdrahten

**Files:**
- Modify: `Feedivo/Services/SQLiteFeedRefreshCoordinator.swift`
- Test: `FeedivoTests/SQLiteFeedRefreshCoordinatorTests.swift`

**Interfaces:**
- Consumes: `FaviconDiscoveryCoordinator` (Task 5), `SQLiteFeedRefreshService`s bestehender `discoverFaviconURL`-Konstruktorparameter (`FaviconFetcher = (URL) async -> String?`, siehe `Feedivo/Services/SQLiteFeedRefreshService.swift:21,42-44`).
- Produces: neuer `init`-Parameter `discoverFavicon: @escaping @Sendable (URL) async -> String? = { siteURL in await FaviconService.discoverFaviconURL(siteURL: siteURL) }` auf `SQLiteFeedRefreshCoordinator`.

- [ ] **Step 1: Write the failing test**

In `FeedivoTests/SQLiteFeedRefreshCoordinatorTests.swift`, neuen Testfall
ergänzen (nach dem in Task 3 hinzugefügten Test, vor der schließenden `}`):

```swift
    @MainActor
    @Test func refreshAllFeedsDedupliziertFaviconDiscoveryFuerDieselbeSiteURL() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let firstFeedID = UUID().uuidString
        let secondFeedID = UUID().uuidString
        try feedStore.save(FeedRecord(id: firstFeedID, url: "https://example.com/first.xml", title: "Feed 1"))
        try feedStore.save(FeedRecord(id: secondFeedID, url: "https://example.com/second.xml", title: "Feed 2"))

        let discoveryCounter = FaviconDiscoveryCallCounter()
        let coordinator = SQLiteFeedRefreshCoordinator(
            database: database,
            discoverFavicon: { _ in
                await discoveryCounter.increment()
                try? await Task.sleep(nanoseconds: 50_000_000)
                return "https://shared-site.example/favicon.ico"
            },
            fetcher: { url, _ in
                .updated(
                    ParsedFeed(
                        sourceURL: url,
                        title: "Feed",
                        description: nil,
                        siteURL: "https://shared-site.example",
                        articles: []
                    ),
                    FeedHTTPValidators(lastStatusCode: 200)
                )
            }
        )

        _ = await coordinator.refreshAllFeeds([
            FeedRefreshSnapshot(id: UUID(uuidString: firstFeedID) ?? UUID(), title: "Feed 1", url: "https://example.com/first.xml"),
            FeedRefreshSnapshot(id: UUID(uuidString: secondFeedID) ?? UUID(), title: "Feed 2", url: "https://example.com/second.xml")
        ])

        #expect(await discoveryCounter.count == 1)
        let firstFeed = try feedStore.feed(id: firstFeedID)
        let secondFeed = try feedStore.feed(id: secondFeedID)
        #expect(firstFeed?.faviconURL == "https://shared-site.example/favicon.ico")
        #expect(secondFeed?.faviconURL == "https://shared-site.example/favicon.ico")
    }
```

Am Ende derselben Datei, außerhalb der `struct SQLiteFeedRefreshCoordinatorTests { ... }`, ergänzen:

```swift
private actor FaviconDiscoveryCallCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:'FeedivoTests/SQLiteFeedRefreshCoordinatorTests/refreshAllFeedsDedupliziertFaviconDiscoveryFuerDieselbeSiteURL()'`
Expected: FAIL — `incorrect argument label in call (have 'database:discoverFavicon:fetcher:', expected ...)` (Parameter `discoverFavicon:` existiert noch nicht).

- [ ] **Step 3: Write minimal implementation**

In `Feedivo/Services/SQLiteFeedRefreshCoordinator.swift`:

Neues privates Property + `init`-Parameter ergänzen (VOR `enrichArticleImages`
einfügen, `fetcher` bleibt letzter Parameter):

```swift
struct SQLiteFeedRefreshCoordinator {
    private let database: FeedivoDatabase
    private let ruleSnapshots: [RuleEngine.RuleSnapshot]
    private let batchSize: Int
    private let now: () -> Date
    private let minimumRefreshInterval: TimeInterval
    private let faviconDiscoveryCoordinator = FaviconDiscoveryCoordinator()
    private let discoverFavicon: @Sendable (URL) async -> String?
    private let fetcher: SQLiteFeedRefreshService.Fetcher
    private let enrichArticleImages: SQLiteFeedRefreshService.ArticleImageEnricher

    init(
        database: FeedivoDatabase,
        batchSize: Int = FeedViewModel.maxConcurrentFeedRefreshes,
        ruleSnapshots: [RuleEngine.RuleSnapshot] = [],
        now: @escaping () -> Date = Date.init,
        minimumRefreshInterval: TimeInterval = 9 * 60,
        discoverFavicon: @escaping @Sendable (URL) async -> String? = { siteURL in
            await FaviconService.discoverFaviconURL(siteURL: siteURL)
        },
        enrichArticleImages: @escaping SQLiteFeedRefreshService.ArticleImageEnricher = { $0 },
        fetcher: @escaping SQLiteFeedRefreshService.Fetcher = { urlString, validators in
            switch try await FeedService.fetchFeedConditionally(urlString: urlString, validators: validators) {
            case .updated(let feed, let validators):
                return .updated(feed, validators)
            case .notModified(let validators):
                return .notModified(validators)
            }
        }
    ) {
        self.database = database
        self.ruleSnapshots = ruleSnapshots
        self.batchSize = batchSize
        self.now = now
        self.minimumRefreshInterval = minimumRefreshInterval
        self.discoverFavicon = discoverFavicon
        self.fetcher = fetcher
        self.enrichArticleImages = enrichArticleImages
    }
```

Innerhalb von `refreshAllFeeds`, in der `withTaskGroup`-Schleife, die
`group.addTask { [database, ruleSnapshots, fetcher, enrichArticleImages] in`-
Zeile um die beiden neuen Captures erweitern und die
`SQLiteFeedRefreshService`-Konstruktion um `discoverFaviconURL:` ergänzen:

```swift
                for snapshot in batch {
                    group.addTask { [database, ruleSnapshots, fetcher, enrichArticleImages, faviconDiscoveryCoordinator, discoverFavicon] in
                        do {
                            let feedID = snapshot.id.uuidString
                            let feedStore = FeedStore(database: database)
                            if try feedStore.feed(id: feedID) == nil {
                                try feedStore.save(
                                    FeedRecord(
                                        id: feedID,
                                        url: snapshot.url,
                                        title: snapshot.title
                                    )
                                )
                            }

                            let service = SQLiteFeedRefreshService(
                                database: database,
                                ruleSnapshots: ruleSnapshots,
                                discoverFaviconURL: { siteURL in
                                    await faviconDiscoveryCoordinator.discover(siteURL: siteURL, using: discoverFavicon)
                                },
                                enrichArticleImages: enrichArticleImages,
                                fetcher: fetcher
                            )
                            let result = try await service.refresh(feedID: feedID)
```

(Der Rest der Task-Closure bleibt unverändert.)

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:'FeedivoTests/SQLiteFeedRefreshCoordinatorTests'`
Expected: PASS (alle vier Tests der Suite grün — inkl. der beiden
ursprünglichen und dem in Task 3 ergänzten).

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Services/SQLiteFeedRefreshCoordinator.swift FeedivoTests/SQLiteFeedRefreshCoordinatorTests.swift
git commit -m "Perf: Favicon-Discovery beim Refresh-All über FaviconDiscoveryCoordinator dedupliziert"
```

---

### Task 7: Abschluss — voller Regressionslauf, Release-Build, CLAUDE.md

**Files:**
- Modify: `CLAUDE.md` (neuer Eintrag unter „Letzte Änderungen")

- [ ] **Step 1: Gezielter Regressionslauf über alle in diesem Plan berührten Suiten**

Run:
```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' \
  -parallel-testing-enabled NO \
  -only-testing:'FeedivoTests/FeedRefreshThrottleTests' \
  -only-testing:'FeedivoTests/SQLiteFeedLogStoreTests' \
  -only-testing:'FeedivoTests/SQLiteFeedRefreshCoordinatorTests' \
  -only-testing:'FeedivoTests/SQLiteUnreadCountServiceTests' \
  -only-testing:'FeedivoTests/FaviconDiscoveryCoordinatorTests' \
  -only-testing:'FeedivoTests/SQLiteFeedRefreshServiceTests'
```
Expected: `** TEST SUCCEEDED **`, keine Fehlschläge.

- [ ] **Step 2: Voller Build**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: CLAUDE.md ergänzen**

Neuen Eintrag unter „## Letzte Änderungen" (oberhalb des aktuell obersten
Eintrags) ergänzen, der kurz zusammenfasst: Refresh-Throttling (9 Min. via
`feed_logs`, nur Refresh-All), `rebuildAllFeedUnreadCounts()`-CTE-Fix,
Favicon-Single-Flight-Dedup — mit Verweis auf Spec
(`docs/superpowers/specs/2026-07-27-refresh-throttling-perf-nachzuegler-design.md`)
und diesen Plan. Format an die bestehenden Einträge in diesem Abschnitt
anlehnen (siehe z. B. den Eintrag vom 2026-07-27 zu den ersten beiden
Perf-Fixes direkt darunter).

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "Docs: Refresh-Throttling + Perf-Nachzügler in CLAUDE.md dokumentiert"
```
