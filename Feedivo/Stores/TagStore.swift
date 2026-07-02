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

    func sidebarTags() throws -> [TagSidebarSnapshot] {
        try database.read { db in
            try TagSidebarSnapshot.fetchAll(db, sql: """
                SELECT
                    t.id,
                    t.name,
                    t.colorHex,
                    COUNT(DISTINCT at.articleID) AS articleCount
                FROM tags t
                LEFT JOIN article_tags at ON at.tagID = t.id
                GROUP BY t.id, t.name, t.colorHex
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
}
