import Foundation

enum ArticleMarkReadOption: CaseIterable, Identifiable {
    case olderThanOneDay
    case olderThanTwoDays
    case olderThanThreeDays
    case olderThanFourDays
    case olderThanOneWeek
    case olderThanTwoWeeks
    case allVisible

    var id: String {
        switch self {
        case .olderThanOneDay:
            "olderThanOneDay"
        case .olderThanTwoDays:
            "olderThanTwoDays"
        case .olderThanThreeDays:
            "olderThanThreeDays"
        case .olderThanFourDays:
            "olderThanFourDays"
        case .olderThanOneWeek:
            "olderThanOneWeek"
        case .olderThanTwoWeeks:
            "olderThanTwoWeeks"
        case .allVisible:
            "allVisible"
        }
    }

    var label: String {
        switch self {
        case .olderThanOneDay:
            L10n.articleMarkReadOlderThanOneDay
        case .olderThanTwoDays:
            L10n.articleMarkReadOlderThanTwoDays
        case .olderThanThreeDays:
            L10n.articleMarkReadOlderThanThreeDays
        case .olderThanFourDays:
            L10n.articleMarkReadOlderThanFourDays
        case .olderThanOneWeek:
            L10n.articleMarkReadOlderThanOneWeek
        case .olderThanTwoWeeks:
            L10n.articleMarkReadOlderThanTwoWeeks
        case .allVisible:
            L10n.articleMarkReadAllVisible
        }
    }

    func matchingArticles(
        in articles: [Article],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Article] {
        articles.filter { article in
            guard !article.isRead else {
                return false
            }

            return includes(article, now: now, calendar: calendar)
        }
    }

    func includes(
        _ article: Article,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        switch self {
        case .allVisible:
            return true
        case .olderThanOneDay:
            return isArticle(article, olderThan: .day, value: 1, now: now, calendar: calendar)
        case .olderThanTwoDays:
            return isArticle(article, olderThan: .day, value: 2, now: now, calendar: calendar)
        case .olderThanThreeDays:
            return isArticle(article, olderThan: .day, value: 3, now: now, calendar: calendar)
        case .olderThanFourDays:
            return isArticle(article, olderThan: .day, value: 4, now: now, calendar: calendar)
        case .olderThanOneWeek:
            return isArticle(article, olderThan: .weekOfYear, value: 1, now: now, calendar: calendar)
        case .olderThanTwoWeeks:
            return isArticle(article, olderThan: .weekOfYear, value: 2, now: now, calendar: calendar)
        }
    }

    private func isArticle(
        _ article: Article,
        olderThan component: Calendar.Component,
        value: Int,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        guard
            let publishedAt = article.publishedAt,
            let cutoffDate = calendar.date(byAdding: component, value: -value, to: now)
        else {
            return false
        }

        return publishedAt < cutoffDate
    }
}
