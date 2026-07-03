import Foundation
import SwiftData

struct ArticleListItemSnapshot: Equatable, Identifiable {
    let id: String
    let title: String
    let summary: String?
    let publishedAt: Date?
    let feedID: UUID?
    let feedTitle: String?
    let isRead: Bool
    let isStarred: Bool
    let isArchived: Bool
    let isHidden: Bool
    let imageURL: String?
    let offlineState: ArticleOfflineState
    let hasOriginalURL: Bool

    init(article: Article, feedTitle: String?) {
        self.id = String(describing: article.persistentModelID)
        self.title = article.title
        self.summary = article.summary
        self.publishedAt = article.publishedAt
        self.feedID = article.feedID
        self.feedTitle = feedTitle
        self.isRead = article.isRead
        self.isStarred = article.isStarred
        self.isArchived = article.isArchived
        self.isHidden = article.isHidden
        self.imageURL = article.imageURL
        self.offlineState = article.offlineState
        self.hasOriginalURL = ArticleOriginalURLResolver.hasUsableWebLink(article.link)
    }

    init(sqliteSnapshot: ArticleListSnapshot) {
        self.id = sqliteSnapshot.id
        self.title = sqliteSnapshot.title
        self.summary = sqliteSnapshot.summary
        self.publishedAt = sqliteSnapshot.publishedAt
        self.feedID = UUID(uuidString: sqliteSnapshot.feedID)
        self.feedTitle = sqliteSnapshot.feedTitle
        self.isRead = sqliteSnapshot.isRead
        self.isStarred = sqliteSnapshot.isStarred
        self.isArchived = sqliteSnapshot.isArchived
        self.isHidden = sqliteSnapshot.isHidden
        self.imageURL = sqliteSnapshot.imageURL
        self.offlineState = sqliteSnapshot.offlineState
        self.hasOriginalURL = ArticleOriginalURLResolver.hasUsableWebLink(sqliteSnapshot.link)
    }
}
