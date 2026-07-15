import Foundation

enum ArticleSortOption: String, CaseIterable, Identifiable, Sendable {
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
}
