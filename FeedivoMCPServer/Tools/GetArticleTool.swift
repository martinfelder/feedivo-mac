import MCP
import Foundation

enum GetArticleTool {
    static let definition = Tool(
        name: "get_article",
        description: "Liest den vollständigen Inhalt eines einzelnen Artikels (als bereinigter Klartext) anhand seiner ID, wie von search_articles oder get_smart_folder_articles zurückgegeben.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "articleID": .object([
                    "type": .string("string"),
                    "description": .string("Die Artikel-ID aus search_articles"),
                ])
            ]),
            "required": .array([.string("articleID")]),
        ])
    )

    static func call(database: FeedivoMCPServerDatabase, arguments: [String: Value]?) throws -> CallTool.Result {
        guard let articleID = arguments?["articleID"]?.stringValue else {
            return .init(content: [.text("Fehlender Parameter: articleID")], isError: true)
        }

        let articleDatabase = ArticleDatabase(database: database.core)
        guard let article = try articleDatabase.readerArticle(id: articleID) else {
            return .init(content: [.text("Kein Artikel mit ID \(articleID) gefunden.")], isError: true)
        }

        let plainContent = HTMLPlainTextConverter.plainText(fromHTML: article.content ?? article.summary ?? "")
        let tagNames = article.tags.map(\.name).joined(separator: ", ")
        let dateString = ISO8601DateFormatter().string(from: article.publishedAt ?? article.arrivedAt)

        let text = """
            Titel: \(article.title)
            Feed: \(article.feedTitle)
            Datum: \(dateString)
            Link: \(article.link ?? "—")
            Autor: \(article.author ?? "—")
            Tags: \(tagNames.isEmpty ? "—" : tagNames)
            Gelesen: \(article.isRead ? "ja" : "nein"), Stern: \(article.isStarred ? "ja" : "nein")

            \(plainContent)
            """
        return .init(content: [.text(text)], isError: false)
    }
}
