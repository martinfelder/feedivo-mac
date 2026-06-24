import Foundation
import Observation
import SwiftData

struct RuleConditionDraft: Identifiable, Equatable {
    var id = UUID()
    var field: RuleConditionField
    var conditionOperator: RuleConditionOperator
    var value: String
}

@Observable
@MainActor
final class RuleViewModel {
    var errorMessage: String?

    func createRule(
        name: String,
        isEnabled: Bool,
        action: RuleAction = .assignTag,
        matchMode: RuleMatchMode,
        conditionDrafts: [RuleConditionDraft],
        assignTag: Tag?,
        context: ModelContext
    ) {
        guard let normalizedName = normalizedName(name),
              let conditions = normalizedConditions(from: conditionDrafts)
        else {
            errorMessage = L10n.ruleValidationError
            return
        }

        guard action != .assignTag || assignTag != nil else {
            errorMessage = L10n.ruleValidationError
            return
        }

        let firstCondition = conditions[0]
        let rule = Rule(
            name: normalizedName,
            conditionField: firstCondition.field,
            conditionOperator: firstCondition.conditionOperator,
            conditionValue: firstCondition.value
        )
        rule.isEnabled = isEnabled
        rule.actionRaw = action.rawValue
        rule.conditionMatchMode = matchMode.rawValue
        rule.assignTag = action == .assignTag ? assignTag : nil
        rule.conditions = conditions.enumerated().map { index, condition in
            RuleCondition(
                field: condition.field,
                conditionOperator: condition.conditionOperator,
                value: condition.value,
                sortOrder: index
            )
        }

        context.insert(rule)
        save(context)
    }

    func updateRule(
        _ rule: Rule,
        name: String,
        isEnabled: Bool,
        action: RuleAction = .assignTag,
        matchMode: RuleMatchMode,
        conditionDrafts: [RuleConditionDraft],
        assignTag: Tag?,
        context: ModelContext
    ) {
        guard let normalizedName = normalizedName(name),
              let conditions = normalizedConditions(from: conditionDrafts)
        else {
            errorMessage = L10n.ruleValidationError
            return
        }

        guard action != .assignTag || assignTag != nil else {
            errorMessage = L10n.ruleValidationError
            return
        }

        rule.name = normalizedName
        rule.isEnabled = isEnabled
        rule.actionRaw = action.rawValue
        rule.conditionMatchMode = matchMode.rawValue
        rule.assignTag = action == .assignTag ? assignTag : nil
        rule.conditionField = conditions[0].field
        rule.conditionOperator = conditions[0].conditionOperator
        rule.conditionValue = conditions[0].value
        rule.conditions.removeAll()
        rule.conditions = conditions.enumerated().map { index, condition in
            RuleCondition(
                field: condition.field,
                conditionOperator: condition.conditionOperator,
                value: condition.value,
                sortOrder: index
            )
        }

        save(context)
    }

    func deleteRule(_ rule: Rule, context: ModelContext) {
        context.delete(rule)
        save(context)
    }

    private func normalizedName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedConditions(from drafts: [RuleConditionDraft]) -> [(field: String, conditionOperator: String, value: String)]? {
        let conditions = drafts.compactMap { draft -> (field: String, conditionOperator: String, value: String)? in
            let value = draft.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else {
                return nil
            }

            return (draft.field.rawValue, draft.conditionOperator.rawValue, value)
        }

        return conditions.isEmpty ? nil : conditions
    }

    private func save(_ context: ModelContext) {
        do {
            try context.save()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
