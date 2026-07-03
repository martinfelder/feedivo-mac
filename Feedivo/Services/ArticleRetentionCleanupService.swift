import Foundation
import GRDB
import SwiftData

enum ArticleRetentionCleanupService {
    @MainActor
    @discardableResult
    static func removeExpiredArticles(
        in context: ModelContext,
        isEnabled: Bool,
        retentionDays: Int,
        includeProtectedArticles: Bool = false,
        now: Date = Date()
    ) throws -> Int {
        // P6: Nur Skalar-Attribute laden (ohne die großen content/offlineContent-
        // Blobs) — die Cleanup-Logik liest nur publishedAt/feedID/isStarred/
        // isArchived/isRead/isHidden. Ein Date-Prädikat zur Vorfilterung ist in
        // SwiftData nicht möglich (Optional<Date> im #Predicate → Runtime-Fault
        // bzw. Compile-Fehler), daher Reduktion über propertiesToFetch.
        let articles = try context.fetch(Article.lightFetchDescriptor())
        let feedsByID = try feedsByID(in: context)
        let articlesToRemove = articles.filter {
            let configuration = retentionConfiguration(
                for: $0,
                feedsByID: feedsByID,
                globalIsEnabled: isEnabled,
                globalRetentionDays: retentionDays,
                globalIncludesProtectedArticles: includeProtectedArticles,
                now: now
            )

            return shouldRemove(
                $0,
                cutoffDate: configuration.cutoffDate,
                isEnabled: configuration.isEnabled,
                includeProtectedArticles: configuration.includeProtectedArticles
            )
        }

        guard !articlesToRemove.isEmpty else {
            return 0
        }

        let changedFeedIDs = Set(articlesToRemove.compactMap(\.feedID))
        let unreadCounts = unreadCountsByFeedID(
            afterRemoving: articlesToRemove,
            from: articles
        )

        for article in articlesToRemove {
            context.delete(article)
        }

        if !changedFeedIDs.isEmpty {
            try syncUnreadCounts(
                for: changedFeedIDs,
                unreadCounts: unreadCounts,
                in: context
            )
        }

        try context.save()

        return articlesToRemove.count
    }

    @MainActor
    @discardableResult
    static func removeExpiredSQLiteArticles(
        in _: ModelContext,
        database: FeedivoDatabase,
        isEnabled: Bool,
        retentionDays: Int,
        includeProtectedArticles: Bool = false,
        now: Date = Date()
    ) throws -> Int {
        let globalConfiguration = ArticleRetentionConfiguration(
            isEnabled: isEnabled,
            retentionDays: retentionDays,
            includeProtectedArticles: includeProtectedArticles,
            now: now
        )
        let feedConfigurations = try sqliteFeedRetentionConfigurations(
            in: database,
            globalConfiguration: globalConfiguration,
            now: now
        )

        let removedCount = try database.write { db in
            let candidates = try SQLiteArticleRetentionCandidate.fetchAll(db, sql: """
                SELECT
                    a.id,
                    a.feedID,
                    a.publishedAt,
                    s.isStarred,
                    s.isArchived,
                    s.isRead,
                    s.isHidden
                FROM articles a
                JOIN article_statuses s ON s.articleID = a.id
                """)

            let expiredCandidates = candidates.filter { candidate in
                let configuration = feedConfigurations[candidate.feedID] ?? globalConfiguration
                return shouldRemove(
                    candidate,
                    cutoffDate: configuration.cutoffDate,
                    isEnabled: configuration.isEnabled,
                    includeProtectedArticles: configuration.includeProtectedArticles
                )
            }

            guard !expiredCandidates.isEmpty else {
                return 0
            }

            let articleIDs = expiredCandidates.map(\.id)
            let changedFeedIDs = Set(expiredCandidates.map(\.feedID))

            try deleteSQLiteArticles(articleIDs, db: db)
            try recalculateSQLiteUnreadCounts(for: changedFeedIDs, db: db)

            return articleIDs.count
        }

        if removedCount > 0 {
            SQLiteDataInvalidation.bumpStatusVersion()
        }

        return removedCount
    }

    static func shouldRemove(
        _ article: Article,
        cutoffDate: Date,
        isEnabled: Bool = true,
        includeProtectedArticles: Bool = false
    ) -> Bool {
        guard isEnabled else {
            return false
        }

        guard
            let publishedAt = article.publishedAt,
            publishedAt < cutoffDate
        else {
            return false
        }

        if includeProtectedArticles {
            return true
        }

        return !article.isStarred && !article.isArchived
    }

    private static func shouldRemove(
        _ article: SQLiteArticleRetentionCandidate,
        cutoffDate: Date,
        isEnabled: Bool = true,
        includeProtectedArticles: Bool = false
    ) -> Bool {
        guard isEnabled else {
            return false
        }

        guard
            let publishedAt = article.publishedAt,
            publishedAt < cutoffDate
        else {
            return false
        }

        if includeProtectedArticles {
            return true
        }

        return !article.isStarred && !article.isArchived
    }

    private static func retentionConfiguration(
        for article: Article,
        feedsByID: [UUID: Feed],
        globalIsEnabled: Bool,
        globalRetentionDays: Int,
        globalIncludesProtectedArticles: Bool,
        now: Date
    ) -> ArticleRetentionConfiguration {
        if
            let feedID = article.feedID,
            let feed = feedsByID[feedID],
            feed.articleRetentionOverridesGlobalSetting
        {
            let configuration = ArticleRetentionSettings.effectiveConfiguration(
                for: feed,
                now: now
            )
            return ArticleRetentionConfiguration(configuration)
        }

        return ArticleRetentionConfiguration(
            isEnabled: globalIsEnabled,
            retentionDays: globalRetentionDays,
            includeProtectedArticles: globalIncludesProtectedArticles,
            now: now
        )
    }

    @MainActor
    private static func feedsByID(in context: ModelContext) throws -> [UUID: Feed] {
        let feeds = try context.fetch(FetchDescriptor<Feed>())
        return Dictionary(uniqueKeysWithValues: feeds.map { ($0.id, $0) })
    }

    private static func sqliteFeedRetentionConfigurations(
        in database: FeedivoDatabase,
        globalConfiguration: ArticleRetentionConfiguration,
        now: Date
    ) throws -> [String: ArticleRetentionConfiguration] {
        let feeds = try database.read { db in
            try FeedRecord.fetchAll(db)
        }
        var configurations: [String: ArticleRetentionConfiguration] = [:]

        for feed in feeds {
            if feed.articleRetentionOverridesGlobalSetting {
                configurations[feed.id] = ArticleRetentionConfiguration(
                    isEnabled: feed.articleRetentionIsEnabled,
                    retentionDays: feed.articleRetentionDays,
                    includeProtectedArticles: feed.articleRetentionIncludesProtectedArticles,
                    now: now
                )
            } else {
                configurations[feed.id] = globalConfiguration
            }
        }

        return configurations
    }

    @MainActor
    private static func syncUnreadCounts(
        for feedIDs: Set<UUID>,
        unreadCounts: [UUID: Int],
        in context: ModelContext
    ) throws {
        let feeds = try context.fetch(FetchDescriptor<Feed>())

        for feed in feeds where feedIDs.contains(feed.id) {
            feed.unreadCount = unreadCounts[feed.id, default: 0]
        }
    }

    private static func unreadCountsByFeedID(
        afterRemoving articlesToRemove: [Article],
        from articles: [Article]
    ) -> [UUID: Int] {
        // P6: Identitäts-Membership per Set<ObjectIdentifier> (O(1)-Lookup) statt
        // O(n·m) `contains(where: ===)` pro Artikel.
        let removeIDs = Set(articlesToRemove.map { ObjectIdentifier($0) })
        var unreadCounts: [UUID: Int] = [:]

        for article in articles
        where !removeIDs.contains(ObjectIdentifier(article)) && !article.isRead && !article.isHidden {
            if let feedID = article.feedID {
                unreadCounts[feedID, default: 0] += 1
            }
        }

        return unreadCounts
    }

    private static func deleteSQLiteArticles(_ articleIDs: [String], db: Database) throws {
        for chunk in articleIDs.chunked(into: 400) {
            let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ", ")
            let arguments = StatementArguments(chunk)

            try db.execute(
                sql: "DELETE FROM article_statuses WHERE articleID IN (\(placeholders))",
                arguments: arguments
            )
            try db.execute(
                sql: "DELETE FROM articles WHERE id IN (\(placeholders))",
                arguments: arguments
            )
        }
    }

    private static func recalculateSQLiteUnreadCounts(for feedIDs: Set<String>, db: Database) throws {
        for feedID in feedIDs {
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
}

private struct SQLiteArticleRetentionCandidate: FetchableRecord {
    let id: String
    let feedID: String
    let publishedAt: Date?
    let isStarred: Bool
    let isArchived: Bool
    let isRead: Bool
    let isHidden: Bool

    init(row: Row) throws {
        id = row["id"]
        feedID = row["feedID"]
        publishedAt = row["publishedAt"]
        isStarred = row["isStarred"]
        isArchived = row["isArchived"]
        isRead = row["isRead"]
        isHidden = row["isHidden"]
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else {
            return [self]
        }

        return stride(from: 0, to: count, by: size).map { startIndex in
            Array(self[startIndex..<Swift.min(startIndex + size, count)])
        }
    }
}

private struct ArticleRetentionConfiguration {
    let isEnabled: Bool
    let cutoffDate: Date
    let includeProtectedArticles: Bool

    init(_ configuration: ArticleRetentionEffectiveConfiguration) {
        self.isEnabled = configuration.isEnabled
        self.cutoffDate = configuration.cutoffDate
        self.includeProtectedArticles = configuration.includeProtectedArticles
    }

    init(
        isEnabled: Bool,
        retentionDays: Int,
        includeProtectedArticles: Bool,
        now: Date
    ) {
        self.isEnabled = isEnabled
        self.cutoffDate = ArticleRetentionSettings.cutoffDate(
            retentionDays: retentionDays,
            now: now
        )
        self.includeProtectedArticles = includeProtectedArticles
    }
}
