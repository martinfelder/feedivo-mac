import SwiftData

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
    @MainActor
    static func articleCount(for tag: Tag, context: ModelContext) throws -> Int {
        let descriptor = FetchDescriptor<Article>(
            predicate: ArticleListQuery.tagPredicate(for: tag, taggedFeeds: tag.feeds)
        )

        return try context.fetchCount(descriptor)
    }

    @MainActor
    static func badgeText(for tag: Tag, context: ModelContext) throws -> String? {
        try SidebarUnreadCount.badgeText(for: articleCount(for: tag, context: context))
    }
}

@MainActor
enum SmartFolderSidebarBadge {
    static func badgeText(for folder: SmartFolder, feeds: [Feed]) -> String? {
        badgeCount(for: folder, feeds: feeds).flatMap(SidebarUnreadCount.badgeText)
    }

    private static func badgeCount(for folder: SmartFolder, feeds: [Feed]) -> Int? {
        let conditions = folder.conditions.sorted { $0.sortOrder < $1.sortOrder }
        guard conditions.count == 1,
              RuleMatchMode.normalized(folder.matchModeRaw) == .all,
              let condition = conditions.first,
              condition.fieldRaw == SmartFolderConditionField.status.rawValue,
              condition.operatorRaw == SmartFolderConditionOperator.is.rawValue,
              condition.value == SmartFolderStatusValue.unread.rawValue
        else {
            return nil
        }

        return SidebarUnreadCount.totalUnreadArticleCount(in: feeds)
    }
}
