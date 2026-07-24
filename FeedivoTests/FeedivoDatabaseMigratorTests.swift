import Foundation
import GRDB
import Testing
@testable import Feedivo

// Migration v22 (iCloud Sync Phase 2a, Task 1): fügt `updatedAt` zu `rule_conditions` und
// `smart_folder_conditions` hinzu (Last-Write-Wins-Grundlage für Task 6/7) und vereinheitlicht
// einen veralteten recordType-String in `cloud_sync_pending_changes`. Nutzt GRDBs eingebautes
// `DatabaseMigrator.migrate(_:upTo:)` für den Vor-Migrations-Zwischenstand — exakt dasselbe
// Muster wie in SQLiteDatabaseMigrationTests.swift (z. B. die v20-Backfill-Tests), keine
// zusätzliche Test-Hilfsfunktion auf FeedivoDatabaseMigrator nötig.
struct FeedivoDatabaseMigratorTests {
    @Test func migrationV22FuegtUpdatedAtZuBedingungstabellenHinzuUndBackfilledBestandszeilen() throws {
        let queue = try DatabaseQueue()
        try FeedivoDatabaseMigrator.migrator.migrate(queue, upTo: "v21_create_cloud_sync_pending_changes")

        try queue.write { db in
            let now = Date()
            try db.execute(
                sql: """
                    INSERT INTO rules (id, name, isEnabled, matchMode, action, notificationTemplate, notificationPriority, sortOrder, createdAt, updatedAt)
                    VALUES ('rule-1', 'Test', 1, 'all', 'assignTag', '{Titel}', 'normal', 0, ?, ?)
                    """,
                arguments: [now, now]
            )
            try db.execute(sql: """
                INSERT INTO rule_conditions (id, ruleID, field, conditionOperator, value, sortOrder, groupIndex)
                VALUES ('cond-1', 'rule-1', 'title', 'contains', 'Test', 0, 0)
                """)
        }

        try FeedivoDatabaseMigrator.migrator.migrate(queue)

        let updatedAt = try queue.read { db in
            try Date.fetchOne(db, sql: "SELECT updatedAt FROM rule_conditions WHERE id = 'cond-1'")
        }
        #expect(updatedAt != nil)
    }

    @Test func migrationV22FuegtUpdatedAtZuSmartFolderConditionsHinzuUndBackfilledBestandszeilen() throws {
        let queue = try DatabaseQueue()
        try FeedivoDatabaseMigrator.migrator.migrate(queue, upTo: "v21_create_cloud_sync_pending_changes")

        try queue.write { db in
            let now = Date()
            try db.execute(
                sql: """
                    INSERT INTO smart_folders (id, name, matchMode, isShownInSidebar, isDefault, sortOrder, createdAt, updatedAt)
                    VALUES ('folder-1', 'Test', 'all', 1, 0, 0, ?, ?)
                    """,
                arguments: [now, now]
            )
            try db.execute(sql: """
                INSERT INTO smart_folder_conditions (id, smartFolderID, field, conditionOperator, value, sortOrder)
                VALUES ('cond-1', 'folder-1', 'title', 'contains', 'Test', 0)
                """)
        }

        try FeedivoDatabaseMigrator.migrator.migrate(queue)

        let updatedAt = try queue.read { db in
            try Date.fetchOne(db, sql: "SELECT updatedAt FROM smart_folder_conditions WHERE id = 'cond-1'")
        }
        #expect(updatedAt != nil)
    }

    @Test func migrationV22BereinigtVeraltetenRecordTypeStringFuerTags() throws {
        let queue = try DatabaseQueue()
        try FeedivoDatabaseMigrator.migrator.migrate(queue, upTo: "v21_create_cloud_sync_pending_changes")

        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO cloud_sync_pending_changes (id, recordType, changeType, queuedAt)
                VALUES ('tag-1', 'tag', 'save', ?)
                """, arguments: [Date()])
        }

        try FeedivoDatabaseMigrator.migrator.migrate(queue)

        let recordType = try queue.read { db in
            try String.fetchOne(db, sql: "SELECT recordType FROM cloud_sync_pending_changes WHERE id = 'tag-1'")
        }
        #expect(recordType == "Tag")
    }

    @Test func migrationV22LaesstAndereRecordTypesUnveraendert() throws {
        let queue = try DatabaseQueue()
        try FeedivoDatabaseMigrator.migrator.migrate(queue, upTo: "v21_create_cloud_sync_pending_changes")

        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO cloud_sync_pending_changes (id, recordType, changeType, queuedAt)
                VALUES ('feed-1', 'Feed', 'save', ?)
                """, arguments: [Date()])
        }

        try FeedivoDatabaseMigrator.migrator.migrate(queue)

        let recordType = try queue.read { db in
            try String.fetchOne(db, sql: "SELECT recordType FROM cloud_sync_pending_changes WHERE id = 'feed-1'")
        }
        #expect(recordType == "Feed")
    }

    // Migration v23 (iCloud Sync Phase 2a, Task 2): fügt `configUpdatedAt` zu `feeds` hinzu —
    // ein von `updatedAt` UNABHÄNGIGES Last-Write-Wins-Vergleichsfeld für den späteren Feed-Sync
    // (Task 4), da `updatedAt` auch bei reinen Refresh-Metadaten-Änderungen (FeedStore.
    // updateAfterRefresh) aktualisiert wird und deshalb als Konflikt-Zeitstempel ungeeignet wäre.
    @Test func migrationV23FuegtConfigUpdatedAtZuFeedsHinzuUndBackfilledBestandszeilen() throws {
        let queue = try DatabaseQueue()
        try FeedivoDatabaseMigrator.migrator.migrate(queue, upTo: "v22_add_updated_at_to_condition_tables")

        try queue.write { db in
            let now = Date()
            try db.execute(
                sql: """
                    INSERT INTO feeds (id, url, title, originalTitle, sortIndex, refreshIntervalMinutes, isNotificationEnabled, articleRetentionOverridesGlobalSetting, articleRetentionIsEnabled, articleRetentionDays, articleRetentionMinimumArticles, articleRetentionIncludesProtectedArticles, unreadCount, createdAt, updatedAt)
                    VALUES ('feed-1', 'https://example.com/feed', 'Test', 'Test', 0, 30, 0, 0, 0, 90, 20, 0, 0, ?, ?)
                    """,
                arguments: [now, now]
            )
        }

        try FeedivoDatabaseMigrator.migrator.migrate(queue)

        let configUpdatedAt = try queue.read { db in
            try Date.fetchOne(db, sql: "SELECT configUpdatedAt FROM feeds WHERE id = 'feed-1'")
        }
        #expect(configUpdatedAt != nil)
    }
}
