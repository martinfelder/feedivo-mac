import Foundation

struct SQLiteFeedActionService {
    struct SingleFeedRefreshResult {
        var refreshResult: SQLiteFeedRefreshResult
        var isNotificationEnabled: Bool
    }

    private let database: FeedivoDatabase
    private let fetchFeed: @Sendable (String) async throws -> ParsedFeed
    private let fetchFeedConditionally: @Sendable (String, FeedHTTPValidators) async throws -> ConditionalFeedFetchResult
    private let discoverFaviconURL: @Sendable (URL) async -> String?

    init(
        database: FeedivoDatabase,
        fetchFeed: @escaping @Sendable (String) async throws -> ParsedFeed = FeedService.fetchFeed,
        fetchFeedConditionally: @escaping @Sendable (String, FeedHTTPValidators) async throws -> ConditionalFeedFetchResult = FeedService.fetchFeedConditionally,
        discoverFaviconURL: @escaping @Sendable (URL) async -> String? = { siteURL in
            await FaviconService.discoverFaviconURL(siteURL: siteURL)
        }
    ) {
        self.database = database
        self.fetchFeed = fetchFeed
        self.fetchFeedConditionally = fetchFeedConditionally
        self.discoverFaviconURL = discoverFaviconURL
    }

    func addFeed(
        urlString: String,
        refreshIntervalMinutes: Int,
        folderName: String? = nil
    ) async throws {
        let service = SQLiteFeedSubscriptionService(
            database: database,
            fetchFeed: fetchFeed,
            discoverFaviconURL: discoverFaviconURL
        )
        _ = try await service.addFeed(
            urlString: urlString,
            refreshIntervalMinutes: refreshIntervalMinutes,
            folderName: folderName
        )
    }

    func refreshFeed(
        feedID: String,
        ruleSnapshots: [RuleEngine.RuleSnapshot]
    ) async throws -> SingleFeedRefreshResult {
        let service = SQLiteFeedRefreshService(
            database: database,
            ruleSnapshots: ruleSnapshots,
            fetcher: fetcher
        )
        let result = try await service.refresh(feedID: feedID)
        let isNotificationEnabled = (try? FeedStore(database: database)
            .feed(id: feedID)?.isNotificationEnabled) ?? false

        return SingleFeedRefreshResult(
            refreshResult: result,
            isNotificationEnabled: isNotificationEnabled
        )
    }

    func refreshSnapshots() throws -> [FeedRefreshSnapshot] {
        try FeedStore(database: database)
            .feeds()
            .compactMap { record in
                guard let id = UUID(uuidString: record.id) else { return nil }
                return FeedRefreshSnapshot(
                    id: id,
                    title: record.title,
                    url: record.url,
                    isNotificationEnabled: record.isNotificationEnabled
                )
            }
    }

    func refreshAllFeeds(
        _ snapshots: [FeedRefreshSnapshot],
        ruleSnapshots: [RuleEngine.RuleSnapshot],
        batchSize: Int
    ) async -> SQLiteFeedRefreshCoordinatorSummary {
        let coordinator = SQLiteFeedRefreshCoordinator(
            database: database,
            batchSize: batchSize,
            ruleSnapshots: ruleSnapshots,
            fetcher: fetcher
        )
        return await coordinator.refreshAllFeeds(snapshots)
    }

    func deleteFeed(feedID: String) throws {
        try FeedStore(database: database).delete(id: feedID)
    }

    private func fetcher(
        urlString: String,
        validators: FeedHTTPValidators
    ) async throws -> SQLiteFeedFetchResult {
        switch try await fetchFeedConditionally(urlString, validators) {
        case .updated(let feed, let validators):
            return .updated(feed, validators)
        case .notModified(let validators):
            return .notModified(validators)
        }
    }
}
