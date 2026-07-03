import Foundation
import SwiftData
import Testing
@testable import Feedivo

struct SQLiteAdminStoreTests {
    @Test func feedFolderStoreSpeichertUndSortiertOrdner() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = FeedFolderStore(database: database)

        try store.save(FeedFolderRecord(id: "folder-b", name: "Zeta"))
        try store.save(FeedFolderRecord(id: "folder-a", name: "Alpha"))

        #expect(try store.folders().map(\.name) == ["Alpha", "Zeta"])

        try store.delete(id: "folder-a")

        #expect(try store.folders().map(\.id) == ["folder-b"])
    }

    @Test func ruleStoreSpeichertRegelnMitConditionsUndTagSnapshot() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try TagStore(database: database).save(TagRecord(id: "tag-1", name: "Swift", colorHex: "#FF0000"))
        let store = SQLiteRuleStore(database: database)

        try store.save(
            RuleRecord(
                id: "11111111-1111-1111-1111-111111111111",
                name: "Swift-Regel",
                isEnabled: true,
                matchMode: RuleMatchMode.any.rawValue,
                action: RuleAction.assignTag.rawValue,
                assignTagID: "tag-1",
                sortOrder: 2
            ),
            conditions: [
                RuleConditionRecord(
                    id: "condition-1",
                    ruleID: "11111111-1111-1111-1111-111111111111",
                    field: RuleConditionField.title.rawValue,
                    conditionOperator: RuleConditionOperator.contains.rawValue,
                    value: "Swift",
                    sortOrder: 1
                )
            ]
        )

        let snapshots = try store.ruleSnapshots()

        #expect(snapshots.map(\.name) == ["Swift-Regel"])
        #expect(snapshots.first?.conditionMatchMode == RuleMatchMode.any.rawValue)
        #expect(snapshots.first?.conditions.map(\.value) == ["Swift"])
        #expect(snapshots.first?.assignTag?.name == "Swift")
    }

    @Test func smartFolderStoreSpeichertOrdnerMitConditionsUndSnapshots() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = SQLiteSmartFolderStore(database: database)

        try store.save(
            SmartFolderRecord(
                id: "folder-1",
                name: "Heute",
                matchMode: RuleMatchMode.all.rawValue,
                isShownInSidebar: true,
                isDefault: true,
                sortOrder: 1,
                defaultKey: "today",
                iconName: "calendar",
                colorHex: "#3B82F6"
            ),
            conditions: [
                SmartFolderConditionRecord(
                    id: "condition-1",
                    smartFolderID: "folder-1",
                    field: SmartFolderConditionField.status.rawValue,
                    conditionOperator: SmartFolderConditionOperator.is.rawValue,
                    value: SmartFolderStatusValue.unread.rawValue,
                    sortOrder: 0
                )
            ]
        )

        let folders = try store.folders()
        let snapshots = try store.sidebarSnapshots()

        #expect(folders.map(\.name) == ["Heute"])
        #expect(snapshots.first?.id == "folder-1")
        #expect(snapshots.first?.conditions.first?.value == SmartFolderStatusValue.unread.rawValue)
    }

    @MainActor
    @Test func adminBackfillSpiegeltSwiftDataVerwaltungNachSQLite() throws {
        let context = try testContext()
        let database = try FeedivoDatabase.inMemoryForTests()
        let tag = Tag(name: "Swift", colorHex: "#FF0000")
        let feedFolder = FeedFolder(name: "Technik")
        let rule = Rule(name: "Swift-Regel")
        let ruleCondition = RuleCondition(
            field: RuleConditionField.title.rawValue,
            conditionOperator: RuleConditionOperator.contains.rawValue,
            value: "Swift",
            sortOrder: 0
        )
        let smartFolder = SmartFolder(
            name: "Ungelesen",
            matchMode: .all,
            isShownInSidebar: true,
            isDefault: true,
            sortOrder: 0,
            iconName: "circle.fill",
            colorHex: "#22C55E",
            defaultKey: "unread",
            conditions: [
                SmartFolderCondition(
                    field: .status,
                    conditionOperator: .is,
                    value: SmartFolderStatusValue.unread.rawValue,
                    sortOrder: 0
                )
            ]
        )

        rule.assignTag = tag
        rule.conditions = [ruleCondition]
        context.insert(tag)
        context.insert(feedFolder)
        context.insert(rule)
        context.insert(smartFolder)
        try context.save()

        let result = try SQLiteAdminDefinitionBackfillService.backfill(
            in: context,
            database: database
        )

        #expect(result == .init(feedFolderCount: 1, ruleCount: 1, smartFolderCount: 1))
        #expect(try FeedFolderStore(database: database).folders().map(\.name) == ["Technik"])
        #expect(try SQLiteRuleStore(database: database).ruleSnapshots().first?.assignTag?.name == "Swift")
        #expect(try SQLiteSmartFolderStore(database: database).sidebarSnapshots().first?.conditions.first?.value == SmartFolderStatusValue.unread.rawValue)
    }

    @MainActor
    private func testContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Feed.self,
            FeedFolder.self,
            Article.self,
            Tag.self,
            Rule.self,
            RuleCondition.self,
            SmartFolder.self,
            SmartFolderCondition.self,
            FeedLogEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )

        return ModelContext(container)
    }
}
