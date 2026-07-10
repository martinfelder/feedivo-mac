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

    func setRead(_ isRead: Bool, articleID: String, at date: Date?) throws {
        try updateBooleanStatus(
            column: "isRead",
            dateColumn: "readAt",
            value: isRead,
            articleID: articleID,
            date: date
        )
    }

    func setStarred(_ isStarred: Bool, articleID: String, at date: Date?) throws {
        try updateBooleanStatus(
            column: "isStarred",
            dateColumn: "starredAt",
            value: isStarred,
            articleID: articleID,
            date: date
        )
    }

    func setArchived(_ isArchived: Bool, articleID: String, at date: Date?) throws {
        try updateBooleanStatus(
            column: "isArchived",
            dateColumn: "archivedAt",
            value: isArchived,
            articleID: articleID,
            date: date
        )
    }

    func setHidden(_ isHidden: Bool, articleID: String, at date: Date?) throws {
        try updateBooleanStatus(
            column: "isHidden",
            dateColumn: "hiddenAt",
            value: isHidden,
            articleID: articleID,
            date: date
        )
    }

    /// Markiert wirklich ALLE ungelesenen Artikel app-weit als gelesen —
    /// im Unterschied zu `SQLiteFeedArticleListView.markRowsRead(.allVisible)`,
    /// die nur auf die aktuell sichtbare Artikelliste wirkt. Für das
    /// Menubar-Dropdown (Feature 21.1), wo es keine "aktuelle Auswahl" gibt.
    func markAllUnreadAsRead() throws {
        let now = Date()
        var didUpdate = false

        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE article_statuses
                    SET isRead = 1, readAt = ?
                    WHERE isRead = 0
                    """,
                arguments: [now]
            )
            didUpdate = db.changesCount > 0

            if didUpdate {
                try db.execute(
                    sql: """
                        UPDATE article_identity_history
                        SET isRead = 1, readAt = ?
                        WHERE isRead = 0
                        """,
                    arguments: [now]
                )
            }
        }

        if didUpdate {
            try SQLiteUnreadCountService(database: database).rebuildAllFeedUnreadCounts()
            SQLiteDataInvalidation.bumpStatusVersion()
        }
    }

    private func updateBooleanStatus(
        column: String,
        dateColumn: String,
        value: Bool,
        articleID: String,
        date: Date?
    ) throws {
        let timestamp = value ? date : nil
        var didUpdate = false
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE article_statuses
                    SET \(column) = ?, \(dateColumn) = ?
                    WHERE articleID = ?
                    """,
                arguments: [value, timestamp, articleID]
            )
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
        }

        if didUpdate {
            SQLiteDataInvalidation.bumpStatusVersion()
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
