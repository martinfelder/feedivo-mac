import Foundation
import GRDB
import Testing
@testable import Feedivo

struct SQLiteStatisticsStoreTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeArticle(
        feedID: String,
        sourceID: String,
        title: String,
        arrivedAt: Date,
        estimatedReadingMinutes: Int?,
        articleStore: ArticleStore
    ) throws -> String {
        try articleStore.upsert(ArticleUpsertInput(
            feedID: feedID,
            sourceID: sourceID,
            title: title,
            arrivedAt: arrivedAt,
            estimatedReadingMinutes: estimatedReadingMinutes
        ))
    }

    @Test func readingStatisticsZaehltHeuteWocheUndGesamtGetrennt() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)
        let statisticsStore = StatisticsStore(database: database)
        let now = Self.now

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))

        let today = try makeArticle(feedID: "feed-1", sourceID: "today", title: "Heute", arrivedAt: now, estimatedReadingMinutes: 5, articleStore: articleStore)
        let thisWeek = try makeArticle(feedID: "feed-1", sourceID: "week", title: "Diese Woche", arrivedAt: now, estimatedReadingMinutes: 5, articleStore: articleStore)
        let longAgo = try makeArticle(feedID: "feed-1", sourceID: "old", title: "Vor langer Zeit", arrivedAt: now, estimatedReadingMinutes: 5, articleStore: articleStore)

        try statusStore.setRead(true, articleID: today, at: now)
        try statusStore.setRead(true, articleID: thisWeek, at: now.addingTimeInterval(-3 * 24 * 60 * 60))
        try statusStore.setRead(true, articleID: longAgo, at: now.addingTimeInterval(-40 * 24 * 60 * 60))

        let stats = try statisticsStore.readingStatistics(range: .all, now: now)

        #expect(stats.articlesReadToday == 1)
        #expect(stats.articlesReadThisWeek == 2)
        #expect(stats.articlesReadTotal == 3)
    }

    @Test func readingStatisticsRankedTopFeedsUndRespektiertZeitraum() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)
        let statisticsStore = StatisticsStore(database: database)
        let now = Self.now

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Beliebt"))
        try feedStore.save(FeedRecord(id: "feed-2", url: "https://other.example/feed.xml", title: "Selten"))

        for index in 0..<3 {
            let articleID = try makeArticle(
                feedID: "feed-1",
                sourceID: "popular-\(index)",
                title: "Artikel \(index)",
                arrivedAt: now,
                estimatedReadingMinutes: 5,
                articleStore: articleStore
            )
            try statusStore.setRead(true, articleID: articleID, at: now)
        }

        let oldArticle = try makeArticle(
            feedID: "feed-2",
            sourceID: "outside-range",
            title: "Außerhalb des Zeitraums",
            arrivedAt: now,
            estimatedReadingMinutes: 5,
            articleStore: articleStore
        )
        try statusStore.setRead(true, articleID: oldArticle, at: now.addingTimeInterval(-40 * 24 * 60 * 60))

        let last7Days = try statisticsStore.readingStatistics(range: .last7Days, now: now)

        #expect(last7Days.topFeeds.count == 1)
        #expect(last7Days.topFeeds.first?.feedTitle == "Beliebt")
        #expect(last7Days.topFeeds.first?.count == 3)
    }

    @Test func readingStatisticsRankedTopTags() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)
        let tagStore = TagStore(database: database)
        let statisticsStore = StatisticsStore(database: database)
        let now = Self.now

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))
        try tagStore.save(TagRecord(id: "tag-swift", name: "Swift", colorHex: "#123456"))

        let articleID = try makeArticle(feedID: "feed-1", sourceID: "tagged", title: "Getaggt", arrivedAt: now, estimatedReadingMinutes: 5, articleStore: articleStore)
        try statusStore.setRead(true, articleID: articleID, at: now)
        try tagStore.assignTag(tagID: "tag-swift", toArticleID: articleID, at: now)

        let stats = try statisticsStore.readingStatistics(range: .all, now: now)

        #expect(stats.topTags.count == 1)
        #expect(stats.topTags.first?.name == "Swift")
        #expect(stats.topTags.first?.count == 1)
    }

    @Test func readingStatisticsBerechnetDurchschnittlicheLesezeitProTag() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)
        let statisticsStore = StatisticsStore(database: database)
        let now = Self.now

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))

        let articleID = try makeArticle(feedID: "feed-1", sourceID: "long-read", title: "Langer Artikel", arrivedAt: now, estimatedReadingMinutes: 14, articleStore: articleStore)
        try statusStore.setRead(true, articleID: articleID, at: now)

        let stats = try statisticsStore.readingStatistics(range: .last7Days, now: now)

        #expect(stats.averageReadingMinutesPerDay == 2)
    }

    @Test func feedReadingStatisticsBerechnetLeseProzentsatzUndDurchschnitte() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)
        let statisticsStore = StatisticsStore(database: database)
        let now = Self.now

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))

        let readArticle = try makeArticle(feedID: "feed-1", sourceID: "read", title: "Gelesen", arrivedAt: now, estimatedReadingMinutes: 10, articleStore: articleStore)
        _ = try makeArticle(feedID: "feed-1", sourceID: "unread", title: "Ungelesen", arrivedAt: now, estimatedReadingMinutes: 6, articleStore: articleStore)
        try statusStore.setRead(true, articleID: readArticle, at: now)

        let stats = try statisticsStore.feedReadingStatistics(feedID: "feed-1", now: now)

        #expect(stats.readPercentage == 50)
        #expect(stats.averageReadingMinutes == 10)
        #expect(stats.averageArticlesPerWeek > 0)
    }

    @Test func feedReadingStatisticsLiefertLeereWerteFuerFeedOhneArtikel() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let statisticsStore = StatisticsStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Leer"))

        let stats = try statisticsStore.feedReadingStatistics(feedID: "feed-1", now: Self.now)

        #expect(stats == .empty)
    }

    @Test func readingStatisticsVergleichtZeitraumMitVorperiode() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)
        let statisticsStore = StatisticsStore(database: database)
        let now = Self.now

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))

        // 2 Artikel in der aktuellen 7-Tage-Periode (Tag 0, Tag 3)
        for offset in [0, 3] {
            let articleID = try makeArticle(feedID: "feed-1", sourceID: "current-\(offset)", title: "Aktuell \(offset)", arrivedAt: now, estimatedReadingMinutes: 5, articleStore: articleStore)
            try statusStore.setRead(true, articleID: articleID, at: now.addingTimeInterval(-Double(offset) * 24 * 60 * 60))
        }

        // 4 Artikel in der Vorperiode (Tag 8 bis Tag 13 — direkt vor der aktuellen 7-Tage-Periode)
        for offset in [8, 9, 10, 13] {
            let articleID = try makeArticle(feedID: "feed-1", sourceID: "previous-\(offset)", title: "Vorher \(offset)", arrivedAt: now, estimatedReadingMinutes: 5, articleStore: articleStore)
            try statusStore.setRead(true, articleID: articleID, at: now.addingTimeInterval(-Double(offset) * 24 * 60 * 60))
        }

        // Genau am Grenztag (Tag 7 = Periodengrenze) gelesen — die aktuelle Periode
        // ist `readAt >= now-7d` (inklusiv), zählt also zur AKTUELLEN Periode, nicht
        // zur Vorperiode (die ist `[now-14d, now-7d)`, exklusiv am oberen Ende).
        let boundaryArticle = try makeArticle(feedID: "feed-1", sourceID: "boundary", title: "Grenztag", arrivedAt: now, estimatedReadingMinutes: 5, articleStore: articleStore)
        try statusStore.setRead(true, articleID: boundaryArticle, at: now.addingTimeInterval(-7 * 24 * 60 * 60))

        let stats = try statisticsStore.readingStatistics(range: .last7Days, now: now)

        #expect(stats.articlesReadInSelectedRange == 3)
        #expect(stats.articlesReadInPreviousPeriod == 4)
        #expect(stats.trendPercentage == -25)
    }

    @Test func readingStatisticsHatKeineVorperiodeBeiGesamtZeitraum() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let statisticsStore = StatisticsStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))

        let stats = try statisticsStore.readingStatistics(range: .all, now: Self.now)

        #expect(stats.articlesReadInPreviousPeriod == nil)
        #expect(stats.trendPercentage == nil)
    }

    @Test func readingStatisticsBerechnetGesamtLesezeitUnabhaengigVomZeitraum() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)
        let statisticsStore = StatisticsStore(database: database)
        let now = Self.now

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))

        let recentArticle = try makeArticle(feedID: "feed-1", sourceID: "recent", title: "Neu", arrivedAt: now, estimatedReadingMinutes: 5, articleStore: articleStore)
        try statusStore.setRead(true, articleID: recentArticle, at: now)

        let oldArticle = try makeArticle(feedID: "feed-1", sourceID: "old", title: "Alt", arrivedAt: now, estimatedReadingMinutes: 20, articleStore: articleStore)
        try statusStore.setRead(true, articleID: oldArticle, at: now.addingTimeInterval(-100 * 24 * 60 * 60))

        let last7Days = try statisticsStore.readingStatistics(range: .last7Days, now: now)

        #expect(last7Days.totalReadingMinutesAllTime == 25)
    }

    @Test func readingStatisticsGruppiertNachWochentagUndTageszeitZeitzonenkorrekt() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)
        let statisticsStore = StatisticsStore(database: database)

        // Dienstag, 20 Uhr UTC — in einer Zeitzone UTC-6 (z. B. amerikanisches Festland)
        // ist das lokal noch Dienstag 14 Uhr (Nachmittag), nicht Abend. Ein SQL-date()/
        // strftime()-basiertes Bucketing würde hier UTC-Dienstagabend liefern statt der
        // lokalen Realität.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let readAt = utc.date(from: DateComponents(year: 2026, month: 8, day: 4, hour: 20))!

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))
        let articleID = try articleStore.upsert(ArticleUpsertInput(
            feedID: "feed-1",
            sourceID: "a1",
            title: "Artikel",
            arrivedAt: readAt,
            estimatedReadingMinutes: 5
        ))
        try statusStore.setRead(true, articleID: articleID, at: readAt)

        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let stats = try statisticsStore.readingStatistics(range: .all, now: readAt, calendar: localCalendar)

        let expectedWeekday = localCalendar.component(.weekday, from: readAt)
        let expectedDaypart = ReadingStatisticsDaypart.from(hour: localCalendar.component(.hour, from: readAt))

        #expect(stats.weekdayCounts.first { $0.weekday == expectedWeekday }?.count == 1)
        #expect(stats.daypartCounts.first { $0.daypart == expectedDaypart }?.count == 1)
        #expect(expectedDaypart == .afternoon)
    }

    @Test func readingStatisticsBerechnetDurchschnittlicheArtikelProTag() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)
        let statisticsStore = StatisticsStore(database: database)
        let now = Self.now

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))

        for index in 0..<14 {
            let articleID = try makeArticle(feedID: "feed-1", sourceID: "a\(index)", title: "Artikel \(index)", arrivedAt: now, estimatedReadingMinutes: 5, articleStore: articleStore)
            try statusStore.setRead(true, articleID: articleID, at: now)
        }

        let stats = try statisticsStore.readingStatistics(range: .last7Days, now: now)

        #expect(stats.averageArticlesPerDay == 2)
    }
}
