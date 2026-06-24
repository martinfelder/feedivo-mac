import Foundation
import SwiftData

enum ArticleOfflineState: String, CaseIterable, Codable {
    case none
    case feedContent
    case fullText
    case failed

    var isAvailable: Bool {
        self == .feedContent || self == .fullText
    }
}

// Article repräsentiert einen einzelnen Artikel aus einem Feed
@Model
class Article {
    var id: UUID
    var title: String
    var link: String?
    var summary: String?
    var content: String?
    var publishedAt: Date?
    var imageURL: String?
    var feedID: UUID?
    var isRead: Bool
    var isStarred: Bool
    var isArchived: Bool = false
    var isHidden: Bool = false
    var offlineStateRaw: String = ArticleOfflineState.none.rawValue
    var offlineContent: String?
    var offlineRequestedAt: Date?
    var offlineSavedAt: Date?
    var offlineErrorMessage: String?

    var offlineState: ArticleOfflineState {
        get {
            ArticleOfflineState(rawValue: offlineStateRaw) ?? .none
        }
        set {
            offlineStateRaw = newValue.rawValue
        }
    }

    @Relationship
    var feed: Feed?

    @Relationship
    var tags: [Tag]

    init(
        title: String,
        link: String? = nil,
        summary: String? = nil,
        content: String? = nil,
        publishedAt: Date? = nil,
        imageURL: String? = nil,
        isRead: Bool = false,
        isStarred: Bool = false,
        isArchived: Bool = false,
        isHidden: Bool = false,
        feed: Feed? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.link = link
        self.summary = summary
        self.content = content
        self.publishedAt = publishedAt
        self.imageURL = imageURL
        self.feedID = feed?.id
        self.isRead = isRead
        self.isStarred = isStarred
        self.isArchived = isArchived
        self.isHidden = isHidden
        self.offlineStateRaw = ArticleOfflineState.none.rawValue
        self.offlineContent = nil
        self.offlineRequestedAt = nil
        self.offlineSavedAt = nil
        self.offlineErrorMessage = nil
        self.feed = feed
        self.tags = []
    }
}
