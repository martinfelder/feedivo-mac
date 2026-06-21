import SwiftUI

enum RuleConditionField: String, CaseIterable, Identifiable {
    case title
    case summary
    case feedTitle

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .title:
            L10n.ruleConditionFieldTitle
        case .summary:
            L10n.ruleConditionFieldSummary
        case .feedTitle:
            L10n.ruleConditionFieldFeedTitle
        }
    }
}
