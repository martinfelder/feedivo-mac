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
}
