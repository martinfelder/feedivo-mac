import Foundation
import Observation

// Legacy-Fallback: Diese ViewModel-Implementierung wird nur noch im
// Migrations- oder Übergangsmodus genutzt.
// Der produktive Regelfluss nutzt ausschließlich RuleRecord/RuleConditionRecord
// über SQLiteRuleStore.
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

    static func sortedRules(_ rules: [RuleRecord]) -> [RuleRecord] {
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
        assignTag: TagRecord?,
        notificationTemplate: String = "{Titel}",
        notificationPriority: RuleNotificationPriority = .normal,
        existingRules: [RuleRecord] = [],
        database: FeedivoDatabase
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

        let record = RuleRecord(
            id: UUID().uuidString,
            name: normalizedName,
            isEnabled: isEnabled,
            matchMode: matchMode.rawValue,
            action: action.rawValue,
            assignTagID: action == .assignTag ? assignTag?.id : nil,
            notificationTemplate: normalizedNotificationTemplate(notificationTemplate),
            notificationPriority: notificationPriority.rawValue,
            sortOrder: nextSortOrder(after: existingRules)
        )
        let conditionRecords = conditions.enumerated().map { index, condition in
            RuleConditionRecord(
                id: UUID().uuidString,
                ruleID: record.id,
                field: condition.field,
                conditionOperator: condition.conditionOperator,
                value: condition.value,
                sortOrder: index
            )
        }

        persist(record, conditions: conditionRecords, in: database)
    }

    func duplicateRule(
        _ rule: RuleRecord,
        existingRules _: [RuleRecord],
        database: FeedivoDatabase
    ) {
        guard !sortedConditions(for: rule, database: database).isEmpty else {
            errorMessage = L10n.ruleValidationError
            return
        }

        do {
            _ = try SQLiteRuleStore(database: database).duplicate(
                id: rule.id,
                copyName: "\(rule.name) Kopie"
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func moveRule(_ rule: RuleRecord, direction: RuleMoveDirection, existingRules: [RuleRecord], database: FeedivoDatabase) {
        let orderedRules = Self.sortedRules(existingRules)
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

        guard currentIndex != destinationIndex,
              orderedRules.indices.contains(destinationIndex)
        else {
            return
        }

        let destinationRule = orderedRules[destinationIndex]
        do {
            try SQLiteRuleStore(database: database).move(id: rule.id, toPositionOf: destinationRule.id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func moveRule(
        _ rule: RuleRecord,
        toPositionOf targetRule: RuleRecord,
        existingRules: [RuleRecord],
        database: FeedivoDatabase
    ) {
        let orderedRules = Self.sortedRules(existingRules)
        guard orderedRules.contains(where: { $0.id == rule.id }),
              orderedRules.contains(where: { $0.id == targetRule.id })
        else {
            return
        }

        do {
            try SQLiteRuleStore(database: database).move(id: rule.id, toPositionOf: targetRule.id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateRule(
        _ rule: RuleRecord,
        name: String,
        isEnabled: Bool,
        action: RuleAction = .assignTag,
        matchMode: RuleMatchMode,
        conditionDrafts: [RuleConditionDraft],
        assignTag: TagRecord?,
        notificationTemplate: String = "{Titel}",
        notificationPriority: RuleNotificationPriority = .normal,
        database: FeedivoDatabase
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

        var updatedRule = rule
        updatedRule.name = normalizedName
        updatedRule.isEnabled = isEnabled
        updatedRule.matchMode = matchMode.rawValue
        updatedRule.action = action.rawValue
        updatedRule.assignTagID = action == .assignTag ? assignTag?.id : nil
        updatedRule.notificationTemplate = normalizedNotificationTemplate(notificationTemplate)
        updatedRule.notificationPriority = notificationPriority.rawValue

        let conditionRecords = conditions.enumerated().map { index, condition in
            RuleConditionRecord(
                id: UUID().uuidString,
                ruleID: rule.id,
                field: condition.field,
                conditionOperator: condition.conditionOperator,
                value: condition.value,
                sortOrder: index
            )
        }

        persist(updatedRule, conditions: conditionRecords, in: database)
    }

    func deleteRule(_ rule: RuleRecord, database: FeedivoDatabase) {
        do {
            try SQLiteRuleStore(database: database).delete(id: rule.id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func persist(_ rule: RuleRecord, conditions: [RuleConditionRecord], in database: FeedivoDatabase) {
        do {
            try SQLiteRuleStore(database: database).save(rule, conditions: conditions)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sortedConditions(for rule: RuleRecord, database: FeedivoDatabase) -> [RuleConditionRecord] {
        (try? ruleStore(in: database).conditions(ruleID: rule.id)) ?? []
    }

    private func ruleStore(in database: FeedivoDatabase) -> SQLiteRuleStore {
        SQLiteRuleStore(database: database)
    }

    private func nextSortOrder(after rules: [RuleRecord]) -> Int {
        (rules.map(\.sortOrder).max() ?? -1) + 1
    }

    private func normalizedName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedConditions(from drafts: [RuleConditionDraft]) -> [(field: String, conditionOperator: String, value: String)]? {
        var conditions: [(field: String, conditionOperator: String, value: String)] = []

        for draft in drafts {
            let value = draft.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else {
                continue
            }

            if draft.conditionOperator == .regex, !RuleConditionOperator.isValidRegexPattern(value) {
                return nil
            }

            conditions.append((draft.field.rawValue, draft.conditionOperator.rawValue, value))
        }

        return conditions.isEmpty ? nil : conditions
    }

    private func normalizedNotificationTemplate(_ template: String) -> String {
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "{Titel}" : trimmed
    }
}
