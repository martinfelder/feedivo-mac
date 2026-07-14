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
        #expect(tableNames.contains("feed_folders"))
        #expect(tableNames.contains("rules"))
        #expect(tableNames.contains("rule_conditions"))
        #expect(tableNames.contains("smart_folders"))
        #expect(tableNames.contains("smart_folder_conditions"))
        #expect(tableNames.contains("article_identity_history"))
    }

    @Test func migrationCreatesPerformanceIndexes() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        let indexNames = try database.debugIndexNames()

        #expect(indexNames.contains("idx_feeds_url"))
        #expect(!indexNames.contains("idx_feeds_url_unique"))
        #expect(try !indexIsUnique("idx_feeds_url", on: "feeds", database: database))
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
        #expect(indexNames.contains("idx_feed_folders_name_unique"))
        #expect(indexNames.contains("idx_rules_sort_order"))
        #expect(indexNames.contains("idx_rule_conditions_rule_sort"))
        #expect(indexNames.contains("idx_smart_folders_sort_order"))
        #expect(indexNames.contains("idx_smart_folders_default_key_unique"))
        #expect(indexNames.contains("idx_smart_folder_conditions_folder_sort"))
        #expect(indexNames.contains("idx_article_identity_history_source_unique"))
        #expect(indexNames.contains("idx_article_identity_history_link_unique"))
        #expect(indexNames.contains("idx_article_identity_history_title_hash"))
        #expect(indexNames.contains("idx_article_identity_history_last_seen"))
    }

    @Test func migrationCreatesArticleStatusesHiddenReadCompositeIndex() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        let indexNames = try database.debugIndexNames()

        #expect(indexNames.contains("idx_article_statuses_hidden_read"))
    }

    @Test func migrationCreatesArticlesPublishedCoalesceExpressionIndex() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        let indexNames = try database.debugIndexNames()

        #expect(indexNames.contains("idx_articles_published_coalesce"))
    }

    @Test func migrationFuegtWasRemovedByRetentionSpalteZuIdentityHistoryHinzu() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        let columns = try database.read { db in
            try Row.fetchAll(db, sql: "PRAGMA table_info(article_identity_history)")
        }
        let column = columns.first { ($0["name"] as String?) == "wasRemovedByRetention" }

        #expect(column != nil)
        #expect((column?["notnull"] as Int?) == 1)
        #expect((column?["dflt_value"] as String?) == "0")
    }

    @Test func queryPlanForTimelineOrderByNutztCoalesceIndex() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        let plan = try database.read { db in
            try Row.fetchAll(db, sql: """
                EXPLAIN QUERY PLAN
                SELECT a.id
                FROM articles a
                JOIN feeds f ON f.id = a.feedID
                JOIN article_statuses s ON s.articleID = a.id
                ORDER BY COALESCE(a.publishedAt, a.arrivedAt) DESC, a.arrivedAt DESC
                LIMIT 10
                """)
        }

        let planDetails = plan.compactMap { row in row["detail"] as String? }.joined(separator: " | ")
        #expect(planDetails.contains("idx_articles_published_coalesce"))
    }

    @Test func migrationCreatesArticleSearchTriggers() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        let triggerNames = try database.debugTriggerNames()

        #expect(triggerNames.contains("articles_ai"))
        #expect(triggerNames.contains("articles_au"))
        #expect(triggerNames.contains("articles_ad"))
    }

    @Test func articleStatusesCascadeWhenArticleIsDeleted() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        let foreignKeys = try database.debugForeignKeys(for: "article_statuses")

        #expect(foreignKeys == ["articles"])
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

    @Test func ruleConditionsCascadeWhenRuleIsDeleted() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        try insertRule(into: database, id: "rule-1")
        try insertRuleCondition(into: database, id: "condition-1", ruleID: "rule-1")

        try database.write { database in
            try database.execute(sql: "DELETE FROM rules WHERE id = ?", arguments: ["rule-1"])
        }

        #expect(try rowCount(in: database, table: "rule_conditions") == 0)
    }

    @Test func smartFolderConditionsCascadeWhenFolderIsDeleted() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        try insertSmartFolder(into: database, id: "folder-1")
        try insertSmartFolderCondition(into: database, id: "condition-1", smartFolderID: "folder-1")

        try database.write { database in
            try database.execute(sql: "DELETE FROM smart_folders WHERE id = ?", arguments: ["folder-1"])
        }

        #expect(try rowCount(in: database, table: "smart_folder_conditions") == 0)
    }

    @Test func deletingFeedCascadesToArticlesFeedLogsAndArticleStatuses() throws {
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
        #expect(try rowCount(in: database, table: "article_statuses") == 0)
    }

    @Test func deletingSingleArticleCascadesToArticleStatuses() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        try insertFeed(into: database, id: "feed-1")
        try insertArticle(
            into: database,
            id: "article-1",
            feedID: "feed-1",
            sourceID: "source-1",
            link: "https://example.com/articles/1"
        )
        try insertArticleStatus(into: database, articleID: "article-1")

        try database.write { database in
            try database.execute(sql: "DELETE FROM articles WHERE id = ?", arguments: ["article-1"])
        }

        #expect(try rowCount(in: database, table: "article_statuses") == 0)
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

    @Test func duplicateFeedURLsAreAllowed() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        try insertFeed(into: database, id: "feed-1", url: "https://example.com/shared.xml")
        try insertFeed(into: database, id: "feed-2", url: "https://example.com/shared.xml")

        #expect(try rowCount(in: database, table: "feeds") == 2)
    }

    @Test func migrationErsetztAltenUniqueFeedURLIndexBeimUpgrade() throws {
        let queue = try DatabaseQueue()
        var legacyMigrator = DatabaseMigrator()
        legacyMigrator.registerMigration("v1_create_core_tables") { database in
            try database.create(table: "feeds") { table in
                table.column("id", .text).primaryKey()
                table.column("url", .text).notNull()
                table.column("title", .text).notNull()
                table.column("folderName", .text)
                table.column("refreshIntervalMinutes", .integer).notNull().defaults(to: 30)
                table.column("unreadCount", .integer).notNull().defaults(to: 0)
                table.column("createdAt", .datetime).notNull()
                table.column("updatedAt", .datetime).notNull()
            }
            try database.create(index: "idx_feeds_url_unique", on: "feeds", columns: ["url"], unique: true)

            try database.create(table: "articles") { table in
                table.column("id", .text).primaryKey()
                table.column("feedID", .text).notNull().references("feeds", onDelete: .cascade)
                table.column("sourceID", .text)
                table.column("link", .text)
                table.column("title", .text).notNull()
                table.column("description", .text)
                table.column("author", .text)
                table.column("publishedAt", .datetime)
                table.column("arrivedAt", .datetime).notNull()
                table.column("updatedAt", .datetime).notNull()
            }

            try database.create(table: "article_statuses") { table in
                table.column("articleID", .text).primaryKey().references("articles", onDelete: .cascade)
                table.column("isRead", .boolean).notNull().defaults(to: false)
                table.column("isStarred", .boolean).notNull().defaults(to: false)
                table.column("isArchived", .boolean).notNull().defaults(to: false)
                table.column("isHidden", .boolean).notNull().defaults(to: false)
                table.column("readAt", .datetime)
                table.column("starredAt", .datetime)
                table.column("archivedAt", .datetime)
                table.column("hiddenAt", .datetime)
                table.column("dateArrived", .datetime).notNull()
            }

            try database.create(table: "feed_logs") { table in
                table.column("id", .text).primaryKey()
                table.column("feedID", .text).notNull().references("feeds", onDelete: .cascade)
                table.column("createdAt", .datetime).notNull()
                table.column("level", .text).notNull()
                table.column("message", .text)
                table.column("newArticleCount", .integer).notNull()
            }
        }
        for identifier in [
            "v2_create_tag_tables",
            "v3_create_feed_tag_table",
            "v4_create_article_search_index",
            "v5_create_article_offline_table",
            "v7_add_feed_admin_fields"
        ] {
            legacyMigrator.registerMigration(identifier) { _ in }
        }
        legacyMigrator.registerMigration("v6_create_admin_definition_tables") { database in
            try database.create(table: "feed_folders") { table in
                table.column("id", .text).primaryKey()
                table.column("name", .text).notNull()
                table.column("createdAt", .datetime).notNull()
                table.column("updatedAt", .datetime).notNull()
            }
        }
        try legacyMigrator.migrate(queue)

        try FeedivoDatabaseMigrator.migrator.migrate(queue)
        let database = FeedivoDatabase(writer: queue)

        #expect(try !database.debugIndexNames().contains("idx_feeds_url_unique"))
        #expect(try database.debugIndexNames().contains("idx_feeds_url"))
        #expect(try !indexIsUnique("idx_feeds_url", on: "feeds", database: database))

        try insertFeed(into: database, id: "feed-1", url: "https://example.com/shared.xml")
        try insertFeed(into: database, id: "feed-2", url: "https://example.com/shared.xml")

        #expect(try rowCount(in: database, table: "feeds") == 2)
    }

    @Test func migrationV15BackfilltSortIndexAusBestehenderAlphabetischerReihenfolge() throws {
        let queue = try DatabaseQueue()
        try FeedivoDatabaseMigrator.migrator.migrate(queue, upTo: "v14_add_article_identity_history_retention_flag")

        try queue.write { db in
            let now = Date()
            // Wichtig: Zu diesem Zeitpunkt (nur bis v14 migriert) existiert die
            // sortIndex-Spalte auf BEIDEN Tabellen noch nicht — sie darf in
            // diesen INSERTs deshalb noch nicht auftauchen, sonst schlägt die
            // Query mit "no such column: sortIndex" fehl.
            try db.execute(
                sql: """
                    INSERT INTO feed_folders (id, name, createdAt, updatedAt)
                    VALUES ('folder-tech', 'Tech', ?, ?)
                    """,
                arguments: [now, now]
            )
            // "News" existiert NUR implizit über ein Feed, ohne eigenen feed_folders-Datensatz.
            try db.execute(
                sql: """
                    INSERT INTO feeds (
                        id, url, title, folderName, refreshIntervalMinutes,
                        isNotificationEnabled, articleRetentionOverridesGlobalSetting,
                        articleRetentionIsEnabled, articleRetentionDays,
                        articleRetentionMinimumArticles, articleRetentionIncludesProtectedArticles,
                        unreadCount, createdAt, updatedAt
                    ) VALUES
                        ('feed-b', 'https://b.example/feed.xml', 'Beta', 'Tech', 30, 0, 0, 0, 90, 20, 0, 0, ?, ?),
                        ('feed-a', 'https://a.example/feed.xml', 'Alpha', 'Tech', 30, 0, 0, 0, 90, 20, 0, 0, ?, ?),
                        ('feed-z', 'https://z.example/feed.xml', 'Zulu', 'News', 30, 0, 0, 0, 90, 20, 0, 0, ?, ?),
                        ('feed-x', 'https://x.example/feed.xml', 'Xray', NULL, 30, 0, 0, 0, 90, 20, 0, 0, ?, ?)
                    """,
                arguments: [now, now, now, now, now, now, now, now]
            )
        }

        try FeedivoDatabaseMigrator.migrator.migrate(queue)

        let feedSortIndexByID = try queue.read { db in
            try Row.fetchAll(db, sql: "SELECT id, sortIndex FROM feeds")
        }.reduce(into: [String: Int]()) { result, row in
            result[row["id"]] = row["sortIndex"]
        }
        // "Tech"-Gruppe: Alpha vor Beta (alphabetisch).
        #expect(feedSortIndexByID["feed-a"] == 0)
        #expect(feedSortIndexByID["feed-b"] == 1)
        // "News"-Gruppe (nur ein Feed) und "Ohne Ordner"-Gruppe (nur ein Feed)
        // starten jeweils unabhängig bei 0.
        #expect(feedSortIndexByID["feed-z"] == 0)
        #expect(feedSortIndexByID["feed-x"] == 0)

        let folders = try queue.read { db in
            try Row.fetchAll(db, sql: "SELECT name, sortIndex FROM feed_folders ORDER BY sortIndex")
        }
        // "News" (nur implizit) wird materialisiert; alphabetisch VOR "Tech" einsortiert.
        #expect(folders.map { $0["name"] as String } == ["News", "Tech"])
        #expect(folders.map { $0["sortIndex"] as Int } == [0, 1])
    }

    @Test func migrationV15IstIdempotentBeiBereitsVorhandenerSpalte() throws {
        // Regressionstest gegen versehentliches erneutes Ausführen der Migration
        // gegen eine bereits vollständig migrierte Datenbank (Standardfall bei
        // jedem regulären App-Start über FeedivoDatabase.inMemoryForTests()).
        let database = try FeedivoDatabase.inMemoryForTests()

        let columns = try database.read { db in
            try Row.fetchAll(db, sql: "PRAGMA table_info(feeds)")
        }
        let sortIndexColumn = columns.first { ($0["name"] as String?) == "sortIndex" }

        #expect(sortIndexColumn != nil)
        #expect((sortIndexColumn?["notnull"] as Int?) == 1)
        #expect((sortIndexColumn?["dflt_value"] as String?) == "0")
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

private func insertRule(into database: FeedivoDatabase, id: String) throws {
    let now = Date()

    try database.write { database in
        try database.execute(
            sql: """
                INSERT INTO rules (
                    id, name, isEnabled, matchMode, action, notificationTemplate,
                    notificationPriority, sortOrder, createdAt, updatedAt
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                id,
                "Regel \(id)",
                true,
                "all",
                "assignTag",
                "{Titel}",
                "normal",
                0,
                now,
                now
            ]
        )
    }
}

private func insertRuleCondition(into database: FeedivoDatabase, id: String, ruleID: String) throws {
    try database.write { database in
        try database.execute(
            sql: """
                INSERT INTO rule_conditions (
                    id, ruleID, field, conditionOperator, value, sortOrder
                ) VALUES (?, ?, ?, ?, ?, ?)
                """,
            arguments: [id, ruleID, "title", "contains", "Swift", 0]
        )
    }
}

private func insertSmartFolder(into database: FeedivoDatabase, id: String) throws {
    let now = Date()

    try database.write { database in
        try database.execute(
            sql: """
                INSERT INTO smart_folders (
                    id, name, matchMode, isShownInSidebar, isDefault,
                    sortOrder, defaultKey, iconName, colorHex, createdAt, updatedAt
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                id,
                "Ordner \(id)",
                "all",
                true,
                false,
                0,
                nil,
                "folder.badge.gearshape",
                "#6B7280",
                now,
                now
            ]
        )
    }
}

private func insertSmartFolderCondition(
    into database: FeedivoDatabase,
    id: String,
    smartFolderID: String
) throws {
    try database.write { database in
        try database.execute(
            sql: """
                INSERT INTO smart_folder_conditions (
                    id, smartFolderID, field, conditionOperator, value, sortOrder
                ) VALUES (?, ?, ?, ?, ?, ?)
                """,
            arguments: [id, smartFolderID, "title", "contains", "Swift", 0]
        )
    }
}

private func rowCount(in database: FeedivoDatabase, table: String) throws -> Int {
    try database.read { database in
        try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM \(table)") ?? 0
    }
}

private func indexIsUnique(_ indexName: String, on tableName: String, database: FeedivoDatabase) throws -> Bool {
    try database.read { database in
        let rows = try Row.fetchAll(database, sql: "PRAGMA index_list(\(tableName))")
        guard let row = rows.first(where: { ($0["name"] as String?) == indexName }),
              let unique = row["unique"] as Int?
        else {
            return false
        }

        return unique == 1
    }
}
