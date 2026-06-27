import Foundation
import SwiftData
import Testing
@testable import Feedivo

@MainActor
struct RuleConditionTests {
    @Test func fieldEnumLiefertNilFuerUnbekanntenRawValue() {
        let condition = RuleCondition(field: "titel", conditionOperator: "contains", value: "x")
        #expect(condition.fieldEnum == nil)
    }

    @Test func fieldEnumLiefertEnumFuerBekanntenRawValue() {
        let condition = RuleCondition(field: RuleConditionField.title.rawValue,
                                       conditionOperator: RuleConditionOperator.contains.rawValue,
                                       value: "x")
        #expect(condition.fieldEnum == .title)
        #expect(condition.operatorEnum == .contains)
    }
}
