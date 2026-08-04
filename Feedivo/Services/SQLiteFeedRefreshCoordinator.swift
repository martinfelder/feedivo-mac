import Foundation
import OSLog

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
    private let faviconDiscoveryCoordinator = FaviconDiscoveryCoordinator()
    private let discoverFavicon: @Sendable (URL) async -> String?
    private let fetcher: SQLiteFeedRefreshService.Fetcher
    private let enrichArticleImages: SQLiteFeedRefreshService.ArticleImageEnricher

    init(
        database: FeedivoDatabase,
        batchSize: Int = FeedViewModel.maxConcurrentFeedRefreshes,
        ruleSnapshots: [RuleEngine.RuleSnapshot] = [],
        now: @escaping () -> Date = Date.init,
        minimumRefreshInterval: TimeInterval = 9 * 60,
        // Wird an den gemeinsamen FaviconDiscoveryCoordinator durchgereicht —
        // dedupliziert gleichzeitig laufende Anfragen für dieselbe siteURL
        // innerhalb desselben Refresh-All-Batches (NetNewsWire-Vergleich,
        // 2026-07-27). Standard ist die echte Discovery, kein No-Op wie bei
        // enrichArticleImages/fetcher. ACHTUNG (Whole-Branch-Review-Fund,
        // 2026-07-27, verifiziert): bestehende Coordinator-Tests, die diesen
        // Parameter nicht setzen, aber ein `siteURL` ohne `faviconURL`
        // liefern, lösen dadurch weiterhin einen echten HTTP-Favicon-
        // Discovery-Aufruf aus (vorbestehendes Verhalten, nicht durch diesen
        // Parameter verursacht) — die Testsuite ist dadurch nicht
        // netzwerk-hermetisch.
        discoverFavicon: @escaping @Sendable (URL) async -> String? = { siteURL in
            await FaviconService.discoverFaviconURL(siteURL: siteURL)
        },
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
        self.discoverFavicon = discoverFavicon
        self.fetcher = fetcher
        self.enrichArticleImages = enrichArticleImages
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
        // selbst hat keine throws-Signatur. Das Verschlucken bleibt aber
        // NICHT still (Whole-Branch-Review-Fund, 2026-07-27): der Fehler
        // landet über AppLogger.dataAccess im Apple-Systemlog, analog zum
        // bereits etablierten Muster in ArticleRetentionCleanupService.swift.
        let lastAttemptTimes: [String: Date]
        do {
            lastAttemptTimes = try FeedLogStore(database: database).latestAttemptTimes()
        } catch {
            AppLogger.dataAccess.error("Refresh-Throttling: feed_logs nicht lesbar, refreshe ungedrosselt: \(error.localizedDescription, privacy: .public)")
            lastAttemptTimes = [:]
        }
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

        // Echte Warteschlange statt fester Batches (Optimierungsliste Punkt 1,
        // docs/performance/feed-refresh-optimierungsliste.md, 2026-08-03; NetNewsWire-
        // Vergleich: DownloadSession füllt ihre Warteschlange ebenfalls sofort nach,
        // sobald ein Slot frei wird, statt in festen Gruppen zu warten). Vorher wartete
        // `for batch in batches(...)` auf den KOMPLETTEN Batch, bevor der nächste
        // startete — ein einzelner langsamer Feed im Batch hielt dadurch bereits
        // fertige Nachbarn UND den Start des nächsten Batches auf, obwohl längst ein
        // freier Slot da wäre. `iterator` wird hier bewusst nur synchron zwischen den
        // `await`-Punkten mutiert (nie innerhalb eines `group.addTask`-Kindtasks), das
        // ist datenrace-frei.
        var iterator = eligibleSnapshots.makeIterator()

        await withTaskGroup(of: SQLiteFeedRefreshCoordinatorOutcome.self) { group in
            func addNextTaskIfAvailable() {
                guard let snapshot = iterator.next() else {
                    return
                }
                group.addTask { [database, ruleSnapshots, fetcher, enrichArticleImages, faviconDiscoveryCoordinator, discoverFavicon] in
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
                            discoverFaviconURL: { siteURL in
                                await faviconDiscoveryCoordinator.discover(siteURL: siteURL, using: discoverFavicon)
                            },
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

            for _ in 0 ..< min(batchSize, eligibleSnapshots.count) {
                addNextTaskIfAvailable()
            }

            while let outcome = await group.next() {
                switch outcome {
                case .success(let feedID, let result, let ruleNotifications):
                    notificationResults.append(result)
                    succeededFeedIDs.append(feedID)
                    ruleNotificationResults.append(contentsOf: ruleNotifications)
                case .failure(let feedID, let failedTitle):
                    failedFeedIDs.append(feedID)
                    failedFeedTitles.append(failedTitle)
                }
                addNextTaskIfAvailable()
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
