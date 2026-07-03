import Foundation
import GRDB
import Testing
@testable import Feedivo

struct SQLiteDatabaseMigrationTests {
    @Test func migrationCreatesCoreTables() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        let tableNames = try database.debugTableNames()

        #expect(tableNames.contains("feeds"))
        #expect(tableNames.contains("articles"))
        #expect(tableNames.contains("article_statuses"))
        #expect(tableNames.contains("feed_logs"))
        #expect(tableNames.contains("tags"))
        #expect(tableNames.contains("article_tags"))
        #expect(tableNames.contains("feed_tags"))
        #expect(tableNames.contains("article_search"))
        #expect(tableNames.contains("article_offline"))
    }

    @Test func migrationCreatesPerformanceIndexes() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        let indexNames = try database.debugIndexNames()

        #expect(indexNames.contains("idx_feeds_url_unique"))
        #expect(indexNames.contains("idx_feeds_title"))
        #expect(indexNames.contains("idx_articles_feed_published"))
        #expect(indexNames.contains("idx_articles_published"))
        #expect(indexNames.contains("idx_articles_feed_source_unique"))
        #expect(indexNames.contains("idx_articles_feed_link_unique"))
        #expect(indexNames.contains("idx_article_statuses_is_read"))
        #expect(indexNames.contains("idx_article_statuses_is_starred"))
        #expect(indexNames.contains("idx_article_statuses_is_archived"))
        #expect(indexNames.contains("idx_article_statuses_is_hidden"))
        #expect(indexNames.contains("idx_feed_logs_feed_created"))
        #expect(indexNames.contains("idx_tags_name_unique"))
        #expect(indexNames.contains("idx_article_tags_tag_article"))
        #expect(indexNames.contains("idx_feed_tags_tag_feed"))
        #expect(indexNames.contains("idx_article_offline_state"))
    }

    @Test func migrationCreatesArticleSearchTriggers() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        let triggerNames = try database.debugTriggerNames()

        #expect(triggerNames.contains("articles_ai"))
        #expect(triggerNames.contains("articles_au"))
        #expect(triggerNames.contains("articles_ad"))
    }

    @Test func articleStatusesHaveNoForeignKeyCascadeToArticles() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        let foreignKeys = try database.debugForeignKeys(for: "article_statuses")

        #expect(foreignKeys.isEmpty)
    }

    @Test func debugForeignKeysRejectsUnsupportedTableNames() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        #expect(throws: FeedivoDatabase.DebugTableInspectionError.self) {
            _ = try database.debugForeignKeys(for: "sqlite_master")
        }
    }

    @Test func articleTagsCascadeWhenArticleOrTagIsDeleted() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        try insertFeed(into: database, id: "feed-1")
        try insertArticle(
            into: database,
            id: "article-1",
            feedID: "feed-1",
            sourceID: "source-1",
            link: "https://example.com/articles/1"
        )
        try insertTag(into: database, id: "tag-1")
        try insertArticleTag(into: database, articleID: "article-1", tagID: "tag-1")

        try database.write { database in
            try database.execute(sql: "DELETE FROM articles WHERE id = ?", arguments: ["article-1"])
        }

        #expect(try rowCount(in: database, table: "article_tags") == 0)

        try insertArticle(
            into: database,
            id: "article-2",
            feedID: "feed-1",
            sourceID: "source-2",
            link: "https://example.com/articles/2"
        )
        try insertArticleTag(into: database, articleID: "article-2", tagID: "tag-1")

        try database.write { database in
            try database.execute(sql: "DELETE FROM tags WHERE id = ?", arguments: ["tag-1"])
        }

        #expect(try rowCount(in: database, table: "article_tags") == 0)
    }

    @Test func feedTagsCascadeWhenFeedOrTagIsDeleted() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        try insertFeed(into: database, id: "feed-1")
        try insertTag(into: database, id: "tag-1")
        try insertFeedTag(into: database, feedID: "feed-1", tagID: "tag-1")

        try database.write { database in
            try database.execute(sql: "DELETE FROM feeds WHERE id = ?", arguments: ["feed-1"])
        }

        #expect(try rowCount(in: database, table: "feed_tags") == 0)

        try insertFeed(into: database, id: "feed-2")
        try insertFeedTag(into: database, feedID: "feed-2", tagID: "tag-1")

        try database.write { database in
            try database.execute(sql: "DELETE FROM tags WHERE id = ?", arguments: ["tag-1"])
        }

        #expect(try rowCount(in: database, table: "feed_tags") == 0)
    }

    @Test func deletingFeedCascadesToArticlesAndFeedLogsButNotArticleStatuses() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        try insertFeed(into: database, id: "feed-1")
        try insertArticle(
            into: database,
            id: "article-1",
            feedID: "feed-1",
            sourceID: "source-1",
            link: "https://example.com/articles/1"
        )
        try insertFeedLog(into: database, id: "log-1", feedID: "feed-1")
        try insertArticleStatus(into: database, articleID: "article-1")

        try database.write { database in
            try database.execute(
                sql: "DELETE FROM feeds WHERE id = ?",
                arguments: ["feed-1"]
            )
        }

        #expect(try rowCount(in: database, table: "articles") == 0)
        #expect(try rowCount(in: database, table: "feed_logs") == 0)
        #expect(try rowCount(in: database, table: "article_statuses") == 1)
    }

    @Test func duplicateNonEmptySourceIDPerFeedViolatesPartialUniqueIndex() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        try insertFeed(into: database, id: "feed-1")
        try insertArticle(
            into: database,
            id: "article-1",
            feedID: "feed-1",
            sourceID: "source-1",
            link: "https://example.com/articles/1"
        )

        #expect(throws: DatabaseError.self) {
            try insertArticle(
                into: database,
                id: "article-2",
                feedID: "feed-1",
                sourceID: "source-1",
                link: "https://example.com/articles/2"
            )
        }
    }

    @Test func duplicateEmptyOrMissingSourceIDPerFeedIsAllowed() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        try insertFeed(into: database, id: "feed-1")
        try insertArticle(
            into: database,
            id: "article-1",
            feedID: "feed-1",
            sourceID: nil,
            link: "https://example.com/articles/1"
        )
        try insertArticle(
            into: database,
            id: "article-2",
            feedID: "feed-1",
            sourceID: nil,
            link: "https://example.com/articles/2"
        )
        try insertArticle(
            into: database,
            id: "article-3",
            feedID: "feed-1",
            sourceID: "",
            link: "https://example.com/articles/3"
        )
        try insertArticle(
            into: database,
            id: "article-4",
            feedID: "feed-1",
            sourceID: "",
            link: "https://example.com/articles/4"
        )

        #expect(try rowCount(in: database, table: "articles") == 4)
    }

    @Test func duplicateNonEmptyLinkPerFeedViolatesPartialUniqueIndex() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        try insertFeed(into: database, id: "feed-1")
        try insertArticle(
            into: database,
            id: "article-1",
            feedID: "feed-1",
            sourceID: "source-1",
            link: "https://example.com/articles/shared"
        )

        #expect(throws: DatabaseError.self) {
            try insertArticle(
                into: database,
                id: "article-2",
                feedID: "feed-1",
                sourceID: "source-2",
                link: "https://example.com/articles/shared"
            )
        }
    }

    @Test func duplicateEmptyOrMissingLinkPerFeedIsAllowed() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        try insertFeed(into: database, id: "feed-1")
        try insertArticle(
            into: database,
            id: "article-1",
            feedID: "feed-1",
            sourceID: "source-1",
            link: nil
        )
        try insertArticle(
            into: database,
            id: "article-2",
            feedID: "feed-1",
            sourceID: "source-2",
            link: nil
        )
        try insertArticle(
            into: database,
            id: "article-3",
            feedID: "feed-1",
            sourceID: "source-3",
            link: ""
        )
        try insertArticle(
            into: database,
            id: "article-4",
            feedID: "feed-1",
            sourceID: "source-4",
            link: ""
        )

        #expect(try rowCount(in: database, table: "articles") == 4)
    }
}

private func insertFeed(
    into database: FeedivoDatabase,
    id: String,
    url: String? = nil,
    title: String = "Beispiel Feed"
) throws {
    let now = Date()

    try database.write { database in
        try database.execute(
            sql: """
                INSERT INTO feeds (
                    id, url, title, refreshIntervalMinutes, unreadCount, createdAt, updatedAt
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                id,
                url ?? "https://example.com/\(id).xml",
                title,
                30,
                0,
                now,
                now
            ]
        )
    }
}

private func insertArticle(
    into database: FeedivoDatabase,
    id: String,
    feedID: String,
    sourceID: String?,
    link: String?
) throws {
    let now = Date()

    try database.write { database in
        try database.execute(
            sql: """
                INSERT INTO articles (
                    id, feedID, sourceID, link, title, arrivedAt, updatedAt
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                id,
                feedID,
                sourceID,
                link,
                "Artikel \(id)",
                now,
                now
            ]
        )
    }
}

private func insertArticleStatus(into database: FeedivoDatabase, articleID: String) throws {
    try database.write { database in
        try database.execute(
            sql: """
                INSERT INTO article_statuses (
                    articleID, isRead, isStarred, isArchived, isHidden, dateArrived
                ) VALUES (?, ?, ?, ?, ?, ?)
                """,
            arguments: [articleID, false, false, false, false, Date()]
        )
    }
}

private func insertFeedLog(into database: FeedivoDatabase, id: String, feedID: String) throws {
    try database.write { database in
        try database.execute(
            sql: """
                INSERT INTO feed_logs (
                    id, feedID, createdAt, level, message, newArticleCount
                ) VALUES (?, ?, ?, ?, ?, ?)
                """,
            arguments: [id, feedID, Date(), "info", "Refresh", 1]
        )
    }
}

private func insertTag(into database: FeedivoDatabase, id: String) throws {
    let now = Date()

    try database.write { database in
        try database.execute(
            sql: """
                INSERT INTO tags (
                    id, name, colorHex, createdAt, updatedAt
                ) VALUES (?, ?, ?, ?, ?)
                """,
            arguments: [id, "Tag \(id)", "#888888", now, now]
        )
    }
}

private func insertArticleTag(into database: FeedivoDatabase, articleID: String, tagID: String) throws {
    try database.write { database in
        try database.execute(
            sql: """
                INSERT INTO article_tags (
                    articleID, tagID, assignedAt
                ) VALUES (?, ?, ?)
                """,
            arguments: [articleID, tagID, Date()]
        )
    }
}

private func insertFeedTag(into database: FeedivoDatabase, feedID: String, tagID: String) throws {
    try database.write { database in
        try database.execute(
            sql: """
                INSERT INTO feed_tags (
                    feedID, tagID, assignedAt
                ) VALUES (?, ?, ?)
                """,
            arguments: [feedID, tagID, Date()]
        )
    }
}

private func rowCount(in database: FeedivoDatabase, table: String) throws -> Int {
    try database.read { database in
        try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM \(table)") ?? 0
    }
}
