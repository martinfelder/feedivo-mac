import Foundation
import Testing
@testable import Feedivo

@MainActor
struct SQLiteFeedArticleListStateTests {
    @Test func listStateLoestFeedURLAufUndLaedtSnapshots() throws {
        let (database, firstID, secondID) = try makeDatabaseWithFeedAndArticles()
        let state = SQLiteFeedArticleListState()

        state.load(
            swiftDataFeedURL: "https://example.com/feed.xml",
            database: database,
            selectedArticleID: secondID
        )

        #expect(state.loadState == .loaded)
        #expect(state.rows.map(\.id) == [secondID, firstID])
        #expect(state.navigationState.previousArticleID == nil)
        #expect(state.navigationState.nextArticleID == firstID)
    }

    @Test func listStateToggeltReadUndAktualisiertRows() throws {
        let (database, firstID, _) = try makeDatabaseWithFeedAndArticles()
        let state = SQLiteFeedArticleListState()

        state.load(
            swiftDataFeedURL: "https://example.com/feed.xml",
            database: database,
            selectedArticleID: firstID
        )
        state.toggleRead(articleID: firstID, database: database)

        #expect(state.rows.first(where: { $0.id == firstID })?.isRead == true)
    }

    @Test func listStateLaedtTagScopeAusSQLite() throws {
        let (database, firstID, secondID) = try makeDatabaseWithFeedAndArticles()
        let tagStore = TagStore(database: database)
        let state = SQLiteFeedArticleListState()
        try tagStore.save(TagRecord(id: "tag-swift", name: "Swift", colorHex: "#ff0000"))
        try tagStore.assignTag(tagID: "tag-swift", toArticleID: firstID, at: Date(timeIntervalSince1970: 100))
        try tagStore.assignTag(tagID: "tag-swift", toArticleID: secondID, at: Date(timeIntervalSince1970: 200))

        state.load(
            tagID: "tag-swift",
            database: database,
            selectedArticleID: secondID
        )

        #expect(state.loadState == .loaded)
        #expect(state.rows.map(\.id) == [secondID, firstID])
        #expect(state.navigationState.nextArticleID == firstID)
    }

    @Test func listStateLaedtSmartFilterScopeAusSQLite() throws {
        let (database, firstID, secondID) = try makeDatabaseWithFeedAndArticles()
        let state = SQLiteFeedArticleListState()
        try ArticleStatusStore(database: database).setRead(true, articleID: firstID, at: Date())

        state.load(
            smartFilter: .unread,
            database: database,
            selectedArticleID: secondID
        )

        #expect(state.loadState == .loaded)
        #expect(state.rows.map(\.id) == [secondID])
        #expect(state.navigationState.previousArticleID == nil)
        #expect(state.navigationState.nextArticleID == nil)
    }

    @Test func listStateFiltertFeedScopeMitSQLiteFTS() throws {
        let (database, _, secondID) = try makeDatabaseWithFeedAndArticles()
        let state = SQLiteFeedArticleListState()

        state.load(
            swiftDataFeedURL: "https://example.com/feed.xml",
            searchText: "Second",
            database: database,
            selectedArticleID: secondID
        )

        #expect(state.loadState == .loaded)
        #expect(state.rows.map(\.id) == [secondID])
        #expect(state.navigationState.previousArticleID == nil)
        #expect(state.navigationState.nextArticleID == nil)
    }

    @Test func listStateLaedtHiddenSmartFilterMitAusgeblendetenArtikeln() throws {
        let (database, firstID, _) = try makeDatabaseWithFeedAndArticles()
        let state = SQLiteFeedArticleListState()
        try ArticleStatusStore(database: database).setHidden(true, articleID: firstID, at: Date())

        state.load(
            smartFilter: .hidden,
            database: database,
            selectedArticleID: firstID
        )

        #expect(state.loadState == .loaded)
        #expect(state.rows.map(\.id) == [firstID])
    }

    @Test func listStateMeldetFehlendenSQLiteFeed() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let state = SQLiteFeedArticleListState()

        state.load(
            swiftDataFeedURL: "https://example.com/missing.xml",
            database: database,
            selectedArticleID: nil
        )

        #expect(state.loadState == .missingFeed)
        #expect(state.rows.isEmpty)
    }

    private func makeDatabaseWithFeedAndArticles() throws -> (FeedivoDatabase, String, String) {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "SQLite Feed"))
        let firstID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "first",
                title: "First",
                publishedAt: Date(timeIntervalSince1970: 100),
                arrivedAt: Date(timeIntervalSince1970: 100)
            )
        )
        let secondID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "second",
                title: "Second",
                publishedAt: Date(timeIntervalSince1970: 200),
                arrivedAt: Date(timeIntervalSince1970: 200)
            )
        )

        return (database, firstID, secondID)
    }
}
