import Testing
import Foundation
import GRDB
@testable import FeedivoMCPServer

@Suite("Listing-Tools")
struct ListingToolsTests {
    @Test("list_feeds nennt Titel, Ordner und Ungelesen-Anzahl")
    func listFeedsNenntErwarteteFelder() throws {
        let core = try FeedivoDatabase.inMemoryForTests()
        try core.write { db in
            var feed = FeedRecord(url: "https://example.com/feed", title: "Swift Blog", folderName: "Tech", unreadCount: 3)
            try feed.insert(db)
        }
        let database = FeedivoMCPServerDatabase(core: core)

        let result = try ListFeedsTool.call(database: database)

        // Hinweis: `MCP.Tool.Content.text` hat 3 assoziierte Werte
        // (text:annotations:_meta:) — ein Pattern mit nur `let text` bindet den
        // kompletten Tupel-Wert statt des reinen Strings, siehe Report.
        guard case .text(let text, _, _) = result.content.first else {
            Issue.record("Erwartete Text-Content")
            return
        }
        #expect(text.contains("Swift Blog"))
        #expect(text.contains("Tech"))
        #expect(text.contains("3"))
        #expect(result.isError == false)
    }

    @Test("list_folders nennt Ordnernamen")
    func listFoldersNenntOrdnernamen() throws {
        let core = try FeedivoDatabase.inMemoryForTests()
        try core.write { db in
            var folder = FeedFolderRecord(name: "Tech")
            try folder.insert(db)
        }
        let database = FeedivoMCPServerDatabase(core: core)

        let result = try ListFoldersTool.call(database: database)

        guard case .text(let text, _, _) = result.content.first else {
            Issue.record("Erwartete Text-Content")
            return
        }
        #expect(text.contains("Tech"))
    }

    @Test("list_tags nennt Tag-Namen")
    func listTagsNenntTagNamen() throws {
        let core = try FeedivoDatabase.inMemoryForTests()
        try core.write { db in
            var tag = TagRecord(name: "Dev")
            try tag.insert(db)
        }
        let database = FeedivoMCPServerDatabase(core: core)

        let result = try ListTagsTool.call(database: database)

        guard case .text(let text, _, _) = result.content.first else {
            Issue.record("Erwartete Text-Content")
            return
        }
        #expect(text.contains("Dev"))
    }
}
