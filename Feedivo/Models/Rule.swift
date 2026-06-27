import Foundation
import SwiftData

// Rule definiert eine Bedingung, die automatisch eine Aktion auf Artikel anwendet.
//
// Bedingungen leben ausschließlich in `conditions: [RuleCondition]` (eine Quelle
// der Wahrheit). Früher gab es zusätzlich flache `conditionField/Operator/Value`-
// Spalten auf Rule, die `conditions[0]` spiegeln sollten — doppelt gepflegt und
// inkonsistent. Diese Legacy-Spalten wurden entfernt; `RuleConditionBackfillService`
// hatte sie beim Start in `conditions` überführt und ist damit entfallen.
//
// `conditionMatchMode` ist KEIN Legacy-Duplikat: es legt fest, wie die Conditions
// UND/ODER verknüpft werden — eine Eigenschaft der Regel, nicht einer Condition.
@Model
class Rule {
    var id: UUID = UUID()
    var name: String = ""
    var isEnabled: Bool = true
    var conditionMatchMode: String = RuleMatchMode.all.rawValue  // "all" oder "any"
    var actionRaw: String = RuleAction.assignTag.rawValue
    var notificationTemplate: String = "{Titel}"
    var notificationPriorityRaw: String = RuleNotificationPriority.normal.rawValue
    var sortOrder: Int = 0

    @Relationship
    var assignTag: Tag?

    @Relationship(deleteRule: .nullify, inverse: \RuleCondition.rule)
    var conditions: [RuleCondition] = []

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.isEnabled = true
        self.conditionMatchMode = RuleMatchMode.all.rawValue
        self.actionRaw = RuleAction.assignTag.rawValue
        self.notificationTemplate = "{Titel}"
        self.notificationPriorityRaw = RuleNotificationPriority.normal.rawValue
        self.sortOrder = 0
        self.conditions = []
    }
}