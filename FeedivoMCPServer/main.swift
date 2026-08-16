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

// Verbindungsvermerk fuer den Einstellungen-Tab: haelt fest, wann zuletzt ein Client den Server
// startete und wie viele Werkzeuge er dabei bekam. Die Anzahl stammt bewusst aus der TATSAECHLICH
// aufgebauten Liste — weicht sie spaeter von den Schaltern ab, sitzt der Client noch auf einer
// veralteten Liste und muss neu gestartet werden.
// Spiegel-Kontrolle: `MCPToolInventory` sagt dem Einstellungen-Tab, wie viele Werkzeuge zu
// erwarten sind. Driftet die Zahl von dieser Liste ab, zeigt der Tab etwas Falsches an — der
// Start scheitert deswegen aber NICHT, ein nicht startender Server waere der groessere Schaden.
let erwarteteWerkzeuge = MCPToolInventory.expectedToolCount(
    isWriteAccessEnabled: writableDatabase != nil
)
if availableTools.count != erwarteteWerkzeuge {
    FileHandle.standardError.write(Data("""
    Warnung: \(availableTools.count) Werkzeuge registriert, MCPToolInventory erwartet \
    \(erwarteteWerkzeuge). Bitte MCPToolInventory anpassen.

    """.utf8))
}

FeedivoMCPServerConnectionRecorder.record(toolCount: availableTools.count)

await server.withMethodHandler(ListTools.self) { _ in
    .init(tools: availableTools)
}

await server.withMethodHandler(CallTool.self) { params in
    let result: CallTool.Result
    switch params.name {
    case "list_feeds":
        result = try ListFeedsTool.call(database: database)
    case "list_folders":
        result = try ListFoldersTool.call(database: database)
    case "list_tags":
        result = try ListTagsTool.call(database: database)
    case "search_articles":
        result = try SearchArticlesTool.call(database: database, arguments: params.arguments)
    case "get_article":
        result = try GetArticleTool.call(database: database, arguments: params.arguments)
    case "list_smart_folders":
        result = try ListSmartFoldersTool.call(database: database)
    case "get_smart_folder_articles":
        result = try GetSmartFolderArticlesTool.call(database: database, arguments: params.arguments)
    case "update_article_status":
        guard let writableDatabase else {
            result = .init(content: [.text("Schreibzugriff ist nicht aktiviert.")], isError: true)
            break
        }
        result = try UpdateArticleStatusTool.call(readDatabase: database, writeDatabase: writableDatabase, arguments: params.arguments)
    case "assign_tag":
        guard let writableDatabase else {
            result = .init(content: [.text("Schreibzugriff ist nicht aktiviert.")], isError: true)
            break
        }
        result = try AssignTagTool.call(readDatabase: database, writeDatabase: writableDatabase, arguments: params.arguments)
    case "remove_tag":
        guard let writableDatabase else {
            result = .init(content: [.text("Schreibzugriff ist nicht aktiviert.")], isError: true)
            break
        }
        result = try RemoveTagTool.call(readDatabase: database, writeDatabase: writableDatabase, arguments: params.arguments)
    default:
        result = .init(content: [.text("Unbekanntes Tool: \(params.name)")], isError: true)
    }

    if result.isError != true, MCPWriteNotifier.writeToolNames.contains(params.name) {
        MCPWriteNotifier.notifyDidWrite()
    }

    return result
}

let transport = StdioTransport()
try await server.start(transport: transport)
await server.waitUntilCompleted()
