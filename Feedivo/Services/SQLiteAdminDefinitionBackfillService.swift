import Foundation
import SwiftData

enum SQLiteAdminDefinitionBackfillService {
    struct BackfillResult: Equatable {
        var feedFolderCount: Int
        var ruleCount: Int
        var smartFolderCount: Int
    }

    @MainActor
    @discardableResult
    static func backfill(
        in context: ModelContext,
        database: FeedivoDatabase
    ) throws -> BackfillResult {
        let feedFolders = try context.fetch(FetchDescriptor<FeedFolder>())
        let rules = try context.fetch(FetchDescriptor<Rule>())
        let smartFolders = try context.fetch(FetchDescriptor<SmartFolder>())

        let feedFolderStore = FeedFolderStore(database: database)
        let ruleStore = SQLiteRuleStore(database: database)
        let smartFolderStore = SQLiteSmartFolderStore(database: database)
        let tagStore = TagStore(database: database)

        for folder in feedFolders {
            try feedFolderStore.save(
                FeedFolderRecord(
                    id: folder.id.uuidString,
                    name: folder.name,
                    createdAt: folder.createdAt,
                    updatedAt: folder.createdAt
                )
            )
        }

        for rule in rules {
            if let tag = rule.assignTag {
                try tagStore.save(
                    TagRecord(
                        id: tag.id.uuidString,
                        name: tag.name,
                        colorHex: tag.colorHex
                    )
                )
            }

            try ruleStore.save(
                RuleRecord(
                    id: rule.id.uuidString,
                    name: rule.name,
                    isEnabled: rule.isEnabled,
                    matchMode: rule.conditionMatchMode,
                    action: rule.actionRaw,
                    assignTagID: rule.assignTag?.id.uuidString,
                    notificationTemplate: rule.notificationTemplate,
                    notificationPriority: rule.notificationPriorityRaw,
                    sortOrder: rule.sortOrder
                ),
                conditions: sortedConditions(rule.conditions ?? []).map { condition in
                    RuleConditionRecord(
                        id: condition.id.uuidString,
                        ruleID: rule.id.uuidString,
                        field: condition.field,
                        conditionOperator: condition.conditionOperator,
                        value: condition.value,
                        sortOrder: condition.sortOrder
                    )
                }
            )
        }

        for folder in smartFolders {
            try smartFolderStore.save(
                SmartFolderRecord(
                    id: folder.id.uuidString,
                    name: folder.name,
                    matchMode: folder.matchModeRaw,
                    isShownInSidebar: folder.isShownInSidebar,
                    isDefault: folder.isDefault,
                    sortOrder: folder.sortOrder,
                    defaultKey: folder.defaultKey,
                    iconName: folder.iconName,
                    colorHex: folder.colorHex
                ),
                conditions: sortedConditions(folder.conditions ?? []).map { condition in
                    SmartFolderConditionRecord(
                        id: condition.id.uuidString,
                        smartFolderID: folder.id.uuidString,
                        field: condition.fieldRaw,
                        conditionOperator: condition.operatorRaw,
                        value: condition.value,
                        sortOrder: condition.sortOrder
                    )
                }
            )
        }

        return BackfillResult(
            feedFolderCount: feedFolders.count,
            ruleCount: rules.count,
            smartFolderCount: smartFolders.count
        )
    }

    private static func sortedConditions(_ conditions: [RuleCondition]) -> [RuleCondition] {
        conditions.sorted { firstCondition, secondCondition in
            if firstCondition.sortOrder == secondCondition.sortOrder {
                return firstCondition.id.uuidString < secondCondition.id.uuidString
            }

            return firstCondition.sortOrder < secondCondition.sortOrder
        }
    }

    private static func sortedConditions(_ conditions: [SmartFolderCondition]) -> [SmartFolderCondition] {
        conditions.sorted { firstCondition, secondCondition in
            if firstCondition.sortOrder == secondCondition.sortOrder {
                return firstCondition.id.uuidString < secondCondition.id.uuidString
            }

            return firstCondition.sortOrder < secondCondition.sortOrder
        }
    }
}
