import Foundation
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
    static func badgeText(for folder: SmartFolder, feeds: [Feed], context: ModelContext) -> String? {
        badgeCount(for: folder, feeds: feeds, context: context).flatMap(SidebarUnreadCount.badgeText)
    }

    private static func badgeCount(for folder: SmartFolder, feeds: [Feed], context: ModelContext) -> Int? {
        guard let badgeKind = SmartFolderSidebarBadgeKind(folder: folder) else {
            return nil
        }

        switch badgeKind {
        case .unread:
            return SidebarUnreadCount.totalUnreadArticleCount(in: feeds)
        case .starred:
            return try? context.fetchCount(
                FetchDescriptor<Article>(
                    predicate: #Predicate<Article> { article in
                        article.isStarred
                    }
                )
            )
        case .hidden:
            return try? context.fetchCount(
                FetchDescriptor<Article>(
                    predicate: #Predicate<Article> { article in
                        article.isHidden
                    }
                )
            )
        case .saved:
            return try? context.fetchCount(
                FetchDescriptor<Article>(
                    predicate: #Predicate<Article> { article in
                        article.isStarred || article.isArchived
                    }
                )
            )
        }
    }
}

private enum SmartFolderSidebarBadgeKind {
    case unread
    case starred
    case hidden
    case saved

    init?(folder: SmartFolder) {
        let conditions = folder.conditions.sorted { $0.sortOrder < $1.sortOrder }

        if RuleMatchMode.normalized(folder.matchModeRaw) == .all,
           conditions.count == 1,
           let condition = conditions.first,
           condition.fieldRaw == SmartFolderConditionField.status.rawValue,
           condition.operatorRaw == SmartFolderConditionOperator.is.rawValue,
           let statusValue = SmartFolderStatusValue(rawValue: condition.value) {
            switch statusValue {
            case .unread:
                self = .unread
                return
            case .starred:
                self = .starred
                return
            case .hidden:
                self = .hidden
                return
            case .read, .archived:
                break
            }
        }

        if RuleMatchMode.normalized(folder.matchModeRaw) == .any,
           conditions.count == 2,
           conditions.allSatisfy({ condition in
               condition.fieldRaw == SmartFolderConditionField.status.rawValue
                   && condition.operatorRaw == SmartFolderConditionOperator.is.rawValue
           }) {
            let values = Set(conditions.map(\.value))
            if values == Set([
                SmartFolderStatusValue.starred.rawValue,
                SmartFolderStatusValue.archived.rawValue
            ]) {
                self = .saved
                return
            }
        }

        return nil
    }
}
