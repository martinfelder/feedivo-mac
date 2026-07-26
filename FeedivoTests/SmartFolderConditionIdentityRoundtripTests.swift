import Foundation
import Testing
@testable import Feedivo

struct SmartFolderConditionIdentityRoundtripTests {
    @Test func bedingungsIDBleibtUeberEinenSpeicherLadeSpeicherZyklusStabil() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = SQLiteSmartFolderStore(database: database)

        let originalConditionID = UUID().uuidString
        let folder = SmartFolderRecord(
            id: UUID().uuidString,
            name: "Test-Ordner",
            iconName: "folder",
            colorHex: "#FF0000",
            defaultShowsReadArticles: false,
            createdAt: Date()
        )
        let condition = SmartFolderConditionRecord(
            id: originalConditionID,
            smartFolderID: folder.id,
            field: SmartFolderConditionField.title.rawValue,
            conditionOperator: SmartFolderConditionOperator.contains.rawValue,
            value: "Alt",
            sortOrder: 0,
            updatedAt: Date()
        )
        try store.save(folder, conditions: [condition])

        // Simuliert den Editor-Lade-/Bearbeitungs-/Speicher-Zyklus mit dem Fix aus Steps 5-7:
        // Drafts über drafts(for:) laden (übernimmt die ID), Wert bearbeiten, per
        // draft.id.uuidString zurückspeichern.
        let reloadedConditions = try store.conditions(folderID: folder.id)
        let drafts = SmartFolderFormatter.drafts(for: reloadedConditions)
        let editedDraft = SmartFolderConditionDraft(
            id: drafts[0].id,
            field: drafts[0].field,
            conditionOperator: drafts[0].conditionOperator,
            value: "Neu"
        )
        let updatedCondition = SmartFolderConditionRecord(
            id: editedDraft.id.uuidString,
            smartFolderID: folder.id,
            field: editedDraft.field.rawValue,
            conditionOperator: editedDraft.conditionOperator.rawValue,
            value: editedDraft.value,
            sortOrder: 0,
            updatedAt: Date()
        )
        try store.save(folder, conditions: [updatedCondition])

        let finalConditions = try store.conditions(folderID: folder.id)
        #expect(finalConditions.count == 1)
        #expect(finalConditions.first?.id == originalConditionID)
        #expect(finalConditions.first?.value == "Neu")
    }
}
