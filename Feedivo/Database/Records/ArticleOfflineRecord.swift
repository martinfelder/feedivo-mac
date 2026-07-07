import Foundation
import GRDB

enum ArticleOfflineState: String, CaseIterable, Codable {
    case none
    case feedContent
    case fullText
    case failed

    var isAvailable: Bool {
        self == .feedContent || self == .fullText
    }
}

struct ArticleOfflineRecord: Codable, FetchableRecord, MutablePersistableRecord, Equatable, Sendable {
    static let databaseTableName = "article_offline"

    var articleID: String
    var stateRaw: String
    var content: String?
    var requestedAt: Date?
    var savedAt: Date?
    var errorMessage: String?

    var state: ArticleOfflineState {
        ArticleOfflineState(rawValue: stateRaw) ?? .none
    }

    enum CodingKeys: String, CodingKey {
        case articleID
        case stateRaw = "state"
        case content
        case requestedAt
        case savedAt
        case errorMessage
    }
}
