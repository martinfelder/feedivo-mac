import Foundation
import Testing
@testable import Feedivo

@MainActor
@Suite(.serialized)
struct SQLiteOfflineDownloadServiceTests {
    @Test func saveForOfflineUsesExistingSQLiteFeedContent() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let offlineStore = SQLiteOfflineStore(database: database)
        let service = SQLiteOfflineDownloadService(
            fetcher: StubSQLiteOfflineContentFetcher(result: .success("<p>Webseite</p>"))
        )

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))
        let articleID = try articleStore.upsert(ArticleUpsertInput(
            feedID: "feed-1",
            sourceID: "article-1",
            link: "https://example.com/articles/1",
            title: "Feed Artikel",
            content: "<p>Feed Volltext</p>"
        ))

        await service.saveForOffline(articleID: articleID, database: database)

        let offline = try offlineStore.offline(articleID: articleID)

        #expect(offline?.state == .feedContent)
        #expect(offline?.content == "<p>Feed Volltext</p>")
        #expect(offline?.errorMessage == nil)
        #expect(offline?.savedAt != nil)
    }

    @Test func saveForOfflineFetchesOriginalWhenSQLiteFeedContentIsMissing() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let offlineStore = SQLiteOfflineStore(database: database)
        let service = SQLiteOfflineDownloadService(
            fetcher: StubSQLiteOfflineContentFetcher(result: .success("<article>Geladener Volltext</article>"))
        )

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))
        let articleID = try articleStore.upsert(ArticleUpsertInput(
            feedID: "feed-1",
            sourceID: "article-1",
            link: "https://example.com/articles/1",
            title: "Web Artikel"
        ))

        await service.saveForOffline(articleID: articleID, database: database)

        let offline = try offlineStore.offline(articleID: articleID)

        #expect(offline?.state == .fullText)
        #expect(offline?.content == "<article>Geladener Volltext</article>")
        #expect(offline?.errorMessage == nil)
    }

    @Test func removeOfflineContentClearsSQLiteOfflineRowAndArchiveStatus() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let offlineStore = SQLiteOfflineStore(database: database)
        let statusStore = ArticleStatusStore(database: database)
        let service = SQLiteOfflineDownloadService()

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))
        let articleID = try articleStore.upsert(ArticleUpsertInput(feedID: "feed-1", sourceID: "article-1", title: "Offline"))
        try offlineStore.markSaved(articleID: articleID, state: .fullText, content: "Text")
        try statusStore.setArchived(true, articleID: articleID, at: Date(timeIntervalSince1970: 100))

        service.removeOfflineContent(articleID: articleID, database: database)

        let offline = try offlineStore.offline(articleID: articleID)
        let status = try statusStore.status(articleID: articleID)

        #expect(offline?.state == ArticleOfflineState.none)
        #expect(offline?.content == nil)
        #expect(status?.isArchived == false)
    }
}

private struct StubSQLiteOfflineContentFetcher: OfflineArticleContentFetching {
    var result: Result<String, Error>

    func content(from url: URL) async throws -> String {
        try result.get()
    }
}
