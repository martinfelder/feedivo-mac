import Foundation
import GRDB

struct ArticleTagRecord: Codable, FetchableRecord, MutablePersistableRecord, Equatable, Sendable {
    static let databaseTableName = "article_tags"

    var articleID: String
    var tagID: String
    var assignedAt: Date
}
