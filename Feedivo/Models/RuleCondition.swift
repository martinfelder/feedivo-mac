import Foundation
import SwiftData

@Model
class RuleCondition {
    var id: UUID
    var field: String
    var conditionOperator: String
    var value: String
    var sortOrder: Int

    @Relationship
    var rule: Rule?

    init(
        field: String,
        conditionOperator: String,
        value: String,
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.field = field
        self.conditionOperator = conditionOperator
        self.value = value
        self.sortOrder = sortOrder
    }
}
