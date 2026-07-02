import Foundation

struct ArticleReaderSnapshot: Equatable, Identifiable, Sendable {
    var id: String
    var feedID: String
    var feedTitle: String
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
}
