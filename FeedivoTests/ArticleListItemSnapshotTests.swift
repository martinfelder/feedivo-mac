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

        #expect(snapshot.id == article.persistentModelID)
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
}
