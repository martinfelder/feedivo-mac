import Foundation
import GRDB

/// Aggregations-Queries für Feature 14 (Lese-Statistiken/Feed-Statistiken). Rein
/// lesend — Rohdaten (`readAt`, `estimatedReadingMinutes`, `assignedAt`) existieren
/// bereits in `articles`/`article_statuses`/`article_tags`, hier wird nur bei
/// Fensteröffnung live aggregiert statt vorab denormalisiert.
struct StatisticsStore {
    private let database: FeedivoDatabase
    private static let heatmapDayCount = 91
    private static let topListLimit = 5

    init(database: FeedivoDatabase) {
        self.database = database
    }

    func readingStatistics(
        range: StatisticsTimeRange,
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> ReadingStatisticsSnapshot {
        try database.read { db in
            let startOfToday = calendar.startOfDay(for: now)
            let startOfThisWeek = calendar.date(byAdding: .day, value: -7, to: now) ?? now
            let heatmapStart = calendar.date(byAdding: .day, value: -(Self.heatmapDayCount - 1), to: startOfToday) ?? startOfToday

            let articlesReadToday = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM article_statuses WHERE isRead = 1 AND readAt >= ?
                """, arguments: [startOfToday]) ?? 0

            let articlesReadThisWeek = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM article_statuses WHERE isRead = 1 AND readAt >= ?
                """, arguments: [startOfThisWeek]) ?? 0

            let articlesReadTotal = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM article_statuses WHERE isRead = 1
                """) ?? 0

            let rangeStart = range.startDate(relativeTo: now)

            let topFeedsByTime = try Row.fetchAll(db, sql: """
                SELECT f.id AS feedID, f.title AS feedTitle, f.faviconURL AS faviconURL,
                       COALESCE(SUM(a.estimatedReadingMinutes), 0) AS minutes, COUNT(*) AS articleCount
                FROM article_statuses s
                JOIN articles a ON a.id = s.articleID
                JOIN feeds f ON f.id = a.feedID
                WHERE s.isRead = 1
                    AND (? IS NULL OR s.readAt >= ?)
                GROUP BY f.id
                ORDER BY minutes DESC, f.title COLLATE NOCASE
                LIMIT ?
                """, arguments: [rangeStart, rangeStart, Self.topListLimit])
                .map {
                    ReadingStatisticsFeedTime(
                        feedID: $0["feedID"],
                        feedTitle: $0["feedTitle"],
                        faviconURL: $0["faviconURL"],
                        minutes: $0["minutes"],
                        articleCount: $0["articleCount"]
                    )
                }

            let topTagsByTime = try Row.fetchAll(db, sql: """
                SELECT t.id AS tagID, t.name AS name, t.colorHex AS colorHex,
                       COALESCE(SUM(a.estimatedReadingMinutes), 0) AS minutes, COUNT(*) AS articleCount
                FROM article_tags at
                JOIN tags t ON t.id = at.tagID
                JOIN article_statuses s ON s.articleID = at.articleID
                JOIN articles a ON a.id = s.articleID
                WHERE s.isRead = 1
                    AND (? IS NULL OR s.readAt >= ?)
                GROUP BY t.id
                ORDER BY minutes DESC, t.name COLLATE NOCASE
                LIMIT ?
                """, arguments: [rangeStart, rangeStart, Self.topListLimit])
                .map {
                    ReadingStatisticsTagTime(
                        tagID: $0["tagID"],
                        name: $0["name"],
                        colorHex: $0["colorHex"],
                        minutes: $0["minutes"],
                        articleCount: $0["articleCount"]
                    )
                }

            let readTimestamps = try Date.fetchAll(db, sql: """
                SELECT readAt FROM article_statuses WHERE isRead = 1 AND readAt >= ?
                """, arguments: [heatmapStart])

            var dailyTally: [Date: Int] = [:]
            var weekdayTally: [Int: Int] = [:]
            var daypartTally: [ReadingStatisticsDaypart: Int] = [:]

            for readAt in readTimestamps {
                let day = calendar.startOfDay(for: readAt)
                dailyTally[day, default: 0] += 1

                let weekday = calendar.component(.weekday, from: readAt)
                weekdayTally[weekday, default: 0] += 1

                let hour = calendar.component(.hour, from: readAt)
                let daypart = ReadingStatisticsDaypart.from(hour: hour)
                daypartTally[daypart, default: 0] += 1
            }

            let dailyReadCounts = dailyTally
                .map { ReadingStatisticsDailyCount(date: $0.key, count: $0.value) }
                .sorted { $0.date < $1.date }
            let weekdayCounts = weekdayTally
                .map { ReadingStatisticsWeekdayCount(weekday: $0.key, count: $0.value) }
                .sorted { $0.weekday < $1.weekday }
            let daypartCounts = ReadingStatisticsDaypart.allCases.map {
                ReadingStatisticsDaypartCount(daypart: $0, count: daypartTally[$0] ?? 0)
            }

            let totalReadingMinutes = try Double.fetchOne(db, sql: """
                SELECT COALESCE(SUM(a.estimatedReadingMinutes), 0)
                FROM article_statuses s
                JOIN articles a ON a.id = s.articleID
                WHERE s.isRead = 1
                    AND (? IS NULL OR s.readAt >= ?)
                """, arguments: [rangeStart, rangeStart]) ?? 0

            let dayCount = Self.dayCount(forRangeStart: rangeStart, now: now)
            let averageReadingMinutesPerDay = dayCount > 0 ? totalReadingMinutes / Double(dayCount) : 0

            let totalReadingMinutesAllTime = try Int.fetchOne(db, sql: """
                SELECT COALESCE(SUM(a.estimatedReadingMinutes), 0)
                FROM article_statuses s
                JOIN articles a ON a.id = s.articleID
                WHERE s.isRead = 1
                """) ?? 0

            let articlesReadInSelectedRange = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM article_statuses
                WHERE isRead = 1 AND (? IS NULL OR readAt >= ?)
                """, arguments: [rangeStart, rangeStart]) ?? 0

            let averageArticlesPerDay = dayCount > 0 ? Double(articlesReadInSelectedRange) / Double(dayCount) : 0

            var articlesReadInPreviousPeriod: Int?
            if let previousPeriod = range.previousPeriodRange(relativeTo: now) {
                articlesReadInPreviousPeriod = try Int.fetchOne(db, sql: """
                    SELECT COUNT(*) FROM article_statuses
                    WHERE isRead = 1 AND readAt >= ? AND readAt < ?
                    """, arguments: [previousPeriod.start, previousPeriod.end]) ?? 0
            }

            return ReadingStatisticsSnapshot(
                articlesReadToday: articlesReadToday,
                articlesReadThisWeek: articlesReadThisWeek,
                articlesReadTotal: articlesReadTotal,
                topFeedsByTime: topFeedsByTime,
                dailyReadCounts: dailyReadCounts,
                averageReadingMinutesPerDay: averageReadingMinutesPerDay,
                topTagsByTime: topTagsByTime,
                weekdayCounts: weekdayCounts,
                daypartCounts: daypartCounts,
                averageArticlesPerDay: averageArticlesPerDay,
                totalReadingMinutesAllTime: totalReadingMinutesAllTime,
                articlesReadInSelectedRange: articlesReadInSelectedRange,
                articlesReadInPreviousPeriod: articlesReadInPreviousPeriod
            )
        }
    }

    func feedReadingStatistics(feedID: String, now: Date = Date()) throws -> FeedReadingStatisticsSnapshot {
        try database.read { db in
            let counts = try Row.fetchOne(db, sql: """
                SELECT
                    COUNT(*) AS totalCount,
                    SUM(CASE WHEN s.isRead = 1 THEN 1 ELSE 0 END) AS readCount,
                    MIN(a.arrivedAt) AS earliestArrivedAt,
                    COALESCE(SUM(CASE WHEN s.isRead = 1 THEN a.estimatedReadingMinutes ELSE 0 END), 0) AS totalReadingMinutes
                FROM articles a
                JOIN article_statuses s ON s.articleID = a.id
                WHERE a.feedID = ?
                """, arguments: [feedID])

            let totalCount: Int = counts?["totalCount"] ?? 0
            let readCount: Int = counts?["readCount"] ?? 0
            let earliestArrivedAt: Date? = counts?["earliestArrivedAt"]
            let totalReadingMinutes: Double = counts?["totalReadingMinutes"] ?? 0

            guard totalCount > 0 else {
                return .empty
            }

            let weekCount = max(1.0, Double(Self.dayCount(forRangeStart: earliestArrivedAt, now: now)) / 7.0)
            let averageArticlesPerWeek = Double(totalCount) / weekCount
            let readPercentage = Double(readCount) / Double(totalCount) * 100
            let averageReadingMinutes = readCount > 0 ? totalReadingMinutes / Double(readCount) : 0

            return FeedReadingStatisticsSnapshot(
                averageArticlesPerWeek: averageArticlesPerWeek,
                readPercentage: readPercentage,
                averageReadingMinutes: averageReadingMinutes
            )
        }
    }

    /// Feeds, die der Nutzer abonniert hat, aber kaum liest — Kandidaten zum Abbestellen
    /// (Feature: Feed-Gesundheit). All-time, unabhängig vom Zeitraum-Picker: "kaum gelesen"
    /// ist ein Langzeit-Signal. `minimumArticleCount` schützt frisch abonnierte Feeds mit
    /// nur wenigen Artikeln davor, fälschlich als "ignoriert" zu erscheinen.
    func feedHealthCandidates(minimumArticleCount: Int = 20, limit: Int = 5) throws -> [ReadingStatisticsFeedHealth] {
        try database.read { db in
            try Row.fetchAll(db, sql: """
                SELECT f.id AS feedID, f.title AS feedTitle,
                       COUNT(*) AS totalCount,
                       SUM(CASE WHEN s.isRead = 1 THEN 1 ELSE 0 END) AS readCount
                FROM articles a
                JOIN article_statuses s ON s.articleID = a.id
                JOIN feeds f ON f.id = a.feedID
                GROUP BY f.id
                HAVING totalCount >= ?
                ORDER BY (CAST(readCount AS REAL) / totalCount) ASC, f.title COLLATE NOCASE
                LIMIT ?
                """, arguments: [minimumArticleCount, limit])
                .map { row -> ReadingStatisticsFeedHealth in
                    let totalCount: Int = row["totalCount"]
                    let readCount: Int = row["readCount"]
                    return ReadingStatisticsFeedHealth(
                        feedID: row["feedID"],
                        feedTitle: row["feedTitle"],
                        unreadCount: totalCount - readCount,
                        totalCount: totalCount,
                        readPercentage: totalCount > 0 ? Double(readCount) / Double(totalCount) * 100 : 0
                    )
                }
        }
    }

    private static func dayCount(forRangeStart start: Date?, now: Date) -> Int {
        guard let start else {
            return 1
        }

        let seconds = now.timeIntervalSince(start)
        return max(1, Int((seconds / 86_400).rounded(.up)))
    }
}
