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
}
