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

    @Test func feedStoreMutiertFeedVerwaltungSQLiteFirst() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = FeedStore(database: database)

        try store.save(
            FeedRecord(
                id: "feed-1",
                url: "https://example.com/feed.xml",
                title: "Example",
                originalTitle: "Example Original",
                refreshIntervalMinutes: 30
            )
        )

        try store.renameFeed(id: "feed-1", displayTitle: "Example Display")
        #expect(try store.feed(id: "feed-1")?.title == "Example Display")
        #expect(try store.feed(id: "feed-1")?.originalTitle == "Example Original")

        try store.restoreOriginalTitle(id: "feed-1")
        #expect(try store.feed(id: "feed-1")?.title == "Example Original")

        try store.updateRefreshInterval(id: "feed-1", minutes: 120)
        try store.updateFolderName(id: "feed-1", folderName: " Technik ")
        try store.updateNotificationEnabled(id: "feed-1", isEnabled: true)
        try store.updateRetentionSettings(
            id: "feed-1",
            overridesGlobal: true,
            isEnabled: true,
            days: 60,
            minimumArticles: 10,
            includesProtectedArticles: true
        )

        let updatedFeedOptional = try store.feed(id: "feed-1")
        let updatedFeed = try #require(updatedFeedOptional)
        #expect(updatedFeed.refreshIntervalMinutes == 120)
        #expect(updatedFeed.folderName == "Technik")
        #expect(updatedFeed.isNotificationEnabled)
        #expect(updatedFeed.articleRetentionOverridesGlobalSetting)
        #expect(updatedFeed.articleRetentionIsEnabled)
        #expect(updatedFeed.articleRetentionDays == 60)
        #expect(updatedFeed.articleRetentionMinimumArticles == 10)
        #expect(updatedFeed.articleRetentionIncludesProtectedArticles)

        try store.delete(id: "feed-1")
        #expect(try store.feed(id: "feed-1") == nil)
    }

    @Test func tagStoreMutiertTagsSQLiteFirst() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = TagStore(database: database)

        try store.save(TagRecord(id: "tag-1", name: "Swift", colorHex: "#FF0000"))
        try store.save(TagRecord(id: "tag-2", name: "Apple", colorHex: "#00FF00"))

        try store.renameTag(id: "tag-1", name: "Swift News")
        try store.updateColor(id: "tag-1", colorHex: "3b82f6")

        let updatedTag = try #require(store.tags().first { $0.id == "tag-1" })
        #expect(updatedTag.name == "Swift News")
        #expect(updatedTag.colorHex == "#3B82F6")
        #expect(throws: TagStore.TagStoreError.duplicateName) {
            try store.renameTag(id: "tag-1", name: "apple")
        }

        try store.deleteTag(id: "tag-2")

        #expect(try store.tags().map(\.id) == ["tag-1"])
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

    @Test func ruleStoreMutiertRegelnSQLiteFirst() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = SQLiteRuleStore(database: database)

        try store.save(
            RuleRecord(
                id: "11111111-1111-1111-1111-111111111111",
                name: "Swift",
                isEnabled: true,
                matchMode: RuleMatchMode.all.rawValue,
                action: RuleAction.hideArticle.rawValue,
                sortOrder: 0
            ),
            conditions: [
                RuleConditionRecord(
                    id: "condition-1",
                    ruleID: "11111111-1111-1111-1111-111111111111",
                    field: RuleConditionField.title.rawValue,
                    conditionOperator: RuleConditionOperator.contains.rawValue,
                    value: "Swift",
                    sortOrder: 0
                )
            ]
        )

        try store.updateEnabled(id: "11111111-1111-1111-1111-111111111111", isEnabled: false)
        #expect(try store.rule(id: "11111111-1111-1111-1111-111111111111")?.isEnabled == false)

        let duplicate = try store.duplicate(
            id: "11111111-1111-1111-1111-111111111111",
            copyName: "Swift Kopie"
        )
        #expect(duplicate.name == "Swift Kopie")
        #expect(try store.conditions(ruleID: duplicate.id).map(\.value) == ["Swift"])

        try store.save(
            RuleRecord(
                id: "22222222-2222-2222-2222-222222222222",
                name: "Apple",
                sortOrder: 2
            ),
            conditions: []
        )
        try store.move(id: "22222222-2222-2222-2222-222222222222", toPositionOf: duplicate.id)

        #expect(try store.rules().map(\.id).prefix(2) == [
            "11111111-1111-1111-1111-111111111111",
            "22222222-2222-2222-2222-222222222222"
        ])
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

    @Test func smartFolderStoreMutiertOrdnerSQLiteFirst() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = SQLiteSmartFolderStore(database: database)

        try store.save(
            SmartFolderRecord(
                id: "folder-1",
                name: "Swift",
                matchMode: RuleMatchMode.all.rawValue,
                isShownInSidebar: true,
                sortOrder: 0,
                iconName: "tray.full",
                colorHex: "#3B82F6"
            ),
            conditions: [
                SmartFolderConditionRecord(
                    id: "condition-1",
                    smartFolderID: "folder-1",
                    field: SmartFolderConditionField.title.rawValue,
                    conditionOperator: SmartFolderConditionOperator.contains.rawValue,
                    value: "Swift",
                    sortOrder: 0
                )
            ]
        )

        try store.updateSidebarVisibility(id: "folder-1", isShownInSidebar: false)
        #expect(try store.folder(id: "folder-1")?.isShownInSidebar == false)

        let duplicate = try store.duplicate(id: "folder-1", copyName: "Swift Kopie")
        #expect(duplicate.name == "Swift Kopie")
        #expect(duplicate.isDefault == false)
        #expect(try store.conditions(folderID: duplicate.id).map(\.value) == ["Swift"])

        try store.restoreDefaultFolders()
        let defaultKeys = try store.folders().compactMap(\.defaultKey)
        #expect(defaultKeys.contains("all"))
        #expect(defaultKeys.contains("saved"))
    }
}
