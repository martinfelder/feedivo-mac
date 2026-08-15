import MCP
import Foundation

enum UpdateArticleStatusTool {
    static let definition = Tool(
        name: "update_article_status",
        description: """
            Setzt Gelesen-/Stern-/Versteckt-Status eines Artikels. Mindestens eines der \
            drei optionalen Felder muss gesetzt sein.
            """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "articleID": .object([
                    "type": .string("string"),
                    "description": .string("Die Artikel-ID aus search_articles oder get_article"),
                ]),
                "isRead": .object([
                    "type": .string("boolean"),
                    "description": .string("Optional: Gelesen-Status setzen"),
                ]),
                "isStarred": .object([
                    "type": .string("boolean"),
                    "description": .string("Optional: Stern-Status setzen"),
                ]),
                "isHidden": .object([
                    "type": .string("boolean"),
                    "description": .string("Optional: Versteckt-Status setzen"),
                ]),
            ]),
            "required": .array([.string("articleID")]),
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

        let isRead = arguments?["isRead"]?.boolValue
        let isStarred = arguments?["isStarred"]?.boolValue
        let isHidden = arguments?["isHidden"]?.boolValue

        guard isRead != nil || isStarred != nil || isHidden != nil else {
            return .init(content: [.text("Mindestens eines von isRead, isStarred, isHidden muss gesetzt sein.")], isError: true)
        }

        // Existenz-Check auf der readonly-Verbindung, BEVOR geschrieben wird — setRead/
        // setStarred/setHidden führen intern nur ein UPDATE ... WHERE articleID = ? aus und
        // werfen bei unbekannter ID keinen Fehler (0 betroffene Zeilen bleibt still), deshalb
        // hier explizit prüfen statt uns auf einen Store-Fehler zu verlassen.
        let articleDatabase = ArticleDatabase(database: readDatabase.core)
        guard try articleDatabase.readerArticle(id: articleID) != nil else {
            return .init(content: [.text("Kein Artikel mit ID \(articleID) gefunden.")], isError: true)
        }

        let statusStore = ArticleStatusStore(database: writeDatabase.core)
        let now = Date()
        var changedFields: [String] = []

        if let isRead {
            try statusStore.setRead(isRead, articleID: articleID, at: now)
            changedFields.append("isRead=\(isRead)")
        }
        if let isStarred {
            try statusStore.setStarred(isStarred, articleID: articleID, at: now)
            changedFields.append("isStarred=\(isStarred)")
        }
        if let isHidden {
            try statusStore.setHidden(isHidden, articleID: articleID, at: now)
            changedFields.append("isHidden=\(isHidden)")
        }

        return .init(content: [.text("Artikel \(articleID) aktualisiert: \(changedFields.joined(separator: ", "))")], isError: false)
    }
}
