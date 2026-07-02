import Foundation
import GRDB

struct FeedTagRecord: Codable, FetchableRecord, MutablePersistableRecord, Equatable, Sendable {
    static let databaseTableName = "feed_tags"

    var feedID: String
    var tagID: String
    var assignedAt: Date
}
