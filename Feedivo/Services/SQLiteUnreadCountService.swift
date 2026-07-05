import Foundation
import GRDB

/// Zentrale SQLite-Schicht für ungelesene Artikelzahlen.
///
/// Der produktive Pfad hält gelesene/versteckte Zustände in `article_statuses`
/// und speichert Feed-Badges in `feeds.unreadCount`. Dieser Service bündelt die
/// dazugehörigen Queries, damit Sidebar, Smart-Folder-Badges und Statusmutationen
/// dieselbe Zähllogik verwenden.
struct SQLiteUnreadCountService {
    private let database: FeedivoDatabase

    init(database: FeedivoDatabase) {
        self.database = database
    }

    func unreadCount(feedID: String) throws -> Int {
        try database.read { db in
            try Self.unreadCount(feedID: feedID, db: db)
        }
    }

    func totalUnreadCount() throws -> Int {
        try database.read { db in
            try Self.totalUnreadCount(db: db)
        }
    }

    @discardableResult
    func rebuildFeedUnreadCount(feedID: String) throws -> Int {
        try database.write { db in
            try Self.rebuildFeedUnreadCount(feedID: feedID, db: db)
        }
    }

    @discardableResult
    func rebuildAllFeedUnreadCounts() throws -> [String: Int] {
        try database.write { db in
            let feedIDs = try String.fetchAll(db, sql: "SELECT id FROM feeds ORDER BY id COLLATE NOCASE")
            var counts: [String: Int] = [:]
            for feedID in feedIDs {
                counts[feedID] = try Self.rebuildFeedUnreadCount(feedID: feedID, db: db)
            }
            return counts
        }
    }

    func sidebarSmartFolderBadgeSnapshot() throws -> SmartFolderSidebarBadgeSnapshot {
        try database.read { db in
            try Self.sidebarSmartFolderBadgeSnapshot(db: db)
        }
    }

    static func unreadCount(feedID: String, db: Database) throws -> Int {
        try Int.fetchOne(db, sql: unreadCountSQL, arguments: [feedID]) ?? 0
    }

    static func totalUnreadCount(db: Database) throws -> Int {
        try Int.fetchOne(db, sql: "SELECT COALESCE(SUM(unreadCount), 0) FROM feeds") ?? 0
    }

    @discardableResult
    static func rebuildFeedUnreadCount(feedID: String, db: Database) throws -> Int {
        let unreadCount = try unreadCount(feedID: feedID, db: db)
        try db.execute(
            sql: """
                UPDATE feeds
                SET unreadCount = ?, updatedAt = ?
                WHERE id = ?
                """,
            arguments: [unreadCount, Date(), feedID]
        )
        return unreadCount
    }

    static func rebuildFeedUnreadCount(forArticleID articleID: String, db: Database) throws {
        guard let feedID = try String.fetchOne(db, sql: """
            SELECT feedID
            FROM articles
            WHERE id = ?
            LIMIT 1
            """, arguments: [articleID]) else {
            return
        }

        try rebuildFeedUnreadCount(feedID: feedID, db: db)
    }

    static func sidebarSmartFolderBadgeSnapshot(db: Database) throws -> SmartFolderSidebarBadgeSnapshot {
        try SmartFolderSidebarBadgeSnapshot.fetchOne(db, sql: """
            SELECT
                (SELECT COALESCE(SUM(unreadCount), 0) FROM feeds) AS unread,
                (SELECT COUNT(*) FROM article_statuses WHERE isStarred = 1) AS starred,
                (SELECT COUNT(*) FROM article_statuses WHERE isHidden = 1) AS hidden,
                (SELECT COUNT(*) FROM article_statuses WHERE isStarred = 1 OR isArchived = 1) AS saved
            """) ?? .empty
    }

    private static let unreadCountSQL = """
        SELECT COUNT(*)
        FROM article_statuses s
        JOIN articles a ON a.id = s.articleID
        WHERE a.feedID = ?
            AND s.isRead = 0
            AND s.isHidden = 0
        """
}
