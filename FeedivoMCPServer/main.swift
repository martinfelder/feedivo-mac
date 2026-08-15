import Foundation
import MCP

let database: FeedivoMCPServerDatabase
do {
    database = try FeedivoMCPServerDatabase.openReadOnly()
} catch {
    let message = "Feedivo MCP Server konnte die Datenbank nicht öffnen: \(error)\n"
    FileHandle.standardError.write(Data(message.utf8))
    exit(1)
}

let accessSettings = MCPServerSettingsStore(database: database.core)
let isAccessEnabled = (try? accessSettings.isEnabled()) ?? false
guard isAccessEnabled else {
    let message = """
        Feedivo MCP Server ist deaktiviert. Aktiviere ihn unter \
        Feedivo → Einstellungen → KI-Zugriff.\n
        """
    FileHandle.standardError.write(Data(message.utf8))
    exit(1)
}

let isWriteAccessEnabled = (try? accessSettings.isWriteAccessEnabled()) ?? false
var writableDatabase: FeedivoMCPServerWritableDatabase?
if isWriteAccessEnabled {
    do {
        writableDatabase = try FeedivoMCPServerWritableDatabase.open()
    } catch {
        let message = """
            Feedivo MCP Server: Schreibzugriff konnte nicht aktiviert werden (\(error)), \
            Server läuft nur lesend weiter.\n
            """
        FileHandle.standardError.write(Data(message.utf8))
    }
}

let server = Server(
    name: "feedivo-mcp-server",
    version: "1.0.0",
    capabilities: .init(
        tools: .init(listChanged: false)
    )
)

var availableTools: [Tool] = [
    ListFeedsTool.definition,
    ListFoldersTool.definition,
    ListTagsTool.definition,
    SearchArticlesTool.definition,
    GetArticleTool.definition,
    ListSmartFoldersTool.definition,
    GetSmartFolderArticlesTool.definition,
]

if let writableDatabase {
    availableTools.append(contentsOf: [
        UpdateArticleStatusTool.definition,
        AssignTagTool.definition,
        RemoveTagTool.definition,
    ])
}

await server.withMethodHandler(ListTools.self) { _ in
    .init(tools: availableTools)
}

await server.withMethodHandler(CallTool.self) { params in
    switch params.name {
    case "list_feeds":
        return try ListFeedsTool.call(database: database)
    case "list_folders":
        return try ListFoldersTool.call(database: database)
    case "list_tags":
        return try ListTagsTool.call(database: database)
    case "search_articles":
        return try SearchArticlesTool.call(database: database, arguments: params.arguments)
    case "get_article":
        return try GetArticleTool.call(database: database, arguments: params.arguments)
    case "list_smart_folders":
        return try ListSmartFoldersTool.call(database: database)
    case "get_smart_folder_articles":
        return try GetSmartFolderArticlesTool.call(database: database, arguments: params.arguments)
    case "update_article_status":
        guard let writableDatabase else {
            return .init(content: [.text("Schreibzugriff ist nicht aktiviert.")], isError: true)
        }
        return try UpdateArticleStatusTool.call(readDatabase: database, writeDatabase: writableDatabase, arguments: params.arguments)
    case "assign_tag":
        guard let writableDatabase else {
            return .init(content: [.text("Schreibzugriff ist nicht aktiviert.")], isError: true)
        }
        return try AssignTagTool.call(readDatabase: database, writeDatabase: writableDatabase, arguments: params.arguments)
    case "remove_tag":
        guard let writableDatabase else {
            return .init(content: [.text("Schreibzugriff ist nicht aktiviert.")], isError: true)
        }
        return try RemoveTagTool.call(readDatabase: database, writeDatabase: writableDatabase, arguments: params.arguments)
    default:
        return .init(content: [.text("Unbekanntes Tool: \(params.name)")], isError: true)
    }
}

let transport = StdioTransport()
try await server.start(transport: transport)
await server.waitUntilCompleted()
