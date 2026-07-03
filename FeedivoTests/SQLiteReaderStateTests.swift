import Foundation
import Testing
@testable import Feedivo

@MainActor
struct SQLiteReaderStateTests {
    @Test func readerStateLaedtSnapshotUndPreparedArticle() throws {
        let (database, articleID) = try makeDatabaseWithArticle()
        let state = SQLiteReaderState()

        state.load(articleID: articleID, database: database)

        #expect(state.snapshot?.id == articleID)
        #expect(state.snapshot?.title == "SQLite Artikel")
        #expect(state.preparedArticle.metadataText.contains("SQLite Feed"))
        #expect(state.preparedArticle.contentAvailability == .feedContent)
    }

    @Test func readerStateToggeltReadUndLaedtSnapshotNeu() throws {
        let (database, articleID) = try makeDatabaseWithArticle()
        let state = SQLiteReaderState()

        state.load(articleID: articleID, database: database)
        state.toggleRead(database: database)

        #expect(state.snapshot?.isRead == true)
    }

    @Test func readerStateToggeltStarredUndLaedtSnapshotNeu() throws {
        let (database, articleID) = try makeDatabaseWithArticle()
        let state = SQLiteReaderState()

        state.load(articleID: articleID, database: database)
        state.toggleStarred(database: database)

        #expect(state.snapshot?.isStarred == true)
    }

    private func makeDatabaseWithArticle() throws -> (FeedivoDatabase, String) {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "SQLite Feed"))
        let articleID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "article-1",
                link: "https://example.com/article-1",
                title: "SQLite Artikel",
                summary: "Kurzfassung",
                content: "<p>Volltext</p>",
                publishedAt: Date(timeIntervalSince1970: 100),
                arrivedAt: Date(timeIntervalSince1970: 200)
            )
        )

        return (database, articleID)
    }
}
