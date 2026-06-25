import SwiftUI

enum RuleNotificationPriority: String, CaseIterable, Identifiable, Sendable {
    case normal
    case critical

    var id: String {
        rawValue
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .normal:
            L10n.ruleNotificationPriorityNormal
        case .critical:
            L10n.ruleNotificationPriorityCritical
        }
    }

    static func normalized(_ rawValue: String?) -> RuleNotificationPriority {
        guard let rawValue,
              let priority = RuleNotificationPriority(rawValue: rawValue)
        else {
            return .normal
        }

        return priority
    }
}
