import MCP
import Foundation

enum AssignTagTool {
    static let definition = Tool(
        name: "assign_tag",
        description: """
            Weist einen bestehenden Tag einem Artikel zu. Der Tag muss bereits existieren \
            (siehe list_tags) — legt keine neuen Tags an.
            """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "articleID": .object([
                    "type": .string("string"),
                    "description": .string("Die Artikel-ID aus search_articles oder get_article"),
                ]),
                "tagID": .object([
                    "type": .string("string"),
                    "description": .string("Die Tag-ID aus list_tags"),
                ]),
            ]),
            "required": .array([.string("articleID"), .string("tagID")]),
        ])
    )

    static func call(
        readDatabase: FeedivoMCPServerDatabase,
        writeDatabase: FeedivoMCPServerWritableDatabase,
        arguments: [String: Value]?
    ) throws -> CallTool.Result {
        guard let articleID = arguments?["articleID"]?.stringValue else {
            return .init(content: [.text("Fehlender Parameter: articleID")], isError: true)
        }
        guard let tagID = arguments?["tagID"]?.stringValue else {
            return .init(content: [.text("Fehlender Parameter: tagID")], isError: true)
        }

        // Explizite Existenz-Checks auf der readonly-Verbindung: TagStore.assignTag nutzt
        // `insert(db, onConflict: .ignore)` — SQLite unterdrückt damit STILL auch
        // Fremdschlüssel-Verletzungen (nicht nur Unique-/PK-Konflikte), ein Aufruf mit
        // ungültiger articleID/tagID würde also klaglos nichts tun statt zu werfen.
        let articleDatabase = ArticleDatabase(database: readDatabase.core)
        guard try articleDatabase.readerArticle(id: articleID) != nil else {
            return .init(content: [.text("Kein Artikel mit ID \(articleID) gefunden.")], isError: true)
        }

        let tagStore = TagStore(database: readDatabase.core)
        guard try tagStore.sidebarTags().contains(where: { $0.id == tagID }) else {
            return .init(content: [.text("Kein Tag mit ID \(tagID) gefunden.")], isError: true)
        }

        try TagStore(database: writeDatabase.core).assignTag(tagID: tagID, toArticleID: articleID, at: Date())

        return .init(content: [.text("Tag \(tagID) wurde Artikel \(articleID) zugewiesen.")], isError: false)
    }
}
