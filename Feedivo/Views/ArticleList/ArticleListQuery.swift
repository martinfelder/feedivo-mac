import Foundation
import SwiftData

enum ArticleListQuery {
    static let sortDescriptors = [
        SortDescriptor<Article>(\.publishedAt, order: .reverse)
    ]

    static func feedPredicate(for feed: Feed) -> Predicate<Article> {
        let feedID = feed.id
        return #Predicate<Article> { article in
            article.feedID == feedID
        }
    }

    static func feedFetchDescriptor(for feed: Feed) -> FetchDescriptor<Article> {
        FetchDescriptor(
            predicate: feedPredicate(for: feed),
            sortBy: sortDescriptors
        )
    }

    static func tagPredicate(for tag: Tag, taggedFeeds: [Feed] = []) -> Predicate<Article> {
        let tagID = tag.id
        let feedIDs = taggedFeeds.map(\.id)
        return #Predicate<Article> { article in
            article.tags.contains { articleTag in
                articleTag.id == tagID
            } || (article.feedID.flatMap { feedID in
                feedIDs.contains(feedID)
            } ?? false)
        }
    }

    static func tagFetchDescriptor(for tag: Tag) -> FetchDescriptor<Article> {
        FetchDescriptor(
            predicate: tagPredicate(for: tag, taggedFeeds: tag.feeds),
            sortBy: sortDescriptors
        )
    }

    static func smartFolderFetchDescriptor(
        for folder: SmartFolder,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> FetchDescriptor<Article>? {
        guard let queryKind = SmartFolderOptimizedQueryKind(folder: folder) else {
            return nil
        }

        switch queryKind {
        case .all:
            return FetchDescriptor(sortBy: sortDescriptors)
        case .unread:
            return FetchDescriptor(
                predicate: #Predicate<Article> { article in
                    !article.isRead
                },
                sortBy: sortDescriptors
            )
        case .read:
            return FetchDescriptor(
                predicate: #Predicate<Article> { article in
                    article.isRead
                },
                sortBy: sortDescriptors
            )
        case .starred:
            return FetchDescriptor(
                predicate: #Predicate<Article> { article in
                    article.isStarred
                },
                sortBy: sortDescriptors
            )
        case .archived:
            return FetchDescriptor(
                predicate: #Predicate<Article> { article in
                    article.isArchived
                },
                sortBy: sortDescriptors
            )
        case .hidden:
            return FetchDescriptor(
                predicate: #Predicate<Article> { article in
                    article.isHidden
                },
                sortBy: sortDescriptors
            )
        case .saved:
            return FetchDescriptor(
                predicate: #Predicate<Article> { article in
                    article.isStarred || article.isArchived
                },
                sortBy: sortDescriptors
            )
        case .today:
            let startOfToday = calendar.startOfDay(for: now)
            let startOfTomorrow = calendar.date(
                byAdding: .day,
                value: 1,
                to: startOfToday
            ) ?? startOfToday
            return FetchDescriptor(
                predicate: #Predicate<Article> { article in
                    article.publishedAt != nil
                        && article.publishedAt! >= startOfToday
                        && article.publishedAt! < startOfTomorrow
                },
                sortBy: sortDescriptors
            )
        case .thisWeek:
            guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now) else {
                return nil
            }
            let startOfWeek = weekInterval.start
            let startOfNextWeek = weekInterval.end
            return FetchDescriptor(
                predicate: #Predicate<Article> { article in
                    article.publishedAt != nil
                        && article.publishedAt! >= startOfWeek
                        && article.publishedAt! < startOfNextWeek
                },
                sortBy: sortDescriptors
            )
        }
    }
}

private enum SmartFolderOptimizedQueryKind {
    case all
    case unread
    case read
    case starred
    case archived
    case hidden
    case saved
    case today
    case thisWeek

    init?(folder: SmartFolder) {
        let conditions = folder.conditions.sorted { firstCondition, secondCondition in
            firstCondition.sortOrder < secondCondition.sortOrder
        }

        guard !conditions.isEmpty else {
            self = .all
            return
        }

        if let singleCondition = conditions.first,
           conditions.count == 1,
           let queryKind = Self.singleConditionKind(singleCondition) {
            self = queryKind
            return
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

    private static func singleConditionKind(_ condition: SmartFolderCondition) -> Self? {
        guard condition.operatorRaw == SmartFolderConditionOperator.is.rawValue else {
            return nil
        }

        if condition.fieldRaw == SmartFolderConditionField.status.rawValue,
           let statusValue = SmartFolderStatusValue(rawValue: condition.value) {
            switch statusValue {
            case .unread:
                return .unread
            case .read:
                return .read
            case .starred:
                return .starred
            case .archived:
                return .archived
            case .hidden:
                return .hidden
            }
        }

        if condition.fieldRaw == SmartFolderConditionField.date.rawValue,
           let dateValue = SmartFolderDateValue(rawValue: condition.value) {
            switch dateValue {
            case .today:
                return .today
            case .thisWeek:
                return .thisWeek
            }
        }

        return nil
    }
}

struct ArticleListDisplayState {
    let articles: [Article]
    let showsReadArticles: Bool
    let selectedArticle: Article?
    let showsHiddenArticles: Bool
    let temporarilyVisibleReadArticleIDs: Set<PersistentIdentifier>

    init(
        articles: [Article],
        showsReadArticles: Bool,
        selectedArticle: Article? = nil,
        showsHiddenArticles: Bool = false,
        temporarilyVisibleReadArticleIDs: Set<PersistentIdentifier> = []
    ) {
        self.articles = articles
        self.showsReadArticles = showsReadArticles
        self.selectedArticle = selectedArticle
        self.showsHiddenArticles = showsHiddenArticles
        self.temporarilyVisibleReadArticleIDs = temporarilyVisibleReadArticleIDs
    }

    var visibleArticles: [Article] {
        snapshot.visibleArticles
    }

    var hiddenReadArticleCount: Int {
        snapshot.hiddenReadArticleCount
    }

    var shouldShowReadArticlesButton: Bool {
        snapshot.shouldShowReadArticlesButton
    }

    var snapshot: ArticleListDisplaySnapshot {
        var visibleArticles: [Article] = []
        var hiddenReadArticleCount = 0

        for article in articles {
            guard showsHiddenArticles || !article.isHidden else {
                continue
            }

            if showsReadArticles || !article.isRead || isSelected(article) || isTemporarilyVisibleReadArticle(article) {
                visibleArticles.append(article)
            } else {
                hiddenReadArticleCount += 1
            }
        }

        return ArticleListDisplaySnapshot(
            visibleArticles: visibleArticles,
            hiddenReadArticleCount: hiddenReadArticleCount
        )
    }

    private func isSelected(_ article: Article) -> Bool {
        selectedArticle?.persistentModelID == article.persistentModelID
    }

    private func isTemporarilyVisibleReadArticle(_ article: Article) -> Bool {
        article.isRead && temporarilyVisibleReadArticleIDs.contains(article.persistentModelID)
    }
}

struct ArticleListDisplaySnapshot {
    let visibleArticles: [Article]
    let hiddenReadArticleCount: Int

    var shouldShowReadArticlesButton: Bool {
        hiddenReadArticleCount > 0
    }
}
