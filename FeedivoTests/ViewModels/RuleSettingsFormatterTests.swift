import Foundation
import Testing
@testable import Feedivo

struct RuleSettingsFormatterTests {
    @Test func conditionSummaryBeiEinerGruppeZeigtKeineKlammern() {
        let conditions = [
            RuleConditionRecord(id: "c1", ruleID: "r1", field: "title", conditionOperator: "contains", value: "Swift", sortOrder: 0, groupIndex: 0),
            RuleConditionRecord(id: "c2", ruleID: "r1", field: "author", conditionOperator: "contains", value: "Apple", sortOrder: 1, groupIndex: 0)
        ]

        let summary = RuleSettingsFormatter.conditionSummary(conditions: conditions)

        #expect(!summary.contains("("))
        #expect(!summary.contains(")"))
        #expect(summary.contains(" UND "))
    }

    @Test func conditionSummaryBeiMehrerenMehrbedingungsGruppenSetztKlammernUndOderVerbindung() {
        let conditions = [
            RuleConditionRecord(id: "c1", ruleID: "r1", field: "title", conditionOperator: "contains", value: "Swift", sortOrder: 0, groupIndex: 0),
            RuleConditionRecord(id: "c2", ruleID: "r1", field: "author", conditionOperator: "contains", value: "Apple", sortOrder: 1, groupIndex: 0),
            RuleConditionRecord(id: "c3", ruleID: "r1", field: "summary", conditionOperator: "contains", value: "macOS", sortOrder: 2, groupIndex: 1),
            RuleConditionRecord(id: "c4", ruleID: "r1", field: "feedTitle", conditionOperator: "contains", value: "News", sortOrder: 3, groupIndex: 1)
        ]

        let summary = RuleSettingsFormatter.conditionSummary(conditions: conditions)

        #expect(summary.contains(") ODER ("))
        #expect(summary.hasPrefix("("))
        #expect(summary.hasSuffix(")"))
    }

    @Test func conditionSummaryBeiEinzelBedingungsGruppenLaesstDieseUnklammert() {
        let conditions = [
            RuleConditionRecord(id: "c1", ruleID: "r1", field: "title", conditionOperator: "contains", value: "Swift", sortOrder: 0, groupIndex: 0),
            RuleConditionRecord(id: "c2", ruleID: "r1", field: "summary", conditionOperator: "contains", value: "macOS", sortOrder: 1, groupIndex: 1)
        ]

        let summary = RuleSettingsFormatter.conditionSummary(conditions: conditions)

        // Beide Gruppen haben nur je eine Bedingung -- trotz mehrerer Gruppen
        // insgesamt bleiben Einzel-Bedingungs-Gruppen unklammert.
        #expect(!summary.contains("("))
        #expect(!summary.contains(")"))
        #expect(summary.contains(" ODER "))
    }

    @Test func conditionSummaryOhneBedingungenLiefertPlatzhalter() {
        let summary = RuleSettingsFormatter.conditionSummary(conditions: [])

        #expect(summary == L10n.ruleSummaryNoCondition)
    }

    @Test func conditionSummaryOrdnetGruppenNachKleinstemSortOrder() {
        // Gruppe 1 (c-erste) hat die kleinere sortOrder als Gruppe 0
        // (c-zweite) -- die Ausgabereihenfolge muss der sortOrder folgen,
        // nicht dem numerischen groupIndex-Wert.
        let conditions = [
            RuleConditionRecord(id: "c-erste", ruleID: "r1", field: "title", conditionOperator: "contains", value: "Erste", sortOrder: 0, groupIndex: 1),
            RuleConditionRecord(id: "c-zweite", ruleID: "r1", field: "title", conditionOperator: "contains", value: "Zweite", sortOrder: 1, groupIndex: 0)
        ]

        let summary = RuleSettingsFormatter.conditionSummary(conditions: conditions)
        let erstePosition = try? #require(summary.range(of: "Erste"))
        let zweitePosition = try? #require(summary.range(of: "Zweite"))

        #expect(erstePosition != nil)
        #expect(zweitePosition != nil)
        if let erstePosition, let zweitePosition {
            #expect(erstePosition.lowerBound < zweitePosition.lowerBound)
        }
    }

    @Test func conditionDraftsForPropagiertGroupIndex() {
        let conditions = [
            RuleConditionRecord(id: "c1", ruleID: "r1", field: "title", conditionOperator: "contains", value: "Swift", sortOrder: 0, groupIndex: 2)
        ]

        let drafts = RuleSettingsFormatter.conditionDrafts(for: conditions)

        #expect(drafts.first?.groupIndex == 2)
    }
}
