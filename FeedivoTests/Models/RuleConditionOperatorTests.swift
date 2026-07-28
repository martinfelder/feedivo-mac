import Foundation
import Testing
@testable import Feedivo

struct RuleConditionOperatorTests {
    @Test func firstInvalidRegexValueIstNilWennAlleMusterGueltigSind() {
        let drafts = [
            RuleConditionDraft(field: .title, conditionOperator: .contains, value: "Swift"),
            RuleConditionDraft(field: .summary, conditionOperator: .regex, value: "^Foo.*Bar$")
        ]

        #expect(RuleConditionOperator.firstInvalidRegexValue(in: drafts) == nil)
    }

    @Test func firstInvalidRegexValueIstNilWennKeineRegexBedingungExistiert() {
        let drafts = [
            RuleConditionDraft(field: .title, conditionOperator: .contains, value: "("),
            RuleConditionDraft(field: .summary, conditionOperator: .equals, value: "[")
        ]

        #expect(RuleConditionOperator.firstInvalidRegexValue(in: drafts) == nil)
    }

    @Test func firstInvalidRegexValueLiefertDasErsteUngueltigeMuster() {
        let drafts = [
            RuleConditionDraft(field: .title, conditionOperator: .regex, value: "gueltig.*"),
            RuleConditionDraft(field: .summary, conditionOperator: .regex, value: "("),
            RuleConditionDraft(field: .author, conditionOperator: .regex, value: "[")
        ]

        #expect(RuleConditionOperator.firstInvalidRegexValue(in: drafts) == "(")
    }
}
