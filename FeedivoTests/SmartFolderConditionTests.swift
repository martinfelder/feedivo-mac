import Foundation
import SwiftData
import Testing
@testable import Feedivo

@MainActor
struct SmartFolderConditionTests {
    @Test func fieldEnumLiefertNilFuerUnbekanntenRawValue() {
        let condition = SmartFolderCondition(field: .title, conditionOperator: .contains, value: "x")
        condition.fieldRaw = "unbekannt"
        #expect(condition.fieldEnum == nil)
    }

    @Test func fieldEnumLiefertEnumFuerBekanntenRawValue() {
        let condition = SmartFolderCondition(field: .status, conditionOperator: .is,
                                              value: SmartFolderStatusValue.unread.rawValue)
        #expect(condition.fieldEnum == .status)
        #expect(condition.operatorEnum == .is)
    }
}