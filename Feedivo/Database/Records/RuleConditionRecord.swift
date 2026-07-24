import Foundation
import GRDB

struct RuleConditionRecord: Codable, FetchableRecord, MutablePersistableRecord, Equatable, Sendable {
    static let databaseTableName = "rule_conditions"

    var id: String
    var ruleID: String
    var field: String
    var conditionOperator: String
    var value: String
    var sortOrder: Int
    var groupIndex: Int

    init(
        id: String = UUID().uuidString,
        ruleID: String,
        field: String,
        conditionOperator: String,
        value: String,
        sortOrder: Int = 0,
        groupIndex: Int = 0
    ) {
        self.id = id
        self.ruleID = ruleID
        self.field = field
        self.conditionOperator = conditionOperator
        self.value = value
        self.sortOrder = sortOrder
        self.groupIndex = groupIndex
    }
}
