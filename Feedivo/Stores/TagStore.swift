import Foundation
import GRDB

struct TagStore {
    private let database: FeedivoDatabase

    init(database: FeedivoDatabase) {
        self.database = database
    }

    func save(_ tag: TagRecord) throws {
        try database.write { db in
            let existingID = try String.fetchOne(db, sql: """
                SELECT id
                FROM tags
                WHERE id = ? OR name = ?
                ORDER BY CASE WHEN id = ? THEN 0 ELSE 1 END
                LIMIT 1
                """, arguments: [tag.id, tag.name, tag.id])
            let now = Date()

            if let existingID {
                try db.execute(
                    sql: """
                        UPDATE tags
                        SET id = ?, name = ?, colorHex = ?, updatedAt = ?
                        WHERE id = ?
                        """,
                    arguments: [tag.id, tag.name, tag.colorHex, now, existingID]
                )
            } else {
                var tag = tag
                try tag.insert(db)
            }
        }
    }

    func tags() throws -> [TagRecord] {
        try database.read { db in
            try TagRecord.fetchAll(db, sql: """
                SELECT *
                FROM tags
                ORDER BY name COLLATE NOCASE, id COLLATE NOCASE
                """)
        }
    }

    func tags(articleID: String) throws -> [TagRecord] {
        try database.read { db in
            try TagRecord.fetchAll(db, sql: """
                SELECT t.*
                FROM tags t
                JOIN article_tags at ON at.tagID = t.id
                WHERE at.articleID = ?
                ORDER BY t.name COLLATE NOCASE, t.id COLLATE NOCASE
                """, arguments: [articleID])
        }
    }

    func tags(feedID: String) throws -> [TagRecord] {
        try database.read { db in
            try TagRecord.fetchAll(db, sql: """
                SELECT t.*
                FROM tags t
                JOIN feed_tags ft ON ft.tagID = t.id
                WHERE ft.feedID = ?
                ORDER BY t.name COLLATE NOCASE, t.id COLLATE NOCASE
                """, arguments: [feedID])
        }
    }

    func sidebarTags() throws -> [TagSidebarSnapshot] {
        try database.read { db in
            try TagSidebarSnapshot.fetchAll(db, sql: """
                SELECT
                    t.id,
                    t.name,
                    t.colorHex,
                    (
                        SELECT COUNT(DISTINCT a.id)
                        FROM articles a
                        WHERE EXISTS (
                            SELECT 1
                            FROM article_tags at
                            WHERE at.articleID = a.id
                                AND at.tagID = t.id
                        )
                        OR EXISTS (
                            SELECT 1
                            FROM feed_tags ft
                            WHERE ft.feedID = a.feedID
                                AND ft.tagID = t.id
                        )
                    ) AS articleCount
                FROM tags t
                ORDER BY t.name COLLATE NOCASE, t.id COLLATE NOCASE
                """)
        }
    }

    func assignTag(tagID: String, toArticleID articleID: String, at assignedAt: Date) throws {
        try database.write { db in
            var assignment = ArticleTagRecord(
                articleID: articleID,
                tagID: tagID,
                assignedAt: assignedAt
            )
            try assignment.insert(db, onConflict: .ignore)
        }
    }

    func assignTag(tagID: String, toFeedID feedID: String, at assignedAt: Date) throws {
        try database.write { db in
            var assignment = FeedTagRecord(
                feedID: feedID,
                tagID: tagID,
                assignedAt: assignedAt
            )
            try assignment.insert(db, onConflict: .ignore)
        }
    }

    func removeTag(tagID: String, fromFeedID feedID: String) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    DELETE FROM feed_tags
                    WHERE feedID = ? AND tagID = ?
                    """,
                arguments: [feedID, tagID]
            )
        }
    }
}
