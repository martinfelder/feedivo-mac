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

    init(title: String) {
        self.id = UUID()
        self.title = title
        self.isRead = false
        self.isStarred = false
        self.tags = []
    }
}
