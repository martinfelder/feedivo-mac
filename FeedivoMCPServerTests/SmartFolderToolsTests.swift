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

    @Test("get_smart_folder_articles liefert versteckte Artikel im eingebauten Ordner \"Ausgeblendet\"")
    func getSmartFolderArticlesLiefertVersteckteArtikelImAusgeblendetOrdner() throws {
        // Regressionstest für einen im Code-Review gefundenen Bug: der hartcodierte
        // `includeHidden: false`-Parameter widersprach sich mit der Ordner-eigenen
        // Bedingung `status is hidden` (die intern zu `s.isHidden = 1` übersetzt, während
        // `includeHidden: false` zusätzlich `s.isHidden = 0` erzwingt — beides zusammen ist
        // unerfüllbar). Fix: `includeHidden: snapshot.includesHiddenArticles` statt eines
        // festen `false`, analog zu den 5 anderen Aufrufstellen in der App
        // (SQLiteSidebarState.swift, SQLiteFeedArticleListState.swift,
        // SQLiteFeedArticleListView.swift, SmartFolderEditorView.swift,
        // SmartFolderSettingsView.swift).
        //
        // Der eingebaute "Ausgeblendet"-Ordner existiert in einer frischen In-Memory-
        // Test-DB nicht automatisch (er wird erst über `restoreDefaultFolders()` angelegt,
        // das die App normalerweise beim ersten Start aufruft) — dieser Aufruf macht ihn
        // hier explizit verfügbar, ohne einen vollen App-Start zu simulieren.
        let core = try FeedivoDatabase.inMemoryForTests()
        let smartFolderStore = SQLiteSmartFolderStore(database: core)
        try smartFolderStore.restoreDefaultFolders()

        guard let hiddenFolder = try smartFolderStore.sidebarSnapshots().first(where: { $0.defaultKey == "hidden" }) else {
            Issue.record("Eingebauter Ordner \"Ausgeblendet\" (defaultKey \"hidden\") wurde nicht angelegt")
            return
        }

        let feedID = try core.write { db -> String in
            var feed = FeedRecord(url: "https://example.com/feed", title: "Blog")
            try feed.insert(db)
            return feed.id
        }
        let articleStore = ArticleStore(database: core)
        let hiddenID = try articleStore.upsert(
            ArticleUpsertInput(feedID: feedID, title: "Versteckter Artikel", arrivedAt: Date())
        )
        try ArticleStatusStore(database: core).setHidden(true, articleID: hiddenID, at: Date())

        let database = FeedivoMCPServerDatabase(core: core)
        let result = try GetSmartFolderArticlesTool.call(
            database: database,
            arguments: ["smartFolderID": .string(hiddenFolder.id)]
        )

        guard case .text(let text, _, _) = result.content.first else {
            Issue.record("Erwartete Text-Content")
            return
        }
        #expect(result.isError == false)
        #expect(text.contains(hiddenID))
        #expect(text.contains("Versteckter Artikel"))
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
