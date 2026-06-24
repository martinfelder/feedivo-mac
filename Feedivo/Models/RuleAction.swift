import SwiftUI

enum RuleAction: String, CaseIterable, Identifiable {
    case assignTag
    case hideArticle

    var id: String {
        rawValue
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .assignTag:
            return L10n.ruleActionAssignTag
        case .hideArticle:
            return L10n.ruleActionHideArticle
        }
    }

    static func normalized(_ rawValue: String?) -> RuleAction {
        guard let rawValue,
              let action = RuleAction(rawValue: rawValue)
        else {
            return .assignTag
        }

        return action
    }
}
