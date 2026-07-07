import Foundation
import GRDB

// Art eines Feed-Logeintrags. Wird als String gespeichert, an den Aufrufstellen
// aber typsicher als enum übergeben — keine Magic-Strings mehr verstreut im Code.
enum FeedLogEntryKind: String {
    case info
    case error
}

struct FeedLogRecord: Codable, FetchableRecord, MutablePersistableRecord, Equatable, Sendable {
    static let databaseTableName = "feed_logs"

    var id: String
    var feedID: String
    var createdAt: Date
    var level: String
    var message: String
    var httpStatusCode: Int?
    var newArticleCount: Int

    init(
        id: String = UUID().uuidString,
        feedID: String,
        createdAt: Date = Date(),
        level: String,
        message: String,
        httpStatusCode: Int? = nil,
        newArticleCount: Int = 0
    ) {
        self.id = id
        self.feedID = feedID
        self.createdAt = createdAt
        self.level = level
        self.message = message
        self.httpStatusCode = httpStatusCode
        self.newArticleCount = newArticleCount
    }
}
