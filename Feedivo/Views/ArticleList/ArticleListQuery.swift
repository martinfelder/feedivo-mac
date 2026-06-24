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

    init(
        articles: [Article],
        showsReadArticles: Bool,
        selectedArticle: Article? = nil,
        showsHiddenArticles: Bool = false
    ) {
        self.articles = articles
        self.showsReadArticles = showsReadArticles
        self.selectedArticle = selectedArticle
        self.showsHiddenArticles = showsHiddenArticles
    }

    var visibleArticles: [Article] {
        let visibleArticles = showsHiddenArticles ? articles : articles.filter { !$0.isHidden }

        guard !showsReadArticles else {
            return visibleArticles
        }

        return visibleArticles.filter { article in
            !article.isRead || isSelected(article)
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

            return count + (article.isRead && !isSelected(article) ? 1 : 0)
        }
    }

    var shouldShowReadArticlesButton: Bool {
        hiddenReadArticleCount > 0
    }

    private func isSelected(_ article: Article) -> Bool {
        selectedArticle?.persistentModelID == article.persistentModelID
    }
}
