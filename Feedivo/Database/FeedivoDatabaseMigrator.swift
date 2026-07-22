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

            try database.create(index: "idx_feeds_url", on: "feeds", columns: ["url"])
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

        migrator.registerMigration("v5_create_article_offline_table") { database in
            try database.create(table: "article_offline") { table in
                table.column("articleID", .text).primaryKey()
                    .references("articles", column: "id", onDelete: .cascade)
                table.column("state", .text).notNull().defaults(to: "none")
                table.column("content", .text)
                table.column("requestedAt", .datetime)
                table.column("savedAt", .datetime)
                table.column("errorMessage", .text)
            }

            try database.create(index: "idx_article_offline_state", on: "article_offline", columns: ["state"])
        }

        migrator.registerMigration("v6_create_admin_definition_tables") { database in
            try database.create(table: "feed_folders") { table in
                table.column("id", .text).primaryKey()
                table.column("name", .text).notNull()
                table.column("createdAt", .datetime).notNull()
                table.column("updatedAt", .datetime).notNull()
            }

            try database.create(table: "rules") { table in
                table.column("id", .text).primaryKey()
                table.column("name", .text).notNull()
                table.column("isEnabled", .boolean).notNull().defaults(to: true)
                table.column("matchMode", .text).notNull().defaults(to: RuleMatchMode.all.rawValue)
                table.column("action", .text).notNull().defaults(to: RuleAction.assignTag.rawValue)
                table.column("assignTagID", .text)
                    .references("tags", column: "id", onDelete: .setNull)
                table.column("notificationTemplate", .text).notNull().defaults(to: "{Titel}")
                table.column("notificationPriority", .text).notNull().defaults(to: RuleNotificationPriority.normal.rawValue)
                table.column("sortOrder", .integer).notNull().defaults(to: 0)
                table.column("createdAt", .datetime).notNull()
                table.column("updatedAt", .datetime).notNull()
            }

            try database.create(table: "rule_conditions") { table in
                table.column("id", .text).primaryKey()
                table.column("ruleID", .text).notNull()
                    .references("rules", column: "id", onDelete: .cascade)
                table.column("field", .text).notNull()
                table.column("conditionOperator", .text).notNull()
                table.column("value", .text).notNull()
                table.column("sortOrder", .integer).notNull().defaults(to: 0)
            }

            try database.create(table: "smart_folders") { table in
                table.column("id", .text).primaryKey()
                table.column("name", .text).notNull()
                table.column("matchMode", .text).notNull().defaults(to: RuleMatchMode.all.rawValue)
                table.column("isShownInSidebar", .boolean).notNull().defaults(to: true)
                table.column("isDefault", .boolean).notNull().defaults(to: false)
                table.column("sortOrder", .integer).notNull().defaults(to: 0)
                table.column("defaultKey", .text)
                table.column("iconName", .text)
                table.column("colorHex", .text)
                table.column("createdAt", .datetime).notNull()
                table.column("updatedAt", .datetime).notNull()
            }

            try database.create(table: "smart_folder_conditions") { table in
                table.column("id", .text).primaryKey()
                table.column("smartFolderID", .text).notNull()
                    .references("smart_folders", column: "id", onDelete: .cascade)
                table.column("field", .text).notNull()
                table.column("conditionOperator", .text).notNull()
                table.column("value", .text).notNull()
                table.column("sortOrder", .integer).notNull().defaults(to: 0)
            }

            try database.create(index: "idx_feed_folders_name_unique", on: "feed_folders", columns: ["name"], unique: true)
            try database.create(index: "idx_rules_sort_order", on: "rules", columns: ["sortOrder", "name"])
            try database.create(index: "idx_rule_conditions_rule_sort", on: "rule_conditions", columns: ["ruleID", "sortOrder"])
            try database.create(index: "idx_smart_folders_sort_order", on: "smart_folders", columns: ["sortOrder", "name"])
            try database.execute(sql: """
                CREATE UNIQUE INDEX idx_smart_folders_default_key_unique
                ON smart_folders(defaultKey)
                WHERE defaultKey IS NOT NULL AND defaultKey <> ''
                """)
            try database.create(index: "idx_smart_folder_conditions_folder_sort", on: "smart_folder_conditions", columns: ["smartFolderID", "sortOrder"])
        }

        migrator.registerMigration("v7_add_feed_admin_fields") { database in
            try database.alter(table: "feeds") { table in
                table.add(column: "originalTitle", .text)
                table.add(column: "isNotificationEnabled", .boolean).notNull().defaults(to: false)
                table.add(column: "articleRetentionOverridesGlobalSetting", .boolean).notNull().defaults(to: false)
                table.add(column: "articleRetentionIsEnabled", .boolean).notNull().defaults(to: false)
                table.add(column: "articleRetentionDays", .integer).notNull().defaults(to: 90)
                table.add(column: "articleRetentionIncludesProtectedArticles", .boolean).notNull().defaults(to: false)
            }

            try database.execute(sql: """
                UPDATE feeds
                SET originalTitle = title
                WHERE originalTitle IS NULL OR originalTitle = ''
                """)
        }

        migrator.registerMigration("v8_drop_unique_feed_url_index") { database in
            try database.execute(sql: "DROP INDEX IF EXISTS idx_feeds_url_unique")
            try database.execute(sql: "CREATE INDEX IF NOT EXISTS idx_feeds_url ON feeds(url)")
        }

        migrator.registerMigration("v9_create_article_identity_history") { database in
            try database.create(table: "article_identity_history") { table in
                table.column("id", .text).primaryKey()
                table.column("feedID", .text).notNull()
                    .references("feeds", column: "id", onDelete: .cascade)
                table.column("sourceID", .text)
                table.column("link", .text)
                table.column("titleHash", .text).notNull()
                table.column("publishedAt", .datetime)
                table.column("firstSeenAt", .datetime).notNull()
                table.column("lastSeenAt", .datetime).notNull()
                table.column("lastArticleID", .text)
                table.column("isRead", .boolean).notNull().defaults(to: false)
                table.column("isStarred", .boolean).notNull().defaults(to: false)
                table.column("isArchived", .boolean).notNull().defaults(to: false)
                table.column("isHidden", .boolean).notNull().defaults(to: false)
                table.column("readAt", .datetime)
                table.column("starredAt", .datetime)
                table.column("archivedAt", .datetime)
                table.column("hiddenAt", .datetime)
            }

            try database.execute(sql: """
                CREATE UNIQUE INDEX idx_article_identity_history_source_unique
                ON article_identity_history(feedID, sourceID)
                WHERE sourceID IS NOT NULL AND sourceID <> ''
                """)
            try database.execute(sql: """
                CREATE UNIQUE INDEX idx_article_identity_history_link_unique
                ON article_identity_history(feedID, link)
                WHERE link IS NOT NULL AND link <> ''
                """)
            try database.create(index: "idx_article_identity_history_title_hash", on: "article_identity_history", columns: ["feedID", "titleHash"])
            try database.create(index: "idx_article_identity_history_last_seen", on: "article_identity_history", columns: ["lastSeenAt"])
        }

        migrator.registerMigration("v10_add_feed_retention_minimum_articles") { database in
            try database.alter(table: "feeds") { table in
                table.add(column: "articleRetentionMinimumArticles", .integer).notNull().defaults(to: 20)
            }
        }

        migrator.registerMigration("v11_add_article_statuses_hidden_read_index") { database in
            try database.create(
                index: "idx_article_statuses_hidden_read",
                on: "article_statuses",
                columns: ["isHidden", "isRead"]
            )
        }

        migrator.registerMigration("v12_add_articles_published_coalesce_index") { database in
            try database.execute(sql: """
                CREATE INDEX idx_articles_published_coalesce
                ON articles(COALESCE(publishedAt, arrivedAt) DESC, arrivedAt DESC)
                """)
        }

        migrator.registerMigration("v13_add_article_statuses_foreign_key") { database in
            try database.create(table: "article_statuses_new") { table in
                table.column("articleID", .text).primaryKey()
                    .references("articles", column: "id", onDelete: .cascade)
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

            // Verwaiste Zeilen (aus dem Bug vor diesem Fix) werden bewusst NICHT
            // mitkopiert — die neue Fremdschluessel-Spalte wuerde sie ablehnen.
            try database.execute(sql: """
                INSERT INTO article_statuses_new
                SELECT
                    s.articleID, s.isRead, s.isStarred, s.isArchived, s.isHidden,
                    s.readAt, s.starredAt, s.archivedAt, s.hiddenAt, s.dateArrived
                FROM article_statuses s
                WHERE EXISTS (SELECT 1 FROM articles a WHERE a.id = s.articleID)
                """)

            try database.drop(table: "article_statuses")
            try database.rename(table: "article_statuses_new", to: "article_statuses")

            try database.create(index: "idx_article_statuses_is_read", on: "article_statuses", columns: ["isRead"])
            try database.create(index: "idx_article_statuses_is_starred", on: "article_statuses", columns: ["isStarred"])
            try database.create(index: "idx_article_statuses_is_archived", on: "article_statuses", columns: ["isArchived"])
            try database.create(index: "idx_article_statuses_is_hidden", on: "article_statuses", columns: ["isHidden"])
            try database.create(
                index: "idx_article_statuses_hidden_read",
                on: "article_statuses",
                columns: ["isHidden", "isRead"]
            )
        }

        migrator.registerMigration("v14_add_article_identity_history_retention_flag") { database in
            try database.alter(table: "article_identity_history") { table in
                table.add(column: "wasRemovedByRetention", .boolean)
                    .notNull()
                    .defaults(to: false)
            }
        }

        migrator.registerMigration("v15_add_feed_and_folder_sort_index") { database in
            try database.alter(table: "feeds") { table in
                table.add(column: "sortIndex", .integer).notNull().defaults(to: 0)
            }
            try database.alter(table: "feed_folders") { table in
                table.add(column: "sortIndex", .integer).notNull().defaults(to: 0)
            }

            try backfillFeedAndFolderSortIndex(database)
        }

        migrator.registerMigration("v16_add_tag_sort_index") { database in
            try database.alter(table: "tags") { table in
                table.add(column: "sortIndex", .integer).notNull().defaults(to: 0)
            }

            try backfillTagSortIndex(database)
        }

        migrator.registerMigration("v17_add_smart_folder_default_shows_read_articles") { database in
            try database.alter(table: "smart_folders") { table in
                table.add(column: "defaultShowsReadArticles", .boolean)
                    .notNull()
                    .defaults(to: false)
            }

            try backfillSmartFolderDefaultShowsReadArticles(database)
        }

        migrator.registerMigration("v18_create_cleanup_run_history") { database in
            try database.create(table: "cleanup_runs") { table in
                table.column("id", .text).primaryKey()
                table.column("executedAt", .datetime).notNull()
                table.column("deletedCount", .integer).notNull()
                table.column("triggerSource", .text).notNull()
                table.column("succeeded", .boolean).notNull()
                table.column("errorMessage", .text)
            }
            try database.create(
                index: "idx_cleanup_runs_executed_at",
                on: "cleanup_runs",
                columns: ["executedAt"]
            )
        }

        return migrator
    }

    /// Vergibt sortIndex-Werte für Feeds und Ordner passend zur AKTUELLEN
    /// alphabetischen Anzeige, damit Bestandsnutzer nach diesem Update keine
    /// sichtbare Umsortierung erleben. Materialisiert dabei zusätzlich alle
    /// bisher rein impliziten Ordner (nur über feeds.folderName, ohne eigenen
    /// feed_folders-Datensatz) als echte Datensätze — reimplementiert die
    /// case-insensitive Dedupliziierungs-/Sortierlogik von
    /// FeedFolderOrganizer.folderNames(...) eigenständig in reinem SQL/Swift,
    /// da FeedFolderOrganizer (Views-Schicht) zum Zeitpunkt dieser Migration
    /// nicht von der Datenbank-Schicht importiert werden soll.
    private static func backfillFeedAndFolderSortIndex(_ database: Database) throws {
        let feedFolderNames = try String.fetchAll(
            database,
            sql: "SELECT DISTINCT folderName FROM feeds WHERE folderName IS NOT NULL"
        )
        let explicitFolderNames = try String.fetchAll(database, sql: "SELECT name FROM feed_folders")

        var canonicalNamesByLowercasedName: [String: String] = [:]
        for name in feedFolderNames + explicitFolderNames {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if canonicalNamesByLowercasedName[key] == nil {
                canonicalNamesByLowercasedName[key] = trimmed
            }
        }

        let orderedFolderNames = canonicalNamesByLowercasedName.values.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }

        let now = Date()
        for (index, folderName) in orderedFolderNames.enumerated() {
            try database.execute(
                sql: "UPDATE feed_folders SET sortIndex = ? WHERE name = ? COLLATE NOCASE",
                arguments: [index, folderName]
            )

            if database.changesCount == 0 {
                try database.execute(
                    sql: """
                        INSERT INTO feed_folders (id, name, sortIndex, createdAt, updatedAt)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                    arguments: [UUID().uuidString, folderName, index, now, now]
                )
            }
        }

        struct FeedRow: FetchableRecord {
            let id: String
            let folderName: String?
            let title: String

            init(row: Row) {
                id = row["id"]
                folderName = row["folderName"]
                title = row["title"]
            }
        }

        let allFeeds = try FeedRow.fetchAll(database, sql: "SELECT id, folderName, title FROM feeds")
        var feedsByNormalizedFolderKey: [String: [FeedRow]] = [:]
        for feed in allFeeds {
            let trimmed = feed.folderName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let key = trimmed.isEmpty ? "" : trimmed.lowercased()
            feedsByNormalizedFolderKey[key, default: []].append(feed)
        }

        for (_, feedsInGroup) in feedsByNormalizedFolderKey {
            let sortedFeeds = feedsInGroup.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
            for (index, feed) in sortedFeeds.enumerated() {
                try database.execute(
                    sql: "UPDATE feeds SET sortIndex = ? WHERE id = ?",
                    arguments: [index, feed.id]
                )
            }
        }
    }

    /// Vergibt sortIndex-Werte für Tags passend zur AKTUELLEN alphabetischen
    /// Anzeige, damit Bestandsnutzer nach diesem Update keine sichtbare
    /// Umsortierung erleben — identisches Muster zu
    /// backfillFeedAndFolderSortIndex (v15).
    private static func backfillTagSortIndex(_ database: Database) throws {
        let orderedIDs = try String.fetchAll(
            database,
            sql: "SELECT id FROM tags ORDER BY name COLLATE NOCASE, id COLLATE NOCASE"
        )

        for (index, id) in orderedIDs.enumerated() {
            try database.execute(
                sql: "UPDATE tags SET sortIndex = ? WHERE id = ?",
                arguments: [index, id]
            )
        }
    }

    /// Setzt defaultShowsReadArticles=1 für die vier Standard-Ordner, die
    /// schon vor dieser Migration per fest verdrahteter Regel immer
    /// gelesene UND ungelesene Artikel zeigten — ihr Verhalten bleibt beim
    /// Umstieg auf die jetzt persistierte, im Editor änderbare Einstellung
    /// unverändert. Alle anderen Zeilen (inkl. eigener Ordner) behalten den
    /// Spalten-Default false.
    private static func backfillSmartFolderDefaultShowsReadArticles(_ database: Database) throws {
        try database.execute(
            sql: """
                UPDATE smart_folders
                SET defaultShowsReadArticles = 1
                WHERE defaultKey IN (?, ?, ?, ?)
                """,
            arguments: ["starred", "thisWeek", "hidden", "saved"]
        )
    }
}
