enum SidebarUnreadCount {
    static func unreadArticleCount(for feed: Feed) -> Int {
        feed.unreadCount
    }

    static func totalUnreadArticleCount(in feeds: [Feed]) -> Int {
        feeds.reduce(0) { total, feed in
            total + feed.unreadCount
        }
    }

    static func badgeText(for count: Int) -> String? {
        count > 0 ? "\(count)" : nil
    }
}

enum SidebarTagCount {
    static func articleCount(for tag: Tag) -> Int {
        let directArticleIDs = Set(tag.articles.map(\.id))
        let feedArticleIDs = Set(tag.feeds.flatMap(\.articles).map(\.id))

        return directArticleIDs.union(feedArticleIDs).count
    }

    static func badgeText(for tag: Tag) -> String? {
        SidebarUnreadCount.badgeText(for: articleCount(for: tag))
    }
}
