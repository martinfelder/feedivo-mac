import Foundation
import SwiftUI

enum SmartFolderFormatter {
    static func conditionSummary(for folder: SmartFolder) -> String {
        let conditions = sortedConditions(for: folder)
        guard !conditions.isEmpty else {
            return L10n.smartFolderSummaryAllArticles
        }

        let connector = RuleMatchMode.normalized(folder.matchModeRaw) == .all ? L10n.smartFolderSummaryAll : L10n.smartFolderSummaryAny
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

    static func showsReadArticlesByDefault(_ folder: SmartFolder) -> Bool {
        let conditions = sortedConditions(for: folder)

        if RuleMatchMode.normalized(folder.matchModeRaw) == .all,
           conditions.count == 1,
           let condition = conditions.first,
           condition.fieldRaw == SmartFolderConditionField.status.rawValue,
           condition.operatorRaw == SmartFolderConditionOperator.is.rawValue,
           let statusValue = SmartFolderStatusValue(rawValue: condition.value) {
            switch statusValue {
            case .starred, .hidden:
                return true
            case .unread, .read, .archived:
                return false
            }
        }

        if RuleMatchMode.normalized(folder.matchModeRaw) == .any,
           conditions.count == 2,
           conditions.allSatisfy({ condition in
               condition.fieldRaw == SmartFolderConditionField.status.rawValue
                   && condition.operatorRaw == SmartFolderConditionOperator.is.rawValue
           }) {
            let values = Set(conditions.map(\.value))
            return values == Set([
                SmartFolderStatusValue.starred.rawValue,
                SmartFolderStatusValue.archived.rawValue
            ])
        }

        return false
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
        (folder.conditions ?? []).sorted { firstCondition, secondCondition in
            firstCondition.sortOrder < secondCondition.sortOrder
        }
    }

    private static func conditionDescription(_ condition: SmartFolderCondition) -> String {
        let field = condition.fieldEnum?.title ?? condition.fieldRaw
        let conditionOperator = condition.operatorEnum?.title ?? condition.operatorRaw
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
