import Foundation
import SwiftUI

enum SmartFolderFormatter {
    static func displayName(for folder: SmartFolderRecord) -> String {
        guard let defaultKey = folder.defaultKey else {
            return folder.name
        }

        switch defaultKey {
        case "all": return String(localized: "smartFolder.default.all")
        case "unread": return String(localized: "smartFolder.default.unread")
        case "starred": return String(localized: "smartFolder.default.starred")
        case "today": return String(localized: "smartFolder.default.today")
        case "hidden": return String(localized: "smartFolder.default.hidden")
        case "archived": return String(localized: "smartFolder.default.archived")
        case "thisWeek": return String(localized: "smartFolder.default.thisWeek")
        case "saved": return String(localized: "smartFolder.default.saved")
        default: return folder.name
        }
    }

    static func conditionSummary(
        for folder: SmartFolderRecord,
        conditions: [SmartFolderConditionRecord]
    ) -> String {
        let conditions = sortedConditions(conditions)
        guard !conditions.isEmpty else {
            return L10n.smartFolderSummaryAllArticles
        }

        let connector = RuleMatchMode.normalized(folder.matchMode) == .all ? L10n.smartFolderSummaryAll : L10n.smartFolderSummaryAny
        return conditions
            .map { condition in
                conditionDescription(condition)
            }
            .joined(separator: " \(connector) ")
    }

    static func drafts(for conditions: [SmartFolderConditionRecord]) -> [SmartFolderConditionDraft] {
        sortedConditions(conditions).compactMap { condition in
            guard let field = SmartFolderConditionField(rawValue: condition.field),
                  let conditionOperator = SmartFolderConditionOperator(rawValue: condition.conditionOperator)
            else {
                return nil
            }

            return SmartFolderConditionDraft(
                id: UUID(uuidString: condition.id) ?? UUID(),
                field: field,
                conditionOperator: conditionOperator,
                value: condition.value
            )
        }
    }

    static func systemImage(for folder: SmartFolderRecord) -> String {
        SmartFolderAppearance.normalizedIconName(folder.iconName ?? SmartFolderAppearance.defaultIconName)
    }

    static func color(for folder: SmartFolderRecord) -> Color {
        SmartFolderAppearance.color(for: folder.colorHex ?? SmartFolderAppearance.defaultColorHex)
    }

    private static func sortedConditions(_ conditions: [SmartFolderConditionRecord]) -> [SmartFolderConditionRecord] {
        conditions.sorted { firstCondition, secondCondition in
            firstCondition.sortOrder < secondCondition.sortOrder
        }
    }

    private static func conditionDescription(_ condition: SmartFolderConditionRecord) -> String {
        let field = SmartFolderConditionField(rawValue: condition.field)?.title ?? condition.field
        let conditionOperator = SmartFolderConditionOperator(rawValue: condition.conditionOperator)?.title ?? condition.conditionOperator
        let value = displayedValue(fieldRaw: condition.field, value: condition.value)
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
