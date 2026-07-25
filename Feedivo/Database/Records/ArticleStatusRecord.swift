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
    /// Last-Write-Wins-Zeitstempel UND Sync-Eligibility-Filter für iCloud Sync Phase 2b —
    /// `nil` bedeutet "nie vom Nutzer bewusst verändert", bleibt außerhalb jeder
    /// Sync-Betrachtung. Siehe `CloudSyncArticleStatusMapping`.
    var statusSyncUpdatedAt: Date?

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
        dateArrived: Date = Date(),
        statusSyncUpdatedAt: Date? = nil
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
        self.statusSyncUpdatedAt = statusSyncUpdatedAt
    }
}
