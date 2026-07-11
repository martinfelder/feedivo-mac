import Foundation
import Testing
@testable import Feedivo

struct SQLiteArticleDatabaseTests {
    @Test func articleDatabaseBuendeltTimelineReaderUndStatuszugriffe() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let articleDatabase = ArticleDatabase(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))
        let articleID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "article-1",
                title: "Erster Artikel",
                summary: "Kurz",
                content: "Volltext",
                arrivedAt: Date(timeIntervalSince1970: 100)
            )
        )

        let rows = try articleDatabase.timelineArticles(scope: .feed("feed-1"), includeRead: true)
        let readerSnapshot = try articleDatabase.readerArticle(id: articleID)

        #expect(try articleDatabase.feedExists(id: "feed-1"))
        #expect(rows.map(\.id) == [articleID])
        #expect(readerSnapshot?.title == "Erster Artikel")
        #expect(readerSnapshot?.content == "Volltext")
    }

    @Test func articleDatabaseSchreibtStatusUeberGemeinsameFassade() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let articleDatabase = ArticleDatabase(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))
        let articleID = try articleStore.upsert(
            ArticleUpsertInput(feedID: "feed-1", sourceID: "article-1", title: "Erster Artikel")
        )

        try articleDatabase.setRead(true, articleID: articleID, at: Date(timeIntervalSince1970: 200))
        try articleDatabase.setStarred(true, articleID: articleID, at: Date(timeIntervalSince1970: 300))
        try articleDatabase.setArchived(true, articleID: articleID, at: Date(timeIntervalSince1970: 400))

        let readerSnapshot = try articleDatabase.readerArticle(id: articleID)

        #expect(readerSnapshot?.isRead == true)
        #expect(readerSnapshot?.isStarred == true)
        #expect(readerSnapshot?.isArchived == true)
    }

    @Test func articleDatabaseBietetBreiteFetchAPIWieNetNewsWire() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)
        let articleDatabase = ArticleDatabase(database: database)
        let today = Calendar.current.startOfDay(for: Date()).addingTimeInterval(60)
        let yesterday = today.addingTimeInterval(-24 * 60 * 60)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))
        try feedStore.save(FeedRecord(id: "feed-2", url: "https://other.example/feed.xml", title: "Other"))

        let feedOneReadID = try articleStore.upsert(ArticleUpsertInput(
            feedID: "feed-1",
            sourceID: "read",
            title: "Gelesen",
            publishedAt: yesterday,
            arrivedAt: yesterday
        ))
        let feedOneUnreadID = try articleStore.upsert(ArticleUpsertInput(
            feedID: "feed-1",
            sourceID: "unread",
            title: "Ungelesen",
            publishedAt: today,
            arrivedAt: today
        ))
        let feedTwoStarredID = try articleStore.upsert(ArticleUpsertInput(
            feedID: "feed-2",
            sourceID: "starred",
            title: "Markiert",
            publishedAt: today.addingTimeInterval(60),
            arrivedAt: today.addingTimeInterval(60)
        ))
        try statusStore.setRead(true, articleID: feedOneReadID, at: today)
        try statusStore.setStarred(true, articleID: feedTwoStarredID, at: today)

        #expect(try articleDatabase.fetchArticles(feedID: "feed-1").map(\.id) == [feedOneUnreadID, feedOneReadID])
        #expect(try articleDatabase.fetchArticles(feedIDs: ["feed-1", "feed-2"]).map(\.id) == [feedTwoStarredID, feedOneUnreadID, feedOneReadID])
        #expect(try articleDatabase.fetchArticles(articleIDs: [feedOneReadID, feedTwoStarredID]).map(\.id) == [feedTwoStarredID, feedOneReadID])
        #expect(try articleDatabase.fetchUnreadArticles(feedIDs: ["feed-1", "feed-2"]).map(\.id) == [feedTwoStarredID, feedOneUnreadID])
        #expect(try articleDatabase.fetchTodayArticles(feedIDs: ["feed-1", "feed-2"]).map(\.id) == [feedTwoStarredID, feedOneUnreadID])
        #expect(try articleDatabase.fetchStarredArticles(feedIDs: ["feed-1", "feed-2"]).map(\.id) == [feedTwoStarredID])
    }

    @Test func articleDatabaseLiefertSucheUndAggregierteCounts() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)
        let articleDatabase = ArticleDatabase(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))

        let readID = try articleStore.upsert(ArticleUpsertInput(
            feedID: "feed-1",
            sourceID: "read",
            title: "SQLite Architektur",
            summary: "Datenbank Fassade"
        ))
        let starredID = try articleStore.upsert(ArticleUpsertInput(
            feedID: "feed-1",
            sourceID: "starred",
            title: "GRDB Suche",
            summary: "SQLite und FTS"
        ))
        let archivedID = try articleStore.upsert(ArticleUpsertInput(
            feedID: "feed-1",
            sourceID: "archived",
            title: "Archiv",
            summary: "Ablage"
        ))
        let hiddenID = try articleStore.upsert(ArticleUpsertInput(
            feedID: "feed-1",
            sourceID: "hidden",
            title: "Versteckt",
            summary: "Ausblendung"
        ))

        try statusStore.setRead(true, articleID: readID, at: Date())
        try statusStore.setStarred(true, articleID: starredID, at: Date())
        try statusStore.setArchived(true, articleID: archivedID, at: Date())
        try statusStore.setHidden(true, articleID: hiddenID, at: Date())

        let counts = try articleDatabase.articleCounts(feedIDs: ["feed-1"])

        #expect(try articleDatabase.searchArticles(matching: "SQLite").map(\.id) == [starredID, readID])
        #expect(counts.totalCount == 4)
        #expect(counts.unreadCount == 2)
        #expect(counts.starredCount == 1)
        #expect(counts.archivedCount == 1)
        #expect(counts.hiddenCount == 1)
        #expect(counts.statusCount == 4)
    }

    @Test func newestUnreadLiefertArtikelUeberAlleFeedsHinwegSortiertNachDatum() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let articleDatabase = ArticleDatabase(database: database)

        try feedStore.save(FeedRecord(id: "feed-a", url: "https://a.example.com/feed", title: "Feed A"))
        try feedStore.save(FeedRecord(id: "feed-b", url: "https://b.example.com/feed", title: "Feed B"))

        let olderID = try articleStore.upsert(ArticleUpsertInput(
            feedID: "feed-a",
            sourceID: "article-older",
            title: "Älterer Artikel",
            publishedAt: Date(timeIntervalSinceNow: -3600),
            arrivedAt: Date(timeIntervalSinceNow: -3600)
        ))
        let newerID = try articleStore.upsert(ArticleUpsertInput(
            feedID: "feed-b",
            sourceID: "article-newer",
            title: "Neuerer Artikel",
            publishedAt: Date(),
            arrivedAt: Date()
        ))

        let result = try articleDatabase.newestUnread(limit: 5)

        #expect(result.map(\.id) == [newerID, olderID])
    }

    @Test func newestUnreadLiefertFaviconURLDesFeedsMit() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let articleDatabase = ArticleDatabase(database: database)

        try feedStore.save(FeedRecord(
            id: "feed-a",
            url: "https://a.example.com/feed",
            title: "Feed A",
            faviconURL: "https://a.example.com/favicon.ico"
        ))
        _ = try articleStore.upsert(ArticleUpsertInput(
            feedID: "feed-a",
            sourceID: "article-1",
            title: "Artikel 1"
        ))

        let result = try articleDatabase.newestUnread(limit: 5)

        #expect(result.first?.faviconURL == "https://a.example.com/favicon.ico")
    }

    @Test func newestUnreadRespektiertDasLimit() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let articleDatabase = ArticleDatabase(database: database)

        try feedStore.save(FeedRecord(id: "feed-a", url: "https://a.example.com/feed", title: "Feed A"))

        for index in 1...5 {
            _ = try articleStore.upsert(ArticleUpsertInput(
                feedID: "feed-a",
                sourceID: "article-\(index)",
                title: "Artikel \(index)",
                publishedAt: Date(timeIntervalSinceNow: Double(-index)),
                arrivedAt: Date(timeIntervalSinceNow: Double(-index))
            ))
        }

        let result = try articleDatabase.newestUnread(limit: 2)

        #expect(result.count == 2)
    }
}
