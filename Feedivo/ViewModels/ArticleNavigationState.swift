import Foundation

struct ArticleNavigationState {
    static let empty = ArticleNavigationState()

    let previousArticle: Article?
    let nextArticle: Article?

    init(previousArticle: Article? = nil, nextArticle: Article? = nil) {
        self.previousArticle = previousArticle
        self.nextArticle = nextArticle
    }

    init(
        articles: [Article],
        selectedArticle: Article?,
        sortArticles: ([Article]) -> [Article] = ArticleViewModel().sortedForList
    ) {
        let sortedArticles = sortArticles(articles)
        self.previousArticle = ArticleNavigationState.previousArticle(
            before: selectedArticle,
            in: sortedArticles
        )
        self.nextArticle = ArticleNavigationState.nextArticle(
            after: selectedArticle,
            in: sortedArticles
        )
    }

    private static func previousArticle(before article: Article?, in articles: [Article]) -> Article? {
        guard
            let article,
            let currentIndex = articles.firstIndex(where: { $0.id == article.id }),
            currentIndex > articles.startIndex
        else {
            return nil
        }

        return articles[articles.index(before: currentIndex)]
    }

    private static func nextArticle(after article: Article?, in articles: [Article]) -> Article? {
        guard
            let article,
            let currentIndex = articles.firstIndex(where: { $0.id == article.id })
        else {
            return nil
        }

        let nextIndex = articles.index(after: currentIndex)
        guard nextIndex < articles.endIndex else {
            return nil
        }

        return articles[nextIndex]
    }
}
