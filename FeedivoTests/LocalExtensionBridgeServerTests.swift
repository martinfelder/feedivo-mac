import Foundation
import Testing
@testable import Feedivo

struct LocalExtensionBridgeServerTests {
    @MainActor
    @Test func isSubscribedLiefertTrueFuerBekannteURL() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try FeedStore(database: database).save(
            FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Feed 1")
        )

        let subscribed = await LocalExtensionBridgeServer.isSubscribed(
            "https://example.com/feed.xml",
            database: database
        )

        #expect(subscribed == true)
    }

    @MainActor
    @Test func isSubscribedVergleichtGetrimmtUndOhneGrossKleinschreibung() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try FeedStore(database: database).save(
            FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Feed 1")
        )

        let subscribed = await LocalExtensionBridgeServer.isSubscribed(
            "  HTTPS://EXAMPLE.COM/FEED.XML  ",
            database: database
        )

        #expect(subscribed == true)
    }

    @MainActor
    @Test func isSubscribedLiefertFalseFuerUnbekannteURL() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        let subscribed = await LocalExtensionBridgeServer.isSubscribed(
            "https://example.com/unbekannt.xml",
            database: database
        )

        #expect(subscribed == false)
    }

    @MainActor
    @Test func addFeedFuegtNeuenFeedHinzu() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        let result = await LocalExtensionBridgeServer.addFeed(
            "https://example.com/feed.xml",
            database: database,
            fetchFeed: { url in
                ParsedFeed(sourceURL: url, title: "Test-Feed", description: nil, articles: [])
            }
        )

        #expect(result == .added)
        let feeds = try FeedStore(database: database).feeds()
        #expect(feeds.count == 1)
        #expect(feeds.first?.url == "https://example.com/feed.xml")
    }

    @MainActor
    @Test func addFeedLiefertAlreadyExistsBeiDuplikat() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let fetchFeed: @Sendable (String) async throws -> ParsedFeed = { url in
            ParsedFeed(sourceURL: url, title: "Test-Feed", description: nil, articles: [])
        }

        let firstResult = await LocalExtensionBridgeServer.addFeed(
            "https://example.com/feed.xml",
            database: database,
            fetchFeed: fetchFeed
        )
        #expect(firstResult == .added)

        let secondResult = await LocalExtensionBridgeServer.addFeed(
            "https://example.com/feed.xml",
            database: database,
            fetchFeed: fetchFeed
        )
        #expect(secondResult == .alreadyExists)
    }

    @MainActor
    @Test func addFeedLiefertErrorBeiFetchFehler() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        let result = await LocalExtensionBridgeServer.addFeed(
            "https://example.com/feed.xml",
            database: database,
            fetchFeed: { _ in
                throw URLError(.notConnectedToInternet)
            }
        )

        guard case .error = result else {
            Issue.record("Erwartete .error, bekam \(result)")
            return
        }
    }
}
