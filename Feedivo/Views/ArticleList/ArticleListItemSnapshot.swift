import Foundation

struct ArticleListItemSnapshot: Equatable, Identifiable {
    let id: String
    let title: String
    let summary: String?
    let publishedAt: Date?
    let feedTitle: String?
    let isRead: Bool
    let isStarred: Bool
    let isArchived: Bool
    let imageURL: String?
    let faviconURL: String?
    let hasOriginalURL: Bool

    init(sqliteSnapshot: ArticleListSnapshot) {
        self.id = sqliteSnapshot.id
        self.title = sqliteSnapshot.title
        self.summary = sqliteSnapshot.summary.map(ReaderContentRenderer.htmlToPlainText)
        self.publishedAt = sqliteSnapshot.publishedAt
        self.feedTitle = sqliteSnapshot.feedTitle
        self.isRead = sqliteSnapshot.isRead
        self.isStarred = sqliteSnapshot.isStarred
        self.isArchived = sqliteSnapshot.isArchived
        self.imageURL = sqliteSnapshot.imageURL
        self.faviconURL = sqliteSnapshot.faviconURL
        self.hasOriginalURL = ArticleOriginalURLResolver.hasUsableWebLink(sqliteSnapshot.link)
    }
}
