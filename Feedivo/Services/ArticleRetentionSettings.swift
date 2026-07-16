import Foundation

enum ArticleRetentionSettings {
    static let isEnabledKey = "articleRetention.isEnabled"
    static let retentionDaysKey = "articleRetention.retentionDays"
    static let minimumArticlesPerFeedKey = "articleRetention.minimumArticlesPerFeed"
    static let includesProtectedArticlesKey = "articleRetention.includesProtectedArticles"
    static let lastAutomaticCleanupDateKey = "articleRetention.lastAutomaticCleanupDate"
    static let lastAutomaticCleanupStatusKey = "articleRetention.lastAutomaticCleanupStatus"
    static let lastAutomaticCleanupErrorKey = "articleRetention.lastAutomaticCleanupError"
    static let lastAutomaticCleanupRemovedCountKey = "articleRetention.lastAutomaticCleanupRemovedCount"
    static let statusSuccess = "success"
    static let statusFailed = "failed"
    static let defaultIsEnabled = false
    static let defaultRetentionDays = 90
    static let defaultMinimumArticlesPerFeed = 20
    static let defaultIncludesProtectedArticles = false
    static let allowedRetentionDays = [30, 60, 90, 180, 365]
    static let allowedMinimumArticlesPerFeed = [0, 10, 20, 50, 100, 200, 300, 400, 500]

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
}
