import Foundation
import GRDB

struct ArticleStatusRecord: Codable, FetchableRecord, MutablePersistableRecord, Equatable, Sendable {
    static let databaseTableName = "article_statuses"

    var articleID: String
    var isRead: Bool
    var isStarred: Bool
    var isArchived: Bool
    var isHidden: Bool
    var readAt: Date?
    var starredAt: Date?
    var archivedAt: Date?
    var hiddenAt: Date?
    var dateArrived: Date

    init(
        articleID: String,
        isRead: Bool = false,
        isStarred: Bool = false,
        isArchived: Bool = false,
        isHidden: Bool = false,
        readAt: Date? = nil,
        starredAt: Date? = nil,
        archivedAt: Date? = nil,
        hiddenAt: Date? = nil,
        dateArrived: Date = Date()
    ) {
        self.articleID = articleID
        self.isRead = isRead
        self.isStarred = isStarred
        self.isArchived = isArchived
        self.isHidden = isHidden
        self.readAt = readAt
        self.starredAt = starredAt
        self.archivedAt = archivedAt
        self.hiddenAt = hiddenAt
        self.dateArrived = dateArrived
    }
}
