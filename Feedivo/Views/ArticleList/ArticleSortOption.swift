import Foundation

enum ArticleSortOption: String, CaseIterable, Identifiable {
    static let storageKey = "articleList.sortOption"

    case newestFirst
    case oldestFirst
    case feed
    case title
    case shortReadingTimeFirst

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .newestFirst:
            L10n.articleSortNewestFirst
        case .oldestFirst:
            L10n.articleSortOldestFirst
        case .feed:
            L10n.articleSortFeed
        case .title:
            L10n.articleSortTitle
        case .shortReadingTimeFirst:
            L10n.articleSortShortReadingTimeFirst
        }
    }

    static func resolved(from rawValue: String) -> ArticleSortOption {
        ArticleSortOption(rawValue: rawValue) ?? .newestFirst
    }

    func sorted(_ articles: [Article]) -> [Article] {
        // P3: Lesezeit einmal pro Artikel pre-computen (Dictionary über die id)
        // und im Komparator per Lookup verwenden, statt bei jedem der O(N·logN)
        // Vergleiche den Text neu in Wörter zu zerlegen. Nur für
        // .shortReadingTimeFirst relevant — für die anderen Sortierungen bleibt
        // die Map leer und kostet nichts.
        let readingMinutesByID: [UUID: Int] =
            self == .shortReadingTimeFirst
            ? Dictionary(articles.map { ($0.id, readingMinutes(for: $0)) }, uniquingKeysWith: { first, _ in first })
            : [:]

        // P9: Feed-Titel einmal pro vorhandenem Feed in eine Map ablegen und im
        // Komparator per feedID-Lookup verwenden, statt bei jedem Vergleich die
        // feed-Relationship (`first.feed?.title`) neu zu faulten. Nur für .feed
        // relevant — sonst bleibt die Map leer. Ein Titel wird gesetzt, sobald ein
        // Artikel mit intaktem Feed ihn liefert; das lässt den seltenen Fall
        // „feedID gesetzt, feed-Relationship kaputt (orphaned)" unverändert
        // (Titel nil), ohne einen späteren intakten Artikel zu blockieren.
        let feedTitleByFeedID: [UUID: String] = {
            guard self == .feed else { return [:] }
            var map: [UUID: String] = [:]
            for article in articles {
                guard let feedID = article.feedID, map[feedID] == nil else { continue }
                if let title = article.feed?.title {
                    map[feedID] = title
                }
            }
            return map
        }()

        return articles.sorted { first, second in
            switch self {
            case .newestFirst:
                newestFirst(first, second)
            case .oldestFirst:
                oldestFirst(first, second)
            case .feed:
                compareText(first.feedID.flatMap { feedTitleByFeedID[$0] }, second.feedID.flatMap { feedTitleByFeedID[$0] })
                    ?? newestFirst(first, second)
            case .title:
                compareText(first.title, second.title) ?? newestFirst(first, second)
            case .shortReadingTimeFirst:
                compareNumber(readingMinutesByID[first.id] ?? Int.max, readingMinutesByID[second.id] ?? Int.max)
                    ?? newestFirst(first, second)
            }
        }
    }

    private func newestFirst(_ first: Article, _ second: Article) -> Bool {
        compareOptionalDate(first.publishedAt, second.publishedAt, newestFirst: true)
            ?? compareText(first.title, second.title)
            ?? (first.id.uuidString < second.id.uuidString)
    }

    private func oldestFirst(_ first: Article, _ second: Article) -> Bool {
        compareOptionalDate(first.publishedAt, second.publishedAt, newestFirst: false)
            ?? compareText(first.title, second.title)
            ?? (first.id.uuidString < second.id.uuidString)
    }

    private func compareOptionalDate(_ first: Date?, _ second: Date?, newestFirst: Bool) -> Bool? {
        guard first != second else {
            return nil
        }

        guard let first else {
            return false
        }

        guard let second else {
            return true
        }

        return newestFirst ? first > second : first < second
    }

    private func compareText(_ first: String?, _ second: String?) -> Bool? {
        let normalizedFirst = normalizedText(first)
        let normalizedSecond = normalizedText(second)

        guard normalizedFirst != normalizedSecond else {
            return nil
        }

        guard let normalizedFirst else {
            return false
        }

        guard let normalizedSecond else {
            return true
        }

        return normalizedFirst.localizedStandardCompare(normalizedSecond) == .orderedAscending
    }

    private func compareNumber(_ first: Int, _ second: Int) -> Bool? {
        guard first != second else {
            return nil
        }

        return first < second
    }

    private func readingMinutes(for article: Article) -> Int {
        let text = normalizedText(article.content) ?? normalizedText(article.summary)
        guard let text else {
            return Int.max
        }

        let wordCount = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count

        return max(1, Int(ceil(Double(wordCount) / 200.0)))
    }

    private func normalizedText(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }
}
