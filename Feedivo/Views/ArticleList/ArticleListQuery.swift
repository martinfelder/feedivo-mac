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
        let visibleArticles = showsHiddenArticles ? articles : articles.filter { !$0.isHidden }

        guard !showsReadArticles else {
            return visibleArticles
        }

        return visibleArticles.filter { article in
            !article.isRead || isSelected(article) || isTemporarilyVisibleReadArticle(article)
        }
    }

    var hiddenReadArticleCount: Int {
        guard !showsReadArticles else {
            return 0
        }

        return articles.reduce(0) { count, article in
            guard showsHiddenArticles || !article.isHidden else {
                return count
            }

            return count + (article.isRead && !isSelected(article) && !isTemporarilyVisibleReadArticle(article) ? 1 : 0)
        }
    }

    var shouldShowReadArticlesButton: Bool {
        hiddenReadArticleCount > 0
    }

    private func isSelected(_ article: Article) -> Bool {
        selectedArticle?.persistentModelID == article.persistentModelID
    }

    private func isTemporarilyVisibleReadArticle(_ article: Article) -> Bool {
        article.isRead && temporarilyVisibleReadArticleIDs.contains(article.persistentModelID)
    }
}
