import Foundation

/// Baut die CSV-Datei für Feature 14.3 — Lese-Statistiken (14.1) und
/// Feed-Statistiken (14.2) zusammen in einer Datei, je eigener Mini-Tabelle
/// getrennt durch eine Leerzeile (kein separater Export-Button in
/// `FeedPropertiesView`, siehe Entscheidung 2026-07-08 in FEATURES.md).
enum StatisticsExportService {
    static func defaultExportFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "Feedivo-Statistiken-\(formatter.string(from: Date())).csv"
    }

    static func buildCSV(
        readingStatistics: ReadingStatisticsSnapshot,
        feedStatistics: [(feedTitle: String, statistics: FeedReadingStatisticsSnapshot)]
    ) -> String {
        var lines: [String] = []

        lines.append("Kennzahl,Wert")
        lines.append(csvRow(["Heute gelesen", "\(readingStatistics.articlesReadToday)"]))
        lines.append(csvRow(["Diese Woche gelesen", "\(readingStatistics.articlesReadThisWeek)"]))
        lines.append(csvRow(["Gesamt gelesen", "\(readingStatistics.articlesReadTotal)"]))
        lines.append(csvRow(["Ø Lesezeit pro Tag (Minuten)", formattedNumber(readingStatistics.averageReadingMinutesPerDay)]))
        lines.append("")

        lines.append("Meistgelesene Feeds,Anzahl")
        for feed in readingStatistics.topFeeds {
            lines.append(csvRow([feed.feedTitle, "\(feed.count)"]))
        }
        lines.append("")

        lines.append("Meistgenutzte Tags,Anzahl")
        for tag in readingStatistics.topTags {
            lines.append(csvRow([tag.name, "\(tag.count)"]))
        }
        lines.append("")

        lines.append("Feed,Artikel pro Woche (Ø),Lese-Prozentsatz,Ø Lesedauer (Minuten)")
        for entry in feedStatistics {
            lines.append(csvRow([
                entry.feedTitle,
                formattedNumber(entry.statistics.averageArticlesPerWeek),
                formattedNumber(entry.statistics.readPercentage),
                formattedNumber(entry.statistics.averageReadingMinutes)
            ]))
        }

        return lines.joined(separator: "\r\n")
    }

    private static func formattedNumber(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private static func csvRow(_ fields: [String]) -> String {
        fields.map(csvField).joined(separator: ",")
    }

    private static func csvField(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else {
            return value
        }

        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
