import Foundation
import SwiftData
import Testing
@testable import Feedivo

struct ArticleListItemSnapshotTests {
    @MainActor
    @Test func snapshotUebernimmtNurLeichteZeilenwerte() throws {
        let feedID = UUID()
        let feed = Feed(url: "https://example.com/feed.xml", title: "Feedtitel")
        feed.id = feedID
        let article = Article(
            title: "Artikel",
            link: "https://example.com/artikel",
            summary: "Kurzfassung",
            publishedAt: Date(timeIntervalSince1970: 100),
            imageURL: "https://example.com/bild.jpg",
            feed: feed
        )
        article.isRead = true
        article.isStarred = true
        article.isArchived = true
        article.isHidden = true
        article.offlineState = .feedContent

        let snapshot = ArticleListItemSnapshot(
            article: article,
            feedTitle: "Feedtitel"
        )

        #expect(snapshot.id == String(describing: article.persistentModelID))
        #expect(snapshot.title == "Artikel")
        #expect(snapshot.summary == "Kurzfassung")
        #expect(snapshot.publishedAt == Date(timeIntervalSince1970: 100))
        #expect(snapshot.feedID == feedID)
        #expect(snapshot.feedTitle == "Feedtitel")
        #expect(snapshot.isRead)
        #expect(snapshot.isStarred)
        #expect(snapshot.isArchived)
        #expect(snapshot.isHidden)
        #expect(snapshot.hasOriginalURL)
        #expect(snapshot.offlineState == .feedContent)
        #expect(snapshot.imageURL == "https://example.com/bild.jpg")
    }

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
        #expect(snapshot.feedID == feedID)
        #expect(snapshot.feedTitle == "SQLite Feed")
        #expect(snapshot.isRead)
        #expect(snapshot.isStarred)
        #expect(!snapshot.isArchived)
        #expect(!snapshot.isHidden)
        #expect(snapshot.hasOriginalURL)
        #expect(snapshot.offlineState == .none)
        #expect(snapshot.imageURL == "https://example.com/sqlite-bild.jpg")
    }
}
