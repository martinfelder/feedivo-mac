import Foundation
import GRDB

struct SQLiteRuleEvaluationStore {
    private let database: FeedivoDatabase

    init(database: FeedivoDatabase) {
        self.database = database
    }

    func matchingArticleCount(
        conditionDrafts: [RuleConditionDraft],
        matchMode: RuleMatchMode
    ) throws -> Int {
        let snapshots = try articleRuleSnapshots()
        return RuleEngine.matchingArticleCount(
            conditionDrafts: conditionDrafts,
            matchMode: matchMode,
            articles: snapshots
        )
    }

    @discardableResult
    func applyRulesToExistingArticles(_ rules: [RuleEngine.RuleSnapshot]) throws -> Int {
        try database.write { db in
            let snapshots = try articleRuleSnapshots(db: db)
            let result = RuleEngine.applySQLiteRules(rules, to: snapshots)
            var appliedCount = result.notifications.count
            var changedFeedIDs = Set<String>()

            for assignment in result.tagAssignments {
                try saveTag(assignment.tag, db: db)
                if try insertTagAssignment(assignment, db: db) {
                    appliedCount += 1
                }
            }

            for articleID in result.hiddenArticleIDs {
                if let feedID = try hideArticleIfNeeded(articleID: articleID, db: db) {
                    changedFeedIDs.insert(feedID)
                    appliedCount += 1
                }
            }

            for feedID in changedFeedIDs {
                try updateUnreadCount(feedID: feedID, db: db)
            }

            if appliedCount > 0 {
                SQLiteDataInvalidation.bumpStatusVersion()
            }

            return appliedCount
        }
    }

    private func articleRuleSnapshots() throws -> [RuleEngine.ArticleRuleSnapshot] {
        try database.read { db in
            try articleRuleSnapshots(db: db)
        }
    }

    private func articleRuleSnapshots(db: Database) throws -> [RuleEngine.ArticleRuleSnapshot] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT
                a.id,
                a.title,
                a.summary,
                a.author,
                a.link,
                f.title AS feedTitle
            FROM articles a
            JOIN feeds f ON f.id = a.feedID
            """)

        return rows.map { row in
            RuleEngine.ArticleRuleSnapshot(
                id: row["id"],
                title: row["title"],
                summary: row["summary"],
                author: row["author"],
                link: row["link"],
                feedTitle: row["feedTitle"]
            )
        }
    }

    private func saveTag(_ tag: RuleEngine.TagSnapshot, db: Database) throws {
        try db.execute(
            sql: """
                INSERT INTO tags (id, name, colorHex, createdAt, updatedAt)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    name = excluded.name,
                    colorHex = excluded.colorHex,
                    updatedAt = excluded.updatedAt
                """,
            arguments: [tag.id, tag.name, tag.colorHex, Date(), Date()]
        )
    }

    private func insertTagAssignment(
        _ assignment: RuleEngine.ArticleTagAssignment,
        db: Database
    ) throws -> Bool {
        try db.execute(
            sql: """
                INSERT OR IGNORE INTO article_tags (articleID, tagID, assignedAt)
                VALUES (?, ?, ?)
                """,
            arguments: [assignment.articleID, assignment.tag.id, Date()]
        )
        return db.changesCount > 0
    }

    private func hideArticleIfNeeded(articleID: String, db: Database) throws -> String? {
        let feedID = try String.fetchOne(db, sql: """
            SELECT feedID
            FROM articles
            WHERE id = ?
            LIMIT 1
            """, arguments: [articleID])

        try db.execute(
            sql: """
                UPDATE article_statuses
                SET isHidden = 1, hiddenAt = ?
                WHERE articleID = ? AND isHidden = 0
                """,
            arguments: [Date(), articleID]
        )

        guard db.changesCount > 0 else {
            return nil
        }

        return feedID
    }

    private func updateUnreadCount(feedID: String, db: Database) throws {
        let unreadCount = try Int.fetchOne(db, sql: """
            SELECT COUNT(*)
            FROM articles a
            JOIN article_statuses s ON s.articleID = a.id
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
