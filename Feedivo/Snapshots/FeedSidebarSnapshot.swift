import Foundation

struct FeedSidebarSnapshot: Equatable, Identifiable, Sendable {
    var id: String
    var title: String
    var faviconURL: String?
    var folderName: String?
    var sortIndex: Int = 0
    var unreadCount: Int
    var hasRecentError: Bool
}
