import Foundation

struct ReadingStatisticsFeedCount: Equatable, Sendable {
    var feedID: String
    var feedTitle: String
    var faviconURL: String?
    var count: Int
}

struct ReadingStatisticsTagCount: Equatable, Sendable {
    var tagID: String
    var name: String
    var colorHex: String
    var count: Int
}

struct ReadingStatisticsDailyCount: Equatable, Sendable {
    var date: Date
    var count: Int
}

enum ReadingStatisticsDaypart: Int, CaseIterable, Equatable, Sendable {
    case morning
    case midday
    case afternoon
    case evening
    case night

    /// Feste, nicht-überlappende Stundenbuckets — decken alle 24 Stunden lückenlos ab.
    static func from(hour: Int) -> ReadingStatisticsDaypart {
        switch hour {
        case 6...10: return .morning
        case 11...13: return .midday
        case 14...17: return .afternoon
        case 18...22: return .evening
        default: return .night // 23, 0...5
        }
    }
}

struct ReadingStatisticsWeekdayCount: Equatable, Sendable {
    /// `Calendar`-Komponente `.weekday`: 1 = Sonntag … 7 = Samstag.
    var weekday: Int
    var count: Int
}

struct ReadingStatisticsDaypartCount: Equatable, Sendable {
    var daypart: ReadingStatisticsDaypart
    var count: Int
}

struct ReadingStatisticsSnapshot: Equatable, Sendable {
    var articlesReadToday: Int
    var articlesReadThisWeek: Int
    var articlesReadTotal: Int
    var topFeeds: [ReadingStatisticsFeedCount]
    var dailyReadCounts: [ReadingStatisticsDailyCount]
    var averageReadingMinutesPerDay: Double
    var topTags: [ReadingStatisticsTagCount]
    var weekdayCounts: [ReadingStatisticsWeekdayCount]
    var daypartCounts: [ReadingStatisticsDaypartCount]
    var averageArticlesPerDay: Double
    /// Gesamte Lesezeit über die komplette Historie, unabhängig vom Zeitraum-Picker.
    var totalReadingMinutesAllTime: Int
    /// Gelesene Artikel im aktuell gewählten Zeitraum (7/30 Tage/Gesamt).
    var articlesReadInSelectedRange: Int
    /// Gelesene Artikel in der unmittelbar davorliegenden, gleich langen Periode.
    /// `nil` bei Zeitraum `.all` — dafür gibt es keine sinnvolle Vorperiode.
    var articlesReadInPreviousPeriod: Int?

    static let empty = ReadingStatisticsSnapshot(
        articlesReadToday: 0,
        articlesReadThisWeek: 0,
        articlesReadTotal: 0,
        topFeeds: [],
        dailyReadCounts: [],
        averageReadingMinutesPerDay: 0,
        topTags: [],
        weekdayCounts: [],
        daypartCounts: [],
        averageArticlesPerDay: 0,
        totalReadingMinutesAllTime: 0,
        articlesReadInSelectedRange: 0,
        articlesReadInPreviousPeriod: nil
    )

    /// `nil` wenn es keine Vorperiode gibt (`.all`) oder die Vorperiode 0 Artikel
    /// hatte (sonst wäre der Prozentwert unendlich/irreführend).
    var trendPercentage: Double? {
        guard let previous = articlesReadInPreviousPeriod, previous > 0 else {
            return nil
        }

        return (Double(articlesReadInSelectedRange - previous) / Double(previous)) * 100
    }

    /// `dailyReadCounts` enthält nur Tage MIT gelesenen Artikeln (die SQL-Query
    /// filtert `isRead = 1` vor dem `GROUP BY`) — Abwesenheit eines Tages bedeutet
    /// bereits "0 gelesen", ein zusätzlicher Nullwert-Check ist nicht nötig.
    ///
    /// Zählt bis heute rückwärts, bleibt aber bis Mitternacht aktiv, auch wenn
    /// heute noch nichts gelesen wurde — sonst würde die Serie jeden Morgen
    /// demotivierend sofort auf 0 zurückspringen, bevor der Tag vorbei ist.
    var currentStreak: Int {
        let calendar = Calendar.current
        let readDays = Set(dailyReadCounts.map { calendar.startOfDay(for: $0.date) })
        let today = calendar.startOfDay(for: Date())

        var streakEnd = today
        if !readDays.contains(today) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else {
                return 0
            }
            streakEnd = yesterday
        }

        var streak = 0
        var day = streakEnd
        while readDays.contains(day) {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: day) else {
                break
            }
            day = previousDay
        }

        return streak
    }

    /// Längste zusammenhängende Serie innerhalb des geladenen Zeitfensters
    /// (91 Tage für die Heatmap) — nicht die längste Serie über die gesamte
    /// Historie, da das eine zusätzliche Store-Query bräuchte.
    var longestStreak: Int {
        let calendar = Calendar.current
        let sortedDays = dailyReadCounts
            .map { calendar.startOfDay(for: $0.date) }
            .sorted()

        var longest = 0
        var current = 0
        var previousDay: Date?

        for day in sortedDays {
            if let previousDay, calendar.date(byAdding: .day, value: 1, to: previousDay) == day {
                current += 1
            } else {
                current = 1
            }

            longest = max(longest, current)
            previousDay = day
        }

        return longest
    }
}
