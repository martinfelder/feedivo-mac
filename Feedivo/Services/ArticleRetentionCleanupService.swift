import Foundation
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
