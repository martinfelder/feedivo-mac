import Foundation
import CoreSpotlight
import Testing
@testable import Feedivo

final class FakeSpotlightIndex: SpotlightIndexWriting {
    private(set) var indexedItems: [CSSearchableItem] = []
    private(set) var deletedIdentifiers: [String] = []
    private(set) var didDeleteAll = false

    func indexSearchableItems(_ items: [CSSearchableItem], completionHandler: ((Error?) -> Void)?) {
        indexedItems.append(contentsOf: items)
        completionHandler?(nil)
    }

    func deleteSearchableItems(withIdentifiers identifiers: [String], completionHandler: ((Error?) -> Void)?) {
        deletedIdentifiers.append(contentsOf: identifiers)
        completionHandler?(nil)
    }

    func deleteAllSearchableItems(completionHandler: ((Error?) -> Void)?) {
        didDeleteAll = true
        completionHandler?(nil)
    }
}

struct SpotlightIndexingServiceTests {
    @Test func indexArticlesBautCSSearchableItemsMitArtikelDaten() throws {
        let defaults = try temporaryUserDefaults()
        let index = FakeSpotlightIndex()
        let snapshot = makeSnapshot(id: "article-1", title: "Titel", summary: "Zusammenfassung", feedTitle: "Mein Feed")

        SpotlightIndexingService.indexArticles([snapshot], userDefaults: defaults, index: index)

        #expect(index.indexedItems.count == 1)
        #expect(index.indexedItems.first?.uniqueIdentifier == "article-1")
        #expect(index.indexedItems.first?.domainIdentifier == SpotlightIndexingService.domainIdentifier)
        #expect(index.indexedItems.first?.attributeSet.title == "Titel")
        #expect(index.indexedItems.first?.attributeSet.contentDescription == "Zusammenfassung")
        #expect(index.indexedItems.first?.attributeSet.kind == "Mein Feed")
    }

    @Test func indexArticlesFaelltBeiFehlenderZusammenfassungAufTitelZurueck() throws {
        let defaults = try temporaryUserDefaults()
        let index = FakeSpotlightIndex()
        let snapshot = makeSnapshot(id: "article-1", title: "Titel", summary: nil, feedTitle: "Mein Feed")

        SpotlightIndexingService.indexArticles([snapshot], userDefaults: defaults, index: index)

        #expect(index.indexedItems.first?.attributeSet.contentDescription == "Titel")
    }

    @Test func indexArticlesIstNoOpWennSchalterAusIst() throws {
        let defaults = try temporaryUserDefaults()
        defaults.set(false, forKey: SpotlightIndexingSettings.isEnabledKey)
        let index = FakeSpotlightIndex()
        let snapshot = makeSnapshot(id: "article-1", title: "Titel", summary: nil, feedTitle: "Feed")

        SpotlightIndexingService.indexArticles([snapshot], userDefaults: defaults, index: index)

        #expect(index.indexedItems.isEmpty)
    }

    @Test func deindexArticlesLeitetIdentifiersWeiter() throws {
        let index = FakeSpotlightIndex()

        SpotlightIndexingService.deindexArticles(ids: ["a", "b"], index: index)

        #expect(index.deletedIdentifiers == ["a", "b"])
    }

    @Test func deindexArticlesIstNoOpBeiLeererListe() throws {
        let index = FakeSpotlightIndex()

        SpotlightIndexingService.deindexArticles(ids: [], index: index)

        #expect(index.deletedIdentifiers.isEmpty)
    }

    @Test func deindexAllLoeschtAllesUndSetztBackfillFlagZurueck() throws {
        let defaults = try temporaryUserDefaults()
        defaults.set(true, forKey: SpotlightIndexingSettings.hasBackfilledKey)
        let index = FakeSpotlightIndex()

        SpotlightIndexingService.deindexAll(userDefaults: defaults, index: index)

        #expect(index.didDeleteAll == true)
        #expect(SpotlightIndexingSettings.hasBackfilled(in: defaults) == false)
    }

    @Test func ensureBackfillIfNeededIndexiertAlleBestehendenArtikel() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let defaults = try temporaryUserDefaults()
        let index = FakeSpotlightIndex()
        try FeedStore(database: database).save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Feed"))
        let articleStore = ArticleStore(database: database)
        _ = try articleStore.upsert(ArticleUpsertInput(feedID: "feed-1", title: "Eins"))
        _ = try articleStore.upsert(ArticleUpsertInput(feedID: "feed-1", title: "Zwei"))

        try await SpotlightIndexingService.ensureBackfillIfNeeded(database: database, userDefaults: defaults, index: index)

        #expect(index.indexedItems.count == 2)
        #expect(SpotlightIndexingSettings.hasBackfilled(in: defaults) == true)
    }

    @Test func ensureBackfillIfNeededLaeuftKeinZweitesMal() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let defaults = try temporaryUserDefaults()
        let index = FakeSpotlightIndex()
        try FeedStore(database: database).save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Feed"))
        _ = try ArticleStore(database: database).upsert(ArticleUpsertInput(feedID: "feed-1", title: "Eins"))

        try await SpotlightIndexingService.ensureBackfillIfNeeded(database: database, userDefaults: defaults, index: index)
        try await SpotlightIndexingService.ensureBackfillIfNeeded(database: database, userDefaults: defaults, index: index)

        #expect(index.indexedItems.count == 1)
    }

    @Test func ensureBackfillIfNeededIstNoOpWennSchalterAusIst() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let defaults = try temporaryUserDefaults()
        defaults.set(false, forKey: SpotlightIndexingSettings.isEnabledKey)
        let index = FakeSpotlightIndex()
        try FeedStore(database: database).save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Feed"))
        _ = try ArticleStore(database: database).upsert(ArticleUpsertInput(feedID: "feed-1", title: "Eins"))

        try await SpotlightIndexingService.ensureBackfillIfNeeded(database: database, userDefaults: defaults, index: index)

        #expect(index.indexedItems.isEmpty)
        #expect(SpotlightIndexingSettings.hasBackfilled(in: defaults) == false)
    }

    @Test func ensureBackfillIfNeededSchliesstVersteckteArtikelAus() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let defaults = try temporaryUserDefaults()
        let index = FakeSpotlightIndex()
        try FeedStore(database: database).save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Feed"))
        let articleStore = ArticleStore(database: database)
        let visibleID = try articleStore.upsert(ArticleUpsertInput(feedID: "feed-1", title: "Sichtbar"))
        let hiddenID = try articleStore.upsert(ArticleUpsertInput(feedID: "feed-1", title: "Versteckt"))
        try ArticleStatusStore(database: database).setHidden(true, articleID: hiddenID, at: Date())

        try await SpotlightIndexingService.ensureBackfillIfNeeded(database: database, userDefaults: defaults, index: index)

        #expect(index.indexedItems.map(\.uniqueIdentifier) == [visibleID])
    }
}

private func temporaryUserDefaults() throws -> UserDefaults {
    let suiteName = "FeedivoTests.SpotlightIndexingService.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

private func makeSnapshot(id: String, title: String, summary: String?, feedTitle: String) -> ArticleListSnapshot {
    ArticleListSnapshot(
        id: id,
        feedID: "feed-1",
        feedTitle: feedTitle,
        title: title,
        summary: summary,
        link: nil,
        imageURL: nil,
        publishedAt: nil,
        arrivedAt: Date(timeIntervalSince1970: 0),
        estimatedReadingMinutes: nil,
        isRead: false,
        isStarred: false,
        isArchived: false,
        isHidden: false,
        faviconURL: nil
    )
}
