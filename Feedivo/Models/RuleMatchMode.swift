import SwiftUI

enum RuleMatchMode: String, CaseIterable, Identifiable {
    case all
    case any

    var id: String { rawValue }

    static func normalized(_ rawValue: String) -> RuleMatchMode {
        RuleMatchMode(rawValue: rawValue) ?? .all
    }
}
