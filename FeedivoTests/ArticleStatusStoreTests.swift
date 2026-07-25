import Foundation
import Testing
@testable import Feedivo

struct ArticleStatusStoreTests {
    @Test func markAllUnreadAsReadSetztWirklichAlleUngelesenenArtikelAufGelesen() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let feed = FeedRecord(id: "feed-1", url: "https://example.com/feed", title: "Feed 1")
        try feedStore.save(feed)

        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)

        var articleIDs: [String] = []
        for index in 1...3 {
            let articleID = try articleStore.upsert(
                ArticleUpsertInput(feedID: feed.id, sourceID: "article-\(index)", title: "Artikel \(index)")
            )
            articleIDs.append(articleID)
        }

        for articleID in articleIDs {
            let status = try statusStore.status(articleID: articleID)
            #expect(status?.isRead == false)
        }

        try statusStore.markAllUnreadAsRead()

        for articleID in articleIDs {
            let status = try statusStore.status(articleID: articleID)
            #expect(status?.isRead == true)
        }
    }
}
