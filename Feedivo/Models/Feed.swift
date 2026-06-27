import Foundation
import SwiftData

// Feed repräsentiert einen abonnierten RSS-Kanal
@Model
class Feed {
    var id: UUID = UUID()
    var url: String = ""
    var title: String = ""
    var originalTitle: String?
    var feedDescription: String?
    var faviconURL: String?
    var siteURL: String?
    var followedAt: Date?
    var folderName: String?
    var lastRefreshed: Date?
    var refreshIntervalMinutes: Int = 60
    var isNotificationEnabled: Bool = false
    var articleRetentionOverridesGlobalSetting: Bool = false
    var articleRetentionIsEnabled: Bool = false
    var articleRetentionDays: Int = 90
    var articleRetentionIncludesProtectedArticles: Bool = false
    var unreadCount: Int = 0

    @Relationship(deleteRule: .cascade)
    var articles: [Article] = []

    @Relationship(deleteRule: .cascade, inverse: \FeedLogEntry.feed)
    var logEntries: [FeedLogEntry] = []

    @Relationship
    var tags: [Tag] = []

    init(
        url: String,
        title: String,
        feedDescription: String? = nil,
        faviconURL: String? = nil,
        siteURL: String? = nil,
        followedAt: Date? = nil,
        folderName: String? = nil,
        lastRefreshed: Date? = nil,
        refreshIntervalMinutes: Int = 60,
        isNotificationEnabled: Bool = false,
        articleRetentionOverridesGlobalSetting: Bool = false,
        articleRetentionIsEnabled: Bool = false,
        articleRetentionDays: Int = 90,
        articleRetentionIncludesProtectedArticles: Bool = false
    ) {
        self.id = UUID()
        self.url = url
        self.title = title
        self.originalTitle = title
        self.feedDescription = feedDescription
        self.faviconURL = faviconURL
        self.siteURL = siteURL
        self.followedAt = followedAt
        self.folderName = folderName
        self.lastRefreshed = lastRefreshed
        self.refreshIntervalMinutes = refreshIntervalMinutes
        self.isNotificationEnabled = isNotificationEnabled
        self.articleRetentionOverridesGlobalSetting = articleRetentionOverridesGlobalSetting
        self.articleRetentionIsEnabled = articleRetentionIsEnabled
        self.articleRetentionDays = articleRetentionDays
        self.articleRetentionIncludesProtectedArticles = articleRetentionIncludesProtectedArticles
        self.unreadCount = 0
        self.articles = []
        self.logEntries = []
        self.tags = []
    }

    convenience init(
        url: String,
        title: String,
        originalTitle: String?,
        feedDescription: String? = nil,
        faviconURL: String? = nil,
        siteURL: String? = nil,
        followedAt: Date? = nil,
        folderName: String? = nil,
        lastRefreshed: Date? = nil,
        refreshIntervalMinutes: Int = 60,
        isNotificationEnabled: Bool = false,
        articleRetentionOverridesGlobalSetting: Bool = false,
        articleRetentionIsEnabled: Bool = false,
        articleRetentionDays: Int = 90,
        articleRetentionIncludesProtectedArticles: Bool = false
    ) {
        self.init(
            url: url,
            title: title,
            feedDescription: feedDescription,
            faviconURL: faviconURL,
            siteURL: siteURL,
            followedAt: followedAt,
            folderName: folderName,
            lastRefreshed: lastRefreshed,
            refreshIntervalMinutes: refreshIntervalMinutes,
            isNotificationEnabled: isNotificationEnabled,
            articleRetentionOverridesGlobalSetting: articleRetentionOverridesGlobalSetting,
            articleRetentionIsEnabled: articleRetentionIsEnabled,
            articleRetentionDays: articleRetentionDays,
            articleRetentionIncludesProtectedArticles: articleRetentionIncludesProtectedArticles
        )
        self.originalTitle = originalTitle ?? title
    }
}
