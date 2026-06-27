import Foundation
import Observation
import SwiftData

struct RuleConditionDraft: Identifiable, Equatable {
    var id = UUID()
    var field: RuleConditionField
    var conditionOperator: RuleConditionOperator
    var value: String
}

enum RuleMoveDirection {
    case up
    case down
}

@Observable
@MainActor
final class RuleViewModel {
    var errorMessage: String?

    static func sortedRules(_ rules: [Rule]) -> [Rule] {
        rules.sorted { firstRule, secondRule in
            if firstRule.sortOrder == secondRule.sortOrder {
                return firstRule.name.localizedCaseInsensitiveCompare(secondRule.name) == .orderedAscending
            }

            return firstRule.sortOrder < secondRule.sortOrder
        }
    }

    func createRule(
        name: String,
        isEnabled: Bool,
        action: RuleAction = .assignTag,
        matchMode: RuleMatchMode,
        conditionDrafts: [RuleConditionDraft],
        assignTag: Tag?,
        notificationTemplate: String = "{Titel}",
        notificationPriority: RuleNotificationPriority = .normal,
        existingRules: [Rule] = [],
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

        let rule = Rule(name: normalizedName)
        rule.isEnabled = isEnabled
        rule.actionRaw = action.rawValue
        rule.notificationTemplate = normalizedNotificationTemplate(notificationTemplate)
        rule.notificationPriorityRaw = notificationPriority.rawValue
        rule.conditionMatchMode = matchMode.rawValue
        rule.assignTag = action == .assignTag ? assignTag : nil
        rule.sortOrder = nextSortOrder(after: existingRules)
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

    func duplicateRule(_ rule: Rule, existingRules: [Rule], context: ModelContext) {
        let conditions = sortedConditions(for: rule)
        guard !conditions.isEmpty else {
            errorMessage = L10n.ruleValidationError
            return
        }

        let duplicate = Rule(name: "\(rule.name) Kopie")
        duplicate.isEnabled = false
        duplicate.actionRaw = rule.actionRaw
        duplicate.notificationTemplate = rule.notificationTemplate
        duplicate.notificationPriorityRaw = rule.notificationPriorityRaw
        duplicate.conditionMatchMode = rule.conditionMatchMode
        duplicate.assignTag = RuleAction.normalized(rule.actionRaw) == .assignTag ? rule.assignTag : nil
        duplicate.conditions = conditions.enumerated().map { index, condition in
            RuleCondition(
                field: condition.field,
                conditionOperator: condition.conditionOperator,
                value: condition.value,
                sortOrder: index
            )
        }

        context.insert(duplicate)

        let orderedRules = Self.sortedRules(existingRules)
        let originalIndex = orderedRules.firstIndex { $0.id == rule.id } ?? orderedRules.endIndex
        var reorderedRules = orderedRules
        reorderedRules.insert(duplicate, at: min(originalIndex + 1, reorderedRules.count))
        normalizeSortOrder(in: reorderedRules)
        save(context)
    }

    func moveRule(
        _ rule: Rule,
        direction: RuleMoveDirection,
        existingRules: [Rule],
        context: ModelContext?
    ) {
        var orderedRules = Self.sortedRules(existingRules)
        guard let currentIndex = orderedRules.firstIndex(where: { $0.id == rule.id }) else {
            return
        }

        let destinationIndex: Int
        switch direction {
        case .up:
            destinationIndex = max(0, currentIndex - 1)
        case .down:
            destinationIndex = min(orderedRules.count - 1, currentIndex + 1)
        }

        guard currentIndex != destinationIndex else {
            return
        }

        orderedRules.swapAt(currentIndex, destinationIndex)
        normalizeSortOrder(in: orderedRules)

        if let context {
            save(context)
        } else {
            errorMessage = nil
        }
    }

    func updateRule(
        _ rule: Rule,
        name: String,
        isEnabled: Bool,
        action: RuleAction = .assignTag,
        matchMode: RuleMatchMode,
        conditionDrafts: [RuleConditionDraft],
        assignTag: Tag?,
        notificationTemplate: String = "{Titel}",
        notificationPriority: RuleNotificationPriority = .normal,
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
        rule.notificationTemplate = normalizedNotificationTemplate(notificationTemplate)
        rule.notificationPriorityRaw = notificationPriority.rawValue
        rule.conditionMatchMode = matchMode.rawValue
        rule.assignTag = action == .assignTag ? assignTag : nil
        // .nullify statt .cascade (CloudKit-kompatibel): removeAll würde die
        // alten Conditions nur verwaisten lassen — deshalb manuell löschen,
        // analog deleteRule.
        for condition in Array(rule.conditions) {
            context.delete(condition)
        }
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
        // .nullify statt .cascade (CloudKit-kompatibel): SwiftData würde die
        // Conditions nur verwaisten lassen — deshalb hier manuell löschen.
        for condition in Array(rule.conditions) {
            context.delete(condition)
        }
        context.delete(rule)
        save(context)
    }

    private func nextSortOrder(after rules: [Rule]) -> Int {
        (rules.map(\.sortOrder).max() ?? -1) + 1
    }

    private func normalizeSortOrder(in rules: [Rule]) {
        for (index, rule) in rules.enumerated() {
            rule.sortOrder = index
        }
    }

    private func sortedConditions(for rule: Rule) -> [RuleCondition] {
        rule.conditions.sorted { $0.sortOrder < $1.sortOrder }
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

    private func normalizedNotificationTemplate(_ template: String) -> String {
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "{Titel}" : trimmed
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
