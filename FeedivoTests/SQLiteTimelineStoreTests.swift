import Foundation
import Testing
@testable import Feedivo

struct SQLiteTimelineStoreTests {
    @Test func timelineFetchesNewestUnreadVisibleSnapshotsForFeed() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)
        let timelineStore = TimelineStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))

        let oldID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "old",
                title: "Old",
                publishedAt: Date(timeIntervalSince1970: 100),
                arrivedAt: Date(timeIntervalSince1970: 100)
            )
        )
        let newID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "new",
                title: "New",
                publishedAt: Date(timeIntervalSince1970: 200),
                arrivedAt: Date(timeIntervalSince1970: 200)
            )
        )
        try statusStore.setRead(true, articleID: oldID, at: Date(timeIntervalSince1970: 300))

        let snapshots = try timelineStore.articles(
            scope: .feed("feed-1"),
            includeRead: false,
            includeHidden: false,
            limit: 20
        )

        #expect(snapshots.map(\.id) == [newID])
        #expect(snapshots.first?.feedTitle == "Example")
    }

    @Test func timelineHonorsLimitAndSortsByPublishedThenArrivedDate() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let timelineStore = TimelineStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))

        _ = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "one",
                title: "One",
                publishedAt: Date(timeIntervalSince1970: 100),
                arrivedAt: Date(timeIntervalSince1970: 100)
            )
        )
        let twoID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "two",
                title: "Two",
                publishedAt: Date(timeIntervalSince1970: 200),
                arrivedAt: Date(timeIntervalSince1970: 200)
            )
        )
        let threeID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "three",
                title: "Three",
                publishedAt: nil,
                arrivedAt: Date(timeIntervalSince1970: 300)
            )
        )

        let snapshots = try timelineStore.articles(
            scope: .all,
            includeRead: true,
            includeHidden: false,
            limit: 2
        )

        #expect(snapshots.map(\.id) == [threeID, twoID])
    }

    @Test func unreadCountIgnoresReadAndHiddenArticles() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)
        let timelineStore = TimelineStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))

        _ = try articleStore.upsert(
            ArticleUpsertInput(feedID: "feed-1", sourceID: "unread", title: "Unread")
        )
        let readID = try articleStore.upsert(
            ArticleUpsertInput(feedID: "feed-1", sourceID: "read", title: "Read")
        )
        let hiddenID = try articleStore.upsert(
            ArticleUpsertInput(feedID: "feed-1", sourceID: "hidden", title: "Hidden")
        )
        try statusStore.setRead(true, articleID: readID, at: Date(timeIntervalSince1970: 200))
        try statusStore.setHidden(true, articleID: hiddenID, at: Date(timeIntervalSince1970: 300))

        let count = try timelineStore.unreadCount(feedID: "feed-1")

        #expect(count == 1)
    }

    @Test func timelineFetchesDirectlyTaggedAndFeedTaggedArticlesFromSQLite() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)
        let tagStore = TagStore(database: database)
        let timelineStore = TimelineStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))
        try feedStore.save(FeedRecord(id: "feed-2", url: "https://example.com/other.xml", title: "Other"))
        try tagStore.save(TagRecord(id: "tag-swift", name: "Swift", colorHex: "#ff0000"))
        try tagStore.save(TagRecord(id: "tag-other", name: "Other", colorHex: "#00ff00"))
        let olderTaggedID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "older-tagged",
                title: "Older Tagged",
                publishedAt: Date(timeIntervalSince1970: 100),
                arrivedAt: Date(timeIntervalSince1970: 100)
            )
        )
        let newerTaggedID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "newer-tagged",
                title: "Newer Tagged",
                publishedAt: Date(timeIntervalSince1970: 300),
                arrivedAt: Date(timeIntervalSince1970: 300)
            )
        )
        let hiddenTaggedID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "hidden-tagged",
                title: "Hidden Tagged",
                publishedAt: Date(timeIntervalSince1970: 400),
                arrivedAt: Date(timeIntervalSince1970: 400)
            )
        )
        let otherTagID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "other-tag",
                title: "Other Tag",
                publishedAt: Date(timeIntervalSince1970: 500),
                arrivedAt: Date(timeIntervalSince1970: 500)
            )
        )
        let feedTaggedID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-2",
                sourceID: "feed-tagged",
                title: "Feed Tagged",
                publishedAt: Date(timeIntervalSince1970: 600),
                arrivedAt: Date(timeIntervalSince1970: 600)
            )
        )

        try tagStore.assignTag(tagID: "tag-swift", toArticleID: olderTaggedID, at: Date(timeIntervalSince1970: 110))
        try tagStore.assignTag(tagID: "tag-swift", toArticleID: newerTaggedID, at: Date(timeIntervalSince1970: 310))
        try tagStore.assignTag(tagID: "tag-swift", toArticleID: hiddenTaggedID, at: Date(timeIntervalSince1970: 410))
        try tagStore.assignTag(tagID: "tag-other", toArticleID: otherTagID, at: Date(timeIntervalSince1970: 510))
        try tagStore.assignTag(tagID: "tag-swift", toFeedID: "feed-2", at: Date(timeIntervalSince1970: 605))
        try statusStore.setHidden(true, articleID: hiddenTaggedID, at: Date(timeIntervalSince1970: 420))

        let snapshots = try timelineStore.articles(
            scope: .tag("tag-swift"),
            includeRead: true,
            includeHidden: false,
            limit: 20
        )

        #expect(snapshots.map(\.id) == [feedTaggedID, newerTaggedID, olderTaggedID])
        #expect(snapshots.map(\.feedTitle) == ["Other", "Example", "Example"])
    }

    @Test func timelineUsesMinimumLimitOfOne() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let timelineStore = TimelineStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))
        let articleID = try articleStore.upsert(
            ArticleUpsertInput(feedID: "feed-1", sourceID: "one", title: "One")
        )

        let snapshots = try timelineStore.articles(
            scope: .all,
            includeRead: true,
            includeHidden: true,
            limit: 0
        )

        #expect(snapshots.map(\.id) == [articleID])
    }
}
