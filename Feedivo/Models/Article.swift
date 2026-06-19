import Foundation
import SwiftData

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
    var isRead: Bool
    var isStarred: Bool

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
        feed: Feed? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.link = link
        self.summary = summary
        self.content = content
        self.publishedAt = publishedAt
        self.imageURL = imageURL
        self.isRead = isRead
        self.isStarred = isStarred
        self.feed = feed
        self.tags = []
    }
}
