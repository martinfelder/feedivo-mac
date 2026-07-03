import Foundation

struct SQLiteSmartFolderSnapshot: Equatable, Sendable {
    var id: String
    var name: String
    var matchMode: RuleMatchMode
    var conditions: [SQLiteSmartFolderConditionSnapshot]

    init(
        id: String,
        name: String,
        matchMode: RuleMatchMode,
        conditions: [SQLiteSmartFolderConditionSnapshot]
    ) {
        self.id = id
        self.name = name
        self.matchMode = matchMode
        self.conditions = conditions
    }

    @MainActor
    init(folder: SmartFolder) {
        self.id = folder.id.uuidString
        self.name = folder.localizedDisplayName
        self.matchMode = RuleMatchMode.normalized(folder.matchModeRaw)
        self.conditions = (folder.conditions ?? [])
            .sorted { firstCondition, secondCondition in
                firstCondition.sortOrder < secondCondition.sortOrder
            }
            .compactMap(SQLiteSmartFolderConditionSnapshot.init(condition:))
    }
}

struct SQLiteSmartFolderConditionSnapshot: Equatable, Sendable {
    var field: SmartFolderConditionField
    var conditionOperator: SmartFolderConditionOperator
    var value: String

    init(
        field: SmartFolderConditionField,
        conditionOperator: SmartFolderConditionOperator,
        value: String
    ) {
        self.field = field
        self.conditionOperator = conditionOperator
        self.value = value
    }

    @MainActor
    init?(condition: SmartFolderCondition) {
        guard let field = condition.fieldEnum,
              let conditionOperator = condition.operatorEnum
        else {
            return nil
        }

        self.init(
            field: field,
            conditionOperator: conditionOperator,
            value: condition.value
        )
    }
}
