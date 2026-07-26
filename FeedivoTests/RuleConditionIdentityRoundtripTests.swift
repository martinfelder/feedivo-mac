import Foundation
import Testing
@testable import Feedivo

struct RuleConditionIdentityRoundtripTests {
    @Test func bedingungsIDBleibtUeberEinenSpeicherLadeSpeicherZyklusStabil() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = SQLiteRuleStore(database: database)

        let originalConditionID = UUID().uuidString
        let rule = RuleRecord(
            id: UUID().uuidString,
            name: "Test-Regel",
            isEnabled: true,
            matchMode: RuleMatchMode.all.rawValue,
            action: "assignTag",
            assignTagID: nil,
            notificationTemplate: "{Titel}",
            notificationPriority: RuleNotificationPriority.normal.rawValue,
            sortOrder: 0,
            createdAt: Date()
        )
        let condition = RuleConditionRecord(
            id: originalConditionID,
            ruleID: rule.id,
            field: RuleConditionField.title.rawValue,
            conditionOperator: RuleConditionOperator.contains.rawValue,
            value: "Alt",
            sortOrder: 0,
            groupIndex: 0,
            updatedAt: Date()
        )
        try store.save(rule, conditions: [condition])

        // Simuliert den Editor-Lade-/Bearbeitungs-/Speicher-Zyklus mit dem Fix aus Steps 3-7:
        // Drafts über conditionDrafts(for:) laden (übernimmt die ID), Wert bearbeiten, per
        // draft.id.uuidString zurückspeichern.
        let reloadedConditions = try store.conditions(ruleID: rule.id)
        let drafts = RuleSettingsFormatter.conditionDrafts(for: reloadedConditions)
        let editedDraft = RuleConditionDraft(
            id: drafts[0].id,
            field: drafts[0].field,
            conditionOperator: drafts[0].conditionOperator,
            value: "Neu",
            groupIndex: drafts[0].groupIndex
        )
        let updatedCondition = RuleConditionRecord(
            id: editedDraft.id.uuidString,
            ruleID: rule.id,
            field: editedDraft.field.rawValue,
            conditionOperator: editedDraft.conditionOperator.rawValue,
            value: editedDraft.value,
            sortOrder: 0,
            groupIndex: editedDraft.groupIndex,
            updatedAt: Date()
        )
        try store.save(rule, conditions: [updatedCondition])

        let finalConditions = try store.conditions(ruleID: rule.id)
        #expect(finalConditions.count == 1)
        #expect(finalConditions.first?.id == originalConditionID)
        #expect(finalConditions.first?.value == "Neu")
    }
}
