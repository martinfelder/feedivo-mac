import Foundation
import Testing
@testable import Feedivo

struct SQLiteFeedRefreshCoordinatorTests {
    @MainActor
    @Test func refreshAllFeedsLädtAlleSnapshotsParallelUndLiefertStatus() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let firstFeedID = UUID().uuidString
        let secondFeedID = UUID().uuidString
        try feedStore.save(
            FeedRecord(
                id: firstFeedID,
                url: "https://example.com/first.xml",
                title: "Feed 1"
            )
        )
        try feedStore.save(
            FeedRecord(
                id: secondFeedID,
                url: "https://example.com/second.xml",
                title: "Feed 2"
            )
        )

        let coordinator = SQLiteFeedRefreshCoordinator(
            database: database,
            batchSize: 1,
            fetcher: { url, _ in
                if url == "https://example.com/first.xml" {
                    return .updated(
                        ParsedFeed(
                            sourceURL: url,
                            title: "Feed 1",
                            description: nil,
                            siteURL: "https://example.com",
                            articles: [
                                ParsedArticle(
                                    title: "Artikel 1",
                                    sourceID: "first-article",
                                    link: "https://example.com/first",
                                    summary: nil,
                                    content: nil,
                                    publishedAt: nil,
                                    imageURL: nil
                                )
                            ]
                        ),
                        FeedHTTPValidators(eTag: "etag-first", lastStatusCode: 200)
                    )
                }

                return .notModified(
                    FeedHTTPValidators(lastStatusCode: 304)
                )
            }
        )

        let summary = await coordinator.refreshAllFeeds([
            FeedRefreshSnapshot(
                id: UUID(uuidString: firstFeedID) ?? UUID(),
                title: "Feed 1",
                url: "https://example.com/first.xml",
                isNotificationEnabled: true
            ),
            FeedRefreshSnapshot(
                id: UUID(uuidString: secondFeedID) ?? UUID(),
                title: "Feed 2",
                url: "https://example.com/second.xml",
                isNotificationEnabled: false
            )
        ])

        #expect(summary.notificationResults.count == 2)
        #expect(summary.failedFeedTitles.isEmpty)
        #expect(summary.succeededFeedIDs.count == 2)
    }

    @MainActor
    @Test func refreshAllFeedsMarkiertNichtVorhandeneFeedsAlsFehler() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let existingFeedID = UUID().uuidString
        let missingFeedID = UUID().uuidString

        try feedStoreTest(database: database, id: existingFeedID)

        let coordinator = SQLiteFeedRefreshCoordinator(
            database: database,
            fetcher: { url, _ in
                if url == "https://example.com/existing.xml" {
                    return .updated(
                        ParsedFeed(
                            sourceURL: "https://example.com/existing.xml",
                            title: "Existing",
                            description: nil,
                            siteURL: "https://example.com",
                            articles: []
                        ),
                        FeedHTTPValidators(lastStatusCode: 200)
                    )
                }

                throw URLError(.badServerResponse)
            }
        )

        let summary = await coordinator.refreshAllFeeds([
            FeedRefreshSnapshot(
                id: UUID(uuidString: existingFeedID) ?? UUID(),
                title: "Existing",
                url: "https://example.com/existing.xml",
                isNotificationEnabled: true
            ),
            FeedRefreshSnapshot(
                id: UUID(uuidString: missingFeedID) ?? UUID(),
                title: "Missing",
                url: "https://example.com/missing.xml",
                isNotificationEnabled: true
            )
        ])

        #expect(summary.failedFeedTitles == ["Missing"])
        #expect(summary.failedFeedIDs.count == 1)
        #expect(summary.succeededFeedIDs.count == 1)
    }

    private func feedStoreTest(database: FeedivoDatabase, id: String) throws {
        try FeedStore(database: database).save(
            FeedRecord(
                id: id,
                url: "https://example.com/existing.xml",
                title: "Existing"
            )
        )
    }

    @MainActor
    @Test func refreshAllFeedsUeberspringtFeedMitZuKurzZurueckliegendemVersuch() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let logStore = FeedLogStore(database: database)
        let recentlyAttemptedFeedID = UUID().uuidString
        let staleAttemptFeedID = UUID().uuidString
        let neverAttemptedFeedID = UUID().uuidString
        let now = Date(timeIntervalSince1970: 100_000)

        try feedStore.save(FeedRecord(id: recentlyAttemptedFeedID, url: "https://example.com/recent.xml", title: "Recent"))
        try feedStore.save(FeedRecord(id: staleAttemptFeedID, url: "https://example.com/stale.xml", title: "Stale"))
        try feedStore.save(FeedRecord(id: neverAttemptedFeedID, url: "https://example.com/never.xml", title: "Never"))

        try logStore.append(FeedLogRecord(
            feedID: recentlyAttemptedFeedID,
            createdAt: now.addingTimeInterval(-5 * 60),
            level: "info",
            message: "Nicht geändert"
        ))
        try logStore.append(FeedLogRecord(
            feedID: staleAttemptFeedID,
            createdAt: now.addingTimeInterval(-10 * 60),
            level: "info",
            message: "Nicht geändert"
        ))

        let coordinator = SQLiteFeedRefreshCoordinator(
            database: database,
            now: { now },
            fetcher: { _, _ in .notModified(FeedHTTPValidators(lastStatusCode: 304)) }
        )

        let summary = await coordinator.refreshAllFeeds([
            FeedRefreshSnapshot(id: UUID(uuidString: recentlyAttemptedFeedID) ?? UUID(), title: "Recent", url: "https://example.com/recent.xml"),
            FeedRefreshSnapshot(id: UUID(uuidString: staleAttemptFeedID) ?? UUID(), title: "Stale", url: "https://example.com/stale.xml"),
            FeedRefreshSnapshot(id: UUID(uuidString: neverAttemptedFeedID) ?? UUID(), title: "Never", url: "https://example.com/never.xml")
        ])

        #expect(summary.skippedFeedIDs == [UUID(uuidString: recentlyAttemptedFeedID)])
        #expect(summary.succeededFeedIDs.count == 2)
        #expect(try logStore.logs(feedID: recentlyAttemptedFeedID, limit: 10).count == 1)
        #expect(try logStore.logs(feedID: staleAttemptFeedID, limit: 10).count == 2)
        #expect(try logStore.logs(feedID: neverAttemptedFeedID, limit: 10).count == 1)
    }

    @MainActor
    @Test func refreshAllFeedsDedupliziertFaviconDiscoveryFuerDieselbeSiteURL() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let firstFeedID = UUID().uuidString
        let secondFeedID = UUID().uuidString
        try feedStore.save(FeedRecord(id: firstFeedID, url: "https://example.com/first.xml", title: "Feed 1"))
        try feedStore.save(FeedRecord(id: secondFeedID, url: "https://example.com/second.xml", title: "Feed 2"))

        let discoveryCounter = FaviconDiscoveryCallCounter()
        let coordinator = SQLiteFeedRefreshCoordinator(
            database: database,
            discoverFavicon: { _ in
                await discoveryCounter.increment()
                try? await Task.sleep(nanoseconds: 50_000_000)
                return "https://shared-site.example/favicon.ico"
            },
            fetcher: { url, _ in
                .updated(
                    ParsedFeed(
                        sourceURL: url,
                        title: "Feed",
                        description: nil,
                        siteURL: "https://shared-site.example",
                        articles: []
                    ),
                    FeedHTTPValidators(lastStatusCode: 200)
                )
            }
        )

        _ = await coordinator.refreshAllFeeds([
            FeedRefreshSnapshot(id: UUID(uuidString: firstFeedID) ?? UUID(), title: "Feed 1", url: "https://example.com/first.xml"),
            FeedRefreshSnapshot(id: UUID(uuidString: secondFeedID) ?? UUID(), title: "Feed 2", url: "https://example.com/second.xml")
        ])

        #expect(await discoveryCounter.count == 1)
        let firstFeed = try feedStore.feed(id: firstFeedID)
        let secondFeed = try feedStore.feed(id: secondFeedID)
        #expect(firstFeed?.faviconURL == "https://shared-site.example/favicon.ico")
        #expect(secondFeed?.faviconURL == "https://shared-site.example/favicon.ico")
    }
}

private actor FaviconDiscoveryCallCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}
