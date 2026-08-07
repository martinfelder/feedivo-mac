import Foundation

enum ReaderMetadataFormatter {
    private static let wordsPerMinute = 200

    /// Persistierbare Lesezeit-Schätzung — nutzt dieselbe Wortzahl-Logik wie die
    /// Reader-Anzeige (`readingTimeText`), damit beide nie auseinanderlaufen. Wird
    /// sowohl beim Anlegen/Aktualisieren eines Artikels (`ArticleUpsertInput.
    /// estimatedReadingMinutes`) als auch beim Bestands-Backfill (Migration v30)
    /// verwendet.
    static func estimatedMinutes(content: String?, summary: String?) -> Int? {
        let text = preferredText(content: content, summary: summary)
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return nil
        }

        return minutes(for: trimmedText)
    }

    static func readingTimeText(content: String?, summary: String?) -> String? {
        let text = preferredText(content: content, summary: summary)
        guard !text.isEmpty else {
            return nil
        }

        return readingTimeText(for: text)
    }

    static func readingTimeText(for text: String) -> String {
        L10n.readerReadingTime(minutes: minutes(for: text))
    }

    private static func minutes(for text: String) -> Int {
        let words = wordCount(in: text)
        return max(1, Int(ceil(Double(words) / Double(wordsPerMinute))))
    }

    static func metadataParts(feedName: String?, readingTime: String?, author: String?, publishedAt: Date?) -> [String] {
        [
            feedName,
            readingTime,
            author,
            publishedAt?.feedivoDisplay(mode: currentDateDisplayMode)
        ]
        .compactMap { value in
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }

            return value
        }
    }

    private static func preferredText(content: String?, summary: String?) -> String {
        if let content, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return content
        }

        return summary ?? ""
    }

    /// Liest den Datum-Anzeigemodus direkt aus UserDefaults statt über
    /// `@AppStorage`, da dieser Formatter auch aus `ReaderPreparedArticle.init`
    /// (bewusst abseits des MainActor) und aus den Export-Renderern
    /// (kein View-Kontext) aufgerufen wird. Analog zu `Date+RelativeDisplay`s
    /// `appLocale`-Property.
    private static var currentDateDisplayMode: ArticleDateDisplayMode {
        let raw = UserDefaults.standard.string(forKey: ArticleDateDisplayMode.storageKey)
            ?? ArticleDateDisplayMode.defaultMode.rawValue
        return ArticleDateDisplayMode.resolved(from: raw)
    }

    private static func wordCount(in text: String) -> Int {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
    }
}
