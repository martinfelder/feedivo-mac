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

    /// Lookup über die geräteübergreifend stabile Identität (iCloud Sync Phase 2b) —
    /// Gegenstück zu `status(articleID:)` für den CloudSync-Layer, der eingehende Records
    /// nicht über die lokale `articleID` identifizieren kann.
    func status(syncStableID: String) throws -> ArticleStatusRecord? {
        try database.read { db in
            try ArticleStatusRecord.fetchOne(db, sql: "SELECT * FROM article_statuses WHERE syncStableID = ?", arguments: [syncStableID])
        }
    }

    func unreadCount(feedID: String) throws -> Int {
        try SQLiteUnreadCountService(database: database).unreadCount(feedID: feedID)
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
    /// übersetzt intern auf die für CloudKit relevante `syncStableID` (iCloud Sync Phase 2b
    /// Stable-Identity-Fix, Task 12 Re-Review) — analog zu
    /// `CloudSyncArticleStatusMapping.enqueueDeletionIfSynced`. Ohne diese Übersetzung würde
    /// `CloudSyncEngine` später versuchen, das CKRecord über `makeCKRecord(fromLocalID:)`
    /// aufzubauen, das `syncStableID` erwartet — mit der rohen lokalen `articleID` als `id`
    /// würde die Lookup fehlschlagen und die Änderung stillschweigend verworfen werden.
    private func enqueuePendingSync(_ db: Database, articleIDs: [String], changeType: CloudSyncChangeType) throws {
        guard CloudSyncSettings.isEnabled(), !articleIDs.isEmpty else { return }
        let placeholders = Array(repeating: "?", count: articleIDs.count).joined(separator: ", ")
        let stableIDs = try String.fetchAll(
            db,
            sql: "SELECT syncStableID FROM article_statuses WHERE syncStableID IS NOT NULL AND articleID IN (\(placeholders))",
            arguments: StatementArguments(articleIDs)
        )
        for stableID in stableIDs {
            try CloudSyncPendingChangeStore.enqueue(db, recordType: CloudSyncArticleStatusMapping.recordType, recordName: stableID, changeType: changeType)
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
