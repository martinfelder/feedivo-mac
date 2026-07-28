import Foundation
import Testing
@testable import Feedivo

struct ArticleListItemSnapshotTests {
    @Test func snapshotKannAusSQLiteListenSnapshotGebautWerden() {
        let feedID = UUID()
        let sqliteSnapshot = ArticleListSnapshot(
            id: "article-1",
            feedID: feedID.uuidString,
            feedTitle: "SQLite Feed",
            title: "SQLite Artikel",
            summary: "SQLite Kurzfassung",
            link: "https://example.com/sqlite-artikel",
            imageURL: "https://example.com/sqlite-bild.jpg",
            publishedAt: Date(timeIntervalSince1970: 200),
            arrivedAt: Date(timeIntervalSince1970: 300),
            estimatedReadingMinutes: 4,
            isRead: true,
            isStarred: true,
            isArchived: false,
            isHidden: false
        )

        let snapshot = ArticleListItemSnapshot(sqliteSnapshot: sqliteSnapshot)

        #expect(snapshot.id == "article-1")
        #expect(snapshot.title == "SQLite Artikel")
        #expect(snapshot.summary == "SQLite Kurzfassung")
        #expect(snapshot.publishedAt == Date(timeIntervalSince1970: 200))
        #expect(snapshot.feedTitle == "SQLite Feed")
        #expect(snapshot.isRead)
        #expect(snapshot.isStarred)
        #expect(!snapshot.isArchived)
        #expect(snapshot.hasOriginalURL)
        #expect(snapshot.imageURL == "https://example.com/sqlite-bild.jpg")
    }
}
