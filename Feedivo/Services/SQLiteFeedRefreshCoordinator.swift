import Foundation

struct SQLiteFeedRefreshCoordinatorSummary: Equatable {
    var notificationResults: [FeedRefreshNotificationResult]
    var ruleNotificationResults: [RuleNotificationResult]
    var failedFeedTitles: [String]
    var failedFeedIDs: [UUID]
    var succeededFeedIDs: [UUID]
}

enum SQLiteFeedRefreshCoordinatorOutcome: Sendable {
    case success(UUID, FeedRefreshNotificationResult, [RuleNotificationResult])
    case failure(UUID, String)
}

struct SQLiteFeedRefreshCoordinator {
    private let database: FeedivoDatabase
    private let ruleSnapshots: [RuleEngine.RuleSnapshot]
    private let batchSize: Int
    private let fetcher: SQLiteFeedRefreshService.Fetcher

    init(
        database: FeedivoDatabase,
        batchSize: Int = FeedViewModel.maxConcurrentFeedRefreshes,
        ruleSnapshots: [RuleEngine.RuleSnapshot] = [],
        fetcher: @escaping SQLiteFeedRefreshService.Fetcher = { urlString, validators in
            switch try await FeedService.fetchFeedConditionally(urlString: urlString, validators: validators) {
            case .updated(let feed, let validators):
                return .updated(feed, validators)
            case .notModified(let validators):
                return .notModified(validators)
            }
        }
    ) {
        self.database = database
        self.ruleSnapshots = ruleSnapshots
        self.batchSize = batchSize
        self.fetcher = fetcher
    }

    private func batches<T>(_ items: [T], size: Int) -> [[T]] {
        guard !items.isEmpty else {
            return []
        }
        return stride(from: 0, to: items.count, by: size).map { start in
            Array(items[start ..< min(start + size, items.count)])
        }
    }

    func refreshAllFeeds(
        _ snapshots: [FeedRefreshSnapshot]
    ) async -> SQLiteFeedRefreshCoordinatorSummary {
        guard !snapshots.isEmpty else {
            return SQLiteFeedRefreshCoordinatorSummary(
                notificationResults: [],
                ruleNotificationResults: [],
                failedFeedTitles: [],
                failedFeedIDs: [],
                succeededFeedIDs: []
            )
        }

        var notificationResults: [FeedRefreshNotificationResult] = []
        var ruleNotificationResults: [RuleNotificationResult] = []
        var failedFeedTitles: [String] = []
        var failedFeedIDs: [UUID] = []
        var succeededFeedIDs: [UUID] = []

        for batch in batches(snapshots, size: batchSize) {
            await withTaskGroup(of: SQLiteFeedRefreshCoordinatorOutcome.self) { group in
                for snapshot in batch {
                    group.addTask { [database, ruleSnapshots, fetcher] in
                        do {
                            let feedID = snapshot.id.uuidString
                            let feedStore = FeedStore(database: database)
                            if try feedStore.feed(id: feedID) == nil {
                                try feedStore.save(
                                    FeedRecord(
                                        id: feedID,
                                        url: snapshot.url,
                                        title: snapshot.title
                                    )
                                )
                            }

                            let service = SQLiteFeedRefreshService(
                                database: database,
                                ruleSnapshots: ruleSnapshots,
                                fetcher: fetcher
                            )
                            let result = try await service.refresh(feedID: feedID)
                            return .success(
                                snapshot.id,
                                FeedRefreshNotificationResult(
                                    feedTitle: result.feedTitle,
                                    newArticleCount: result.newArticleCount,
                                    isNotificationEnabled: snapshot.isNotificationEnabled
                                ),
                                result.ruleNotifications
                            )
                        } catch {
                            return .failure(snapshot.id, snapshot.title)
                        }
                    }
                }

                for await outcome in group {
                    switch outcome {
                    case .success(let feedID, let result, let ruleNotifications):
                        notificationResults.append(result)
                        succeededFeedIDs.append(feedID)
                        ruleNotificationResults.append(contentsOf: ruleNotifications)
                    case .failure(let feedID, let failedTitle):
                        failedFeedIDs.append(feedID)
                        failedFeedTitles.append(failedTitle)
                    }
                }
            }
        }

        return SQLiteFeedRefreshCoordinatorSummary(
            notificationResults: notificationResults,
            ruleNotificationResults: ruleNotificationResults,
            failedFeedTitles: failedFeedTitles,
            failedFeedIDs: failedFeedIDs,
            succeededFeedIDs: succeededFeedIDs
        )
    }

}
