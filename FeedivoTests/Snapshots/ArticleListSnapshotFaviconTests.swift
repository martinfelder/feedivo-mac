import Foundation
import Testing
@testable import Feedivo

struct ArticleListSnapshotFaviconTests {

    @Test func timelineArticlesLiefertFaviconURLDesFeeds() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let timelineStore = TimelineStore(database: database)

        try feedStore.save(
            FeedRecord(
                id: "feed-1",
                url: "https://example.com/feed.xml",
                title: "Example",
                faviconURL: "https://example.com/favicon.ico"
            )
        )
        _ = try articleStore.upsert(
            ArticleUpsertInput(feedID: "feed-1", sourceID: "one", title: "One")
        )

        let snapshots = try timelineStore.articles(
            scope: .feed("feed-1"),
            includeRead: true,
            includeHidden: false,
            limit: 20
        )

        #expect(snapshots.first?.faviconURL == "https://example.com/favicon.ico")
    }

    @Test func articleListItemSnapshotUebernimmtFaviconURLAusSqliteSnapshot() {
        let sqliteSnapshot = ArticleListSnapshot(
            id: "article-1",
            feedID: "feed-1",
            feedTitle: "Example",
            title: "Title",
            summary: nil,
            link: nil,
            imageURL: nil,
            publishedAt: nil,
            arrivedAt: Date(),
            estimatedReadingMinutes: nil,
            isRead: false,
            isStarred: false,
            isArchived: false,
            isHidden: false,
            faviconURL: "https://example.com/favicon.ico"
        )

        let itemSnapshot = ArticleListItemSnapshot(sqliteSnapshot: sqliteSnapshot)

        #expect(itemSnapshot.faviconURL == "https://example.com/favicon.ico")
    }
}
