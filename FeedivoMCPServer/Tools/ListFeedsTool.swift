import MCP

enum ListFeedsTool {
    static let definition = Tool(
        name: "list_feeds",
        description: "Listet alle abonnierten Feeds mit Ordner-Zuordnung und Ungelesen-Anzahl auf.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([:]),
        ])
    )

    static func call(database: FeedivoMCPServerDatabase) throws -> CallTool.Result {
        let store = FeedStore(database: database.core)
        let feeds = try store.feeds()

        if feeds.isEmpty {
            return .init(content: [.text("Keine Feeds abonniert.")], isError: false)
        }

        let lines = feeds.map { feed in
            "\(feed.title) (id: \(feed.id), Ordner: \(feed.folderName ?? "—"), ungelesen: \(feed.unreadCount))"
        }
        return .init(content: [.text(lines.joined(separator: "\n"))], isError: false)
    }
}
