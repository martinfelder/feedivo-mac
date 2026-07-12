import Foundation

struct RuleConditionDraft: Identifiable, Equatable {
    var id = UUID()
    var field: RuleConditionField
    var conditionOperator: RuleConditionOperator
    var value: String
}
