import Foundation

struct FeedRefreshSnapshot: Sendable {
    var id: UUID
    var title: String
    var url: String
    var isNotificationEnabled: Bool = false
}
