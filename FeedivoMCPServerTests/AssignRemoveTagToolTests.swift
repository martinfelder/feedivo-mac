import Testing
import Foundation
import GRDB
import MCP
@testable import FeedivoMCPServer

@Suite("AssignTagTool und RemoveTagTool")
struct AssignRemoveTagToolTests {
    @Test("assign_tag weist einen bestehenden Tag einem Artikel zu")
    func assignTagWeistTagZu() throws {
        let core = try FeedivoDatabase.inMemoryForTests()
        let articleID = try makeArticle(in: core)
        let tagID = try makeTag(in: core, name: "Swift")
        let readDatabase = FeedivoMCPServerDatabase(core: core)
        let writeDatabase = FeedivoMCPServerWritableDatabase(core: core)

        let result = try AssignTagTool.call(
            readDatabase: readDatabase,
            writeDatabase: writeDatabase,
            arguments: ["articleID": .string(articleID), "tagID": .string(tagID)]
        )

        #expect(result.isError == false)
        let tags = try TagStore(database: core).tags(articleID: articleID)
        #expect(tags.contains { $0.id == tagID })
    }

    @Test("assign_tag liefert einen Fehler bei unbekannter tagID")
    func assignTagFehlerBeiUnbekannterTagID() throws {
        let core = try FeedivoDatabase.inMemoryForTests()
        let articleID = try makeArticle(in: core)
        let readDatabase = FeedivoMCPServerDatabase(core: core)
        let writeDatabase = FeedivoMCPServerWritableDatabase(core: core)

        let result = try AssignTagTool.call(
            readDatabase: readDatabase,
            writeDatabase: writeDatabase,
            arguments: ["articleID": .string(articleID), "tagID": .string("does-not-exist")]
        )

        #expect(result.isError == true)
    }

    @Test("assign_tag liefert einen Fehler bei unbekannter articleID")
    func assignTagFehlerBeiUnbekannterArticleID() throws {
        let core = try FeedivoDatabase.inMemoryForTests()
        let tagID = try makeTag(in: core, name: "Swift")
        let readDatabase = FeedivoMCPServerDatabase(core: core)
        let writeDatabase = FeedivoMCPServerWritableDatabase(core: core)

        let result = try AssignTagTool.call(
            readDatabase: readDatabase,
            writeDatabase: writeDatabase,
            arguments: ["articleID": .string("does-not-exist"), "tagID": .string(tagID)]
        )

        #expect(result.isError == true)
    }

    @Test("remove_tag entfernt einen zugewiesenen Tag")
    func removeTagEntferntTag() throws {
        let core = try FeedivoDatabase.inMemoryForTests()
        let articleID = try makeArticle(in: core)
        let tagID = try makeTag(in: core, name: "Swift")
        try TagStore(database: core).assignTag(tagID: tagID, toArticleID: articleID, at: Date())
        let readDatabase = FeedivoMCPServerDatabase(core: core)
        let writeDatabase = FeedivoMCPServerWritableDatabase(core: core)

        let result = try RemoveTagTool.call(
            readDatabase: readDatabase,
            writeDatabase: writeDatabase,
            arguments: ["articleID": .string(articleID), "tagID": .string(tagID)]
        )

        #expect(result.isError == false)
        let tags = try TagStore(database: core).tags(articleID: articleID)
        #expect(!tags.contains { $0.id == tagID })
    }

    @Test("remove_tag ist idempotent, wenn der Tag gar nicht zugewiesen war")
    func removeTagIstIdempotent() throws {
        let core = try FeedivoDatabase.inMemoryForTests()
        let articleID = try makeArticle(in: core)
        let tagID = try makeTag(in: core, name: "Swift")
        let readDatabase = FeedivoMCPServerDatabase(core: core)
        let writeDatabase = FeedivoMCPServerWritableDatabase(core: core)

        let result = try RemoveTagTool.call(
            readDatabase: readDatabase,
            writeDatabase: writeDatabase,
            arguments: ["articleID": .string(articleID), "tagID": .string(tagID)]
        )

        #expect(result.isError == false)
    }

    @Test("remove_tag liefert einen Fehler bei unbekannter tagID")
    func removeTagFehlerBeiUnbekannterTagID() throws {
        let core = try FeedivoDatabase.inMemoryForTests()
        let articleID = try makeArticle(in: core)
        let readDatabase = FeedivoMCPServerDatabase(core: core)
        let writeDatabase = FeedivoMCPServerWritableDatabase(core: core)

        let result = try RemoveTagTool.call(
            readDatabase: readDatabase,
            writeDatabase: writeDatabase,
            arguments: ["articleID": .string(articleID), "tagID": .string("does-not-exist")]
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

    private func makeTag(in core: FeedivoDatabase, name: String) throws -> String {
        var tag = TagRecord(name: name)
        try core.write { db in try tag.insert(db) }
        return tag.id
    }
}
