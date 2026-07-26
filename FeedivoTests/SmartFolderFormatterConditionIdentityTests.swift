import Foundation
import Testing
@testable import Feedivo

struct SmartFolderFormatterConditionIdentityTests {
    @Test func draftsUebernimmtDieBestehendeIDStattEinerNeuen() {
        let existingID = UUID()
        let condition = SmartFolderConditionRecord(
            id: existingID.uuidString,
            smartFolderID: "folder-1",
            field: SmartFolderConditionField.title.rawValue,
            conditionOperator: SmartFolderConditionOperator.contains.rawValue,
            value: "Test",
            sortOrder: 0,
            updatedAt: Date()
        )

        let drafts = SmartFolderFormatter.drafts(for: [condition])

        #expect(drafts.first?.id == existingID)
    }
}
