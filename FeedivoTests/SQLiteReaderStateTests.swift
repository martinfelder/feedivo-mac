import Foundation
import Testing
@testable import Feedivo

@MainActor
struct SQLiteReaderStateTests {
    @Test func readerStateLaedtSnapshotUndPreparedArticle() async throws {
        let (database, articleID) = try makeDatabaseWithArticle()
        let state = SQLiteReaderState()

        state.load(articleID: articleID, database: database)
        await state.waitForActiveLoad()

        #expect(state.snapshot?.id == articleID)
        #expect(state.snapshot?.title == "SQLite Artikel")
        #expect(state.preparedArticle.metadataText.contains("SQLite Feed"))
        #expect(state.preparedArticle.contentAvailability == .feedContent)
        #expect(state.isLoading == false)
    }

    @Test func readerStateToggeltReadUndLaedtSnapshotNeu() async throws {
        let (database, articleID) = try makeDatabaseWithArticle()
        let state = SQLiteReaderState()

        state.load(articleID: articleID, database: database)
        await state.waitForActiveLoad()

        state.toggleRead(database: database)
        await state.waitForActiveLoad()

        #expect(state.snapshot?.isRead == true)
    }

    @Test func readerStateToggeltStarredUndLaedtSnapshotNeu() async throws {
        let (database, articleID) = try makeDatabaseWithArticle()
        let state = SQLiteReaderState()

        state.load(articleID: articleID, database: database)
        await state.waitForActiveLoad()

        state.toggleStarred(database: database)
        await state.waitForActiveLoad()

        #expect(state.snapshot?.isStarred == true)
    }

    // Regressionstest fuer den Spinner-Flash-Fix: Beim Wechsel auf einen anderen
    // Artikel darf der bereits geladene Snapshot NICHT synchron auf nil zurueckgesetzt
    // werden — der alte Inhalt bleibt sichtbar, bis der neue geladen ist. Sonst
    // rendert die View einen Frame mit snapshot == nil und zeigt den ProgressView.
    @Test func readerStateBehaeltAltenSnapshotWaehrendWechselSichtbar() async throws {
        let (database, firstID, secondID) = try makeDatabaseWithTwoArticles()
        let state = SQLiteReaderState()

        state.load(articleID: firstID, database: database)
        await state.waitForActiveLoad()
        #expect(state.snapshot?.id == firstID)

        // Wechsel auf den zweiten Artikel anstossen, aber NICHT abwarten:
        // in genau diesem synchronen Moment muss der erste Snapshot noch stehen.
        state.load(articleID: secondID, database: database)
        #expect(state.snapshot?.id == firstID)
        #expect(state.preparedArticle.metadataText.contains("SQLite Feed"))

        // Nach Abschluss des Ladevorgangs ist der zweite Artikel aktiv.
        await state.waitForActiveLoad()
        #expect(state.snapshot?.id == secondID)
        #expect(state.snapshot?.title == "Zweiter Artikel")
    }

    // Beim allerersten Laden gibt es noch keinen Snapshot — hier MUSS isLoading
    // greifen, damit die View den ProgressView anzeigen kann.
    @Test func readerStateSignalisiertLadenBeimAllerErstenLaden() throws {
        let (database, articleID) = try makeDatabaseWithArticle()
        let state = SQLiteReaderState()

        state.load(articleID: articleID, database: database)

        // Synchron direkt nach load(): Task noch nicht gelaufen, nichts geladen.
        #expect(state.snapshot == nil)
        #expect(state.isLoading == true)
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

    private func makeDatabaseWithTwoArticles() throws -> (FeedivoDatabase, String, String) {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "SQLite Feed"))
        let firstID = try articleStore.upsert(
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
        let secondID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "article-2",
                link: "https://example.com/article-2",
                title: "Zweiter Artikel",
                summary: "Zweite Kurzfassung",
                content: "<p>Zweiter Volltext</p>",
                publishedAt: Date(timeIntervalSince1970: 300),
                arrivedAt: Date(timeIntervalSince1970: 400)
            )
        )

        return (database, firstID, secondID)
    }
}
