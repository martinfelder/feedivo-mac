import Testing
import Foundation
import GRDB
import MCP
@testable import FeedivoMCPServer

@Suite("GetArticleTool")
struct GetArticleToolTests {
    @Test("Liefert bereinigten Klartext statt rohes HTML")
    func liefertBereinigtenKlartext() throws {
        let core = try FeedivoDatabase.inMemoryForTests()
        let feedID = try core.write { db -> String in
            var feed = FeedRecord(url: "https://example.com/feed", title: "Swift Blog")
            try feed.insert(db)
            return feed.id
        }
        let articleID = try ArticleStore(database: core).upsert(
            ArticleUpsertInput(
                feedID: feedID,
                title: "Ein Testartikel",
                content: "<p>Erster <strong>Absatz</strong>.</p><p>Zweiter Absatz.</p>",
                author: "Max Mustermann",
                arrivedAt: Date()
            )
        )
        let database = FeedivoMCPServerDatabase(core: core)

        let result = try GetArticleTool.call(database: database, arguments: ["articleID": .string(articleID)])

        guard case .text(let text, _, _) = result.content.first else {
            Issue.record("Erwartete Text-Content")
            return
        }
        #expect(text.contains("Ein Testartikel"))
        #expect(text.contains("Max Mustermann"))
        #expect(text.contains("Erster Absatz."))
        #expect(!text.contains("<p>"))
        #expect(!text.contains("<strong>"))
        #expect(result.isError == false)
    }

    @Test("Liefert einen Fehler bei unbekannter Artikel-ID")
    func liefertFehlerBeiUnbekannterID() throws {
        let core = try FeedivoDatabase.inMemoryForTests()
        let database = FeedivoMCPServerDatabase(core: core)

        let result = try GetArticleTool.call(database: database, arguments: ["articleID": .string("does-not-exist")])

        #expect(result.isError == true)
    }

    @Test("Liefert einen Fehler bei fehlendem articleID-Parameter")
    func liefertFehlerBeiFehlendemParameter() throws {
        let core = try FeedivoDatabase.inMemoryForTests()
        let database = FeedivoMCPServerDatabase(core: core)

        let result = try GetArticleTool.call(database: database, arguments: [:])

        #expect(result.isError == true)
    }
}
