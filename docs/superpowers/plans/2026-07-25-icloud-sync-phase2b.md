# iCloud Sync Phase 2b: Artikelstatus-Sync (Gelesen/Stern) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Synchronisiert `isRead`/`isStarred` (inkl. `readAt`/`starredAt`) über iCloud/CloudKit zwischen Geräten, über die bestehende Registry-basierte `CloudSyncEngine`-Architektur, ohne bei jedem App-Start zehntausende unberührte Artikel-Status-Zeilen zu backfillen.

**Architecture:** Neuer `CloudSyncArticleStatusMapping`-Typ (8. Eintrag in `CloudSyncEngine`s Registry), Sparse Sync über eine neue nullable `article_statuses.statusSyncUpdatedAt`-Spalte (nur "je berührte" Zeilen werden gesynct/backfilled), eine neue `orphaned_article_status_updates`-Tabelle fängt eingehende Status für lokal noch unbekannte Artikel ab und wendet sie an, sobald der Artikel per Feed-Refresh ankommt, kaskadenbewusste Löschpropagierung an drei bestehenden Löschpfaden.

**Tech Stack:** Swift, GRDB (SQLite), CloudKit (`CKSyncEngine`), Swift Testing (`@Test`/`#expect`, kein XCTest).

## Global Constraints

- Nur `isRead`/`isStarred` (inkl. `readAt`/`starredAt`) werden synchronisiert. `isArchived`/`isHidden` bleiben rein lokal.
- Neue Migration darf NIEMALS `.defaults(sql: "CURRENT_TIMESTAMP")` verwenden — SQLite lehnt das auf nicht-leeren Tabellen ab ("Cannot add a column with non-constant default"). `article_statuses.statusSyncUpdatedAt` bekommt bewusst GAR KEIN Default (nullable, kein `.notNull()`) statt `.defaults(to: Date())`, da NULL zusätzlich als Sync-Eligibility-Filter dient.
- Bestehende Migrationen werden NIE nachträglich verändert — neue Migration immer als neuer `migrator.registerMigration("vN_…")`-Block anhängen. Nächste freie Nummern: `v24`, `v25`.
- Jede neue `database.write`-Mutation, die eine Sync-relevante Änderung markiert, muss `CloudSyncSettings.isEnabled()` prüfen, bevor sie einen Pending-Change enqueued (Projektkonvention aus `TagStore`/`FeedStore`).
- Jede öffentliche Store-Mutation, die einen Pending-Change enqueued, ruft danach `CloudSyncEngine.notifyPendingChangesAvailable(database:)` auf (außerhalb der `database.write`-Transaktion).
- Migrationstests immer gegen eine Tabelle mit mindestens einer vorab eingefügten Bestandszeile schreiben, nicht nur gegen eine leere Tabelle.
- Kommentare im Code auf Deutsch (Projektkonvention).
- TDD: Test zuerst schreiben, Fehlschlag verifizieren, dann implementieren.

---

### Task 1: Migration v24 — `article_statuses.statusSyncUpdatedAt`

**Files:**
- Modify: `Feedivo/Database/FeedivoDatabaseMigrator.swift` (neue Migration nach `v23_add_feed_config_updated_at`, aktuell endend bei Zeile 479 vor `return migrator`)
- Modify: `Feedivo/Database/Records/ArticleStatusRecord.swift` (neue Property `statusSyncUpdatedAt`)
- Test: `FeedivoTests/FeedivoDatabaseMigratorTests.swift`

**Interfaces:**
- Produces: `ArticleStatusRecord.statusSyncUpdatedAt: Date?` (Default `nil`) — von allen Folge-Tasks als Last-Write-Wins-Zeitstempel und Sync-Eligibility-Filter genutzt.

- [ ] **Step 1: Write the failing migration test**

In `FeedivoTests/FeedivoDatabaseMigratorTests.swift`, direkt nach der letzten bestehenden `@Test func migrationV23...`-Methode (vor der schließenden `}` der `struct FeedivoDatabaseMigratorTests`), einfügen:

```swift
    @Test func migrationV24FuegtStatusSyncUpdatedAtHinzuUndLaesstBestandszeilenNull() throws {
        let queue = try DatabaseQueue()
        try FeedivoDatabaseMigrator.migrator.migrate(queue, upTo: "v23_add_feed_config_updated_at")

        try queue.write { db in
            let now = Date()
            try db.execute(
                sql: """
                    INSERT INTO feeds (id, url, title, originalTitle, sortIndex, refreshIntervalMinutes, isNotificationEnabled, articleRetentionOverridesGlobalSetting, articleRetentionIsEnabled, articleRetentionDays, articleRetentionMinimumArticles, articleRetentionIncludesProtectedArticles, unreadCount, createdAt, updatedAt)
                    VALUES ('feed-1', 'https://example.com/feed', 'Test', 'Test', 0, 30, 0, 0, 0, 90, 20, 0, 0, ?, ?)
                    """,
                arguments: [now, now]
            )
            try db.execute(
                sql: """
                    INSERT INTO articles (id, feedID, title, arrivedAt, updatedAt)
                    VALUES ('article-1', 'feed-1', 'Titel', ?, ?)
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

        let row = try queue.read { db in
            try Row.fetchOne(db, sql: "SELECT statusSyncUpdatedAt FROM article_statuses WHERE articleID = 'article-1'")
        }
        let statusSyncUpdatedAt: Date? = row?["statusSyncUpdatedAt"]
        #expect(statusSyncUpdatedAt == nil)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoDatabaseMigratorTests/migrationV24FuegtStatusSyncUpdatedAtHinzuUndLaesstBestandszeilenNull -parallel-testing-enabled NO`
Expected: FAIL — `SQLite error 1: no such column: statusSyncUpdatedAt` (die Spalte existiert noch nicht).

- [ ] **Step 3: Add the migration**

In `Feedivo/Database/FeedivoDatabaseMigrator.swift`, direkt nach dem Ende von `migrator.registerMigration("v23_add_feed_config_updated_at") { ... }` (vor `return migrator`), einfügen:

```swift
        migrator.registerMigration("v24_add_article_status_sync_updated_at") { database in
            // Bewusst OHNE Default (weder `.notNull()` noch `.defaults(...)`) — anders als
            // v22/v23. Diese Spalte dient nicht nur als Last-Write-Wins-Zeitstempel, sondern
            // gleichzeitig als Sync-Eligibility-Filter: NULL bedeutet "dieser Artikelstatus
            // wurde vom Nutzer nie bewusst verändert" und bleibt komplett außerhalb der
            // Sync-Betrachtung (Sparse Sync, siehe Design-Spec
            // docs/superpowers/specs/2026-07-25-icloud-sync-phase2b-design.md, Abschnitt 2).
            // Ein `.defaults(to: Date())` wie bei v22/v23 würde ALLE Bestandszeilen (auch
            // nie berührte) fälschlich als "berührt" markieren. NULL ist immer ein gültiges
            // Konstanten-Default, umgeht dadurch auch den bekannten
            // CURRENT_TIMESTAMP-Migrationscrash-Gotcha, ohne das Problem überhaupt erst zu
            // berühren.
            try database.alter(table: "article_statuses") { table in
                table.add(column: "statusSyncUpdatedAt", .datetime)
            }
        }
```

- [ ] **Step 4: Update `ArticleStatusRecord` to expose the new column**

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
        statusSyncUpdatedAt: Date? = nil
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
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoDatabaseMigratorTests/migrationV24FuegtStatusSyncUpdatedAtHinzuUndLaesstBestandszeilenNull -parallel-testing-enabled NO`
Expected: PASS

- [ ] **Step 6: Run the full migrator test suite to check for regressions**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoDatabaseMigratorTests -parallel-testing-enabled NO`
Expected: alle PASS

- [ ] **Step 7: Commit**

```bash
git add Feedivo/Database/FeedivoDatabaseMigrator.swift Feedivo/Database/Records/ArticleStatusRecord.swift FeedivoTests/FeedivoDatabaseMigratorTests.swift
git commit -m "Feature: Migration v24 fügt article_statuses.statusSyncUpdatedAt hinzu (iCloud Sync Phase 2b Task 1)"
```

---

### Task 2: Migration v25 — `orphaned_article_status_updates`

**Files:**
- Create: `Feedivo/Database/Records/OrphanedArticleStatusUpdateRecord.swift`
- Create: `Feedivo/Stores/OrphanedArticleStatusUpdateStore.swift`
- Modify: `Feedivo/Database/FeedivoDatabaseMigrator.swift` (neue Migration nach v24)
- Test: `FeedivoTests/FeedivoDatabaseMigratorTests.swift`
- Test: `FeedivoTests/OrphanedArticleStatusUpdateStoreTests.swift`

**Interfaces:**
- Consumes: nichts aus vorherigen Tasks.
- Produces: `OrphanedArticleStatusUpdateRecord` (GRDB-Record), `OrphanedArticleStatusUpdateStore.deleteOlderThan(_ cutoffDate: Date) throws -> Int` — von Task 6 genutzt. `OrphanedArticleStatusUpdateRecord` wird direkt (nicht über den Store) von Task 3 (`applyIncoming`) und Task 5 (Reconciliation-Hook) verwendet.

- [ ] **Step 1: Write the failing migration test**

In `FeedivoTests/FeedivoDatabaseMigratorTests.swift`, nach dem in Task 1 hinzugefügten Test einfügen:

```swift
    @Test func migrationV25ErstelltOrphanedArticleStatusUpdatesTabelle() throws {
        let queue = try DatabaseQueue()
        try FeedivoDatabaseMigrator.migrator.migrate(queue, upTo: "v24_add_article_status_sync_updated_at")

        try FeedivoDatabaseMigrator.migrator.migrate(queue)

        try queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO orphaned_article_status_updates (articleID, isRead, isStarred, readAt, starredAt, receivedAt)
                    VALUES ('article-unbekannt', 1, 0, ?, NULL, ?)
                    """,
                arguments: [Date(), Date()]
            )
        }

        let count = try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM orphaned_article_status_updates") ?? 0
        }
        #expect(count == 1)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoDatabaseMigratorTests/migrationV25ErstelltOrphanedArticleStatusUpdatesTabelle -parallel-testing-enabled NO`
Expected: FAIL — `SQLite error 1: no such table: orphaned_article_status_updates`

- [ ] **Step 3: Add the migration**

In `Feedivo/Database/FeedivoDatabaseMigrator.swift`, direkt nach der in Task 1 hinzugefügten `v24_add_article_status_sync_updated_at`-Migration (vor `return migrator`), einfügen:

```swift
        migrator.registerMigration("v25_create_orphaned_article_status_updates") { database in
            // Fängt eingehende Artikelstatus-Updates für Artikel ab, die lokal noch nicht
            // existieren (Artikel selbst werden nie synct — Feed-Refresh ist rein lokal).
            // KEIN Fremdschlüssel auf articles.id, das ist genau der Fall, den diese Tabelle
            // abfängt. Siehe Design-Spec
            // docs/superpowers/specs/2026-07-25-icloud-sync-phase2b-design.md, Abschnitt 4.
            try database.create(table: "orphaned_article_status_updates") { table in
                table.column("articleID", .text).primaryKey()
                table.column("isRead", .boolean).notNull()
                table.column("isStarred", .boolean).notNull()
                table.column("readAt", .datetime)
                table.column("starredAt", .datetime)
                table.column("receivedAt", .datetime).notNull()
            }
        }
```

- [ ] **Step 4: Run migration test to verify it passes**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoDatabaseMigratorTests/migrationV25ErstelltOrphanedArticleStatusUpdatesTabelle -parallel-testing-enabled NO`
Expected: PASS

- [ ] **Step 5: Create the GRDB record**

Create `Feedivo/Database/Records/OrphanedArticleStatusUpdateRecord.swift`:

```swift
import Foundation
import GRDB

/// Ein eingehender Artikelstatus (iCloud Sync Phase 2b), dessen zugehöriger Artikel lokal
/// noch nicht existiert. Wird beim Eintreffen des Artikels (`ArticleStore.upsert`) angewendet
/// und dann gelöscht — siehe `CloudSyncArticleStatusMapping.applyIncoming`.
struct OrphanedArticleStatusUpdateRecord: Codable, FetchableRecord, MutablePersistableRecord, Equatable, Sendable {
    static let databaseTableName = "orphaned_article_status_updates"

    var articleID: String
    var isRead: Bool
    var isStarred: Bool
    var readAt: Date?
    var starredAt: Date?
    /// Lokaler Empfangszeitpunkt (nicht der `CKRecord.modificationDate` des Absenders) —
    /// Grundlage für die spätere Bereinigung nie abgeholter Einträge, siehe
    /// `OrphanedArticleStatusUpdateStore.deleteOlderThan(_:)`.
    var receivedAt: Date
}
```

- [ ] **Step 6: Write the failing store test**

Create `FeedivoTests/OrphanedArticleStatusUpdateStoreTests.swift`:

```swift
import Foundation
import Testing
@testable import Feedivo

struct OrphanedArticleStatusUpdateStoreTests {
    @Test func deleteOlderThanEntferntNurAeltereEintraege() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = OrphanedArticleStatusUpdateStore(database: database)
        try database.write { db in
            var alt = OrphanedArticleStatusUpdateRecord(
                articleID: "alt",
                isRead: true,
                isStarred: false,
                readAt: Date(timeIntervalSince1970: 0),
                starredAt: nil,
                receivedAt: Date(timeIntervalSince1970: 0)
            )
            try alt.insert(db)
            var neu = OrphanedArticleStatusUpdateRecord(
                articleID: "neu",
                isRead: false,
                isStarred: true,
                readAt: nil,
                starredAt: Date(timeIntervalSince1970: 1_000_000),
                receivedAt: Date(timeIntervalSince1970: 1_000_000)
            )
            try neu.insert(db)
        }

        let deletedCount = try store.deleteOlderThan(Date(timeIntervalSince1970: 500_000))

        #expect(deletedCount == 1)
        let remaining = try database.read { db in
            try OrphanedArticleStatusUpdateRecord.fetchAll(db)
        }
        #expect(remaining.map(\.articleID) == ["neu"])
    }
}
```

- [ ] **Step 7: Run test to verify it fails**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/OrphanedArticleStatusUpdateStoreTests -parallel-testing-enabled NO`
Expected: FAIL — `cannot find 'OrphanedArticleStatusUpdateStore' in scope`

- [ ] **Step 8: Create the store**

Create `Feedivo/Stores/OrphanedArticleStatusUpdateStore.swift`:

```swift
import Foundation
import GRDB

struct OrphanedArticleStatusUpdateStore {
    private let database: FeedivoDatabase

    init(database: FeedivoDatabase) {
        self.database = database
    }

    /// Entfernt Einträge, die älter als `cutoffDate` sind (nie abgeholte verwaiste Status,
    /// z. B. weil der zugehörige Feed längst deabonniert wurde) — genutzt von
    /// `ArticleRetentionCleanupService.runAutomaticCleanup`.
    func deleteOlderThan(_ cutoffDate: Date) throws -> Int {
        try database.write { db in
            try db.execute(sql: "DELETE FROM orphaned_article_status_updates WHERE receivedAt < ?", arguments: [cutoffDate])
            return db.changesCount
        }
    }
}
```

- [ ] **Step 9: Run test to verify it passes**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/OrphanedArticleStatusUpdateStoreTests -parallel-testing-enabled NO`
Expected: PASS

- [ ] **Step 10: Commit**

```bash
git add Feedivo/Database/FeedivoDatabaseMigrator.swift Feedivo/Database/Records/OrphanedArticleStatusUpdateRecord.swift Feedivo/Stores/OrphanedArticleStatusUpdateStore.swift FeedivoTests/FeedivoDatabaseMigratorTests.swift FeedivoTests/OrphanedArticleStatusUpdateStoreTests.swift
git commit -m "Feature: Migration v25 + OrphanedArticleStatusUpdateRecord/Store (iCloud Sync Phase 2b Task 2)"
```

---

### Task 3: `CloudSyncArticleStatusMapping` + Registry-Eintrag + Lösch-Helfer

**Files:**
- Create: `Feedivo/Services/CloudSync/CloudSyncArticleStatusMapping.swift`
- Modify: `Feedivo/Services/CloudSync/CloudSyncEngine.swift:48-56` (Registry)
- Test: `FeedivoTests/CloudSyncArticleStatusMappingTests.swift`
- Test: `FeedivoTests/CloudSyncEngineRegistryTests.swift`

**Interfaces:**
- Consumes: `ArticleStatusStore.status(articleID:) throws -> ArticleStatusRecord?` (bestehend), `ArticleStatusRecord.statusSyncUpdatedAt` (Task 1), `OrphanedArticleStatusUpdateRecord` (Task 2), `CloudSyncPendingChangeStore.enqueue(_:recordType:recordName:changeType:) throws` (bestehend), `CloudSyncSettings.isEnabled() -> Bool` (bestehend).
- Produces: `CloudSyncArticleStatusMapping` (konform zu `CloudSyncRecordMapping`, `recordType = "ArticleStatus"`), `CloudSyncArticleStatusMapping.enqueueDeletionIfSynced(articleIDs: [String], db: Database) throws` — von Task 7/8/9 genutzt.

- [ ] **Step 1: Write the failing mapping tests**

Create `FeedivoTests/CloudSyncArticleStatusMappingTests.swift`:

```swift
import Foundation
import CloudKit
import GRDB
import Testing
@testable import Feedivo

private func seedArticle(database: FeedivoDatabase, articleID: String = "article-1", feedID: String = "feed-1") throws -> String {
    try FeedStore(database: database).save(FeedRecord(id: feedID, url: "https://example.com/\(feedID)", title: "Feed"))
    return try ArticleStore(database: database).upsert(
        ArticleUpsertInput(feedID: feedID, sourceID: articleID, title: "Titel", arrivedAt: Date(timeIntervalSince1970: 100))
    )
}

struct CloudSyncArticleStatusMappingTests {
    @Test func makeCKRecordMapptIsReadUndIsStarred() {
        let status = ArticleStatusRecord(
            articleID: "article-1",
            isRead: true,
            isStarred: true,
            readAt: Date(timeIntervalSince1970: 100),
            starredAt: Date(timeIntervalSince1970: 200),
            statusSyncUpdatedAt: Date(timeIntervalSince1970: 300)
        )

        let record = CloudSyncArticleStatusMapping.makeCKRecord(from: status)

        #expect(record.recordType == "ArticleStatus")
        #expect(record["isRead"] as? Bool == true)
        #expect(record["isStarred"] as? Bool == true)
        #expect(record["readAt"] as? Date == Date(timeIntervalSince1970: 100))
        #expect(record["starredAt"] as? Date == Date(timeIntervalSince1970: 200))
    }

    @Test func allLocalIDsListetNurBeruehrteStatusAuf() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let unberuehrtID = try seedArticle(database: database, articleID: "unberuehrt", feedID: "feed-1")
        let beruehrtID = try seedArticle(database: database, articleID: "beruehrt", feedID: "feed-1")
        try ArticleStatusStore(database: database).setRead(true, articleID: beruehrtID, at: Date())

        let ids = try CloudSyncArticleStatusMapping.allLocalIDs(database: database)

        #expect(ids == [beruehrtID])
        _ = unberuehrtID
    }

    @Test func makeCKRecordFromLocalIDLiefertNilFuerUnbekannteID() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        let record = try CloudSyncArticleStatusMapping.makeCKRecord(fromLocalID: "unbekannt", existing: nil, database: database)

        #expect(record == nil)
    }

    @Test func localUpdatedAtLiefertStatusSyncUpdatedAt() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let articleID = try seedArticle(database: database)
        let touchedAt = Date(timeIntervalSince1970: 5_000)
        try ArticleStatusStore(database: database).setRead(true, articleID: articleID, at: touchedAt)

        let localUpdatedAt = try CloudSyncArticleStatusMapping.localUpdatedAt(forLocalID: articleID, database: database)

        #expect(localUpdatedAt != nil)
    }

    @Test func applyIncomingAktualisiertBestehendenArtikelStatus() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let articleID = try seedArticle(database: database)
        let record = CKRecord(recordType: "ArticleStatus", recordID: CloudSyncArticleStatusMapping.recordID(forLocalID: articleID))
        record["isRead"] = true as CKRecordValue
        record["isStarred"] = false as CKRecordValue

        try CloudSyncArticleStatusMapping.applyIncoming(record, database: database)

        let status = try ArticleStatusStore(database: database).status(articleID: articleID)
        #expect(status?.isRead == true)
        #expect(status?.isStarred == false)
    }

    @Test func applyIncomingLegtVerwaistenEintragAnFuerUnbekannteArticleID() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let record = CKRecord(recordType: "ArticleStatus", recordID: CloudSyncArticleStatusMapping.recordID(forLocalID: "unbekannt"))
        record["isRead"] = true as CKRecordValue
        record["isStarred"] = false as CKRecordValue

        try CloudSyncArticleStatusMapping.applyIncoming(record, database: database)

        let orphan = try database.read { db in
            try OrphanedArticleStatusUpdateRecord.fetchOne(db, key: "unbekannt")
        }
        #expect(orphan?.isRead == true)
        #expect(orphan?.isStarred == false)
    }

    @Test func applyIncomingDeletionEntferntStatusUndVerwaistenEintrag() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let articleID = try seedArticle(database: database)
        try ArticleStatusStore(database: database).setRead(true, articleID: articleID, at: Date())
        try database.write { db in
            var orphan = OrphanedArticleStatusUpdateRecord(articleID: "verwaist", isRead: true, isStarred: false, readAt: nil, starredAt: nil, receivedAt: Date())
            try orphan.insert(db)
        }

        try CloudSyncArticleStatusMapping.applyIncomingDeletion(recordID: CloudSyncArticleStatusMapping.recordID(forLocalID: articleID), database: database)
        try CloudSyncArticleStatusMapping.applyIncomingDeletion(recordID: CloudSyncArticleStatusMapping.recordID(forLocalID: "verwaist"), database: database)

        let status = try ArticleStatusStore(database: database).status(articleID: articleID)
        #expect(status?.isRead == false)
        let orphan = try database.read { db in
            try OrphanedArticleStatusUpdateRecord.fetchOne(db, key: "verwaist")
        }
        #expect(orphan == nil)
    }

    @Test func enqueueDeletionIfSyncedEnqueuedNurBeruehrteIDs() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        UserDefaults.standard.set(true, forKey: CloudSyncSettings.isEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey) }
        let beruehrtID = try seedArticle(database: database, articleID: "beruehrt", feedID: "feed-1")
        let unberuehrtID = try seedArticle(database: database, articleID: "unberuehrt", feedID: "feed-1")
        try ArticleStatusStore(database: database).setStarred(true, articleID: beruehrtID, at: Date())

        try database.write { db in
            try CloudSyncArticleStatusMapping.enqueueDeletionIfSynced(articleIDs: [beruehrtID, unberuehrtID], db: db)
        }

        let pending = try CloudSyncPendingChangeStore(database: database).pendingChanges()
        #expect(pending.map(\.id) == [beruehrtID])
        #expect(pending.first?.changeType == .delete)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CloudSyncArticleStatusMappingTests -parallel-testing-enabled NO`
Expected: FAIL — `cannot find 'CloudSyncArticleStatusMapping' in scope`

- [ ] **Step 3: Create the mapping type**

Create `Feedivo/Services/CloudSync/CloudSyncArticleStatusMapping.swift`:

```swift
import Foundation
import CloudKit
import GRDB

/// Mapping für die syncbare TEILMENGE der `article_statuses`-Tabelle — NUR `isRead`/
/// `isStarred` (inkl. `readAt`/`starredAt`) syncen. `isArchived`/`isHidden` bleiben bewusst
/// rein lokal (siehe Design-Spec
/// `docs/superpowers/specs/2026-07-25-icloud-sync-phase2b-design.md`, Abschnitt 1).
///
/// **Sparse Sync:** Anders als alle bisherigen Mappings umfasst `allLocalIDs` NICHT jede
/// Zeile der Tabelle, sondern nur die, deren `statusSyncUpdatedAt` gesetzt ist (der Nutzer
/// hat den Status je bewusst verändert) — siehe Abschnitt 3 der Design-Spec.
enum CloudSyncArticleStatusMapping: CloudSyncRecordMapping {
    static let recordType = "ArticleStatus"

    static func makeCKRecord(from status: ArticleStatusRecord, existing: CKRecord? = nil) -> CKRecord {
        let record = existing ?? CKRecord(recordType: recordType, recordID: recordID(forLocalID: status.articleID))
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

    static func makeCKRecord(fromLocalID id: String, existing: CKRecord?, database: FeedivoDatabase) throws -> CKRecord? {
        guard let status = try ArticleStatusStore(database: database).status(articleID: id) else { return nil }
        return makeCKRecord(from: status, existing: existing)
    }

    /// Unterscheidet zwei Fälle: existiert der Artikel lokal bereits, wird `article_statuses`
    /// direkt aktualisiert. Existiert er noch nicht (Feed auf diesem Gerät noch nicht
    /// aktualisiert, Fremdschlüssel würde einen direkten Insert verhindern), landet der
    /// Status stattdessen in `orphaned_article_status_updates` und wird erst angewendet,
    /// sobald der Artikel per `ArticleStore.upsert()` lokal ankommt (Task 5).
    static func applyIncoming(_ record: CKRecord, database: FeedivoDatabase) throws {
        guard let incoming = incomingStatus(from: record) else { return }
        let articleID = record.recordID.recordName
        let modificationDate = record.modificationDate ?? Date()

        try database.write { db in
            let articleExists = try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM articles WHERE id = ?)", arguments: [articleID]) ?? false

            if articleExists {
                try db.execute(
                    sql: """
                        UPDATE article_statuses
                        SET isRead = ?, isStarred = ?, readAt = ?, starredAt = ?, statusSyncUpdatedAt = ?
                        WHERE articleID = ?
                        """,
                    arguments: [incoming.isRead, incoming.isStarred, incoming.readAt, incoming.starredAt, modificationDate, articleID]
                )
            } else {
                var orphan = OrphanedArticleStatusUpdateRecord(
                    articleID: articleID,
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

    static func applyIncomingDeletion(recordID: CKRecord.ID, database: FeedivoDatabase) throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM article_statuses WHERE articleID = ?", arguments: [recordID.recordName])
            try db.execute(sql: "DELETE FROM orphaned_article_status_updates WHERE articleID = ?", arguments: [recordID.recordName])
        }
    }

    static func localUpdatedAt(forLocalID id: String, database: FeedivoDatabase) throws -> Date? {
        try ArticleStatusStore(database: database).status(articleID: id)?.statusSyncUpdatedAt
    }

    static func allLocalIDs(database: FeedivoDatabase) throws -> [String] {
        try database.read { db in
            try String.fetchAll(db, sql: "SELECT articleID FROM article_statuses WHERE statusSyncUpdatedAt IS NOT NULL ORDER BY articleID")
        }
    }

    /// Enqueued `.delete` für alle `articleIDs`, deren Status je synchronisiert wurde
    /// (`statusSyncUpdatedAt IS NOT NULL`) — No-Op für nie synchronisierte Zeilen (nie ein
    /// passender `CKRecord` existierte) und wenn iCloud Sync gerade deaktiviert ist.
    /// Gemeinsamer Helfer für alle drei Löschpropagierungs-Stellen (Retention-Cleanup,
    /// Einzel-Löschung, Feed-Löschung-Kaskade, siehe Design-Spec Abschnitt 5) — muss VOR dem
    /// eigentlichen `DELETE` aufgerufen werden, in derselben `database.write`-Transaktion.
    static func enqueueDeletionIfSynced(articleIDs: [String], db: Database) throws {
        guard CloudSyncSettings.isEnabled(), !articleIDs.isEmpty else { return }
        let placeholders = Array(repeating: "?", count: articleIDs.count).joined(separator: ", ")
        let syncedIDs = try String.fetchAll(
            db,
            sql: "SELECT articleID FROM article_statuses WHERE statusSyncUpdatedAt IS NOT NULL AND articleID IN (\(placeholders))",
            arguments: StatementArguments(articleIDs)
        )
        for articleID in syncedIDs {
            try CloudSyncPendingChangeStore.enqueue(db, recordType: recordType, recordName: articleID, changeType: .delete)
        }
    }
}
```

- [ ] **Step 4: Run mapping tests to verify they pass**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CloudSyncArticleStatusMappingTests -parallel-testing-enabled NO`
Expected: PASS

- [ ] **Step 5: Write the failing registry test**

In `FeedivoTests/CloudSyncEngineRegistryTests.swift`, direkt nach `registryLoestSmartFolderConditionRecordTypeAufCloudSyncSmartFolderConditionMappingAuf()` einfügen:

```swift
    @Test func registryLoestArticleStatusRecordTypeAufCloudSyncArticleStatusMappingAuf() {
        let mapping = CloudSyncEngine.mapping(forRecordType: "ArticleStatus")

        #expect(mapping is CloudSyncArticleStatusMapping.Type)
    }
```

- [ ] **Step 6: Run test to verify it fails**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CloudSyncEngineRegistryTests/registryLoestArticleStatusRecordTypeAufCloudSyncArticleStatusMappingAuf -parallel-testing-enabled NO`
Expected: FAIL — `#expect` liefert `false` (Registry kennt "ArticleStatus" noch nicht, `mapping` ist `nil`)

- [ ] **Step 7: Register the mapping**

In `Feedivo/Services/CloudSync/CloudSyncEngine.swift:48-56`, den bestehenden Registry-Block ersetzen durch:

```swift
    private nonisolated static let registry: [String: any CloudSyncRecordMapping.Type] = [
        CloudSyncTagMapping.recordType: CloudSyncTagMapping.self,
        CloudSyncFeedMapping.recordType: CloudSyncFeedMapping.self,
        CloudSyncFeedFolderMapping.recordType: CloudSyncFeedFolderMapping.self,
        CloudSyncRuleMapping.recordType: CloudSyncRuleMapping.self,
        CloudSyncRuleConditionMapping.recordType: CloudSyncRuleConditionMapping.self,
        CloudSyncSmartFolderMapping.recordType: CloudSyncSmartFolderMapping.self,
        CloudSyncSmartFolderConditionMapping.recordType: CloudSyncSmartFolderConditionMapping.self,
        CloudSyncArticleStatusMapping.recordType: CloudSyncArticleStatusMapping.self
    ]
```

- [ ] **Step 8: Run test to verify it passes**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CloudSyncEngineRegistryTests -parallel-testing-enabled NO`
Expected: PASS (alle Tests der Datei)

- [ ] **Step 9: Commit**

```bash
git add Feedivo/Services/CloudSync/CloudSyncArticleStatusMapping.swift Feedivo/Services/CloudSync/CloudSyncEngine.swift FeedivoTests/CloudSyncArticleStatusMappingTests.swift FeedivoTests/CloudSyncEngineRegistryTests.swift
git commit -m "Feature: CloudSyncArticleStatusMapping + Registry-Eintrag (iCloud Sync Phase 2b Task 3)"
```

---

### Task 4: `ArticleStatusStore` — Sync-Enqueue bei `setRead`/`setStarred`

**Files:**
- Modify: `Feedivo/Stores/ArticleStatusStore.swift`
- Test: `FeedivoTests/SQLiteArticleStatusStoreTests.swift`

**Interfaces:**
- Consumes: `CloudSyncArticleStatusMapping.recordType` (Task 3), `CloudSyncPendingChangeStore.enqueue(_:recordType:recordName:changeType:) throws` (bestehend), `CloudSyncSettings.isEnabled() -> Bool` (bestehend), `CloudSyncEngine.notifyPendingChangesAvailable(database:)` (bestehend).
- Produces: `ArticleStatusStore.setRead`/`.setStarred` setzen ab jetzt `article_statuses.statusSyncUpdatedAt` und enqueuen bei aktivem Sync einen Pending-Change.

- [ ] **Step 1: Write the failing tests**

In `FeedivoTests/SQLiteArticleStatusStoreTests.swift`, am Ende der `struct SQLiteArticleStatusStoreTests` (vor der schließenden `}`) einfügen:

```swift
    @Test func setReadSetztStatusSyncUpdatedAt() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = ArticleStatusStore(database: database)
        let articleID = try seedArticleForStatusTest(database: database)

        try store.setRead(true, articleID: articleID, at: Date())

        let status = try store.status(articleID: articleID)
        #expect(status?.statusSyncUpdatedAt != nil)
    }

    @Test func setReadSetztStatusSyncUpdatedAtAuchBeiRevertAufFalse() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = ArticleStatusStore(database: database)
        let articleID = try seedArticleForStatusTest(database: database)
        try store.setRead(true, articleID: articleID, at: Date())

        try store.setRead(false, articleID: articleID, at: nil)

        let status = try store.status(articleID: articleID)
        #expect(status?.isRead == false)
        #expect(status?.statusSyncUpdatedAt != nil)
    }

    @Test func setArchivedLaesstStatusSyncUpdatedAtUnveraendert() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = ArticleStatusStore(database: database)
        let articleID = try seedArticleForStatusTest(database: database)

        try store.setArchived(true, articleID: articleID, at: Date())

        let status = try store.status(articleID: articleID)
        #expect(status?.statusSyncUpdatedAt == nil)
    }

    @Test func setReadEnqueuedPendingChangeWennSyncAktiv() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        UserDefaults.standard.set(true, forKey: CloudSyncSettings.isEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey) }
        let store = ArticleStatusStore(database: database)
        let articleID = try seedArticleForStatusTest(database: database)

        try store.setStarred(true, articleID: articleID, at: Date())

        let pending = try CloudSyncPendingChangeStore(database: database).pendingChanges()
        #expect(pending.contains { $0.id == articleID && $0.recordType == CloudSyncArticleStatusMapping.recordType })
    }

    @Test func setReadEnqueuedKeinenPendingChangeWennSyncDeaktiviert() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey)
        let store = ArticleStatusStore(database: database)
        let articleID = try seedArticleForStatusTest(database: database)

        try store.setStarred(true, articleID: articleID, at: Date())

        let pending = try CloudSyncPendingChangeStore(database: database).pendingChanges()
        #expect(pending.isEmpty)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteArticleStatusStoreTests -parallel-testing-enabled NO`
Expected: FAIL — `setReadSetztStatusSyncUpdatedAt` u. a. schlagen fehl (`statusSyncUpdatedAt` bleibt `nil`, keine Pending-Changes enqueued)

- [ ] **Step 3: Implement**

In `Feedivo/Stores/ArticleStatusStore.swift`, den kompletten Inhalt ersetzen durch:

```swift
import Foundation
import GRDB

struct ArticleStatusStore {
    private let database: FeedivoDatabase

    init(database: FeedivoDatabase) {
        self.database = database
    }

    func ensureStatus(articleID: String, dateArrived: Date) throws {
        try database.write { db in
            if try ArticleStatusRecord.fetchOne(db, key: articleID) == nil {
                var status = ArticleStatusRecord(articleID: articleID, dateArrived: dateArrived)
                try status.insert(db)
            }
        }
    }

    func status(articleID: String) throws -> ArticleStatusRecord? {
        try database.read { db in
            try ArticleStatusRecord.fetchOne(db, key: articleID)
        }
    }

    func unreadCount(feedID: String) throws -> Int {
        try SQLiteUnreadCountService(database: database).unreadCount(feedID: feedID)
    }

    func sidebarSmartFolderBadgeSnapshot() throws -> SmartFolderSidebarBadgeSnapshot {
        try SQLiteUnreadCountService(database: database).sidebarSmartFolderBadgeSnapshot()
    }

    /// Setzt `isRead` UND markiert den Status als sync-relevant (iCloud Sync Phase 2b) —
    /// im Unterschied zu `setArchived`/`setHidden`, die außerhalb des Sync-Scopes bleiben.
    func setRead(_ isRead: Bool, articleID: String, at date: Date?) throws {
        try updateBooleanStatus(
            column: "isRead",
            dateColumn: "readAt",
            value: isRead,
            articleID: articleID,
            date: date,
            marksSyncTouched: true
        )
    }

    /// Setzt `isStarred` UND markiert den Status als sync-relevant (iCloud Sync Phase 2b) —
    /// im Unterschied zu `setArchived`/`setHidden`, die außerhalb des Sync-Scopes bleiben.
    func setStarred(_ isStarred: Bool, articleID: String, at date: Date?) throws {
        try updateBooleanStatus(
            column: "isStarred",
            dateColumn: "starredAt",
            value: isStarred,
            articleID: articleID,
            date: date,
            marksSyncTouched: true
        )
    }

    func setArchived(_ isArchived: Bool, articleID: String, at date: Date?) throws {
        try updateBooleanStatus(
            column: "isArchived",
            dateColumn: "archivedAt",
            value: isArchived,
            articleID: articleID,
            date: date,
            marksSyncTouched: false
        )
    }

    func setHidden(_ isHidden: Bool, articleID: String, at date: Date?) throws {
        try updateBooleanStatus(
            column: "isHidden",
            dateColumn: "hiddenAt",
            value: isHidden,
            articleID: articleID,
            date: date,
            marksSyncTouched: false
        )
    }

    /// Markiert wirklich ALLE ungelesenen Artikel app-weit als gelesen —
    /// im Unterschied zu `SQLiteFeedArticleListView.markRowsRead(.allVisible)`,
    /// die nur auf die aktuell sichtbare Artikelliste wirkt. Für das
    /// Menubar-Dropdown (Feature 21.1), wo es keine "aktuelle Auswahl" gibt.
    func markAllUnreadAsRead() throws {
        let now = Date()
        var touchedArticleIDs: [String] = []

        try database.write { db in
            touchedArticleIDs = try String.fetchAll(db, sql: "SELECT articleID FROM article_statuses WHERE isRead = 0")

            try db.execute(
                sql: """
                    UPDATE article_statuses
                    SET isRead = 1, readAt = ?, statusSyncUpdatedAt = ?
                    WHERE isRead = 0
                    """,
                arguments: [now, now]
            )

            if !touchedArticleIDs.isEmpty {
                try db.execute(
                    sql: """
                        UPDATE article_identity_history
                        SET isRead = 1, readAt = ?
                        WHERE isRead = 0
                        """,
                    arguments: [now]
                )
                try enqueuePendingSync(db, articleIDs: touchedArticleIDs, changeType: .save)
            }
        }

        if !touchedArticleIDs.isEmpty {
            try SQLiteUnreadCountService(database: database).rebuildAllFeedUnreadCounts()
            SQLiteDataInvalidation.bumpStatusVersion()
            CloudSyncEngine.notifyPendingChangesAvailable(database: database)
        }
    }

    /// Markiert `articleID` als ausstehende Sync-Änderung, falls iCloud Sync aktiv ist —
    /// analog zu `TagStore.enqueuePendingSync`.
    private func enqueuePendingSync(_ db: Database, articleIDs: [String], changeType: CloudSyncChangeType) throws {
        guard CloudSyncSettings.isEnabled() else { return }
        for articleID in articleIDs {
            try CloudSyncPendingChangeStore.enqueue(db, recordType: CloudSyncArticleStatusMapping.recordType, recordName: articleID, changeType: changeType)
        }
    }

    private func updateBooleanStatus(
        column: String,
        dateColumn: String,
        value: Bool,
        articleID: String,
        date: Date?,
        marksSyncTouched: Bool
    ) throws {
        let timestamp = value ? date : nil
        var didUpdate = false
        try database.write { db in
            if marksSyncTouched {
                try db.execute(
                    sql: """
                        UPDATE article_statuses
                        SET \(column) = ?, \(dateColumn) = ?, statusSyncUpdatedAt = ?
                        WHERE articleID = ?
                        """,
                    arguments: [value, timestamp, Date(), articleID]
                )
            } else {
                try db.execute(
                    sql: """
                        UPDATE article_statuses
                        SET \(column) = ?, \(dateColumn) = ?
                        WHERE articleID = ?
                        """,
                    arguments: [value, timestamp, articleID]
                )
            }
            didUpdate = db.changesCount > 0

            if didUpdate {
                try syncIdentityHistory(
                    articleID: articleID,
                    column: column,
                    dateColumn: dateColumn,
                    value: value,
                    timestamp: timestamp,
                    db: db
                )
            }

            if column == "isRead" || column == "isHidden" {
                try SQLiteUnreadCountService.rebuildFeedUnreadCount(forArticleID: articleID, db: db)
            }

            if didUpdate, marksSyncTouched {
                try enqueuePendingSync(db, articleIDs: [articleID], changeType: .save)
            }
        }

        if didUpdate {
            SQLiteDataInvalidation.bumpStatusVersion()
            if marksSyncTouched {
                CloudSyncEngine.notifyPendingChangesAvailable(database: database)
            }
        }
    }

    private func syncIdentityHistory(
        articleID: String,
        column: String,
        dateColumn: String,
        value: Bool,
        timestamp: Date?,
        db: Database
    ) throws {
        try db.execute(
            sql: """
                UPDATE article_identity_history
                SET \(column) = ?, \(dateColumn) = ?
                WHERE lastArticleID = ?
                """,
            arguments: [value, timestamp, articleID]
        )
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteArticleStatusStoreTests -parallel-testing-enabled NO`
Expected: PASS (alle Tests der Datei, inkl. der bereits bestehenden)

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Stores/ArticleStatusStore.swift FeedivoTests/SQLiteArticleStatusStoreTests.swift
git commit -m "Feature: ArticleStatusStore markiert Gelesen/Stern-Änderungen als sync-relevant (iCloud Sync Phase 2b Task 4)"
```

---

### Task 5: Reconciliation-Hook in `ArticleStore.upsert()`

**Files:**
- Modify: `Feedivo/Stores/ArticleStore.swift:434-447`
- Test: `FeedivoTests/SQLiteArticleStoreTests.swift` (Struct `SQLiteArticleStoreTests`)

**Interfaces:**
- Consumes: `OrphanedArticleStatusUpdateRecord` (Task 2).
- Produces: `ArticleStore.applyOrphanedStatusUpdateIfPresent(articleID:db:) throws` (static) — ein neu eingefügter Artikel übernimmt automatisch einen wartenden, verwaisten Status.

- [ ] **Step 1: Write the failing test**

In `FeedivoTests/SQLiteArticleStoreTests.swift`, am Ende der `struct SQLiteArticleStoreTests` (vor der schließenden `}`) ergänzen:

```swift
    @Test func upsertWendetWartendenVerwaistenStatusAn() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try FeedStore(database: database).save(FeedRecord(id: "feed-1", url: "https://example.com/feed", title: "Feed"))
        let articleID = "artikel-vorab-bekannt"
        try database.write { db in
            var orphan = OrphanedArticleStatusUpdateRecord(
                articleID: articleID,
                isRead: true,
                isStarred: true,
                readAt: Date(timeIntervalSince1970: 100),
                starredAt: Date(timeIntervalSince1970: 200),
                receivedAt: Date(timeIntervalSince1970: 300)
            )
            try orphan.insert(db)
        }

        // Simuliert den Reconciliation-Aufruf, den `ArticleStore.upsert()` intern direkt nach
        // dem Einfügen einer neuen `article_statuses`-Zeile ausführt (siehe Step 4) — hier
        // isoliert getestet, ohne den kompletten Upsert-Pfad (der eine neue UUID vergäbe,
        // nicht `articleID`) durchlaufen zu müssen.
        try database.write { db in
            var article = ArticleRecord(
                id: articleID,
                feedID: "feed-1",
                title: "Titel",
                arrivedAt: Date(),
                updatedAt: Date()
            )
            try article.insert(db)
            var status = ArticleStatusRecord(articleID: articleID, dateArrived: Date())
            try status.insert(db)
            try ArticleStore.applyOrphanedStatusUpdateIfPresent(articleID: articleID, db: db)
        }

        let status = try ArticleStatusStore(database: database).status(articleID: articleID)
        #expect(status?.isRead == true)
        #expect(status?.isStarred == true)
        #expect(status?.statusSyncUpdatedAt != nil)

        let orphan = try database.read { db in
            try OrphanedArticleStatusUpdateRecord.fetchOne(db, key: articleID)
        }
        #expect(orphan == nil)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteArticleStoreTests/upsertWendetWartendenVerwaistenStatusAn -parallel-testing-enabled NO`
Expected: FAIL — `type 'ArticleStore' has no member 'applyOrphanedStatusUpdateIfPresent'`

- [ ] **Step 3: Add the reconciliation hook**

In `Feedivo/Stores/ArticleStore.swift`, den Block von Zeile 434 bis 447 (`var status = ArticleStatusRecord(...` bis `return .inserted(articleID: articleID)`) ersetzen durch:

```swift
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
            dateArrived: history?.firstSeenAt ?? input.arrivedAt
        )
        try status.insert(db)
        try Self.applyOrphanedStatusUpdateIfPresent(articleID: articleID, db: db)
        try saveIdentityHistory(forArticleID: articleID, input: input, status: status, db: db)

        return .inserted(articleID: articleID)
    }

    /// Übernimmt einen wartenden, verwaisten Artikelstatus (iCloud Sync Phase 2b) — ein
    /// Status, der per iCloud ankam, BEVOR der zugehörige Artikel lokal existierte. Läuft
    /// direkt nach dem Insert der frischen `article_statuses`-Zeile, in derselben
    /// Transaktion. `statusSyncUpdatedAt` wird bewusst auf `orphan.receivedAt` gesetzt (lokaler
    /// Empfangszeitpunkt des Orphans, nicht der ursprüngliche `CKRecord.modificationDate` des
    /// Absenders) — akzeptierte, dokumentierte Vereinfachung: ein Folgekonflikt auf genau
    /// diesem Status unmittelbar nach der Reconciliation könnte dadurch in einem schmalen
    /// Zeitfenster fälschlich "lokal gewinnt" statt "Server gewinnt" auflösen. Siehe
    /// Design-Spec docs/superpowers/specs/2026-07-25-icloud-sync-phase2b-design.md,
    /// Abschnitt 4.
    static func applyOrphanedStatusUpdateIfPresent(articleID: String, db: Database) throws {
        guard let orphan = try OrphanedArticleStatusUpdateRecord.fetchOne(db, key: articleID) else { return }

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

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteArticleStoreTests/upsertWendetWartendenVerwaistenStatusAn -parallel-testing-enabled NO`
Expected: PASS

- [ ] **Step 5: Run the full ArticleStore test suite to check for regressions**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteArticleStoreTests -parallel-testing-enabled NO`
Expected: alle PASS

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Stores/ArticleStore.swift FeedivoTests/
git commit -m "Feature: Reconciliation-Hook für verwaiste Artikelstatus in ArticleStore.upsert (iCloud Sync Phase 2b Task 5)"
```

---

### Task 6: Bereinigung verwaister Einträge in `ArticleRetentionCleanupService.runAutomaticCleanup`

**Files:**
- Modify: `Feedivo/Services/ArticleRetentionCleanupService.swift:96-154`
- Test: `FeedivoTests/ArticleRetentionCleanupServiceTests.swift`

**Interfaces:**
- Consumes: `OrphanedArticleStatusUpdateStore.deleteOlderThan(_:) throws -> Int` (Task 2).
- Produces: `runAutomaticCleanup` bereinigt bei jedem Aufruf zusätzlich alte `orphaned_article_status_updates`-Einträge, unabhängig vom `isEnabled`-Parameter (analog zur bestehenden Feed-Log-Bereinigung in derselben Methode).

- [ ] **Step 1: Write the failing test**

In `FeedivoTests/ArticleRetentionCleanupServiceTests.swift`, am Ende der Test-Struct einfügen (Struct-Namen vorher per `grep -n "^struct" FeedivoTests/ArticleRetentionCleanupServiceTests.swift` verifizieren und in den folgenden Zeilen exakt übernehmen):

```swift
    @Test func runAutomaticCleanupEntferntAlteVerwaisteArtikelStatusEintraege() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let now = Date(timeIntervalSince1970: 10_000_000)
        try database.write { db in
            var alt = OrphanedArticleStatusUpdateRecord(
                articleID: "alt",
                isRead: true,
                isStarred: false,
                readAt: nil,
                starredAt: nil,
                receivedAt: now.addingTimeInterval(-200 * 86_400)
            )
            try alt.insert(db)
        }

        _ = ArticleRetentionCleanupService.runAutomaticCleanup(
            database: database,
            isEnabled: false,
            retentionDays: 90,
            triggerSource: .appStart,
            now: now
        )

        let remaining = try database.read { db in
            try OrphanedArticleStatusUpdateRecord.fetchAll(db)
        }
        #expect(remaining.isEmpty)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ArticleRetentionCleanupServiceTests/runAutomaticCleanupEntferntAlteVerwaisteArtikelStatusEintraege -parallel-testing-enabled NO`
Expected: FAIL — der alte Orphan-Eintrag ist noch vorhanden (`remaining.isEmpty` ist `false`)

- [ ] **Step 3: Implement**

In `Feedivo/Services/ArticleRetentionCleanupService.swift`, direkt nach dem bestehenden Feed-Log-Bereinigungs-Block (nach dem `catch`-Block mit `AppLogger.dataAccess.error("Feed-Log-Bereinigung: ...")`, vor `do { let removedCount = try removeExpiredSQLiteArticles(...`), einfügen:

```swift
        // Verwaiste eingehende Artikelstatus-Updates bereinigen (iCloud Sync Phase 2b) — läuft
        // wie die Feed-Log-Bereinigung immer mit, unabhängig von `isEnabled` (Artikel-
        // Aufbewahrung): eine deaktivierte Artikel-Aufbewahrung würde sonst dazu führen, dass
        // niemals abgeholte verwaiste Status (z. B. für einen längst deabonnierten Feed)
        // unbegrenzt wachsen. Nutzt `retentionDays`, falls Artikel-Aufbewahrung aktiv ist,
        // sonst einen festen 90-Tage-Fallback.
        let orphanCutoffDays = isEnabled ? retentionDays : 90
        let orphanCutoff = Calendar.current.date(byAdding: .day, value: -orphanCutoffDays, to: now) ?? now
        do {
            try OrphanedArticleStatusUpdateStore(database: database).deleteOlderThan(orphanCutoff)
        } catch {
            AppLogger.dataAccess.error("Bereinigung verwaister Artikelstatus-Updates: \(error.localizedDescription, privacy: .public)")
        }

```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ArticleRetentionCleanupServiceTests/runAutomaticCleanupEntferntAlteVerwaisteArtikelStatusEintraege -parallel-testing-enabled NO`
Expected: PASS

- [ ] **Step 5: Run the full retention cleanup test suite to check for regressions**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ArticleRetentionCleanupServiceTests -parallel-testing-enabled NO`
Expected: alle PASS

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Services/ArticleRetentionCleanupService.swift FeedivoTests/ArticleRetentionCleanupServiceTests.swift
git commit -m "Feature: Bereinigung alter verwaister Artikelstatus-Updates in runAutomaticCleanup (iCloud Sync Phase 2b Task 6)"
```

---

### Task 7: Löschpropagierung — `ArticleRetentionCleanupService.deleteSQLiteArticles`

**Files:**
- Modify: `Feedivo/Services/ArticleRetentionCleanupService.swift:261-275`
- Test: `FeedivoTests/ArticleRetentionCleanupServiceTests.swift`

**Interfaces:**
- Consumes: `CloudSyncArticleStatusMapping.enqueueDeletionIfSynced(articleIDs:db:) throws` (Task 3).
- Produces: Retention-Cleanup enqueued jetzt `.delete`-Pending-Changes für synchronisierte Artikelstatus, bevor die Zeilen gelöscht werden.

- [ ] **Step 1: Write the failing test**

In `FeedivoTests/ArticleRetentionCleanupServiceTests.swift` ergänzen:

```swift
    @Test func removeExpiredArticlesEnqueuedLoeschungFuerSynchronisierteStatus() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        UserDefaults.standard.set(true, forKey: CloudSyncSettings.isEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey) }
        try FeedStore(database: database).save(FeedRecord(id: "feed-1", url: "https://example.com/feed", title: "Feed"))
        let alterTag = Date(timeIntervalSince1970: 0)
        let articleID = try ArticleStore(database: database).upsert(
            ArticleUpsertInput(feedID: "feed-1", sourceID: "alt", title: "Titel", publishedAt: alterTag, arrivedAt: alterTag)
        )
        try ArticleStatusStore(database: database).setStarred(true, articleID: articleID, at: Date())
        try ArticleStatusStore(database: database).setStarred(false, articleID: articleID, at: nil)

        _ = try ArticleRetentionCleanupService.removeExpiredSQLiteArticles(
            database: database,
            isEnabled: true,
            retentionDays: 1,
            now: Date(timeIntervalSince1970: 100_000_000)
        )

        let pending = try CloudSyncPendingChangeStore(database: database).pendingChanges()
        #expect(pending.contains { $0.id == articleID && $0.recordType == CloudSyncArticleStatusMapping.recordType && $0.changeType == .delete })
    }
```

Hinweis: `setStarred(true, ...)` gefolgt von `setStarred(false, ...)` stellt sicher, dass der Artikel nicht mehr als `isStarred` geschützt ist (die bestehende Bereinigungslogik schließt aktuell gesternte Artikel aus, siehe `shouldRemove`), aber `statusSyncUpdatedAt` bereits gesetzt wurde.

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ArticleRetentionCleanupServiceTests/removeExpiredArticlesEnqueuedLoeschungFuerSynchronisierteStatus -parallel-testing-enabled NO`
Expected: FAIL — `pending` ist leer

- [ ] **Step 3: Implement**

In `Feedivo/Services/ArticleRetentionCleanupService.swift`, die private Methode `deleteSQLiteArticles` (Zeile 261-275) ersetzen durch:

```swift
    private static func deleteSQLiteArticles(_ articleIDs: [String], db: Database) throws {
        for chunk in articleIDs.chunked(into: 400) {
            let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ", ")
            let arguments = StatementArguments(chunk)

            try CloudSyncArticleStatusMapping.enqueueDeletionIfSynced(articleIDs: chunk, db: db)

            try db.execute(
                sql: "DELETE FROM article_statuses WHERE articleID IN (\(placeholders))",
                arguments: arguments
            )
            try db.execute(
                sql: "DELETE FROM articles WHERE id IN (\(placeholders))",
                arguments: arguments
            )
        }
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ArticleRetentionCleanupServiceTests/removeExpiredArticlesEnqueuedLoeschungFuerSynchronisierteStatus -parallel-testing-enabled NO`
Expected: PASS

- [ ] **Step 5: Run the full retention cleanup test suite to check for regressions**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ArticleRetentionCleanupServiceTests -parallel-testing-enabled NO`
Expected: alle PASS

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Services/ArticleRetentionCleanupService.swift FeedivoTests/ArticleRetentionCleanupServiceTests.swift
git commit -m "Feature: Löschpropagierung für Artikelstatus im Retention-Cleanup (iCloud Sync Phase 2b Task 7)"
```

---

### Task 8: Löschpropagierung — `SQLiteFeedArticleListState.deleteArticle`

**Files:**
- Modify: `Feedivo/ViewModels/SQLiteFeedArticleListState.swift:381-402`
- Test: `FeedivoTests/SQLiteFeedArticleListStateTests.swift` (Struct `SQLiteFeedArticleListStateTests`)

**Interfaces:**
- Consumes: `CloudSyncArticleStatusMapping.enqueueDeletionIfSynced(articleIDs:db:) throws` (Task 3).
- Produces: `deleteArticle` enqueued jetzt eine `.delete`-Pending-Change für den synchronisierten Artikelstatus, bevor der Artikel gelöscht wird.

- [ ] **Step 1: Write the failing test**

In `FeedivoTests/SQLiteFeedArticleListStateTests.swift`, am Ende der `struct SQLiteFeedArticleListStateTests` (vor der schließenden `}`) ergänzen:

```swift
    @Test func deleteArticleEnqueuedLoeschungFuerSynchronisiertenStatus() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        UserDefaults.standard.set(true, forKey: CloudSyncSettings.isEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey) }
        try FeedStore(database: database).save(FeedRecord(id: "feed-1", url: "https://example.com/feed", title: "Feed"))
        let articleID = try ArticleStore(database: database).upsert(
            ArticleUpsertInput(feedID: "feed-1", sourceID: "a", title: "Titel", arrivedAt: Date())
        )
        try ArticleStatusStore(database: database).setRead(true, articleID: articleID, at: Date())
        let state = SQLiteFeedArticleListState()

        let didDelete = state.deleteArticle(articleID: articleID, database: database, deindexForSpotlight: { _ in })

        #expect(didDelete == true)
        let pending = try CloudSyncPendingChangeStore(database: database).pendingChanges()
        #expect(pending.contains { $0.id == articleID && $0.recordType == CloudSyncArticleStatusMapping.recordType && $0.changeType == .delete })
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedArticleListStateTests/deleteArticleEnqueuedLoeschungFuerSynchronisiertenStatus -parallel-testing-enabled NO`
Expected: FAIL — `pending` ist leer

- [ ] **Step 3: Implement**

In `Feedivo/ViewModels/SQLiteFeedArticleListState.swift`, die Methode `deleteArticle` (Zeile 381-402) ersetzen durch:

```swift
    func deleteArticle(
        articleID: String,
        database: FeedivoDatabase,
        deindexForSpotlight: ([String]) -> Void = { SpotlightIndexingService.deindexArticles(ids: $0) }
    ) -> Bool {
        do {
            try database.write { db in
                try CloudSyncArticleStatusMapping.enqueueDeletionIfSynced(articleIDs: [articleID], db: db)
                try db.execute(sql: "DELETE FROM articles WHERE id = ?", arguments: [articleID])
            }
            CloudSyncEngine.notifyPendingChangesAvailable(database: database)
            deindexForSpotlight([articleID])
            if let deletedRow = rows.first(where: { $0.id == articleID }),
               !deletedRow.isRead,
               !deletedRow.isHidden {
                totalUnreadCount = max(0, totalUnreadCount - 1)
            }
            rows.removeAll { $0.id == articleID }
            return true
        } catch {
            loadState = .failed(error.localizedDescription)
            return false
        }
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedArticleListStateTests/deleteArticleEnqueuedLoeschungFuerSynchronisiertenStatus -parallel-testing-enabled NO`
Expected: PASS

- [ ] **Step 5: Run the full suite of that test file to check for regressions**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedArticleListStateTests -parallel-testing-enabled NO`
Expected: alle PASS

- [ ] **Step 6: Commit**

```bash
git add Feedivo/ViewModels/SQLiteFeedArticleListState.swift FeedivoTests/
git commit -m "Feature: Löschpropagierung für Artikelstatus bei Einzel-Artikel-Löschung (iCloud Sync Phase 2b Task 8)"
```

---

### Task 9: Löschpropagierung — `FeedStore.delete` (Feed-Löschung-Kaskade)

**Files:**
- Modify: `Feedivo/Stores/FeedStore.swift:209-221`
- Test: `FeedivoTests/SQLiteFeedStoreTests.swift`

**Interfaces:**
- Consumes: `CloudSyncArticleStatusMapping.enqueueDeletionIfSynced(articleIDs:db:) throws` (Task 3).
- Produces: `FeedStore.delete(id:)` enqueued jetzt `.delete`-Pending-Changes für alle synchronisierten Artikelstatus dieses Feeds, bevor die FK-Kaskade sie entfernt.

- [ ] **Step 1: Write the failing test**

In `FeedivoTests/SQLiteFeedStoreTests.swift` ergänzen (Struct-Namen vorher per `grep -n "^struct" FeedivoTests/SQLiteFeedStoreTests.swift` verifizieren):

```swift
    @Test func deleteEnqueuedLoeschungFuerSynchronisierteArtikelStatusDesFeeds() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        UserDefaults.standard.set(true, forKey: CloudSyncSettings.isEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey) }
        let store = FeedStore(database: database)
        try store.save(FeedRecord(id: "feed-1", url: "https://example.com/feed", title: "Feed"))
        let articleID = try ArticleStore(database: database).upsert(
            ArticleUpsertInput(feedID: "feed-1", sourceID: "a", title: "Titel", arrivedAt: Date())
        )
        try ArticleStatusStore(database: database).setStarred(true, articleID: articleID, at: Date())

        try store.delete(id: "feed-1")

        let pending = try CloudSyncPendingChangeStore(database: database).pendingChanges()
        #expect(pending.contains { $0.id == articleID && $0.recordType == CloudSyncArticleStatusMapping.recordType && $0.changeType == .delete })
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedStoreTests/deleteEnqueuedLoeschungFuerSynchronisierteArtikelStatusDesFeeds -parallel-testing-enabled NO`
Expected: FAIL — der `pending`-Eintrag für `articleID` mit `recordType == "ArticleStatus"` fehlt (nur der Feed-Delete-Pending-Change existiert)

- [ ] **Step 3: Implement**

In `Feedivo/Stores/FeedStore.swift`, die Methode `delete(id:)` (Zeile 209-221) ersetzen durch:

```swift
    func delete(id: String) throws {
        try database.write { db in
            try enqueuePendingSync(db, feedID: id, changeType: .delete)

            let articleIDs = try String.fetchAll(db, sql: "SELECT id FROM articles WHERE feedID = ?", arguments: [id])
            try CloudSyncArticleStatusMapping.enqueueDeletionIfSynced(articleIDs: articleIDs, db: db)

            try db.execute(
                sql: """
                    DELETE FROM feeds
                    WHERE id = ?
                    """,
                arguments: [id]
            )
        }
        CloudSyncEngine.notifyPendingChangesAvailable(database: database)
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedStoreTests/deleteEnqueuedLoeschungFuerSynchronisierteArtikelStatusDesFeeds -parallel-testing-enabled NO`
Expected: PASS

- [ ] **Step 5: Run the full FeedStore test suite to check for regressions**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedStoreTests -parallel-testing-enabled NO`
Expected: alle PASS

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Stores/FeedStore.swift FeedivoTests/SQLiteFeedStoreTests.swift
git commit -m "Feature: Löschpropagierung für Artikelstatus bei Feed-Löschung-Kaskade (iCloud Sync Phase 2b Task 9)"
```

---

### Task 10: Vollständiger Regressionslauf + Release-Build

**Files:**
- Keine Code-Änderungen — reine Verifikation.

**Interfaces:**
- Consumes: alle vorherigen Tasks.
- Produces: Bestätigung, dass die volle relevante Testsuite grün ist und ein Release-Build erfolgreich durchläuft, bevor Whole-Branch-Review angefragt wird.

- [ ] **Step 1: Gezielter Testlauf über alle in dieser Phase berührten Suiten**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoDatabaseMigratorTests -only-testing:FeedivoTests/OrphanedArticleStatusUpdateStoreTests -only-testing:FeedivoTests/CloudSyncArticleStatusMappingTests -only-testing:FeedivoTests/CloudSyncEngineRegistryTests -only-testing:FeedivoTests/SQLiteArticleStatusStoreTests -only-testing:FeedivoTests/ArticleRetentionCleanupServiceTests -only-testing:FeedivoTests/SQLiteFeedStoreTests -parallel-testing-enabled NO`
Expected: alle PASS (bekannte, vorbestehende Fehlschläge in `FeedivoAppSceneConfigurationTests.swift` und die 2 flaky-unter-Last-Tests in `FeedViewModelTests.swift` sind hiervon nicht betroffen, da diese Suiten hier nicht mitlaufen)

- [ ] **Step 2: Release-Build**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -configuration Release`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Diff-Stat-Kontrolle**

Run: `git diff --stat main`
Expected: Ausschließlich die in dieser Plan-Datei genannten Dateien (2 neue Records, 1 neuer Store, 1 neues Mapping, plus die 9 modifizierten Bestandsdateien + Testdateien) — kein unbeabsichtigter Reformatierungs-Diff (z. B. an `Localizable.xcstrings`, die dieser Plan nicht berührt).

- [ ] **Step 4: Commit (nur falls Step 1-3 Anpassungen nötig machten)**

Falls alle drei Schritte ohne Änderungen bestehen, entfällt dieser Commit — Task 10 ist dann reine Verifikation ohne Diff.
