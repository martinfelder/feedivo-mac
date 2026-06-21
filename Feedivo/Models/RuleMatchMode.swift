import SwiftUI

enum RuleMatchMode: String, CaseIterable, Identifiable {
    case all
    case any

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .all:
            L10n.ruleMatchModeAll
        case .any:
            L10n.ruleMatchModeAny
        }
    }

    static func normalized(_ rawValue: String) -> RuleMatchMode {
        RuleMatchMode(rawValue: rawValue) ?? .all
    }
}
