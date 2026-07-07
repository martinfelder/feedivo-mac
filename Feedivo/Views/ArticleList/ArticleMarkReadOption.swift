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
            L10n.articleMarkAllReadCommand
        }
    }
}
