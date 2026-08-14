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

    @Test func migrationV29ErgaenztIndizesFuerCloudSyncTabellen() throws {
        let queue = try DatabaseQueue()
        try FeedivoDatabaseMigrator.migrator.migrate(queue, upTo: "v28_create_pending_sync_conflicts")

        try queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO cloud_sync_pending_changes (id, recordType, changeType, queuedAt)
                    VALUES ('change-1', 'Tag', 'save', ?)
                    """,
                arguments: [Date()]
            )
            try db.execute(
                sql: """
                    INSERT INTO pending_sync_conflicts (recordType, recordName, fieldName, localValue, serverValue, detectedAt)
                    VALUES ('Tag', 'tag-1', 'name', 'Alt', 'Neu', ?)
                    """,
                arguments: [Date()]
            )
        }

        try FeedivoDatabaseMigrator.migrator.migrate(queue)

        let indexNames = try queue.read { db -> Set<String> in
            let pendingChangesIndexes = try Row.fetchAll(db, sql: "PRAGMA index_list(cloud_sync_pending_changes)")
                .compactMap { $0["name"] as String? }
            let conflictIndexes = try Row.fetchAll(db, sql: "PRAGMA index_list(pending_sync_conflicts)")
                .compactMap { $0["name"] as String? }
            return Set(pendingChangesIndexes).union(conflictIndexes)
        }

        #expect(indexNames.contains("idx_cloud_sync_pending_changes_record_type"))
        #expect(indexNames.contains("idx_pending_sync_conflicts_record_type_name"))
    }

    @Test func migrationV30BackfilltFehlendeLesezeitUndLaesstBestehendeWerteUnangetastet() throws {
        let queue = try DatabaseQueue()
        try FeedivoDatabaseMigrator.migrator.migrate(queue, upTo: "v29_add_cloud_sync_indexes")

        try queue.write { db in
            let now = Date()
            try db.execute(
                sql: """
                    INSERT INTO feeds (id, url, title, refreshIntervalMinutes, unreadCount, createdAt, updatedAt)
                    VALUES ('feed-1', 'https://example.com/feed.xml', 'Test', 30, 0, ?, ?)
                    """,
                arguments: [now, now]
            )

            let longContent = Array(repeating: "wort", count: 400).joined(separator: " ")
            try db.execute(
                sql: """
                    INSERT INTO articles (id, feedID, title, content, arrivedAt, updatedAt, estimatedReadingMinutes)
                    VALUES ('article-null', 'feed-1', 'Ohne Lesezeit', ?, ?, ?, NULL)
                    """,
                arguments: [longContent, now, now]
            )
            try db.execute(
                sql: """
                    INSERT INTO articles (id, feedID, title, content, arrivedAt, updatedAt, estimatedReadingMinutes)
                    VALUES ('article-existing', 'feed-1', 'Mit Lesezeit', ?, ?, ?, 7)
                    """,
                arguments: [longContent, now, now]
            )
        }

        try FeedivoDatabaseMigrator.migrator.migrate(queue)

        let backfilled = try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT estimatedReadingMinutes FROM articles WHERE id = 'article-null'")
        }
        let untouched = try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT estimatedReadingMinutes FROM articles WHERE id = 'article-existing'")
        }

        #expect(backfilled == 2)
        #expect(untouched == 7)
    }

    @Test func migrationV31LegtMcpServerSettingsMitDeaktiviertemStandardwertAn() throws {
        let queue = try DatabaseQueue()
        try FeedivoDatabaseMigrator.migrator.migrate(queue, upTo: "v30_backfill_article_estimated_reading_minutes")

        try FeedivoDatabaseMigrator.migrator.migrate(queue)

        let isEnabled = try queue.read { db in
            try Bool.fetchOne(db, sql: "SELECT isEnabled FROM mcp_server_settings WHERE id = 1")
        }
        #expect(isEnabled == false)

        let rowCount = try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM mcp_server_settings")
        }
        #expect(rowCount == 1)
    }
}
