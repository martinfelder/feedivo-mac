import Foundation

struct ArticleListSnapshot: Equatable, Identifiable, Sendable {
    var id: String
    var feedID: String
    var feedTitle: String
    var title: String
    var summary: String?
    var link: String?
    var imageURL: String?
    var publishedAt: Date?
    var arrivedAt: Date
    var estimatedReadingMinutes: Int?
    var isRead: Bool
    var isStarred: Bool
    var isArchived: Bool
    var isHidden: Bool
    var faviconURL: String?
    var offlineStateRaw: String = ArticleOfflineState.none.rawValue

    var offlineState: ArticleOfflineState {
        ArticleOfflineState(rawValue: offlineStateRaw) ?? .none
    }
}
