import Testing
import Foundation
import GRDB
import MCP
@testable import FeedivoMCPServer

@Suite("SearchArticlesTool")
struct SearchArticlesToolTests {
    @Test("Findet Artikel per Volltextsuche im Titel und liefert Kurztext statt Volltext")
    func findetArtikelPerVolltextsuche() throws {
        let core = try FeedivoDatabase.inMemoryForTests()
        let feedID = try core.write { db -> String in
            var feed = FeedRecord(url: "https://example.com/feed", title: "Swift Blog")
            try feed.insert(db)
            return feed.id
        }
        let articleStore = ArticleStore(database: core)
        _ = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: feedID,
                title: "Neuigkeiten zu Swift 6 Concurrency",
                content: "<p>Ein sehr langer Artikeltext über Concurrency in Swift 6, der hier absichtlich lang ist, damit der Kurztext-Grenzwert überprüft werden kann.</p>",
                arrivedAt: Date()
            )
        )
        _ = try articleStore.upsert(
            ArticleUpsertInput(feedID: feedID, title: "Ganz anderes Thema", arrivedAt: Date())
        )

        let database = FeedivoMCPServerDatabase(core: core)
        let arguments: [String: Value] = ["query": .string("Swift 6")]

        let result = try SearchArticlesTool.call(database: database, arguments: arguments)

        // Hinweis: `MCP.Tool.Content.text` hat 3 assoziierte Werte
        // (text:annotations:_meta:) — ein Pattern mit nur `let text` bindet den
        // kompletten Tupel-Wert statt des reinen Strings, siehe Report.
        guard case .text(let text, _, _) = result.content.first else {
            Issue.record("Erwartete Text-Content")
            return
        }
        #expect(text.contains("Neuigkeiten zu Swift 6 Concurrency"))
        #expect(text.contains("Swift Blog"))
        #expect(!text.contains("Ganz anderes Thema"))
        #expect(result.isError == false)
    }

    @Test("Filtert nach Status ungelesen")
    func filtertNachStatusUngelesen() throws {
        let core = try FeedivoDatabase.inMemoryForTests()
        let feedID = try core.write { db -> String in
            var feed = FeedRecord(url: "https://example.com/feed", title: "Blog")
            try feed.insert(db)
            return feed.id
        }
        let articleStore = ArticleStore(database: core)
        let readID = try articleStore.upsert(
            ArticleUpsertInput(feedID: feedID, title: "Gelesener Artikel", arrivedAt: Date())
        )
        _ = try articleStore.upsert(
            ArticleUpsertInput(feedID: feedID, title: "Ungelesener Artikel", arrivedAt: Date())
        )
        try ArticleStatusStore(database: core).setRead(true, articleID: readID, at: Date())

        let database = FeedivoMCPServerDatabase(core: core)
        let arguments: [String: Value] = ["status": .string("unread")]

        let result = try SearchArticlesTool.call(database: database, arguments: arguments)

        guard case .text(let text, _, _) = result.content.first else {
            Issue.record("Erwartete Text-Content")
            return
        }
        #expect(text.contains("Ungelesener Artikel"))
        #expect(!text.contains("Gelesener Artikel"))
    }

    @Test("Liefert eine verständliche Meldung bei keinem Treffer")
    func liefertMeldungBeiKeinemTreffer() throws {
        let core = try FeedivoDatabase.inMemoryForTests()
        let database = FeedivoMCPServerDatabase(core: core)

        let result = try SearchArticlesTool.call(database: database, arguments: ["query": .string("nichts")])

        guard case .text(let text, _, _) = result.content.first else {
            Issue.record("Erwartete Text-Content")
            return
        }
        #expect(text.contains("Keine Artikel"))
        #expect(result.isError == false)
    }
}
