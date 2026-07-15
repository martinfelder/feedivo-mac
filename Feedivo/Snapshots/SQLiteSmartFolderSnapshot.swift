import Foundation

struct SQLiteSmartFolderSnapshot: Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var matchMode: RuleMatchMode
    var conditions: [SQLiteSmartFolderConditionSnapshot]
    var iconName: String?
    var colorHex: String?
    var defaultKey: String?
    var defaultShowsReadArticles: Bool

    init(
        id: String,
        name: String,
        matchMode: RuleMatchMode,
        conditions: [SQLiteSmartFolderConditionSnapshot],
        iconName: String? = nil,
        colorHex: String? = nil,
        defaultKey: String? = nil,
        defaultShowsReadArticles: Bool = false
    ) {
        self.id = id
        self.name = name
        self.matchMode = matchMode
        self.conditions = conditions
        self.iconName = iconName
        self.colorHex = colorHex
        self.defaultKey = defaultKey
        self.defaultShowsReadArticles = defaultShowsReadArticles
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        matchMode: RuleMatchMode,
        conditionDrafts: [SmartFolderConditionDraft],
        defaultShowsReadArticles: Bool = false
    ) {
        self.id = id
        self.name = name
        self.matchMode = matchMode
        self.iconName = nil
        self.colorHex = nil
        self.defaultKey = nil
        self.defaultShowsReadArticles = defaultShowsReadArticles
        self.conditions = conditionDrafts.map { draft in
            SQLiteSmartFolderConditionSnapshot(
                field: draft.field,
                conditionOperator: draft.conditionOperator,
                value: draft.value
            )
        }
    }

    init(folder: SmartFolderRecord, conditions: [SmartFolderConditionRecord]) {
        self.id = folder.id
        self.name = SmartFolderFormatter.displayName(for: folder)
        self.matchMode = RuleMatchMode.normalized(folder.matchMode)
        self.iconName = folder.iconName
        self.colorHex = folder.colorHex
        self.defaultKey = folder.defaultKey
        self.defaultShowsReadArticles = folder.defaultShowsReadArticles
        self.conditions = conditions.compactMap(SQLiteSmartFolderConditionSnapshot.init(condition:))
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

    init?(condition: SmartFolderConditionRecord) {
        guard let field = SmartFolderConditionField(rawValue: condition.field),
              let conditionOperator = SmartFolderConditionOperator(rawValue: condition.conditionOperator)
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

extension SQLiteSmartFolderSnapshot {
    var includesHiddenArticles: Bool {
        conditions.contains { condition in
            condition.field == .status
                && condition.conditionOperator != .isNot
                && condition.value == SmartFolderStatusValue.hidden.rawValue
        }
    }
}
