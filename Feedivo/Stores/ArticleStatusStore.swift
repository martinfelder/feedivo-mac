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
        try database.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*)
                FROM article_statuses s
                JOIN articles a ON a.id = s.articleID
                WHERE a.feedID = ?
                    AND s.isRead = 0
                    AND s.isHidden = 0
                """, arguments: [feedID]) ?? 0
        }
    }

    func sidebarSmartFolderBadgeSnapshot() throws -> SmartFolderSidebarBadgeSnapshot {
        try database.read { db in
            try SmartFolderSidebarBadgeSnapshot.fetchOne(db, sql: """
                SELECT
                    (SELECT COALESCE(SUM(unreadCount), 0) FROM feeds) AS unread,
                    (SELECT COUNT(*) FROM article_statuses WHERE isStarred = 1) AS starred,
                    (SELECT COUNT(*) FROM article_statuses WHERE isHidden = 1) AS hidden,
                    (SELECT COUNT(*) FROM article_statuses WHERE isStarred = 1 OR isArchived = 1) AS saved
                """) ?? .empty
        }
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

            if column == "isRead" || column == "isHidden" {
                try updateFeedUnreadCount(forArticleID: articleID, db: db)
            }
        }

        if didUpdate {
            SQLiteDataInvalidation.bumpStatusVersion()
        }
    }

    private func updateFeedUnreadCount(forArticleID articleID: String, db: Database) throws {
        guard let feedID = try String.fetchOne(db, sql: """
            SELECT feedID
            FROM articles
            WHERE id = ?
            LIMIT 1
            """, arguments: [articleID]) else {
            return
        }

        let unreadCount = try Int.fetchOne(db, sql: """
            SELECT COUNT(*)
            FROM article_statuses s
            JOIN articles a ON a.id = s.articleID
            WHERE a.feedID = ?
                AND s.isRead = 0
                AND s.isHidden = 0
            """, arguments: [feedID]) ?? 0

        try db.execute(
            sql: """
                UPDATE feeds
                SET unreadCount = ?, updatedAt = ?
                WHERE id = ?
                """,
            arguments: [unreadCount, Date(), feedID]
        )
    }
}
