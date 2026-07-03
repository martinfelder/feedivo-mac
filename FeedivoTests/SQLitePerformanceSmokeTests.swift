import Foundation
import Testing
@testable import Feedivo

struct SQLitePerformanceSmokeTests {
    @Test func timelineAndUnreadCountsStayUsableWithLargeSyntheticDataset() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)
        let timelineStore = TimelineStore(database: database)

        for feedIndex in 0..<100 {
            let feedID = "feed-\(feedIndex)"
            try feedStore.save(
                FeedRecord(
                    id: feedID,
                    url: "https://example.com/\(feedIndex)/feed.xml",
                    title: "Feed \(feedIndex)"
                )
            )

            for articleIndex in 0..<500 {
                let articleID = try articleStore.upsert(
                    ArticleUpsertInput(
                        feedID: feedID,
                        sourceID: "source-\(feedIndex)-\(articleIndex)",
                        link: "https://example.com/\(feedIndex)/\(articleIndex)",
                        title: "Article \(articleIndex)",
                        summary: "Summary \(articleIndex)",
                        publishedAt: Date(timeIntervalSince1970: TimeInterval(articleIndex)),
                        arrivedAt: Date(timeIntervalSince1970: TimeInterval(articleIndex))
                    )
                )

                if articleIndex % 2 == 0 {
                    try statusStore.setRead(true, articleID: articleID, at: Date())
                }
            }
        }

        let start = Date()
        let snapshots = try timelineStore.articles(scope: .all, includeRead: false, includeHidden: false, limit: 50)
        let count = try timelineStore.unreadCount(feedID: "feed-42")
        let elapsed = Date().timeIntervalSince(start)

        #expect(snapshots.count == 50)
        #expect(count == 250)
        #expect(elapsed < 1.0)
    }
}
