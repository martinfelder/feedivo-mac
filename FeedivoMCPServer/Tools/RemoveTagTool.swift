import MCP
import Foundation

enum RemoveTagTool {
    static let definition = Tool(
        name: "remove_tag",
        description: "Entfernt einen Tag von einem Artikel. Kein Fehler, falls der Tag dem Artikel ohnehin nicht zugewiesen war.",
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

        let articleDatabase = ArticleDatabase(database: readDatabase.core)
        guard try articleDatabase.readerArticle(id: articleID) != nil else {
            return .init(content: [.text("Kein Artikel mit ID \(articleID) gefunden.")], isError: true)
        }

        let tagStore = TagStore(database: readDatabase.core)
        guard try tagStore.sidebarTags().contains(where: { $0.id == tagID }) else {
            return .init(content: [.text("Kein Tag mit ID \(tagID) gefunden.")], isError: true)
        }

        try TagStore(database: writeDatabase.core).removeTag(tagID: tagID, fromArticleID: articleID)

        return .init(content: [.text("Tag \(tagID) wurde von Artikel \(articleID) entfernt.")], isError: false)
    }
}
