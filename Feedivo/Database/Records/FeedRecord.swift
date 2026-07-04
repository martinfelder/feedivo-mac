import Foundation
import GRDB

struct FeedRecord: Codable, FetchableRecord, Identifiable, MutablePersistableRecord, Equatable, Sendable {
    static let databaseTableName = "feeds"

    var id: String
    var url: String
    var title: String
    var originalTitle: String?
    var websiteURL: String?
    var faviconURL: String?
    var folderName: String?
    var refreshIntervalMinutes: Int
    var isNotificationEnabled: Bool
    var articleRetentionOverridesGlobalSetting: Bool
    var articleRetentionIsEnabled: Bool
    var articleRetentionDays: Int
    var articleRetentionMinimumArticles: Int
    var articleRetentionIncludesProtectedArticles: Bool
    var lastRefreshedAt: Date?
    var lastETag: String?
    var lastModified: String?
    var lastBodyHash: String?
    var lastHTTPStatusCode: Int?
    var cacheControlMaxAge: Int?
    var conditionalGetSetAt: Date?
    var unreadCount: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        url: String,
        title: String,
        originalTitle: String? = nil,
        websiteURL: String? = nil,
        faviconURL: String? = nil,
        folderName: String? = nil,
        refreshIntervalMinutes: Int = 30,
        isNotificationEnabled: Bool = false,
        articleRetentionOverridesGlobalSetting: Bool = false,
        articleRetentionIsEnabled: Bool = false,
        articleRetentionDays: Int = 90,
        articleRetentionMinimumArticles: Int = 20,
        articleRetentionIncludesProtectedArticles: Bool = false,
        lastRefreshedAt: Date? = nil,
        lastETag: String? = nil,
        lastModified: String? = nil,
        lastBodyHash: String? = nil,
        lastHTTPStatusCode: Int? = nil,
        cacheControlMaxAge: Int? = nil,
        conditionalGetSetAt: Date? = nil,
        unreadCount: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.originalTitle = originalTitle ?? title
        self.websiteURL = websiteURL
        self.faviconURL = faviconURL
        self.folderName = folderName
        self.refreshIntervalMinutes = refreshIntervalMinutes
        self.isNotificationEnabled = isNotificationEnabled
        self.articleRetentionOverridesGlobalSetting = articleRetentionOverridesGlobalSetting
        self.articleRetentionIsEnabled = articleRetentionIsEnabled
        self.articleRetentionDays = articleRetentionDays
        self.articleRetentionMinimumArticles = articleRetentionMinimumArticles
        self.articleRetentionIncludesProtectedArticles = articleRetentionIncludesProtectedArticles
        self.lastRefreshedAt = lastRefreshedAt
        self.lastETag = lastETag
        self.lastModified = lastModified
        self.lastBodyHash = lastBodyHash
        self.lastHTTPStatusCode = lastHTTPStatusCode
        self.cacheControlMaxAge = cacheControlMaxAge
        self.conditionalGetSetAt = conditionalGetSetAt
        self.unreadCount = unreadCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
