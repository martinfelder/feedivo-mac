import Foundation

enum ArticleFilterOption: String, CaseIterable, Identifiable {
    static let storageKey = "articleList.filterOption"

    case all
    case unread
    case starred
    case archived
    case today

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .all:
            L10n.articleFilterAll
        case .unread:
            L10n.articleFilterUnread
        case .starred:
            L10n.articleFilterStarred
        case .archived:
            L10n.articleFilterArchived
        case .today:
            L10n.articleFilterToday
        }
    }

    var systemImage: String {
        switch self {
        case .all:
            "tray.full"
        case .unread:
            "circle.fill"
        case .starred:
            "star.fill"
        case .archived:
            "archivebox"
        case .today:
            "calendar"
        }
    }

    static func resolved(from rawValue: String) -> ArticleFilterOption {
        ArticleFilterOption(rawValue: rawValue) ?? .all
    }
}
