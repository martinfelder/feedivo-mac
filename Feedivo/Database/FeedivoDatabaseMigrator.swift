import Foundation
import GRDB

enum FeedivoDatabaseMigrator {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_create_core_tables") { database in
            try database.create(table: "feeds") { table in
                table.column("id", .text).primaryKey()
                table.column("url", .text).notNull()
                table.column("title", .text).notNull()
                table.column("websiteURL", .text)
                table.column("faviconURL", .text)
                table.column("folderName", .text)
                table.column("refreshIntervalMinutes", .integer).notNull().defaults(to: 30)
                table.column("lastRefreshedAt", .datetime)
                table.column("lastETag", .text)
                table.column("lastModified", .text)
                table.column("lastBodyHash", .text)
                table.column("lastHTTPStatusCode", .integer)
                table.column("unreadCount", .integer).notNull().defaults(to: 0)
                table.column("createdAt", .datetime).notNull()
                table.column("updatedAt", .datetime).notNull()
            }

            try database.create(table: "articles") { table in
                table.column("id", .text).primaryKey()
                table.column("feedID", .text).notNull()
                    .references("feeds", column: "id", onDelete: .cascade)
                table.column("sourceID", .text)
                table.column("link", .text)
                table.column("title", .text).notNull()
                table.column("summary", .text)
                table.column("content", .text)
                table.column("imageURL", .text)
                table.column("author", .text)
                table.column("publishedAt", .datetime)
                table.column("arrivedAt", .datetime).notNull()
                table.column("updatedAt", .datetime).notNull()
                table.column("estimatedReadingMinutes", .integer)
            }

            try database.create(table: "article_statuses") { table in
                table.column("articleID", .text).primaryKey()
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
                table.column("feedID", .text).notNull()
                    .references("feeds", column: "id", onDelete: .cascade)
                table.column("createdAt", .datetime).notNull()
                table.column("level", .text).notNull()
                table.column("message", .text).notNull()
                table.column("httpStatusCode", .integer)
                table.column("newArticleCount", .integer).notNull().defaults(to: 0)
            }

            try database.create(index: "idx_feeds_url_unique", on: "feeds", columns: ["url"], unique: true)
            try database.create(index: "idx_feeds_title", on: "feeds", columns: ["title"])
            try database.create(index: "idx_articles_feed_published", on: "articles", columns: ["feedID", "publishedAt"])
            try database.create(index: "idx_articles_published", on: "articles", columns: ["publishedAt"])
            try database.execute(sql: """
                CREATE UNIQUE INDEX idx_articles_feed_source_unique
                ON articles(feedID, sourceID)
                WHERE sourceID IS NOT NULL AND sourceID <> ''
                """)
            try database.execute(sql: """
                CREATE UNIQUE INDEX idx_articles_feed_link_unique
                ON articles(feedID, link)
                WHERE link IS NOT NULL AND link <> ''
                """)
            try database.create(index: "idx_article_statuses_is_read", on: "article_statuses", columns: ["isRead"])
            try database.create(index: "idx_article_statuses_is_starred", on: "article_statuses", columns: ["isStarred"])
            try database.create(index: "idx_article_statuses_is_archived", on: "article_statuses", columns: ["isArchived"])
            try database.create(index: "idx_article_statuses_is_hidden", on: "article_statuses", columns: ["isHidden"])
            try database.create(index: "idx_feed_logs_feed_created", on: "feed_logs", columns: ["feedID", "createdAt"])
        }

        migrator.registerMigration("v2_create_tag_tables") { database in
            try database.create(table: "tags") { table in
                table.column("id", .text).primaryKey()
                table.column("name", .text).notNull()
                table.column("colorHex", .text).notNull().defaults(to: "#888888")
                table.column("createdAt", .datetime).notNull()
                table.column("updatedAt", .datetime).notNull()
            }

            try database.create(table: "article_tags") { table in
                table.column("articleID", .text).notNull()
                    .references("articles", column: "id", onDelete: .cascade)
                table.column("tagID", .text).notNull()
                    .references("tags", column: "id", onDelete: .cascade)
                table.column("assignedAt", .datetime).notNull()
                table.primaryKey(["articleID", "tagID"])
            }

            try database.create(index: "idx_tags_name_unique", on: "tags", columns: ["name"], unique: true)
            try database.create(index: "idx_article_tags_tag_article", on: "article_tags", columns: ["tagID", "articleID"])
        }

        migrator.registerMigration("v3_create_feed_tag_table") { database in
            try database.create(table: "feed_tags") { table in
                table.column("feedID", .text).notNull()
                    .references("feeds", column: "id", onDelete: .cascade)
                table.column("tagID", .text).notNull()
                    .references("tags", column: "id", onDelete: .cascade)
                table.column("assignedAt", .datetime).notNull()
                table.primaryKey(["feedID", "tagID"])
            }

            try database.create(index: "idx_feed_tags_tag_feed", on: "feed_tags", columns: ["tagID", "feedID"])
        }

        migrator.registerMigration("v4_create_article_search_index") { database in
            try database.execute(sql: """
                CREATE VIRTUAL TABLE article_search USING fts5(
                    title,
                    summary,
                    content,
                    author,
                    content='articles',
                    content_rowid='rowid',
                    tokenize='unicode61 remove_diacritics 2'
                )
                """)

            try database.execute(sql: """
                CREATE TRIGGER articles_ai AFTER INSERT ON articles BEGIN
                    INSERT INTO article_search(rowid, title, summary, content, author)
                    VALUES (new.rowid, new.title, new.summary, new.content, new.author);
                END
                """)

            try database.execute(sql: """
                CREATE TRIGGER articles_ad AFTER DELETE ON articles BEGIN
                    INSERT INTO article_search(article_search, rowid, title, summary, content, author)
                    VALUES ('delete', old.rowid, old.title, old.summary, old.content, old.author);
                END
                """)

            try database.execute(sql: """
                CREATE TRIGGER articles_au AFTER UPDATE ON articles BEGIN
                    INSERT INTO article_search(article_search, rowid, title, summary, content, author)
                    VALUES ('delete', old.rowid, old.title, old.summary, old.content, old.author);
                    INSERT INTO article_search(rowid, title, summary, content, author)
                    VALUES (new.rowid, new.title, new.summary, new.content, new.author);
                END
                """)

            try database.execute(sql: "INSERT INTO article_search(article_search) VALUES ('rebuild')")
        }

        return migrator
    }
}
