import Foundation
import GRDB

struct ArticleRecord: Codable, FetchableRecord, MutablePersistableRecord, Equatable, Sendable {
    static let databaseTableName = "articles"

    var id: String
    var feedID: String
    var sourceID: String?
    var link: String?
    var title: String
    var summary: String?
    var content: String?
    var imageURL: String?
    var author: String?
    var publishedAt: Date?
    var arrivedAt: Date
    var updatedAt: Date
    var estimatedReadingMinutes: Int?
}
