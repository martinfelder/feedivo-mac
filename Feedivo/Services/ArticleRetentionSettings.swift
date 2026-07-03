import Foundation

enum ArticleRetentionSettings {
    static let isEnabledKey = "articleRetention.isEnabled"
    static let retentionDaysKey = "articleRetention.retentionDays"
    static let minimumArticlesPerFeedKey = "articleRetention.minimumArticlesPerFeed"
    static let includesProtectedArticlesKey = "articleRetention.includesProtectedArticles"
    static let defaultIsEnabled = false
    static let defaultRetentionDays = 90
    static let defaultMinimumArticlesPerFeed = 20
    static let defaultIncludesProtectedArticles = false
    static let allowedRetentionDays = [30, 60, 90, 180, 365]
    static let allowedMinimumArticlesPerFeed = [0, 10, 20, 50, 100]

    static func clampedRetentionDays(_ days: Int) -> Int {
        allowedRetentionDays.min { first, second in
            abs(first - days) < abs(second - days)
        } ?? defaultRetentionDays
    }

    static func cutoffDate(retentionDays: Int, now: Date = Date()) -> Date {
        now.addingTimeInterval(-TimeInterval(clampedRetentionDays(retentionDays) * 24 * 60 * 60))
    }

    static func clampedMinimumArticlesPerFeed(_ count: Int) -> Int {
        allowedMinimumArticlesPerFeed.min { first, second in
            abs(first - count) < abs(second - count)
        } ?? defaultMinimumArticlesPerFeed
    }

    static func effectiveConfiguration(
        for feed: Feed,
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) -> ArticleRetentionEffectiveConfiguration {
        if feed.articleRetentionOverridesGlobalSetting {
            return ArticleRetentionEffectiveConfiguration(
                isEnabled: feed.articleRetentionIsEnabled,
                retentionDays: feed.articleRetentionDays,
                minimumArticlesPerFeed: feed.articleRetentionMinimumArticles,
                includeProtectedArticles: feed.articleRetentionIncludesProtectedArticles,
                now: now
            )
        }

        return ArticleRetentionEffectiveConfiguration(
            isEnabled: defaults.bool(forKey: isEnabledKey),
            retentionDays: storedRetentionDays(in: defaults),
            minimumArticlesPerFeed: storedMinimumArticlesPerFeed(in: defaults),
            includeProtectedArticles: defaults.bool(forKey: includesProtectedArticlesKey),
            now: now
        )
    }

    static func canImportParsedArticle(
        _ parsedArticle: ParsedArticle,
        for feed: Feed,
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) -> Bool {
        let configuration = effectiveConfiguration(
            for: feed,
            defaults: defaults,
            now: now
        )

        guard configuration.isEnabled else {
            return true
        }

        guard let publishedAt = parsedArticle.publishedAt else {
            return true
        }

        return publishedAt >= configuration.cutoffDate
    }

    private static func storedRetentionDays(in defaults: UserDefaults) -> Int {
        let storedDays = defaults.integer(forKey: retentionDaysKey)
        guard storedDays > 0 else {
            return defaultRetentionDays
        }

        return clampedRetentionDays(storedDays)
    }

    private static func storedMinimumArticlesPerFeed(in defaults: UserDefaults) -> Int {
        guard defaults.object(forKey: minimumArticlesPerFeedKey) != nil else {
            return defaultMinimumArticlesPerFeed
        }

        return clampedMinimumArticlesPerFeed(defaults.integer(forKey: minimumArticlesPerFeedKey))
    }
}

struct ArticleRetentionEffectiveConfiguration {
    let isEnabled: Bool
    let cutoffDate: Date
    let minimumArticlesPerFeed: Int
    let includeProtectedArticles: Bool

    init(
        isEnabled: Bool,
        retentionDays: Int,
        minimumArticlesPerFeed: Int,
        includeProtectedArticles: Bool,
        now: Date
    ) {
        self.isEnabled = isEnabled
        self.cutoffDate = ArticleRetentionSettings.cutoffDate(
            retentionDays: retentionDays,
            now: now
        )
        self.minimumArticlesPerFeed = ArticleRetentionSettings.clampedMinimumArticlesPerFeed(minimumArticlesPerFeed)
        self.includeProtectedArticles = includeProtectedArticles
    }
}
