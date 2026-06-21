enum SidebarUnreadCount {
    static func unreadArticleCount(in feed: Feed) -> Int {
        feed.articles.filter { !$0.isRead }.count
    }

    static func totalUnreadArticleCount(in feeds: [Feed]) -> Int {
        feeds.reduce(0) { $0 + unreadArticleCount(in: $1) }
    }

    static func badgeText(for count: Int) -> String? {
        count > 0 ? "\(count)" : nil
    }
}
