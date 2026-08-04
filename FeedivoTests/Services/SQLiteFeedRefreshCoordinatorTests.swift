import Foundation
import GRDB
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

    // Whole-Branch-Review-Fund (2026-07-27, Finding 2): das ursprüngliche
    // `try? FeedLogStore(...).latestAttemptTimes()` verschluckte einen
    // Lesefehler beim Throttle-Read komplett still. Fail-open (lieber
    // ungedrosselt refreshen als gar nicht) bleibt die richtige Policy —
    // dieser Test beweist, dass sie bei defekter `feed_logs`-Tabelle
    // weiterhin greift: der Feed wird trotz fehlgeschlagenem Throttle-Read
    // NICHT übersprungen, der `fetcher` wird tatsächlich aufgerufen. (Die
    // fehlende `feed_logs`-Tabelle lässt den NACHGELAGERTEN Log-Schreibzugriff
    // von `SQLiteFeedRefreshService.refresh` bewusst absichtlich weiterhin
    // fehlschlagen — das ist ein unabhängiger, hier nicht relevanter
    // Kollateraleffekt derselben Tabelle, deshalb wird hier nur
    // `skippedFeedIDs`/der tatsächliche Fetcher-Aufruf geprüft, nicht
    // `succeededFeedIDs`.) Die eigentliche Fehlerprotokollierung über
    // `AppLogger.dataAccess` selbst ist mangels Test-Seam für `os.Logger`
    // nicht direkt prüfbar.
    @MainActor
    @Test func refreshAllFeedsRefreshtUngedrosseltWennFeedLogsNichtLesbarSind() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let feedID = UUID().uuidString
        try feedStore.save(FeedRecord(id: feedID, url: "https://example.com/feed.xml", title: "Feed"))

        // Simuliert einen Lesefehler beim Throttle-Read: `latestAttemptTimes()`
        // selektiert aus `feed_logs`, eine fehlende Tabelle lässt `try` fehlschlagen.
        try database.write { db in
            try db.execute(sql: "DROP TABLE feed_logs")
        }

        let fetcherCallCounter = FetcherCallCounter()
        let coordinator = SQLiteFeedRefreshCoordinator(
            database: database,
            fetcher: { url, validators in
                await fetcherCallCounter.increment()
                return .updated(
                    ParsedFeed(sourceURL: url, title: "Feed", description: nil, articles: []),
                    FeedHTTPValidators(lastStatusCode: 200)
                )
            }
        )

        let summary = await coordinator.refreshAllFeeds([
            FeedRefreshSnapshot(id: UUID(uuidString: feedID) ?? UUID(), title: "Feed", url: "https://example.com/feed.xml")
        ])

        #expect(summary.skippedFeedIDs.isEmpty)
        #expect(await fetcherCallCounter.count == 1)
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

    // Optimierungsliste Punkt 1 (docs/performance/feed-refresh-optimierungsliste.md,
    // 2026-08-03): feste Batches à `batchSize` warteten bisher darauf, dass der
    // GESAMTE Batch fertig ist, bevor der nächste startet — ein einzelner langsamer
    // Feed im ersten Batch hielt dadurch Feeds im zweiten Batch auf, obwohl längst
    // ein freier Slot da wäre. Dieser Test hätte gegen den alten Batch-Code
    // fehlgeschlagen: bei batchSize 2 und 4 Feeds (slow, fast0, fast1, fast2) wäre
    // fast2 erst nach Abschluss von Batch 1 (also erst nach Ablauf der 200ms von
    // "slow") gestartet.
    // Erster Anlauf dieses Tests nutzte Wanduhrzeiten (feste Schwelle, dann relativer
    // Vergleich start(fast2) < finish(slow)) — beides flackerte, sobald diese Suite
    // gemeinsam mit anderen Testsuiten lief: Swift Testing führt async Tests standard-
    // mäßig nebenläufig aus, und unter der dadurch entstehenden Konkurrenz um den
    // kooperativen Thread-Pool konnte selbst ein "sofortiger" Task erst nach über 2s
    // tatsächlich starten — deutlich länger als die künstlichen 200-400ms der
    // "langsamen" Testfeeds. Deshalb jetzt eine deterministische Variante ganz ohne
    // Wanduhrzeiten: "slow" blockiert an einem Gate, das der Test selbst erst öffnet,
    // NACHDEM er aktiv beobachtet hat, dass fast2 bereits gestartet ist (oder ein
    // großzügiges Timeout erreicht wurde). Unter dem alten, festen Batch-Code KANN
    // fast2 nie starten, solange "slow" (im selben Batch) blockiert — das Gate würde
    // dadurch nie erreichbar geöffnet, der Test schlägt nach dem Timeout fehl, statt
    // auf eine bestimmte Ausführungsgeschwindigkeit angewiesen zu sein.
    @MainActor
    @Test func refreshAllFeedsFuelltFreieSlotsSofortNachStattAufGanzenBatchZuWarten() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let slowFeedID = UUID().uuidString
        let fastFeedIDs = (0 ..< 3).map { _ in UUID().uuidString }

        try feedStore.save(FeedRecord(id: slowFeedID, url: "https://example.com/slow.xml", title: "Slow"))
        for (index, feedID) in fastFeedIDs.enumerated() {
            try feedStore.save(FeedRecord(id: feedID, url: "https://example.com/fast\(index).xml", title: "Fast \(index)"))
        }

        let slowGate = RefreshTestGate()
        let startedURLs = RefreshTestStartedURLs()

        let coordinator = SQLiteFeedRefreshCoordinator(
            database: database,
            batchSize: 2,
            fetcher: { url, _ in
                await startedURLs.markStarted(url)
                if url == "https://example.com/slow.xml" {
                    await slowGate.wait()
                }
                return .updated(
                    ParsedFeed(sourceURL: url, title: "Feed", description: nil, articles: []),
                    FeedHTTPValidators(lastStatusCode: 200)
                )
            }
        )

        let snapshots = [
            FeedRefreshSnapshot(id: UUID(uuidString: slowFeedID) ?? UUID(), title: "Slow", url: "https://example.com/slow.xml")
        ] + fastFeedIDs.enumerated().map { index, feedID in
            FeedRefreshSnapshot(id: UUID(uuidString: feedID) ?? UUID(), title: "Fast \(index)", url: "https://example.com/fast\(index).xml")
        }

        let refreshTask = Task { await coordinator.refreshAllFeeds(snapshots) }

        // fast2 ist der 4. Feed — bei alten festen 2er-Batches (Batch 1: slow+fast0,
        // Batch 2: fast1+fast2) kann er NIE starten, solange "slow" (Batch 1) noch
        // nicht fertig ist — und "slow" wird hier absichtlich erst nach dieser
        // Beobachtung freigegeben. Bis zu 5s pollen (100ms-Schritte), dann Gate in
        // jedem Fall öffnen, damit kein Task hängen bleibt.
        var fast2StartedWhileSlowBlocked = false
        for _ in 0 ..< 50 {
            if await startedURLs.contains("https://example.com/fast2.xml") {
                fast2StartedWhileSlowBlocked = true
                break
            }
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        await slowGate.open()
        _ = await refreshTask.value

        #expect(fast2StartedWhileSlowBlocked)
    }
}

private actor FaviconDiscoveryCallCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}

private actor FetcherCallCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}

/// Blockiert `wait()`-Aufrufer, bis `open()` gerufen wird — unabhängig davon, ob
/// `wait()` vor oder nach `open()` aufgerufen wurde (spätere `wait()`-Aufrufe nach
/// `open()` kehren sofort zurück).
private actor RefreshTestGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen {
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let toResume = waiters
        waiters = []
        for continuation in toResume {
            continuation.resume()
        }
    }
}

private actor RefreshTestStartedURLs {
    private var urls: Set<String> = []
    func markStarted(_ url: String) {
        urls.insert(url)
    }
    func contains(_ url: String) -> Bool {
        urls.contains(url)
    }
}
