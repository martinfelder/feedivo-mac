import Foundation
import SwiftUI

enum SmartFilter: String, CaseIterable, Identifiable, Hashable {
    case allArticles
    case unread
    case starred
    case today

    var id: String {
        rawValue
    }

    var title: LocalizedStringKey {
        switch self {
        case .allArticles:
            return L10n.smartFilterAllArticles
        case .unread:
            return L10n.smartFilterUnread
        case .starred:
            return L10n.smartFilterStarred
        case .today:
            return L10n.smartFilterToday
        }
    }

    var systemImage: String {
        switch self {
        case .allArticles:
            return "tray.full"
        case .unread:
            return "circle.fill"
        case .starred:
            return "star.fill"
        case .today:
            return "calendar"
        }
    }

    func includes(
        _ article: Article,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        switch self {
        case .allArticles:
            return true
        case .unread:
            return !article.isRead
        case .starred:
            return article.isStarred
        case .today:
            guard let publishedAt = article.publishedAt else {
                return false
            }

            return calendar.isDate(publishedAt, inSameDayAs: now)
        }
    }
}
