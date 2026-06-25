import Foundation
import SwiftUI

enum SmartFolderFormatter {
    static func conditionSummary(for folder: SmartFolder) -> String {
        let conditions = sortedConditions(for: folder)
        guard !conditions.isEmpty else {
            return "Alle Artikel"
        }

        let connector = RuleMatchMode.normalized(folder.matchModeRaw) == .all ? "UND" : "ODER"
        return conditions
            .map { condition in
                conditionDescription(condition)
            }
            .joined(separator: " \(connector) ")
    }

    static func includesHiddenStatus(_ folder: SmartFolder) -> Bool {
        sortedConditions(for: folder).contains { condition in
            condition.fieldRaw == SmartFolderConditionField.status.rawValue
                && condition.value == SmartFolderStatusValue.hidden.rawValue
                && condition.operatorRaw == SmartFolderConditionOperator.is.rawValue
        }
    }

    static func systemImage(for folder: SmartFolder) -> String {
        SmartFolderAppearance.normalizedIconName(folder.iconName)
    }

    static func color(for folder: SmartFolder) -> Color {
        SmartFolderAppearance.color(for: folder.colorHex)
    }

    static func drafts(for folder: SmartFolder) -> [SmartFolderConditionDraft] {
        sortedConditions(for: folder).compactMap { condition in
            guard let field = SmartFolderConditionField(rawValue: condition.fieldRaw),
                  let conditionOperator = SmartFolderConditionOperator(rawValue: condition.operatorRaw)
            else {
                return nil
            }

            return SmartFolderConditionDraft(
                field: field,
                conditionOperator: conditionOperator,
                value: condition.value
            )
        }
    }

    private static func sortedConditions(for folder: SmartFolder) -> [SmartFolderCondition] {
        folder.conditions.sorted { firstCondition, secondCondition in
            firstCondition.sortOrder < secondCondition.sortOrder
        }
    }

    private static func conditionDescription(_ condition: SmartFolderCondition) -> String {
        let field = SmartFolderConditionField(rawValue: condition.fieldRaw)?.title ?? condition.fieldRaw
        let conditionOperator = SmartFolderConditionOperator(rawValue: condition.operatorRaw)?.title ?? condition.operatorRaw
        let value = displayedValue(fieldRaw: condition.fieldRaw, value: condition.value)
        return "\(field) \(conditionOperator) \"\(value)\""
    }

    private static func displayedValue(fieldRaw: String, value: String) -> String {
        if fieldRaw == SmartFolderConditionField.status.rawValue,
           let status = SmartFolderStatusValue(rawValue: value) {
            return status.title
        }

        if fieldRaw == SmartFolderConditionField.date.rawValue,
           let dateValue = SmartFolderDateValue(rawValue: value) {
            return dateValue.title
        }

        return value
    }
}
