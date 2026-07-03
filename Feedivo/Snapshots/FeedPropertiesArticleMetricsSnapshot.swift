import Foundation

struct FeedPropertiesArticleMetricsSnapshot: Equatable, Sendable {
    var latestArticle: ArticleListSnapshot?
    var recentArticleCount: Int

    static let empty = FeedPropertiesArticleMetricsSnapshot(
        latestArticle: nil,
        recentArticleCount: 0
    )
}
