import Foundation
import GRDB
import Testing
@testable import Feedivo

private func seedLargeSQLiteDataset(
    database: FeedivoDatabase,
    feedCount: Int,
    articlesPerFeed: Int
) throws {
    let now = Date()

    // Der komplette Seed läuft in einer Transaktion. So misst der Benchmark die
    // produktiven Lesewege und nicht zehntausende einzelne Test-Transaktionen.
    try database.write { db in
        for feedIndex in 0..<feedCount {
            let feedID = "feed-\(feedIndex)"
            try db.execute(
                sql: """
                    INSERT INTO feeds (id, url, title, createdAt, updatedAt)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: [
                    feedID,
                    "https://example.com/\(feedIndex).xml",
                    "Feed \(feedIndex)",
                    now,
                    now
                ]
            )

            for articleIndex in 0..<articlesPerFeed {
                let globalIndex = feedIndex * articlesPerFeed + articleIndex
                let publishedAt = now.addingTimeInterval(TimeInterval(-globalIndex))
                let articleID = "article-\(feedIndex)-\(articleIndex)"
                try db.execute(
                    sql: """
                        INSERT INTO articles (
                            id, feedID, sourceID, link, title, summary,
                            publishedAt, arrivedAt, updatedAt, estimatedReadingMinutes
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        articleID,
                        feedID,
                        "source-\(feedIndex)-\(articleIndex)",
                        "https://example.com/\(feedIndex)/\(articleIndex)",
                        "Article \(feedIndex)-\(articleIndex)",
                        "Summary \(feedIndex)-\(articleIndex)",
                        publishedAt,
                        publishedAt,
                        publishedAt,
                        (articleIndex % 12) + 1
                    ]
                )
                try db.execute(
                    sql: """
                        INSERT INTO article_statuses (articleID, isRead, dateArrived, readAt)
                        VALUES (?, ?, ?, ?)
                        """,
                    arguments: [
                        articleID,
                        articleIndex % 2 == 0,
                        publishedAt,
                        articleIndex % 2 == 0 ? now : nil
                    ]
                )
            }
        }
    }
}

private func measureMilliseconds<T>(
    _ name: String,
    operation: () throws -> T
) rethrows -> (value: T, milliseconds: Double) {
    let start = ProcessInfo.processInfo.systemUptime
    let result = try operation()
    let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1_000
    print(String(format: "PERF_METRIC %@ %.3f ms", name, elapsed))
    return (result, elapsed)
}

private func seedFeedLogsHistory(
    database: FeedivoDatabase,
    feedIDs: [String],
    entriesPerFeed: Int,
    now: Date
) throws {
    try database.write { db in
        for feedID in feedIDs {
            for entryIndex in 0..<entriesPerFeed {
                // Genau 1 Eintrag pro Feed bleibt innerhalb der 30-Tage-
                // Standard-Aufbewahrung (1 Tag alt), der Rest liegt bewusst weit
                // außerhalb (200 Tage alt) — macht die erwartete Zeilenzahl nach
                // der Bereinigung deterministisch prüfbar.
                let createdAt = entryIndex == 0
                    ? now.addingTimeInterval(-1 * 24 * 60 * 60)
                    : now.addingTimeInterval(-200 * 24 * 60 * 60)
                try db.execute(
                    sql: """
                        INSERT INTO feed_logs (
                            id, feedID, createdAt, level, message, newArticleCount
                        ) VALUES (?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        "\(feedID)-log-\(entryIndex)",
                        feedID,
                        createdAt,
                        "info",
                        "Refresh \(entryIndex)",
                        1
                    ]
                )
            }
        }
    }
}

@Suite(.serialized)
struct SQLiteLargeDatasetPerformanceTests {
    @Test func zielbestandMitTieferPaginationBleibtReaktionsschnell() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        var metrics: [(String, Double)] = []
        let seed = try measureMilliseconds("seed_500_feeds_100000_articles") {
            try seedLargeSQLiteDataset(database: database, feedCount: 500, articlesPerFeed: 200)
        }
        metrics.append(("seed_500_feeds_100000_articles", seed.milliseconds))

        let timelineStore = TimelineStore(database: database)
        let feedStore = FeedStore(database: database)

        let firstPageMeasurement = try measureMilliseconds("timeline_first_page_newest") {
            try timelineStore.articles(
                scope: .all,
                includeRead: true,
                includeHidden: false,
                sortOption: .newestFirst,
                limit: 200
            )
        }
        let firstPage = firstPageMeasurement.value
        metrics.append(("timeline_first_page_newest", firstPageMeasurement.milliseconds))
        #expect(firstPage.count == 200)

        let middlePageMeasurement = try measureMilliseconds("timeline_offset_50000_newest") {
            try timelineStore.articles(
                scope: .all,
                includeRead: true,
                includeHidden: false,
                sortOption: .newestFirst,
                limit: 200,
                offset: 50_000
            )
        }
        let middlePage = middlePageMeasurement.value
        metrics.append(("timeline_offset_50000_newest", middlePageMeasurement.milliseconds))
        #expect(middlePage.count == 200)

        let deepestPageMeasurement = try measureMilliseconds("timeline_offset_99800_newest") {
            try timelineStore.articles(
                scope: .all,
                includeRead: true,
                includeHidden: false,
                sortOption: .newestFirst,
                limit: 200,
                offset: 99_800
            )
        }
        let deepestPage = deepestPageMeasurement.value
        metrics.append(("timeline_offset_99800_newest", deepestPageMeasurement.milliseconds))
        #expect(deepestPage.count == 200)

        let deepestTitlePageMeasurement = try measureMilliseconds("timeline_offset_99800_title") {
            try timelineStore.articles(
                scope: .all,
                includeRead: true,
                includeHidden: false,
                sortOption: .title,
                limit: 200,
                offset: 99_800
            )
        }
        let deepestTitlePage = deepestTitlePageMeasurement.value
        metrics.append(("timeline_offset_99800_title", deepestTitlePageMeasurement.milliseconds))
        #expect(deepestTitlePage.count == 200)

        let searchMeasurement = try measureMilliseconds("fts_search") {
            try timelineStore.articles(
                scope: .all,
                searchText: "Article 42",
                includeRead: true,
                includeHidden: false,
                limit: 200
            )
        }
        let searchResults = searchMeasurement.value
        metrics.append(("fts_search", searchMeasurement.milliseconds))
        #expect(!searchResults.isEmpty)

        let countMeasurement = try measureMilliseconds("timeline_count_all") {
            try timelineStore.count(
                scope: .all,
                includeRead: true,
                includeHidden: false
            )
        }
        let articleCount = countMeasurement.value
        metrics.append(("timeline_count_all", countMeasurement.milliseconds))
        #expect(articleCount == 100_000)

        let sidebarMeasurement = try measureMilliseconds("sidebar_500_feeds") {
            try feedStore.sidebarFeeds()
        }
        let sidebarFeeds = sidebarMeasurement.value
        metrics.append(("sidebar_500_feeds", sidebarMeasurement.milliseconds))
        #expect(sidebarFeeds.count == 500)
        #expect(sidebarMeasurement.milliseconds < 1_000)

        let metricsText = metrics
            .map { String(format: "%@=%.3f", $0.0, $0.1) }
            .joined(separator: "\n") + "\n"
        Attachment.record(metricsText, named: "feedivo-performance-metrics.txt")

        // Auch die tiefste Seite soll klar unter einer wahrnehmbaren Sekunde
        // bleiben. Die Messwerte werden zusätzlich für den Bericht ausgegeben.
        let thresholdStart = ProcessInfo.processInfo.systemUptime
        _ = try timelineStore.articles(
            scope: .all,
            includeRead: true,
            includeHidden: false,
            sortOption: .newestFirst,
            limit: 200,
            offset: 99_800
        )
        #expect(ProcessInfo.processInfo.systemUptime - thresholdStart < 1.0)
    }

    @Test func timelineQueriesSindUnterLastbedingungenSchnell() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try seedLargeSQLiteDataset(database: database, feedCount: 100, articlesPerFeed: 600)

        let timelineStore = TimelineStore(database: database)
        let articleStore = ArticleStore(database: database)

        let timelineAllStart = Date()
        let firstBatch = try timelineStore.articles(
            scope: .all,
            searchText: nil,
            includeRead: false,
            includeHidden: false,
            limit: 500
        )
        let timelineAllElapsed = Date().timeIntervalSince(timelineAllStart)
        #expect(firstBatch.count == 500)
        #expect(timelineAllElapsed < 1.8)

        let timelineFeedStart = Date()
        let perFeedBatch = try timelineStore.articles(
            scope: .feed("feed-42"),
            searchText: nil,
            includeRead: false,
            includeHidden: false,
            limit: 500
        )
        let timelineFeedElapsed = Date().timeIntervalSince(timelineFeedStart)
        #expect(perFeedBatch.count <= 500)
        #expect(timelineFeedElapsed < 0.9)

        let searchStart = Date()
        let searchResults = try articleStore.searchArticles(
            state: ArticleSearchWindowState(searchText: "Article 42"),
            includeHidden: false,
            limit: 100
        )
        let searchElapsed = Date().timeIntervalSince(searchStart)
        #expect(searchResults.count > 0)
        #expect(searchElapsed < 0.9)
    }

    @Test func readsUmschaltenUndTimelineNeuLadenIstEffizient() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try seedLargeSQLiteDataset(database: database, feedCount: 100, articlesPerFeed: 600)

        let timelineStore = TimelineStore(database: database)
        let statusStore = ArticleStatusStore(database: database)
        let firstUnread = try timelineStore.articles(
            scope: .all,
            searchText: nil,
            includeRead: false,
            includeHidden: false,
            limit: 1
        ).first
        #expect(firstUnread != nil)

        let updateStart = Date()
        try statusStore.setRead(true, articleID: try #require(firstUnread?.id), at: Date())
        let afterUpdate = try timelineStore.articles(
            scope: .all,
            searchText: nil,
            includeRead: false,
            includeHidden: false,
            limit: 1
        )
        let updateElapsed = Date().timeIntervalSince(updateStart)

        #expect(afterUpdate.isEmpty || afterUpdate.allSatisfy { !$0.id.isEmpty })
        #expect(updateElapsed < 0.4)
    }

    @Test func sidebarUndArtikelCountsLassenSichSchnellBerechnen() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try seedLargeSQLiteDataset(database: database, feedCount: 100, articlesPerFeed: 600)

        let feedStore = FeedStore(database: database)
        let statusStore = ArticleStatusStore(database: database)
        let countStart = Date()

        let feedSnapshots = try feedStore.sidebarFeeds()
        var totalUnread = 0
        for index in 0..<feedSnapshots.count {
            totalUnread += try statusStore.unreadCount(feedID: "feed-\(index)")
        }

        let countElapsed = Date().timeIntervalSince(countStart)
        #expect(feedSnapshots.count == 100)
        #expect(totalUnread > 0)
        #expect(countElapsed < 1.5)
    }

    @Test func feedLogsRetentionHaeltSidebarFeedsSchnellBeiGrosserHistorie() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let now = Date()

        let feedIDs = (0..<500).map { "feed-\($0)" }
        try database.write { db in
            for feedID in feedIDs {
                try db.execute(
                    sql: """
                        INSERT INTO feeds (id, url, title, createdAt, updatedAt)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                    arguments: [feedID, "https://example.com/\(feedID).xml", "Feed \(feedID)", now, now]
                )
            }
        }
        try seedFeedLogsHistory(database: database, feedIDs: feedIDs, entriesPerFeed: 200, now: now)

        let totalBeforePruning = try database.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM feed_logs") ?? 0
        }
        #expect(totalBeforePruning == 500 * 200)

        let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -FeedLogRetentionSettings.defaultRetentionDays,
            to: now
        )!
        try FeedLogStore(database: database).deleteOlderThan(cutoff)

        let totalAfterPruning = try database.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM feed_logs") ?? 0
        }
        #expect(totalAfterPruning == 500)

        let sidebarMeasurement = try measureMilliseconds("sidebar_500_feeds_after_feedlog_retention") {
            try feedStore.sidebarFeeds()
        }
        #expect(sidebarMeasurement.value.count == 500)
        #expect(sidebarMeasurement.milliseconds < 1_000)
    }
}
