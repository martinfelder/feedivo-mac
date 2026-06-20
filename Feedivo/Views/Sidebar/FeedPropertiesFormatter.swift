import Foundation

enum FeedPropertiesFormatter {
    static func copyableXMLAddress(_ urlString: String) -> String? {
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedURL.isEmpty ? nil : trimmedURL
    }

    static func nextRefreshDate(lastRefreshed: Date?, intervalMinutes: Int) -> Date? {
        guard let lastRefreshed else {
            return nil
        }

        return lastRefreshed.addingTimeInterval(TimeInterval(intervalMinutes * 60))
    }

    static func latestArticle(in articles: [Article]) -> Article? {
        articles.sorted {
            ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast)
        }
        .first
    }

    static func latestLogEntries(_ entries: [FeedLogEntry], limit: Int = 20) -> [FeedLogEntry] {
        Array(
            entries
                .sorted { $0.createdAt > $1.createdAt }
                .prefix(limit)
        )
    }

    static func latestLogEntryCount(_ entries: [FeedLogEntry], limit: Int = 20) -> Int {
        latestLogEntries(entries, limit: limit).count
    }
}
