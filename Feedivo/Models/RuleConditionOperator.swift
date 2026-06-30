import Foundation
import SwiftUI

enum RuleConditionOperator: String, CaseIterable, Identifiable {
    case contains
    case startsWith
    case endsWith
    case regex

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .contains:
            L10n.ruleConditionOperatorContains
        case .startsWith:
            L10n.ruleConditionOperatorStartsWith
        case .endsWith:
            L10n.ruleConditionOperatorEndsWith
        case .regex:
            L10n.ruleConditionOperatorRegex
        }
    }

    static func isValidRegexPattern(_ pattern: String) -> Bool {
        (try? NSRegularExpression(pattern: pattern)) != nil
    }
}
