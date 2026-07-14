import Foundation
import GRDB

struct ArticleIdentityHistoryRecord: Codable, FetchableRecord, MutablePersistableRecord, Equatable, Sendable {
    static let databaseTableName = "article_identity_history"

    var id: String
    var feedID: String
    var sourceID: String?
    var link: String?
    var titleHash: String
    var publishedAt: Date?
    var firstSeenAt: Date
    var lastSeenAt: Date
    var lastArticleID: String?
    var isRead: Bool
    var isStarred: Bool
    var isArchived: Bool
    var isHidden: Bool
    var readAt: Date?
    var starredAt: Date?
    var archivedAt: Date?
    var hiddenAt: Date?
    var wasRemovedByRetention: Bool = false
}
