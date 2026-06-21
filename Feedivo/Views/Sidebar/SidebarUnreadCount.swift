import SwiftData

enum SidebarUnreadCount {
    static func unreadCountsByFeed(in unreadArticles: [Article]) -> [PersistentIdentifier: Int] {
        unreadArticles.reduce(into: [:]) { counts, article in
            guard let feed = article.feed else {
                return
            }

            counts[feed.persistentModelID, default: 0] += 1
        }
    }

    static func unreadArticleCount(
        for feed: Feed,
        in unreadCountsByFeed: [PersistentIdentifier: Int]
    ) -> Int {
        unreadCountsByFeed[feed.persistentModelID, default: 0]
    }

    static func totalUnreadArticleCount(in unreadArticles: [Article]) -> Int {
        unreadArticles.count
    }

    static func badgeText(for count: Int) -> String? {
        count > 0 ? "\(count)" : nil
    }
}
