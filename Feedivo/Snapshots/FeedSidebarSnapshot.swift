import Foundation

struct FeedSidebarSnapshot: Equatable, Identifiable, Sendable {
    var id: String
    var title: String
    var url: String
    var faviconURL: String?
    var folderName: String?
    var unreadCount: Int
}
