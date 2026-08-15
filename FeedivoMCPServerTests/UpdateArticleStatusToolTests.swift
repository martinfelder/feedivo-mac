import Testing
import Foundation
import GRDB
import MCP
@testable import FeedivoMCPServer

@Suite("UpdateArticleStatusTool")
struct UpdateArticleStatusToolTests {
    @Test("Setzt isRead und persistiert den neuen Status")
    func setztIsRead() throws {
        let core = try FeedivoDatabase.inMemoryForTests()
        let articleID = try makeArticle(in: core)
        let readDatabase = FeedivoMCPServerDatabase(core: core)
        let writeDatabase = FeedivoMCPServerWritableDatabase(core: core)

        let result = try UpdateArticleStatusTool.call(
            readDatabase: readDatabase,
            writeDatabase: writeDatabase,
            arguments: ["articleID": .string(articleID), "isRead": .bool(true)]
        )

        #expect(result.isError == false)
        let status = try ArticleStatusStore(database: core).status(articleID: articleID)
        #expect(status?.isRead == true)
    }

    @Test("Setzt mehrere Felder in einem Aufruf")
    func setztMehrereFelder() throws {
        let core = try FeedivoDatabase.inMemoryForTests()
        let articleID = try makeArticle(in: core)
        let readDatabase = FeedivoMCPServerDatabase(core: core)
        let writeDatabase = FeedivoMCPServerWritableDatabase(core: core)

        let result = try UpdateArticleStatusTool.call(
            readDatabase: readDatabase,
            writeDatabase: writeDatabase,
            arguments: [
                "articleID": .string(articleID),
                "isRead": .bool(true),
                "isStarred": .bool(true),
            ]
        )

        #expect(result.isError == false)
        let status = try ArticleStatusStore(database: core).status(articleID: articleID)
        #expect(status?.isRead == true)
        #expect(status?.isStarred == true)
    }

    @Test("Liefert einen Fehler bei unbekannter Artikel-ID")
    func liefertFehlerBeiUnbekannterID() throws {
        let core = try FeedivoDatabase.inMemoryForTests()
        let readDatabase = FeedivoMCPServerDatabase(core: core)
        let writeDatabase = FeedivoMCPServerWritableDatabase(core: core)

        let result = try UpdateArticleStatusTool.call(
            readDatabase: readDatabase,
            writeDatabase: writeDatabase,
            arguments: ["articleID": .string("does-not-exist"), "isRead": .bool(true)]
        )

        #expect(result.isError == true)
    }

    @Test("Liefert einen Fehler, wenn kein Statusfeld gesetzt ist")
    func liefertFehlerOhneStatusfeld() throws {
        let core = try FeedivoDatabase.inMemoryForTests()
        let articleID = try makeArticle(in: core)
        let readDatabase = FeedivoMCPServerDatabase(core: core)
        let writeDatabase = FeedivoMCPServerWritableDatabase(core: core)

        let result = try UpdateArticleStatusTool.call(
            readDatabase: readDatabase,
            writeDatabase: writeDatabase,
            arguments: ["articleID": .string(articleID)]
        )

        #expect(result.isError == true)
    }

    @Test("Liefert einen Fehler bei fehlendem articleID-Parameter")
    func liefertFehlerBeiFehlendemParameter() throws {
        let core = try FeedivoDatabase.inMemoryForTests()
        let readDatabase = FeedivoMCPServerDatabase(core: core)
        let writeDatabase = FeedivoMCPServerWritableDatabase(core: core)

        let result = try UpdateArticleStatusTool.call(
            readDatabase: readDatabase,
            writeDatabase: writeDatabase,
            arguments: [:]
        )

        #expect(result.isError == true)
    }

    private func makeArticle(in core: FeedivoDatabase) throws -> String {
        let feedID = try core.write { db -> String in
            var feed = FeedRecord(url: "https://example.com/feed", title: "Test-Feed")
            try feed.insert(db)
            return feed.id
        }
        return try ArticleStore(database: core).upsert(
            ArticleUpsertInput(feedID: feedID, title: "Testartikel", content: "<p>Inhalt</p>", arrivedAt: Date())
        )
    }
}
