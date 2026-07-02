import Foundation
import GRDB

enum TimelineScope: Equatable, Sendable {
    case all
    case feed(String)
    case tag(String)
}

struct TimelineStore {
    private let database: FeedivoDatabase

    init(database: FeedivoDatabase) {
        self.database = database
    }

    func articles(
        scope: TimelineScope,
        includeRead: Bool,
        includeHidden: Bool,
        limit: Int
    ) throws -> [ArticleListSnapshot] {
        let safeLimit = max(1, limit)
        var whereClauses: [String] = []
        var arguments = StatementArguments()

        switch scope {
        case .all:
            break
        case let .feed(feedID):
            whereClauses.append("a.feedID = ?")
            _ = arguments.append(contentsOf: [feedID])
        case let .tag(tagID):
            whereClauses.append("""
                (
                    EXISTS (
                        SELECT 1
                        FROM article_tags at
                        WHERE at.articleID = a.id
                            AND at.tagID = ?
                    )
                    OR EXISTS (
                        SELECT 1
                        FROM feed_tags ft
                        WHERE ft.feedID = a.feedID
                            AND ft.tagID = ?
                    )
                )
                """)
            _ = arguments.append(contentsOf: [tagID, tagID])
        }

        if !includeRead {
            whereClauses.append("s.isRead = 0")
        }

        if !includeHidden {
            whereClauses.append("s.isHidden = 0")
        }

        let whereSQL = whereClauses.isEmpty ? "" : "WHERE \(whereClauses.joined(separator: " AND "))"
        _ = arguments.append(contentsOf: [safeLimit])

        return try database.read { db in
            try ArticleListSnapshot.fetchAll(db, sql: """
                SELECT
                    a.id,
                    a.feedID,
                    f.title AS feedTitle,
                    a.title,
                    a.summary,
                    a.link,
                    a.imageURL,
                    a.publishedAt,
                    a.arrivedAt,
                    a.estimatedReadingMinutes,
                    s.isRead,
                    s.isStarred,
                    s.isArchived,
                    s.isHidden
                FROM articles a
                JOIN feeds f ON f.id = a.feedID
                JOIN article_statuses s ON s.articleID = a.id
                \(whereSQL)
                ORDER BY COALESCE(a.publishedAt, a.arrivedAt) DESC, a.arrivedAt DESC
                LIMIT ?
                """, arguments: arguments)
        }
    }

    func unreadCount(feedID: String) throws -> Int {
        try database.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*)
                FROM articles a
                JOIN article_statuses s ON s.articleID = a.id
                WHERE a.feedID = ?
                    AND s.isRead = 0
                    AND s.isHidden = 0
                """, arguments: [feedID]) ?? 0
        }
    }
}

extension ArticleListSnapshot: FetchableRecord {
    init(row: Row) throws {
        id = row["id"]
        feedID = row["feedID"]
        feedTitle = row["feedTitle"]
        title = row["title"]
        summary = row["summary"]
        link = row["link"]
        imageURL = row["imageURL"]
        publishedAt = row["publishedAt"]
        arrivedAt = row["arrivedAt"]
        estimatedReadingMinutes = row["estimatedReadingMinutes"]
        isRead = row["isRead"]
        isStarred = row["isStarred"]
        isArchived = row["isArchived"]
        isHidden = row["isHidden"]
    }
}
