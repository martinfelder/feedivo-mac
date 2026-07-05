import Foundation

struct ReaderArticleTagMetadata: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let colorHex: String

    init(id: String, name: String, colorHex: String) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
    }

    init(record: TagRecord) {
        self.id = record.id
        self.name = record.name
        self.colorHex = record.colorHex
    }

    init(tag: Tag) {
        self.id = tag.id.uuidString
        self.name = tag.name
        self.colorHex = tag.colorHex
    }
}

struct ArticleReaderSnapshot: Equatable, Identifiable, Sendable {
    var id: String
    var feedID: String
    var feedTitle: String
    var folderName: String?
    var title: String
    var link: String?
    var summary: String?
    var content: String?
    var imageURL: String?
    var author: String?
    var publishedAt: Date?
    var arrivedAt: Date
    var estimatedReadingMinutes: Int?
    var isRead: Bool
    var isStarred: Bool
    var isArchived: Bool
    var isHidden: Bool
    var tags: [ReaderArticleTagMetadata] = []
    var offlineStateRaw: String = ArticleOfflineState.none.rawValue
    var offlineContent: String?
    var offlineRequestedAt: Date?
    var offlineSavedAt: Date?
    var offlineErrorMessage: String?

    var offlineState: ArticleOfflineState {
        ArticleOfflineState(rawValue: offlineStateRaw) ?? .none
    }
}
