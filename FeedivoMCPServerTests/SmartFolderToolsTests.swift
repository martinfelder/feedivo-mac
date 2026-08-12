import Testing
import Foundation
import GRDB
import MCP
@testable import FeedivoMCPServer

@Suite("Smart-Folder-Tools")
struct SmartFolderToolsTests {
    @Test("list_smart_folders nennt Namen inkl. Standard-Markierung")
    func listSmartFoldersNenntNamenUndStandardMarkierung() throws {
        let core = try FeedivoDatabase.inMemoryForTests()
        let store = SQLiteSmartFolderStore(database: core)
        let customFolder = SmartFolderRecord(name: "Meine Auswahl", isDefault: false)
        try store.save(customFolder, conditions: [])
        let database = FeedivoMCPServerDatabase(core: core)

        let result = try ListSmartFoldersTool.call(database: database)

        guard case .text(let text, _, _) = result.content.first else {
            Issue.record("Erwartete Text-Content")
            return
        }
        #expect(text.contains("Meine Auswahl"))
    }

    @Test("get_smart_folder_articles liefert nur Artikel, die die Bedingung erfüllen")
    func getSmartFolderArticlesFiltertNachBedingung() throws {
        let core = try FeedivoDatabase.inMemoryForTests()
        let feedID = try core.write { db -> String in
            var feed = FeedRecord(url: "https://example.com/feed", title: "Blog")
            try feed.insert(db)
            return feed.id
        }
        let articleStore = ArticleStore(database: core)
        let unreadID = try articleStore.upsert(
            ArticleUpsertInput(feedID: feedID, title: "Ungelesener Artikel", arrivedAt: Date())
        )
        let readID = try articleStore.upsert(
            ArticleUpsertInput(feedID: feedID, title: "Gelesener Artikel", arrivedAt: Date())
        )
        try ArticleStatusStore(database: core).setRead(true, articleID: readID, at: Date())

        let smartFolderStore = SQLiteSmartFolderStore(database: core)
        let folder = SmartFolderRecord(name: "Nur ungelesen", isDefault: false)
        let condition = SmartFolderConditionRecord(
            smartFolderID: folder.id,
            field: SmartFolderConditionField.status.rawValue,
            conditionOperator: SmartFolderConditionOperator.`is`.rawValue,
            value: "unread"
        )
        try smartFolderStore.save(folder, conditions: [condition])

        let database = FeedivoMCPServerDatabase(core: core)
        let result = try GetSmartFolderArticlesTool.call(
            database: database,
            arguments: ["smartFolderID": .string(folder.id)]
        )

        guard case .text(let text, _, _) = result.content.first else {
            Issue.record("Erwartete Text-Content")
            return
        }
        #expect(text.contains(unreadID))
        #expect(!text.contains("Gelesener Artikel"))
    }

    @Test("get_smart_folder_articles liefert Fehler bei unbekannter ID")
    func getSmartFolderArticlesLiefertFehlerBeiUnbekannterID() throws {
        let core = try FeedivoDatabase.inMemoryForTests()
        let database = FeedivoMCPServerDatabase(core: core)

        let result = try GetSmartFolderArticlesTool.call(
            database: database,
            arguments: ["smartFolderID": .string("unbekannt")]
        )

        #expect(result.isError == true)
    }
}
