import Foundation

/// Deterministisch aus den Gewohnheiten-Daten abgeleiteter, kurzer Hinweissatz für den
/// Hero-Bereich des Statistik-Fensters — reine Formatierungslogik, keine KI-Generierung.
enum ReadingStatisticsInsight {
    /// Mindestanzahl gelesener Artikel im 91-Tage-Fenster, ab der ein Satz überhaupt
    /// angezeigt wird — sonst würde ein aus Rauschen abgeleiteter Satz irreführen.
    private static let minimumSampleSize = 10
    /// Schwelle, unter der Samstag+Sonntag zusammen als "praktisch ungenutzt" gelten.
    private static let weekendQuietThreshold = 0.15

    static func generate(
        weekdayCounts: [ReadingStatisticsWeekdayCount],
        daypartCounts: [ReadingStatisticsDaypartCount],
        calendar: Calendar = .current
    ) -> String? {
        let totalReads = weekdayCounts.reduce(0) { $0 + $1.count }
        guard totalReads >= minimumSampleSize,
              let peakWeekday = weekdayCounts.max(by: { $0.count < $1.count }),
              let peakDaypart = daypartCounts.max(by: { $0.count < $1.count })
        else {
            return nil
        }

        let weekdaySymbol = calendar.weekdaySymbols[peakWeekday.weekday - 1]
        let daypartPhrase = L10n.statisticsInsightDaypartPhrase(peakDaypart.daypart)
        var sentence = L10n.statisticsInsightPeak(weekday: weekdaySymbol, daypart: daypartPhrase)

        let weekendReads = weekdayCounts
            .filter { $0.weekday == 1 || $0.weekday == 7 } // Sonntag, Samstag
            .reduce(0) { $0 + $1.count }
        if Double(weekendReads) / Double(totalReads) < weekendQuietThreshold {
            sentence += L10n.statisticsInsightWeekendQuiet
        }

        return sentence
    }
}
