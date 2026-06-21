import SwiftUI

enum RuleConditionOperator: String, CaseIterable, Identifiable {
    case contains
    case startsWith
    case endsWith

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .contains:
            L10n.ruleConditionOperatorContains
        case .startsWith:
            L10n.ruleConditionOperatorStartsWith
        case .endsWith:
            L10n.ruleConditionOperatorEndsWith
        }
    }
}
