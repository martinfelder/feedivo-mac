import Foundation
import SwiftData

enum RuleConditionBackfillService {
    @MainActor
    static func backfillMissingConditions(context: ModelContext) throws {
        let rules = try context.fetch(FetchDescriptor<Rule>())

        for rule in rules where rule.conditions.isEmpty {
            let value = rule.conditionValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else {
                continue
            }

            let condition = RuleCondition(
                field: rule.conditionField,
                conditionOperator: rule.conditionOperator,
                value: value,
                sortOrder: 0
            )
            condition.rule = rule
            rule.conditions = [condition]
        }

        try context.save()
    }
}
