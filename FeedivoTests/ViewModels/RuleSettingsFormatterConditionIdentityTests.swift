import Foundation
import Testing
@testable import Feedivo

struct RuleSettingsFormatterConditionIdentityTests {
    @Test func conditionDraftsUebernimmtDieBestehendeIDStattEinerNeuen() {
        let existingID = UUID()
        let condition = RuleConditionRecord(
            id: existingID.uuidString,
            ruleID: "rule-1",
            field: RuleConditionField.title.rawValue,
            conditionOperator: RuleConditionOperator.contains.rawValue,
            value: "Test",
            sortOrder: 0,
            groupIndex: 0,
            updatedAt: Date()
        )

        let drafts = RuleSettingsFormatter.conditionDrafts(for: [condition])

        #expect(drafts.first?.id == existingID)
    }
}
