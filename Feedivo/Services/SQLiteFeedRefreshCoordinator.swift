import Foundation

struct SQLiteFeedRefreshCoordinatorSummary: Equatable {
    var notificationResults: [FeedRefreshNotificationResult]
    var ruleNotificationResults: [RuleNotificationResult]
    var failedFeedTitles: [String]
    var failedFeedIDs: [UUID]
    var succeededFeedIDs: [UUID]
    var skippedFeedIDs: [UUID] = []
}

enum SQLiteFeedRefreshCoordinatorOutcome: Sendable {
    case success(UUID, FeedRefreshNotificationResult, [RuleNotificationResult])
    case failure(UUID, String)
}

struct SQLiteFeedRefreshCoordinator {
    private let database: FeedivoDatabase
    private let ruleSnapshots: [RuleEngine.RuleSnapshot]
    private let batchSize: Int
    private let now: () -> Date
    private let minimumRefreshInterval: TimeInterval
    private let fetcher: SQLiteFeedRefreshService.Fetcher
    private let enrichArticleImages: SQLiteFeedRefreshService.ArticleImageEnricher

    init(
        database: FeedivoDatabase,
        batchSize: Int = FeedViewModel.maxConcurrentFeedRefreshes,
        ruleSnapshots: [RuleEngine.RuleSnapshot] = [],
        now: @escaping () -> Date = Date.init,
        minimumRefreshInterval: TimeInterval = 9 * 60,
        // Standard bewusst ein No-Op — dieselbe Begründung wie in
        // SQLiteFeedRefreshService: schützt SQLiteFeedRefreshCoordinatorTests
        // vor unbeabsichtigten echten Netzwerkaufrufen. Der produktive Aufrufer
        // (SQLiteFeedActionService) setzt den echten Wert explizit.
        //
        // WICHTIG: steht bewusst VOR `fetcher` — `fetcher` muss der letzte
        // Parameter bleiben, weil bestehende Tests ihn per Trailing-Closure
        // setzen. Siehe ausführliche Begründung in SQLiteFeedRefreshService.swift.
        enrichArticleImages: @escaping SQLiteFeedRefreshService.ArticleImageEnricher = { $0 },
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
        self.now = now
        self.minimumRefreshInterval = minimumRefreshInterval
        self.fetcher = fetcher
        self.enrichArticleImages = enrichArticleImages
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

        // Mindestabstand pro Feed (NetNewsWire-Vergleich, 2026-07-27):
        // feed_logs wird bei JEDEM Abrufversuch geschrieben (Erfolg, „Nicht
        // geändert" UND Fehler) — im Unterschied zu feeds.lastRefreshedAt,
        // das nur bei Erfolg gesetzt wird und in der UI als „Zuletzt
        // aktualisiert" erscheint. Ein Lesefehler hier führt bewusst NICHT
        // dazu, dass gar nicht refresht wird (fail open) — refreshAllFeeds
        // selbst hat keine throws-Signatur.
        let lastAttemptTimes = (try? FeedLogStore(database: database).latestAttemptTimes()) ?? [:]
        let currentDate = now()
        var eligibleSnapshots: [FeedRefreshSnapshot] = []
        var skippedFeedIDs: [UUID] = []
        for snapshot in snapshots {
            let lastAttemptAt = lastAttemptTimes[snapshot.id.uuidString]
            if FeedRefreshThrottle.shouldSkip(
                lastAttemptAt: lastAttemptAt,
                now: currentDate,
                minimumInterval: minimumRefreshInterval
            ) {
                skippedFeedIDs.append(snapshot.id)
            } else {
                eligibleSnapshots.append(snapshot)
            }
        }

        guard !eligibleSnapshots.isEmpty else {
            return SQLiteFeedRefreshCoordinatorSummary(
                notificationResults: [],
                ruleNotificationResults: [],
                failedFeedTitles: [],
                failedFeedIDs: [],
                succeededFeedIDs: [],
                skippedFeedIDs: skippedFeedIDs
            )
        }

        var notificationResults: [FeedRefreshNotificationResult] = []
        var ruleNotificationResults: [RuleNotificationResult] = []
        var failedFeedTitles: [String] = []
        var failedFeedIDs: [UUID] = []
        var succeededFeedIDs: [UUID] = []

        for batch in batches(eligibleSnapshots, size: batchSize) {
            await withTaskGroup(of: SQLiteFeedRefreshCoordinatorOutcome.self) { group in
                for snapshot in batch {
                    group.addTask { [database, ruleSnapshots, fetcher, enrichArticleImages] in
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
                                enrichArticleImages: enrichArticleImages,
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
            succeededFeedIDs: succeededFeedIDs,
            skippedFeedIDs: skippedFeedIDs
        )
    }

}
