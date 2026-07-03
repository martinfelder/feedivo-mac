import Foundation
import SwiftUI

enum SmartFilterIconColor: Hashable {
    case blue
    case teal
    case yellow
    case green
    case gray

    var color: Color {
        switch self {
        case .blue:
            return .blue
        case .teal:
            return .teal
        case .yellow:
            return .yellow
        case .green:
            return .green
        case .gray:
            return .gray
        }
    }
}

enum SmartFilter: String, CaseIterable, Identifiable, Hashable, Sendable {
    case allArticles
    case unread
    case starred
    case today
    case hidden

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
        case .hidden:
            return L10n.smartFilterHidden
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
        case .hidden:
            return "eye.slash"
        }
    }

    var iconColor: SmartFilterIconColor {
        switch self {
        case .allArticles:
            return .blue
        case .unread:
            return .teal
        case .starred:
            return .yellow
        case .today:
            return .green
        case .hidden:
            return .gray
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
        case .hidden:
            return article.isHidden
        }
    }
}
