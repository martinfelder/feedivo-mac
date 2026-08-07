import Foundation
import Testing
@testable import Feedivo

struct ReadingStatisticsInsightTests {
    @Test func generateLiefertNilBeiZuWenigDaten() {
        let weekdayCounts = [ReadingStatisticsWeekdayCount(weekday: 3, count: 5)]
        let daypartCounts = ReadingStatisticsDaypart.allCases.map {
            ReadingStatisticsDaypartCount(daypart: $0, count: $0 == .evening ? 5 : 0)
        }

        let insight = ReadingStatisticsInsight.generate(weekdayCounts: weekdayCounts, daypartCounts: daypartCounts)

        #expect(insight == nil)
    }

    @Test func generateNenntStaerkstenWochentagUndTageszeit() {
        // Dienstag (Calendar-Komponente 3) mit 20 Treffern, Rest verteilt — Dienstag klar Peak.
        let weekdayCounts = [
            ReadingStatisticsWeekdayCount(weekday: 2, count: 3), // Montag
            ReadingStatisticsWeekdayCount(weekday: 3, count: 20), // Dienstag
            ReadingStatisticsWeekdayCount(weekday: 4, count: 2) // Mittwoch
        ]
        let daypartCounts = [
            ReadingStatisticsDaypartCount(daypart: .morning, count: 2),
            ReadingStatisticsDaypartCount(daypart: .midday, count: 1),
            ReadingStatisticsDaypartCount(daypart: .afternoon, count: 3),
            ReadingStatisticsDaypartCount(daypart: .evening, count: 18),
            ReadingStatisticsDaypartCount(daypart: .night, count: 1)
        ]

        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "de_DE")

        let insight = ReadingStatisticsInsight.generate(weekdayCounts: weekdayCounts, daypartCounts: daypartCounts, calendar: calendar)

        #expect(insight != nil)
        #expect(insight?.contains("Dienstag") == true)
        #expect(insight?.contains("abends") == true)
    }

    @Test func generateErgaenztWochenendHinweisUnterFuenfzehnProzent() {
        // Gesamt 25 Artikel, Sa+So zusammen nur 2 (8 % < 15 %-Schwelle).
        let weekdayCounts = [
            ReadingStatisticsWeekdayCount(weekday: 2, count: 5),
            ReadingStatisticsWeekdayCount(weekday: 3, count: 10),
            ReadingStatisticsWeekdayCount(weekday: 4, count: 5),
            ReadingStatisticsWeekdayCount(weekday: 5, count: 2),
            ReadingStatisticsWeekdayCount(weekday: 1, count: 1), // Sonntag
            ReadingStatisticsWeekdayCount(weekday: 7, count: 2) // Samstag
        ]
        let daypartCounts = [ReadingStatisticsDaypartCount(daypart: .evening, count: 25)]

        let insight = ReadingStatisticsInsight.generate(weekdayCounts: weekdayCounts, daypartCounts: daypartCounts)

        #expect(insight?.contains("Wochenende") == true)
    }

    @Test func generateOhneWochenendHinweisUeberFuenfzehnProzent() {
        // Sa+So zusammen 10 von 25 = 40 % — deutlich über der 15 %-Schwelle.
        let weekdayCounts = [
            ReadingStatisticsWeekdayCount(weekday: 2, count: 5),
            ReadingStatisticsWeekdayCount(weekday: 3, count: 10),
            ReadingStatisticsWeekdayCount(weekday: 1, count: 5), // Sonntag
            ReadingStatisticsWeekdayCount(weekday: 7, count: 5) // Samstag
        ]
        let daypartCounts = [ReadingStatisticsDaypartCount(daypart: .evening, count: 25)]

        let insight = ReadingStatisticsInsight.generate(weekdayCounts: weekdayCounts, daypartCounts: daypartCounts)

        #expect(insight?.contains("Wochenende") == false)
    }
}
