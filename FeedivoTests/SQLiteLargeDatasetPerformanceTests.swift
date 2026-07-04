import Foundation
import Testing
@testable import Feedivo

private func seedLargeSQLiteDataset(
    database: FeedivoDatabase,
    feedCount: Int,
    articlesPerFeed: Int
) throws {
    let feedStore = FeedStore(database: database)
    let articleStore = ArticleStore(database: database)
    let statusStore = ArticleStatusStore(database: database)
    let now = Date()

    for feedIndex in 0..<feedCount {
        let feedID = "feed-\(feedIndex)"
        try feedStore.save(
            FeedRecord(
                id: feedID,
                url: "https://example.com/\(feedIndex).xml",
                title: "Feed \(feedIndex)"
            )
        )

        for articleIndex in 0..<articlesPerFeed {
            let publishedAt = now.addingTimeInterval(TimeInterval(-(feedIndex * articlesPerFeed + articleIndex)))
            let articleID = try articleStore.upsert(
                ArticleUpsertInput(
                    feedID: feedID,
                    sourceID: "source-\(feedIndex)-\(articleIndex)",
                    link: "https://example.com/\(feedIndex)/\(articleIndex)",
                    title: "Article \(feedIndex)-\(articleIndex)",
                    summary: "Summary \(feedIndex)-\(articleIndex)",
                    publishedAt: publishedAt,
                    arrivedAt: publishedAt
                )
            )

            if articleIndex % 2 == 0 {
                try statusStore.setRead(true, articleID: articleID, at: now)
            }
        }
    }
}

struct SQLiteLargeDatasetPerformanceTests {
    @Test func timelineQueriesSindUnterLastbedingungenSchnell() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try seedLargeSQLiteDataset(database: database, feedCount: 100, articlesPerFeed: 600)

        let timelineStore = TimelineStore(database: database)
        let articleStore = ArticleStore(database: database)

        let timelineAllStart = Date()
        let firstBatch = try timelineStore.articles(
            scope: .all,
            searchText: nil,
            includeRead: false,
            includeHidden: false,
            limit: 500
        )
        let timelineAllElapsed = Date().timeIntervalSince(timelineAllStart)
        #expect(firstBatch.count == 500)
        #expect(timelineAllElapsed < 1.8)

        let timelineFeedStart = Date()
        let perFeedBatch = try timelineStore.articles(
            scope: .feed("feed-42"),
            searchText: nil,
            includeRead: false,
            includeHidden: false,
            limit: 500
        )
        let timelineFeedElapsed = Date().timeIntervalSince(timelineFeedStart)
        #expect(perFeedBatch.count <= 500)
        #expect(timelineFeedElapsed < 0.9)

        let searchStart = Date()
        let searchResults = try articleStore.searchArticles(
            matching: "Article 42",
            includeHidden: false,
            limit: 100
        )
        let searchElapsed = Date().timeIntervalSince(searchStart)
        #expect(searchResults.count > 0)
        #expect(searchElapsed < 0.9)
    }

    @Test func readsUmschaltenUndTimelineNeuLadenIstEffizient() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try seedLargeSQLiteDataset(database: database, feedCount: 100, articlesPerFeed: 600)

        let timelineStore = TimelineStore(database: database)
        let statusStore = ArticleStatusStore(database: database)
        let firstUnread = try timelineStore.articles(
            scope: .all,
            searchText: nil,
            includeRead: false,
            includeHidden: false,
            limit: 1
        ).first
        #expect(firstUnread != nil)

        let updateStart = Date()
        try statusStore.setRead(true, articleID: try #require(firstUnread?.id), at: Date())
        let afterUpdate = try timelineStore.articles(
            scope: .all,
            searchText: nil,
            includeRead: false,
            includeHidden: false,
            limit: 1
        )
        let updateElapsed = Date().timeIntervalSince(updateStart)

        #expect(afterUpdate.isEmpty || afterUpdate.allSatisfy { !$0.id.isEmpty })
        #expect(updateElapsed < 0.4)
    }

    @Test func sidebarUndArtikelCountsLassenSichSchnellBerechnen() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try seedLargeSQLiteDataset(database: database, feedCount: 100, articlesPerFeed: 600)

        let feedStore = FeedStore(database: database)
        let timelineStore = TimelineStore(database: database)
        let countStart = Date()

        let feedSnapshots = try feedStore.sidebarFeeds()
        var totalUnread = 0
        for index in 0..<feedSnapshots.count {
            totalUnread += try timelineStore.unreadCount(feedID: "feed-\(index)")
        }

        let countElapsed = Date().timeIntervalSince(countStart)
        #expect(feedSnapshots.count == 100)
        #expect(totalUnread > 0)
        #expect(countElapsed < 1.5)
    }
}
