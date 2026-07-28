# iCloud Sync Phase 2b Fix: Stabile Artikel-Identität für CloudKit-Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Behebt einen im Whole-Branch-Review von Phase 2b gefundenen kritischen Architekturfehler: `article_statuses.articleID` ist eine pro Gerät zufällig erzeugte UUID (Artikel werden nie synct, jedes Gerät entdeckt denselben RSS-Artikel unabhängig per eigenem Feed-Refresh und vergibt dabei eine eigene UUID). Ein `ArticleStatus`-`CKRecord`, das über diese lokale UUID geschlüsselt wird, kann auf einem zweiten Gerät NIE gefunden werden — Gelesen/Stern-Sync zwischen Geräten funktioniert dadurch faktisch nicht, jeder eingehende Status landet dauerhaft unreconciled in `orphaned_article_status_updates` und wird nach 90 Tagen kommentarlos verworfen.

**Architecture:** Neue, geräteübergreifend deterministische Identität `syncStableID` — ein SHA256-Hash aus `feedID` (bereits stabil, da Feeds per CloudKit-Sync-ID übernommen werden, nicht unabhängig neu erzeugt) + (`sourceID` ?? `link` ?? `titleHash`), exakt analog zur bereits bestehenden `ArticleIdentityHistoryRecord`-Identitätslogik (`ArticleStore.findExistingArticleID`/`findIdentityHistory`). Wird für JEDE neu eingefügte `article_statuses`-Zeile unconditional berechnet und gespeichert (nicht nur für berührte — das entkoppelt "hat eine stabile Identität" von "ist sync-relevant", was für eingehende Reconciliation unverzichtbar ist: der Empfänger muss eine STABLE-ID-basierte Zeile finden können, auch wenn ER selbst den Status nie berührt hat). `CloudSyncArticleStatusMapping` nutzt ab sofort `syncStableID` statt der lokalen `articleID` als `CKRecord.ID`-Basis — die bestehende Sparse-Sync-Eligibility (`statusSyncUpdatedAt IS NOT NULL`) bleibt unverändert, sie bestimmt weiterhin NUR, welche Zeilen tatsächlich synct werden, nicht wie sie identifiziert werden.

**Tech Stack:** Swift, GRDB (SQLite), CryptoKit (SHA256, bereits in `ArticleStore.swift` importiert und für `titleHash` genutzt), CloudKit, Swift Testing.

## Global Constraints

- `syncStableID` wird für JEDE neu eingefügte `article_statuses`-Zeile berechnet — unabhängig davon, ob der Status je "berührt" wurde. Die Sparse-Sync-Filterung (`statusSyncUpdatedAt IS NOT NULL`) bleibt die alleinige Grundlage dafür, WELCHE Zeilen tatsächlich synct/backfilled werden.
- `syncStableID = SHA256("\(feedID)|\(sourceID ?? link ?? titleHash)")` als Hex-String — exakt dieselbe Prioritätsreihenfolge (`sourceID` vor `link` vor `titleHash`) wie die bestehende `ArticleStore.findExistingArticleID`/`findIdentityHistory`-Logik, damit beide Identitätskonzepte konsistent bleiben.
- Neue Migration darf NIEMALS `.defaults(sql: "CURRENT_TIMESTAMP")` verwenden. `article_statuses.syncStableID` bekommt kein NOT-NULL-Constraint (nullable, kein Default) — Bestandszeilen werden per Swift-Loop im selben Migrationsschritt befüllt (analog zu `backfillRuleConditionGroupIndex`/`backfillFeedAndFolderSortIndex`), da SQLite selbst keine SHA256-Funktion hat.
- Bestehende Migrationen (inkl. v24/v25 aus derselben Phase) werden NIE nachträglich verändert — neue Migration als `v26` angehängt.
- `orphaned_article_status_updates.articleID` (Spaltenname bleibt unverändert, keine Schema-Änderung an dieser bereits gemergten Migration nötig) speichert ab sofort `syncStableID`-Werte statt lokaler `articleID`-Werte — reine Bedeutungsänderung des Inhalts, kein Migrationsschritt nötig.
- Kommentare im Code auf Deutsch (Projektkonvention). TDD: Test zuerst schreiben, Fehlschlag verifizieren, dann implementieren.
- Migrationstests immer gegen eine Tabelle mit mindestens einer vorab eingefügten Bestandszeile schreiben.

---

### Task 11: Migration v26 (`syncStableID`) + Berechnung beim Artikel-Insert + Reconciliation-Fix

**Files:**
- Modify: `Feedivo/Database/FeedivoDatabaseMigrator.swift` (neue Migration nach `v25_create_orphaned_article_status_updates`)
- Modify: `Feedivo/Database/Records/ArticleStatusRecord.swift` (neue Property `syncStableID`)
- Modify: `Feedivo/Stores/ArticleStore.swift:416-451` (Insert-Branch berechnet `syncStableID`; Reconciliation-Aufruf `applyOrphanedStatusUpdateIfPresent` matcht ab jetzt über `syncStableID` statt lokale `articleID`)
- Test: `FeedivoTests/FeedivoDatabaseMigratorTests.swift`
- Test: `FeedivoTests/SQLiteArticleStoreTests.swift`

**Interfaces:**
- Consumes: `ArticleStore.titleHash(_:) -> String` (bestehend, Zeile 622).
- Produces: `ArticleStatusRecord.syncStableID: String?` (vom Typ `String?`, nicht zu verwechseln mit `statusSyncUpdatedAt`). `static func CloudSyncArticleStatusMapping.stableRecordName(feedID:sourceID:link:titleHash:) -> String` — von Task 12 für ausgehende und eingehende Records genutzt. `ArticleStore.applyOrphanedStatusUpdateIfPresent(articleID:syncStableID:db:)` — Signatur erweitert um `syncStableID`, von Task 12 indirekt betroffen (nur Aufrufer in `upsert`, keine externen Konsumenten).

- [ ] **Step 1: Write the failing migration test**

In `FeedivoTests/FeedivoDatabaseMigratorTests.swift`, nach dem letzten bestehenden Test einfügen:

```swift
    @Test func migrationV26FuegtSyncStableIDHinzuUndBackfilledBestandszeilen() throws {
        let queue = try DatabaseQueue()
        try FeedivoDatabaseMigrator.migrator.migrate(queue, upTo: "v25_create_orphaned_article_status_updates")

        try queue.write { db in
            let now = Date()
            try db.execute(
                sql: """
                    INSERT INTO feeds (id, url, title, originalTitle, sortIndex, refreshIntervalMinutes, isNotificationEnabled, articleRetentionOverridesGlobalSetting, articleRetentionIsEnabled, articleRetentionDays, articleRetentionMinimumArticles, articleRetentionIncludesProtectedArticles, unreadCount, createdAt, updatedAt, configUpdatedAt)
                    VALUES ('feed-1', 'https://example.com/feed', 'Test', 'Test', 0, 30, 0, 0, 0, 90, 20, 0, 0, ?, ?, ?)
                    """,
                arguments: [now, now, now]
            )
            try db.execute(
                sql: """
                    INSERT INTO articles (id, feedID, sourceID, title, arrivedAt, updatedAt)
                    VALUES ('article-1', 'feed-1', 'guid-123', 'Titel', ?, ?)
                    """,
                arguments: [now, now]
            )
            try db.execute(
                sql: """
                    INSERT INTO article_statuses (articleID, isRead, isStarred, isArchived, isHidden, dateArrived)
                    VALUES ('article-1', 0, 0, 0, 0, ?)
                    """,
                arguments: [now]
            )
        }

        try FeedivoDatabaseMigrator.migrator.migrate(queue)

        let syncStableID = try queue.read { db in
            try String.fetchOne(db, sql: "SELECT syncStableID FROM article_statuses WHERE articleID = 'article-1'")
        }
        #expect(syncStableID != nil)
        #expect(syncStableID?.isEmpty == false)

        // Deterministisch: derselbe feedID+sourceID muss immer denselben Hash ergeben.
        let expected = CloudSyncArticleStatusMapping.stableRecordName(
            feedID: "feed-1",
            sourceID: "guid-123",
            link: nil,
            titleHash: ArticleStore.titleHash("Titel")
        )
        #expect(syncStableID == expected)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoDatabaseMigratorTests -parallel-testing-enabled NO`
Expected: FAIL — `no such column: syncStableID` bzw. `cannot find 'stableRecordName' in scope`.

- [ ] **Step 3: Add the stable-identity helper**

In `Feedivo/Services/CloudSync/CloudSyncArticleStatusMapping.swift`, direkt nach `static let recordType = "ArticleStatus"` einfügen:

```swift

    /// Geräteübergreifend deterministische Identität für einen Artikel-Status — Artikel
    /// selbst werden nie synct (jedes Gerät entdeckt denselben RSS-Artikel unabhängig per
    /// eigenem Feed-Refresh und vergibt dabei eine eigene, rein lokale UUID als
    /// `articles.id`). Diese Funktion liefert stattdessen einen aus inhaltlichen Merkmalen
    /// abgeleiteten Hash, der auf JEDEM Gerät identisch berechnet wird — exakt dieselbe
    /// Prioritätsreihenfolge (`sourceID` vor `link` vor `titleHash`) wie die bestehende
    /// `ArticleStore.findExistingArticleID`/`findIdentityHistory`-Identitätslogik, damit
    /// beide Konzepte konsistent bleiben. `feedID` ist bereits geräteübergreifend stabil,
    /// da Feeds per CloudKit-Sync-ID übernommen werden (Phase 2a), nicht unabhängig neu
    /// erzeugt.
    static func stableRecordName(feedID: String, sourceID: String?, link: String?, titleHash: String) -> String {
        let identityComponent = sourceID ?? link ?? titleHash
        let digest = SHA256.hash(data: Data("\(feedID)|\(identityComponent)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
```

Am Dateianfang `import CryptoKit` ergänzen (nach `import CloudKit`).

- [ ] **Step 4: Add `syncStableID` to `ArticleStatusRecord`**

In `Feedivo/Database/Records/ArticleStatusRecord.swift`, den kompletten Inhalt ersetzen durch:

```swift
import Foundation
import GRDB

struct ArticleStatusRecord: Codable, FetchableRecord, MutablePersistableRecord, Equatable, Sendable {
    static let databaseTableName = "article_statuses"

    var articleID: String
    var isRead: Bool
    var isStarred: Bool
    var isArchived: Bool
    var isHidden: Bool
    var readAt: Date?
    var starredAt: Date?
    var archivedAt: Date?
    var hiddenAt: Date?
    var dateArrived: Date
    /// Last-Write-Wins-Zeitstempel UND Sync-Eligibility-Filter für iCloud Sync Phase 2b —
    /// `nil` bedeutet "nie vom Nutzer bewusst verändert", bleibt außerhalb jeder
    /// Sync-Betrachtung. Siehe `CloudSyncArticleStatusMapping`.
    var statusSyncUpdatedAt: Date?
    /// Geräteübergreifend deterministische Identität (SHA256 aus feedID + sourceID/link/
    /// titleHash) — für JEDE Zeile gesetzt (unabhängig von statusSyncUpdatedAt), da eingehende
    /// Reconciliation eine lokale Zeile unabhängig davon finden muss, ob dieses Gerät den
    /// Status je selbst berührt hat. Siehe `CloudSyncArticleStatusMapping.stableRecordName`.
    var syncStableID: String?

    init(
        articleID: String,
        isRead: Bool = false,
        isStarred: Bool = false,
        isArchived: Bool = false,
        isHidden: Bool = false,
        readAt: Date? = nil,
        starredAt: Date? = nil,
        archivedAt: Date? = nil,
        hiddenAt: Date? = nil,
        dateArrived: Date = Date(),
        statusSyncUpdatedAt: Date? = nil,
        syncStableID: String? = nil
    ) {
        self.articleID = articleID
        self.isRead = isRead
        self.isStarred = isStarred
        self.isArchived = isArchived
        self.isHidden = isHidden
        self.readAt = readAt
        self.starredAt = starredAt
        self.archivedAt = archivedAt
        self.hiddenAt = hiddenAt
        self.dateArrived = dateArrived
        self.statusSyncUpdatedAt = statusSyncUpdatedAt
        self.syncStableID = syncStableID
    }
}
```

- [ ] **Step 5: Add the migration with Swift-side backfill**

In `Feedivo/Database/FeedivoDatabaseMigrator.swift`, direkt nach der `v25_create_orphaned_article_status_updates`-Migration (vor `return migrator`), einfügen:

```swift
        migrator.registerMigration("v26_add_article_status_sync_stable_id") { database in
            // Nullable, kein Default — SQLite hat keine SHA256-Funktion, daher wird die
            // Spalte hier per ALTER TABLE angelegt und Bestandszeilen anschließend per
            // Swift-Loop befüllt (analog zu backfillRuleConditionGroupIndex/
            // backfillFeedAndFolderSortIndex weiter unten in dieser Datei). Siehe Design-
            // Begründung in CloudSyncArticleStatusMapping.stableRecordName.
            try database.alter(table: "article_statuses") { table in
                table.add(column: "syncStableID", .text)
            }
            try database.create(index: "idx_article_statuses_sync_stable_id", on: "article_statuses", columns: ["syncStableID"])

            try backfillArticleStatusSyncStableID(database)
        }
```

Direkt nach der bereits bestehenden `private static func backfillFeedAndFolderSortIndex(_ database: Database) throws { ... }`-Funktion (irgendwo weiter unten in derselben Datei — mit `grep -n "private static func backfill"` die bestehenden Backfill-Helfer lokalisieren und diese neue Funktion in denselben Stil/Bereich einfügen) folgende neue private Funktion ergänzen:

```swift
    /// Berechnet `syncStableID` für ALLE bestehenden `article_statuses`-Zeilen (Migration
    /// v26) — pro Zeile ein Join gegen `articles` für `feedID`/`sourceID`/`link`/`title`,
    /// dieselbe Priorisierung wie `CloudSyncArticleStatusMapping.stableRecordName`.
    private static func backfillArticleStatusSyncStableID(_ database: Database) throws {
        struct Row: FetchableRecord {
            let articleID: String
            let feedID: String
            let sourceID: String?
            let link: String?
            let title: String

            init(row: GRDB.Row) throws {
                articleID = row["articleID"]
                feedID = row["feedID"]
                sourceID = row["sourceID"]
                link = row["link"]
                title = row["title"]
            }
        }

        let rows = try Row.fetchAll(database, sql: """
            SELECT s.articleID AS articleID, a.feedID AS feedID, a.sourceID AS sourceID, a.link AS link, a.title AS title
            FROM article_statuses s
            JOIN articles a ON a.id = s.articleID
            """)

        for row in rows {
            let stableID = CloudSyncArticleStatusMapping.stableRecordName(
                feedID: row.feedID,
                sourceID: row.sourceID,
                link: row.link,
                titleHash: ArticleStore.titleHash(row.title)
            )
            try database.execute(
                sql: "UPDATE article_statuses SET syncStableID = ? WHERE articleID = ?",
                arguments: [stableID, row.articleID]
            )
        }
    }
```

- [ ] **Step 6: Run migration test to verify it passes**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoDatabaseMigratorTests -parallel-testing-enabled NO`
Expected: PASS (alle Tests der Datei)

- [ ] **Step 7: Write the failing test for insert-time computation + reconciliation**

In `FeedivoTests/SQLiteArticleStoreTests.swift`, am Ende der Test-Struct ergänzen:

```swift
    @Test func upsertBerechnetSyncStableIDFuerNeuenArtikel() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try FeedStore(database: database).save(FeedRecord(id: "feed-1", url: "https://example.com/feed", title: "Feed"))

        let articleID = try ArticleStore(database: database).upsert(
            ArticleUpsertInput(feedID: "feed-1", sourceID: "guid-abc", title: "Titel")
        )

        let status = try ArticleStatusStore(database: database).status(articleID: articleID)
        let expected = CloudSyncArticleStatusMapping.stableRecordName(
            feedID: "feed-1",
            sourceID: "guid-abc",
            link: nil,
            titleHash: ArticleStore.titleHash("Titel")
        )
        #expect(status?.syncStableID == expected)
    }

    @Test func upsertWendetVerwaistenStatusUeberSyncStableIDAn() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try FeedStore(database: database).save(FeedRecord(id: "feed-1", url: "https://example.com/feed", title: "Feed"))
        let stableID = CloudSyncArticleStatusMapping.stableRecordName(
            feedID: "feed-1",
            sourceID: "guid-xyz",
            link: nil,
            titleHash: ArticleStore.titleHash("Anderer Titel")
        )
        try database.write { db in
            var orphan = OrphanedArticleStatusUpdateRecord(
                articleID: stableID,
                isRead: true,
                isStarred: true,
                readAt: Date(timeIntervalSince1970: 100),
                starredAt: Date(timeIntervalSince1970: 200),
                receivedAt: Date(timeIntervalSince1970: 300)
            )
            try orphan.insert(db)
        }

        // Simuliert ein zweites, unabhängiges Gerät: derselbe logische Artikel (gleicher
        // feedID+sourceID), aber der Upsert-Aufruf selbst vergibt intern eine FRISCHE,
        // von der wartenden Orphan-Zeile komplett unabhängige lokale articleID-UUID —
        // genau das Szenario, das den ursprünglichen Bug ausmachte.
        let articleID = try ArticleStore(database: database).upsert(
            ArticleUpsertInput(feedID: "feed-1", sourceID: "guid-xyz", title: "Anderer Titel")
        )

        let status = try ArticleStatusStore(database: database).status(articleID: articleID)
        #expect(status?.isRead == true)
        #expect(status?.isStarred == true)
        #expect(status?.syncStableID == stableID)

        let orphan = try database.read { db in
            try OrphanedArticleStatusUpdateRecord.fetchOne(db, key: stableID)
        }
        #expect(orphan == nil)
    }
```

- [ ] **Step 8: Run test to verify it fails**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteArticleStoreTests -parallel-testing-enabled NO`
Expected: FAIL — `syncStableID` bleibt `nil` (noch nirgends berechnet); zweiter Test schlägt fehl, weil `applyOrphanedStatusUpdateIfPresent` noch über die (hier bewusst unterschiedliche) lokale `articleID` statt über `syncStableID` sucht.

- [ ] **Step 9: Wire computation + fix reconciliation lookup in `ArticleStore.upsert`**

In `Feedivo/Stores/ArticleStore.swift`, den Block von Zeile 416 bis 451 (`let articleID = UUID().uuidString` bis zum Ende der Methode `upsert(_:db:)`) ersetzen durch:

```swift
        let articleID = UUID().uuidString
        var article = ArticleRecord(
            id: articleID,
            feedID: input.feedID,
            sourceID: sourceID,
            link: link,
            title: input.title,
            summary: input.summary,
            content: input.content,
            imageURL: input.imageURL,
            author: input.author,
            publishedAt: input.publishedAt,
            arrivedAt: input.arrivedAt,
            updatedAt: Date(),
            estimatedReadingMinutes: input.estimatedReadingMinutes
        )
        try article.insert(db)

        let syncStableID = CloudSyncArticleStatusMapping.stableRecordName(
            feedID: input.feedID,
            sourceID: sourceID,
            link: link,
            titleHash: Self.titleHash(input.title)
        )
        var status = ArticleStatusRecord(
            articleID: articleID,
            isRead: history?.isRead ?? false,
            isStarred: history?.isStarred ?? false,
            isArchived: history?.isArchived ?? false,
            isHidden: history?.isHidden ?? false,
            readAt: history?.readAt,
            starredAt: history?.starredAt,
            archivedAt: history?.archivedAt,
            hiddenAt: history?.hiddenAt,
            dateArrived: history?.firstSeenAt ?? input.arrivedAt,
            syncStableID: syncStableID
        )
        try status.insert(db)
        try Self.applyOrphanedStatusUpdateIfPresent(articleID: articleID, syncStableID: syncStableID, db: db)
        try saveIdentityHistory(forArticleID: articleID, input: input, status: status, db: db)

        return .inserted(articleID: articleID)
    }

    /// Übernimmt einen wartenden, verwaisten Artikelstatus (iCloud Sync Phase 2b) — ein
    /// Status, der per iCloud ankam, BEVOR der zugehörige Artikel lokal existierte. Läuft
    /// direkt nach dem Insert der frischen `article_statuses`-Zeile, in derselben
    /// Transaktion. Sucht über `syncStableID` (geräteübergreifend deterministisch), NICHT
    /// über die lokale `articleID` (die ist auf jedem Gerät zufällig und deshalb für diesen
    /// Abgleich ungeeignet — siehe Design-Begründung in
    /// `CloudSyncArticleStatusMapping.stableRecordName`). `statusSyncUpdatedAt` wird bewusst
    /// auf `orphan.receivedAt` gesetzt (lokaler Empfangszeitpunkt des Orphans, nicht der
    /// ursprüngliche `CKRecord.modificationDate` des Absenders) — akzeptierte, dokumentierte
    /// Vereinfachung: ein Folgekonflikt auf genau diesem Status unmittelbar nach der
    /// Reconciliation könnte dadurch in einem schmalen Zeitfenster fälschlich "lokal
    /// gewinnt" statt "Server gewinnt" auflösen. Siehe Design-Spec
    /// docs/superpowers/specs/2026-07-25-icloud-sync-phase2b-design.md, Abschnitt 4.
    static func applyOrphanedStatusUpdateIfPresent(articleID: String, syncStableID: String, db: Database) throws {
        guard let orphan = try OrphanedArticleStatusUpdateRecord.fetchOne(db, key: syncStableID) else { return }

        try db.execute(
            sql: """
                UPDATE article_statuses
                SET isRead = ?, isStarred = ?, readAt = ?, starredAt = ?, statusSyncUpdatedAt = ?
                WHERE articleID = ?
                """,
            arguments: [orphan.isRead, orphan.isStarred, orphan.readAt, orphan.starredAt, orphan.receivedAt, articleID]
        )
        try orphan.delete(db)
    }
```

- [ ] **Step 10: Run tests to verify they pass**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteArticleStoreTests -parallel-testing-enabled NO`
Expected: PASS (alle Tests der Datei, inkl. der bereits bestehenden)

- [ ] **Step 11: Run the full migrator + article store suites to check for regressions**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoDatabaseMigratorTests -only-testing:FeedivoTests/SQLiteArticleStoreTests -only-testing:FeedivoTests/CloudSyncArticleStatusMappingTests -parallel-testing-enabled NO`
Expected: alle PASS (`CloudSyncArticleStatusMappingTests` wird in dieser Reihenfolge noch NICHT auf die neue `syncStableID`-Logik umgestellt sein — das ist Task 12 — daher bei etwaigen hier auftretenden Fehlschlägen NICHT versuchen, `CloudSyncArticleStatusMapping.swift`s bestehende `applyIncoming`/`allLocalIDs`/etc.-Methoden in DIESEM Task zu ändern; sollte dort etwas fehlschlagen, im Report als Konzern für Task 12 vermerken statt selbst zu beheben)

- [ ] **Step 12: Commit**

```bash
git add Feedivo/Database/FeedivoDatabaseMigrator.swift Feedivo/Database/Records/ArticleStatusRecord.swift Feedivo/Services/CloudSync/CloudSyncArticleStatusMapping.swift Feedivo/Stores/ArticleStore.swift FeedivoTests/FeedivoDatabaseMigratorTests.swift FeedivoTests/SQLiteArticleStoreTests.swift
git commit -m "Fix: Migration v26 + syncStableID-Berechnung beim Artikel-Insert (iCloud Sync Phase 2b Stable-Identity-Fix Task 11)"
```

---

### Task 12: `CloudSyncArticleStatusMapping` auf `syncStableID` als CloudKit-Identität umstellen

**Files:**
- Modify: `Feedivo/Services/CloudSync/CloudSyncArticleStatusMapping.swift` (kompletter Umbau von `makeCKRecord`, `applyIncoming`, `applyIncomingDeletion`, `localUpdatedAt`, `allLocalIDs`, `enqueueDeletionIfSynced`)
- Modify: `Feedivo/Stores/ArticleStatusStore.swift` (neue Methode `status(syncStableID:)`)
- Test: `FeedivoTests/CloudSyncArticleStatusMappingTests.swift`

**Interfaces:**
- Consumes: `CloudSyncArticleStatusMapping.stableRecordName(feedID:sourceID:link:titleHash:)` (Task 11), `ArticleStatusRecord.syncStableID: String?` (Task 11).
- Produces: `ArticleStatusStore.status(syncStableID: String) throws -> ArticleStatusRecord?` — neue Lookup-Methode, analog zur bestehenden `status(articleID:)`.

- [ ] **Step 1: Write the failing tests**

In `FeedivoTests/CloudSyncArticleStatusMappingTests.swift`, den kompletten Inhalt ersetzen durch:

```swift
import Foundation
import CloudKit
import GRDB
import Testing
@testable import Feedivo

private func seedArticle(database: FeedivoDatabase, articleID: String = "article-1", feedID: String = "feed-1", sourceID: String = "article-1", title: String = "Titel") throws -> String {
    try FeedStore(database: database).save(FeedRecord(id: feedID, url: "https://example.com/\(feedID)", title: "Feed"))
    return try ArticleStore(database: database).upsert(
        ArticleUpsertInput(feedID: feedID, sourceID: sourceID, title: title, arrivedAt: Date(timeIntervalSince1970: 100))
    )
}

struct CloudSyncArticleStatusMappingTests {
    @Test func makeCKRecordMapptIsReadUndIsStarredUndNutztSyncStableIDAlsRecordID() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let articleID = try seedArticle(database: database)
        var status = try ArticleStatusStore(database: database).status(articleID: articleID)!
        status.isRead = true
        status.isStarred = true
        status.readAt = Date(timeIntervalSince1970: 100)
        status.starredAt = Date(timeIntervalSince1970: 200)

        let record = CloudSyncArticleStatusMapping.makeCKRecord(from: status)

        #expect(record.recordType == "ArticleStatus")
        #expect(record.recordID.recordName == status.syncStableID)
        #expect(record["isRead"] as? Bool == true)
        #expect(record["isStarred"] as? Bool == true)
        #expect(record["readAt"] as? Date == Date(timeIntervalSince1970: 100))
        #expect(record["starredAt"] as? Date == Date(timeIntervalSince1970: 200))
    }

    @Test func allLocalIDsListetSyncStableIDsNurBeruehrterStatusAuf() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let unberuehrtID = try seedArticle(database: database, articleID: "unberuehrt", sourceID: "s-unberuehrt")
        let beruehrtID = try seedArticle(database: database, articleID: "beruehrt", sourceID: "s-beruehrt")
        try ArticleStatusStore(database: database).setRead(true, articleID: beruehrtID, at: Date())
        let beruehrterStatus = try ArticleStatusStore(database: database).status(articleID: beruehrtID)!

        let ids = try CloudSyncArticleStatusMapping.allLocalIDs(database: database)

        #expect(ids == [beruehrterStatus.syncStableID])
        _ = unberuehrtID
    }

    @Test func makeCKRecordFromLocalIDLiefertNilFuerUnbekannteID() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        let record = try CloudSyncArticleStatusMapping.makeCKRecord(fromLocalID: "unbekannt-hash", existing: nil, database: database)

        #expect(record == nil)
    }

    @Test func localUpdatedAtLiefertStatusSyncUpdatedAtUeberSyncStableID() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let articleID = try seedArticle(database: database)
        try ArticleStatusStore(database: database).setRead(true, articleID: articleID, at: Date())
        let status = try ArticleStatusStore(database: database).status(articleID: articleID)!

        let localUpdatedAt = try CloudSyncArticleStatusMapping.localUpdatedAt(forLocalID: status.syncStableID!, database: database)

        #expect(localUpdatedAt != nil)
    }

    @Test func applyIncomingAktualisiertBestehendenArtikelStatusUeberSyncStableID() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let articleID = try seedArticle(database: database)
        let status = try ArticleStatusStore(database: database).status(articleID: articleID)!
        let record = CKRecord(recordType: "ArticleStatus", recordID: CloudSyncArticleStatusMapping.recordID(forLocalID: status.syncStableID!))
        record["isRead"] = true as CKRecordValue
        record["isStarred"] = false as CKRecordValue

        try CloudSyncArticleStatusMapping.applyIncoming(record, database: database)

        let updated = try ArticleStatusStore(database: database).status(articleID: articleID)
        #expect(updated?.isRead == true)
        #expect(updated?.isStarred == false)
    }

    @Test func applyIncomingSimuliertZweitesGeraetMitAndererLokalerArticleID() throws {
        // Zwei unabhängige "Geräte": beide kennen denselben logischen Artikel (gleicher
        // feedID+sourceID), aber jedes hat seine EIGENE lokale articleID-UUID — genau das
        // Szenario, das der ursprüngliche Bug nicht abdeckte. Ein von "Gerät A" gesendeter
        // Status muss auf "Gerät B" trotzdem ankommen.
        let deviceA = try FeedivoDatabase.inMemoryForTests()
        let deviceB = try FeedivoDatabase.inMemoryForTests()
        let articleIDOnA = try seedArticle(database: deviceA, articleID: "a-local-id", feedID: "feed-1", sourceID: "guid-shared", title: "Geteilter Titel")
        let articleIDOnB = try seedArticle(database: deviceB, articleID: "b-local-id", feedID: "feed-1", sourceID: "guid-shared", title: "Geteilter Titel")
        #expect(articleIDOnA != articleIDOnB)

        try ArticleStatusStore(database: deviceA).setRead(true, articleID: articleIDOnA, at: Date())
        let statusOnA = try ArticleStatusStore(database: deviceA).status(articleID: articleIDOnA)!
        let record = CloudSyncArticleStatusMapping.makeCKRecord(from: statusOnA)

        try CloudSyncArticleStatusMapping.applyIncoming(record, database: deviceB)

        let statusOnB = try ArticleStatusStore(database: deviceB).status(articleID: articleIDOnB)
        #expect(statusOnB?.isRead == true)
    }

    @Test func applyIncomingLegtVerwaistenEintragAnFuerUnbekanntesSyncStableID() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let record = CKRecord(recordType: "ArticleStatus", recordID: CloudSyncArticleStatusMapping.recordID(forLocalID: "unbekannt-hash"))
        record["isRead"] = true as CKRecordValue
        record["isStarred"] = false as CKRecordValue

        try CloudSyncArticleStatusMapping.applyIncoming(record, database: database)

        let orphan = try database.read { db in
            try OrphanedArticleStatusUpdateRecord.fetchOne(db, key: "unbekannt-hash")
        }
        #expect(orphan?.isRead == true)
        #expect(orphan?.isStarred == false)
    }

    @Test func applyIncomingDeletionSetztStatusAufDefaultsWennArtikelLokalNochExistiert() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let articleID = try seedArticle(database: database)
        try ArticleStatusStore(database: database).setRead(true, articleID: articleID, at: Date())
        let status = try ArticleStatusStore(database: database).status(articleID: articleID)!

        try CloudSyncArticleStatusMapping.applyIncomingDeletion(recordID: CloudSyncArticleStatusMapping.recordID(forLocalID: status.syncStableID!), database: database)

        let afterDeletion = try ArticleStatusStore(database: database).status(articleID: articleID)
        #expect(afterDeletion != nil)
        #expect(afterDeletion?.isRead == false)
        #expect(afterDeletion?.isStarred == false)
    }

    @Test func applyIncomingDeletionEntferntVerwaistenEintrag() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try database.write { db in
            var orphan = OrphanedArticleStatusUpdateRecord(articleID: "verwaist-hash", isRead: true, isStarred: false, readAt: nil, starredAt: nil, receivedAt: Date())
            try orphan.insert(db)
        }

        try CloudSyncArticleStatusMapping.applyIncomingDeletion(recordID: CloudSyncArticleStatusMapping.recordID(forLocalID: "verwaist-hash"), database: database)

        let orphan = try database.read { db in
            try OrphanedArticleStatusUpdateRecord.fetchOne(db, key: "verwaist-hash")
        }
        #expect(orphan == nil)
    }

    @Test func enqueueDeletionIfSyncedEnqueuedSyncStableIDNurFuerBeruehrteIDs() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let beruehrtID = try seedArticle(database: database, articleID: "beruehrt", sourceID: "s-beruehrt")
        let unberuehrtID = try seedArticle(database: database, articleID: "unberuehrt", sourceID: "s-unberuehrt")
        try ArticleStatusStore(database: database).setStarred(true, articleID: beruehrtID, at: Date())
        let beruehrterStatus = try ArticleStatusStore(database: database).status(articleID: beruehrtID)!
        UserDefaults.standard.set(true, forKey: CloudSyncSettings.isEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey) }

        try database.write { db in
            try CloudSyncArticleStatusMapping.enqueueDeletionIfSynced(articleIDs: [beruehrtID, unberuehrtID], db: db)
        }

        let pending = try CloudSyncPendingChangeStore(database: database).pendingChanges()
        #expect(pending.map(\.id) == [beruehrterStatus.syncStableID])
        #expect(pending.first?.changeType == .delete)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CloudSyncArticleStatusMappingTests -parallel-testing-enabled NO`
Expected: FAIL — mehrere Tests, da `CloudSyncArticleStatusMapping` noch über `articleID` statt `syncStableID` arbeitet.

- [ ] **Step 3: Add `ArticleStatusStore.status(syncStableID:)`**

In `Feedivo/Stores/ArticleStatusStore.swift`, direkt nach der bestehenden `func status(articleID: String) throws -> ArticleStatusRecord?`-Methode einfügen:

```swift

    /// Lookup über die geräteübergreifend stabile Identität (iCloud Sync Phase 2b) —
    /// Gegenstück zu `status(articleID:)` für den CloudSync-Layer, der eingehende Records
    /// nicht über die lokale `articleID` identifizieren kann.
    func status(syncStableID: String) throws -> ArticleStatusRecord? {
        try database.read { db in
            try ArticleStatusRecord.fetchOne(db, sql: "SELECT * FROM article_statuses WHERE syncStableID = ?", arguments: [syncStableID])
        }
    }
```

- [ ] **Step 4: Rewrite `CloudSyncArticleStatusMapping`**

In `Feedivo/Services/CloudSync/CloudSyncArticleStatusMapping.swift`, den kompletten Inhalt ersetzen durch:

```swift
import Foundation
import CloudKit
import CryptoKit
import GRDB

/// Mapping für die syncbare TEILMENGE der `article_statuses`-Tabelle — NUR `isRead`/
/// `isStarred` (inkl. `readAt`/`starredAt`) syncen. `isArchived`/`isHidden` bleiben bewusst
/// rein lokal (siehe Design-Spec
/// `docs/superpowers/specs/2026-07-25-icloud-sync-phase2b-design.md`, Abschnitt 1).
///
/// **Sparse Sync:** Anders als alle bisherigen Mappings umfasst `allLocalIDs` NICHT jede
/// Zeile der Tabelle, sondern nur die, deren `statusSyncUpdatedAt` gesetzt ist (der Nutzer
/// hat den Status je bewusst verändert) — siehe Abschnitt 3 der Design-Spec.
///
/// **Stabile Identität:** Die `CKRecord.ID` basiert auf `ArticleStatusRecord.syncStableID`
/// (ein aus `feedID`+`sourceID`/`link`/`titleHash` abgeleiteter Hash), NICHT auf der lokalen
/// `articleID` — Artikel selbst werden nie synct, jedes Gerät vergibt beim eigenen
/// Feed-Refresh eine eigene, zufällige `articles.id`-UUID für denselben logischen Artikel.
/// Siehe `stableRecordName` unten für die Herleitung.
enum CloudSyncArticleStatusMapping: CloudSyncRecordMapping {
    static let recordType = "ArticleStatus"

    /// Geräteübergreifend deterministische Identität für einen Artikel-Status — exakt
    /// dieselbe Prioritätsreihenfolge (`sourceID` vor `link` vor `titleHash`) wie die
    /// bestehende `ArticleStore.findExistingArticleID`/`findIdentityHistory`-Identitätslogik.
    /// `feedID` ist bereits geräteübergreifend stabil, da Feeds per CloudKit-Sync-ID
    /// übernommen werden (Phase 2a), nicht unabhängig neu erzeugt.
    static func stableRecordName(feedID: String, sourceID: String?, link: String?, titleHash: String) -> String {
        let identityComponent = sourceID ?? link ?? titleHash
        let digest = SHA256.hash(data: Data("\(feedID)|\(identityComponent)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Baut ein `CKRecord` aus einem `ArticleStatusRecord`. Setzt voraus, dass
    /// `status.syncStableID` bereits gesetzt ist — gilt für jede Zeile, die über
    /// `allLocalIDs`/`makeCKRecord(fromLocalID:)` erreicht wird, da diese Zeilen zwingend
    /// bereits eine berechnete `syncStableID` besitzen (jede `article_statuses`-Zeile bekommt
    /// sie beim Insert in `ArticleStore.upsert`, unabhängig vom Sync-Berührt-Status).
    static func makeCKRecord(from status: ArticleStatusRecord, existing: CKRecord? = nil) -> CKRecord {
        let record = existing ?? CKRecord(recordType: recordType, recordID: recordID(forLocalID: status.syncStableID!))
        record["isRead"] = status.isRead as CKRecordValue
        record["isStarred"] = status.isStarred as CKRecordValue
        record["readAt"] = status.readAt as CKRecordValue?
        record["starredAt"] = status.starredAt as CKRecordValue?
        return record
    }

    struct IncomingStatus {
        let isRead: Bool
        let isStarred: Bool
        let readAt: Date?
        let starredAt: Date?
    }

    static func incomingStatus(from ckRecord: CKRecord) -> IncomingStatus? {
        guard
            let isRead = ckRecord["isRead"] as? Bool,
            let isStarred = ckRecord["isStarred"] as? Bool
        else {
            return nil
        }
        return IncomingStatus(
            isRead: isRead,
            isStarred: isStarred,
            readAt: ckRecord["readAt"] as? Date,
            starredAt: ckRecord["starredAt"] as? Date
        )
    }

    // MARK: - CloudSyncRecordMapping

    /// `id` ist hier eine `syncStableID`, keine lokale `articleID`.
    static func makeCKRecord(fromLocalID id: String, existing: CKRecord?, database: FeedivoDatabase) throws -> CKRecord? {
        guard let status = try ArticleStatusStore(database: database).status(syncStableID: id) else { return nil }
        return makeCKRecord(from: status, existing: existing)
    }

    /// `record.recordID.recordName` ist die `syncStableID` des Absenders. Unterscheidet
    /// zwei Fälle: existiert lokal bereits eine `article_statuses`-Zeile mit dieser
    /// `syncStableID` (der Artikel wurde hier ebenfalls schon per Feed-Refresh entdeckt),
    /// wird sie direkt aktualisiert. Existiert noch keine (Feed auf diesem Gerät noch nicht
    /// aktualisiert), landet der Status in `orphaned_article_status_updates`, keyed über
    /// dieselbe `syncStableID` — wird erst angewendet, sobald der Artikel per
    /// `ArticleStore.upsert()` lokal ankommt und dabei dieselbe `syncStableID` berechnet
    /// (Task 11).
    static func applyIncoming(_ record: CKRecord, database: FeedivoDatabase) throws {
        guard let incoming = incomingStatus(from: record) else { return }
        let stableID = record.recordID.recordName
        let modificationDate = record.modificationDate ?? Date()

        try database.write { db in
            let localExists = try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM article_statuses WHERE syncStableID = ?)", arguments: [stableID]) ?? false

            if localExists {
                try db.execute(
                    sql: """
                        UPDATE article_statuses
                        SET isRead = ?, isStarred = ?, readAt = ?, starredAt = ?, statusSyncUpdatedAt = ?
                        WHERE syncStableID = ?
                        """,
                    arguments: [incoming.isRead, incoming.isStarred, incoming.readAt, incoming.starredAt, modificationDate, stableID]
                )
            } else {
                var orphan = OrphanedArticleStatusUpdateRecord(
                    articleID: stableID,
                    isRead: incoming.isRead,
                    isStarred: incoming.isStarred,
                    readAt: incoming.readAt,
                    starredAt: incoming.starredAt,
                    receivedAt: Date()
                )
                try orphan.save(db)
            }
        }
    }

    /// Setzt den lokalen Status auf Defaults zurück, statt die Zeile zu löschen — falls der
    /// Artikel lokal noch existiert, würde ein echtes `DELETE` die `article_statuses`-Zeile
    /// entfernen, obwohl `articles` die Zeile noch hat; jede Artikellisten-Abfrage nutzt
    /// aber einen INNER JOIN auf `article_statuses`, wodurch der Artikel unsichtbar würde,
    /// obwohl der Nutzer den Feed weiterhin abonniert hat (gefunden im Whole-Branch-Review
    /// von Phase 2b). Existiert lokal keine Zeile mit dieser `syncStableID`, ist das
    /// UPDATE ein No-Op — zusätzlich wird ein ggf. wartender Orphan-Eintrag entfernt.
    static func applyIncomingDeletion(recordID: CKRecord.ID, database: FeedivoDatabase) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE article_statuses
                    SET isRead = 0, isStarred = 0, readAt = NULL, starredAt = NULL, statusSyncUpdatedAt = NULL, syncStableID = NULL
                    WHERE syncStableID = ?
                    """,
                arguments: [recordID.recordName]
            )
            try db.execute(sql: "DELETE FROM orphaned_article_status_updates WHERE articleID = ?", arguments: [recordID.recordName])
        }
    }

    static func localUpdatedAt(forLocalID id: String, database: FeedivoDatabase) throws -> Date? {
        try ArticleStatusStore(database: database).status(syncStableID: id)?.statusSyncUpdatedAt
    }

    static func allLocalIDs(database: FeedivoDatabase) throws -> [String] {
        try database.read { db in
            try String.fetchAll(db, sql: """
                SELECT syncStableID FROM article_statuses
                WHERE statusSyncUpdatedAt IS NOT NULL AND syncStableID IS NOT NULL
                ORDER BY syncStableID
                """)
        }
    }

    /// Enqueued `.delete` für die `syncStableID` jeder `articleID` aus `articleIDs`, deren
    /// Status je synchronisiert wurde (`statusSyncUpdatedAt IS NOT NULL`) — No-Op für nie
    /// synchronisierte Zeilen und wenn iCloud Sync gerade deaktiviert ist. Aufrufer
    /// (Löschpropagierung, Tasks 7/8/9 der ursprünglichen Phase-2b-Implementierung)
    /// arbeiten mit lokalen `articleID`s (das ist, was sie beim Löschen kennen) — diese
    /// Methode übersetzt intern auf die für CloudKit relevante `syncStableID`.
    static func enqueueDeletionIfSynced(articleIDs: [String], db: Database) throws {
        guard CloudSyncSettings.isEnabled(), !articleIDs.isEmpty else { return }
        let placeholders = Array(repeating: "?", count: articleIDs.count).joined(separator: ", ")
        let syncedStableIDs = try String.fetchAll(
            db,
            sql: """
                SELECT syncStableID FROM article_statuses
                WHERE statusSyncUpdatedAt IS NOT NULL AND syncStableID IS NOT NULL AND articleID IN (\(placeholders))
                """,
            arguments: StatementArguments(articleIDs)
        )
        for stableID in syncedStableIDs {
            try CloudSyncPendingChangeStore.enqueue(db, recordType: recordType, recordName: stableID, changeType: .delete)
        }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CloudSyncArticleStatusMappingTests -parallel-testing-enabled NO`
Expected: PASS (alle 10 Tests der Datei)

- [ ] **Step 6: Run the full regression suite from the original Phase 2b tasks to check for cross-task breakage**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteArticleStatusStoreTests -only-testing:FeedivoTests/ArticleRetentionCleanupServiceTests -only-testing:FeedivoTests/SQLiteFeedArticleListStateTests -only-testing:FeedivoTests/SQLiteFeedStoreTests -only-testing:FeedivoTests/CloudSyncEngineRegistryTests -only-testing:FeedivoTests/OrphanedArticleStatusUpdateStoreTests -parallel-testing-enabled NO`
Expected: alle PASS (`SQLiteFeedArticleListStateTests` hat den bereits dokumentierten, vorbestehenden, unabhängigen Fehlschlag `listStateToggeltReadUndAktualisiertRows` — falls dieser einzelne Test fehlschlägt, ist das erwartet und KEIN neuer Regressionsfund; alle anderen Tests dieser Suiten müssen grün sein)

- [ ] **Step 7: Commit**

```bash
git add Feedivo/Services/CloudSync/CloudSyncArticleStatusMapping.swift Feedivo/Stores/ArticleStatusStore.swift FeedivoTests/CloudSyncArticleStatusMappingTests.swift
git commit -m "Fix: CloudSyncArticleStatusMapping nutzt syncStableID als CloudKit-Identität statt lokaler articleID (iCloud Sync Phase 2b Stable-Identity-Fix Task 12)"
```

---

### Task 13: Vollständiger Regressionslauf + Release-Build + CLAUDE.md-Dokumentation

**Files:**
- Modify: `CLAUDE.md` (neuer Gotcha-Eintrag zum gefundenen und behobenen Architekturfehler, plus Ergänzung des bereits bestehenden `SQLiteFeedArticleListStateTests`-Vorabfehlschlags um `listStateToggeltReadUndAktualisiertRows`)

**Interfaces:**
- Consumes: alle vorherigen Tasks.

- [ ] **Step 1: Gezielter Testlauf über alle Phase-2b-relevanten Suiten**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoDatabaseMigratorTests -only-testing:FeedivoTests/OrphanedArticleStatusUpdateStoreTests -only-testing:FeedivoTests/CloudSyncArticleStatusMappingTests -only-testing:FeedivoTests/CloudSyncEngineRegistryTests -only-testing:FeedivoTests/SQLiteArticleStatusStoreTests -only-testing:FeedivoTests/ArticleRetentionCleanupServiceTests -only-testing:FeedivoTests/SQLiteFeedStoreTests -only-testing:FeedivoTests/SQLiteArticleStoreTests -only-testing:FeedivoTests/SQLiteFeedArticleListStateTests -parallel-testing-enabled NO`
Expected: alle PASS bis auf den bereits bekannten, unabhängigen `listStateToggeltReadUndAktualisiertRows`-Fehlschlag.

- [ ] **Step 2: Release-Build**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -configuration Release`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: CLAUDE.md ergänzen**

In `CLAUDE.md`, im Abschnitt „Bekannte Gotchas & Fallstricke" (ganz oben, direkt nach der Überschrift, vor dem ersten bestehenden Eintrag) folgenden neuen Eintrag einfügen:

```markdown
- **`article_statuses.articleID` ist pro Gerät zufällig — eine iCloud-Sync-Identität, die
  direkt darauf aufbaut, kann geräteübergreifend NIE matchen:** Beim Whole-Branch-Review von
  iCloud Sync Phase 2b (Artikelstatus-Sync, 2026-07-25) fand der Reviewer einen kritischen
  Architekturfehler, den keiner der 9 Einzel-Task-Reviews sehen konnte: Artikel selbst werden
  in keiner Phase synct — jedes Gerät entdeckt denselben RSS-Artikel unabhängig per eigenem
  Feed-Refresh und vergibt dabei via `ArticleStore.upsert()` eine eigene, zufällige
  `UUID().uuidString` als `articles.id`. Der ursprüngliche `CloudSyncArticleStatusMapping`
  keyte den `ArticleStatus`-`CKRecord` direkt über diese lokale `articleID` — dadurch konnte
  ein von Gerät A hochgeladener Status auf Gerät B NIE gefunden werden (Gerät B hat denselben
  logischen Artikel unter einer anderen UUID), landete dauerhaft in
  `orphaned_article_status_updates` und wurde nach 90 Tagen kommentarlos verworfen.
  Gelesen/Stern-Sync zwischen zwei Geräten funktionierte dadurch faktisch nicht — trotz
  86/86 grüner Tests in allen 9 Einzel-Tasks, da jeder Test dieselbe In-Memory-DB mit
  derselben `articleID` auf "Sender"- und "Empfänger"-Seite nutzte und damit exakt die
  Falschannahme mit-testete. **Fix:** neue, aus `feedID`+`sourceID`/`link`/`titleHash`
  abgeleitete `syncStableID` (SHA256-Hash, siehe `CloudSyncArticleStatusMapping.
  stableRecordName`) — dieselbe Priorisierung wie die bereits bestehende
  `ArticleStore.findExistingArticleID`/`findIdentityHistory`-Identitätslogik, `feedID` ist
  bereits geräteübergreifend stabil (Feeds werden per CloudKit-Sync-ID übernommen, nicht
  unabhängig neu erzeugt). Wird für JEDE neu eingefügte `article_statuses`-Zeile berechnet
  (nicht nur berührte — sonst könnte ein Gerät, das einen Status nie selbst berührt hat,
  einen eingehenden Status trotzdem nicht zuordnen), Migration v26 backfillt Bestandszeilen
  per Swift-Loop (SQLite hat keine SHA256-Funktion). **Lehre:** Bei JEDEM künftigen
  Sync-Mapping für eine Tabelle, deren Zeilen auf MEHREREN Geräten unabhängig voneinander neu
  entstehen können (nicht nur auf einem Gerät erzeugt und dann verteilt, wie bei Tags/Feeds/
  Regeln), reicht die lokale Primärschlüssel-Spalte NICHT als `CKRecord.ID`-Basis — und Tests
  müssen das Zwei-Geräte-Szenario mit zwei UNABHÄNGIGEN In-Memory-Datenbanken und zwei
  UNTERSCHIEDLICHEN lokalen IDs für denselben logischen Datensatz abbilden, sonst bleibt
  genau diese Klasse von Fehlern für jeden Einzel-Task-Review unsichtbar.
```

Danach im bestehenden Eintrag zu den „Bekannten, dauerhaft vorbestehenden Testfehlschlägen" (Suche nach `FeedivoAppSceneConfigurationTests.swift`) den Satz zu den 2 flaky-unter-Last-Tests erweitern, sodass zusätzlich `listStateToggeltReadUndAktualisiertRows` in `SQLiteFeedArticleListStateTests.swift` als dritter, unabhängig vom iCloud-Sync-Phase-2b-Feature vorbestehender Fehlschlag genannt wird (per `git stash`-Baseline-Vergleich während Task 8 der ursprünglichen Phase-2b-Implementierung verifiziert).

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "Docs: Gotcha zum ArticleStatus-Sync-Identitätsfix + listStateToggeltReadUndAktualisiertRows als bekannter Vorabfehlschlag dokumentiert (iCloud Sync Phase 2b Stable-Identity-Fix Task 13)"
```
