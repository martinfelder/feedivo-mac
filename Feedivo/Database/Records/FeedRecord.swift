import Foundation
import GRDB

struct FeedRecord: Codable, FetchableRecord, MutablePersistableRecord, Equatable, Sendable {
    static let databaseTableName = "feeds"

    var id: String
    var url: String
    var title: String
    var websiteURL: String?
    var faviconURL: String?
    var folderName: String?
    var refreshIntervalMinutes: Int
    var lastRefreshedAt: Date?
    var lastETag: String?
    var lastModified: String?
    var lastBodyHash: String?
    var lastHTTPStatusCode: Int?
    var unreadCount: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        url: String,
        title: String,
        websiteURL: String? = nil,
        faviconURL: String? = nil,
        folderName: String? = nil,
        refreshIntervalMinutes: Int = 30,
        lastRefreshedAt: Date? = nil,
        lastETag: String? = nil,
        lastModified: String? = nil,
        lastBodyHash: String? = nil,
        lastHTTPStatusCode: Int? = nil,
        unreadCount: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.websiteURL = websiteURL
        self.faviconURL = faviconURL
        self.folderName = folderName
        self.refreshIntervalMinutes = refreshIntervalMinutes
        self.lastRefreshedAt = lastRefreshedAt
        self.lastETag = lastETag
        self.lastModified = lastModified
        self.lastBodyHash = lastBodyHash
        self.lastHTTPStatusCode = lastHTTPStatusCode
        self.unreadCount = unreadCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
