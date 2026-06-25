import Foundation
import SwiftData

// Rule definiert eine Bedingung, die automatisch eine Aktion auf Artikel anwendet
@Model
class Rule {
    var id: UUID
    var name: String
    var isEnabled: Bool
    var conditionField: String      // "title", "summary", "feedTitle"
    var conditionOperator: String   // "contains", "startsWith", "endsWith"
    var conditionValue: String      // z.B. "Apple", "WWDC"
    var conditionMatchMode: String  // "all" oder "any"
    var actionRaw: String = RuleAction.assignTag.rawValue
    var sortOrder: Int

    @Relationship
    var assignTag: Tag?

    @Relationship(deleteRule: .cascade, inverse: \RuleCondition.rule)
    var conditions: [RuleCondition]

    init(name: String, conditionField: String,
         conditionOperator: String, conditionValue: String) {
        self.id = UUID()
        self.name = name
        self.isEnabled = true
        self.conditionField = conditionField
        self.conditionOperator = conditionOperator
        self.conditionValue = conditionValue
        self.conditionMatchMode = RuleMatchMode.all.rawValue
        self.actionRaw = RuleAction.assignTag.rawValue
        self.sortOrder = 0
        self.conditions = []
    }
}
