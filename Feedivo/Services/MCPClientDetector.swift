import AppKit
import Foundation

/// In welcher Form ein Client seine MCP-Server notiert.
enum MCPClientConfigSchema: Equatable {
    /// Flaches `{"mcpServers": {"feedivo": {"command": "…"}}}` — Claude Desktop, Cursor, Windsurf.
    case mcpServers
    /// Wie `mcpServers`, nur unter dem Schlüssel `servers` — VS Code.
    case servers
    /// `{"context_servers": {"feedivo": {"command": {"path": "…", "args": []}}}}` — Zed.
    case contextServers
    /// Keine Datei, sondern ein Terminal-Befehl — Claude Code.
    case commandLine

    /// Der Schlüssel, unter dem die Servereinträge liegen. `nil` beim Terminal-Befehl.
    var rootKey: String? {
        switch self {
        case .mcpServers: return "mcpServers"
        case .servers: return "servers"
        case .contextServers: return "context_servers"
        case .commandLine: return nil
        }
    }
}

/// Ein KI-Client, der Feedivos MCP-Server einbinden kann.
struct MCPClient: Equatable, Identifiable {
    let id: String
    let displayName: String
    /// Absoluter Pfad zur Konfigurationsdatei; `nil` bei Clients ohne Datei (Claude Code).
    let configPath: String?
    let schema: MCPClientConfigSchema
    /// Ob die App laut LaunchServices installiert ist. Nur ein Hinweis für die Reihenfolge —
    /// nicht installierte Clients bleiben wählbar.
    let isInstalled: Bool

    /// Ob Feedivo den Eintrag selbst vornehmen darf.
    ///
    /// Bewusst nur bei `mcpServers`: VS Code und Zed erlauben Kommentare in ihren Dateien, ein
    /// JSON-Roundtrip würde sie stillschweigend löschen. Claude Code speichert in
    /// `~/.claude.json` den kompletten Zustand der Kommandozeilen-App — dort gehört
    /// `claude mcp add` hin, kein fremder Schreibzugriff.
    var supportsAutomaticEntry: Bool {
        schema == .mcpServers && configPath != nil
    }
}

/// Das Verzeichnis der unterstützten KI-Clients.
///
/// Die Installationsprüfung läuft über **LaunchServices** (`NSWorkspace.urlForApplication(
/// withBundleIdentifier:)`), nicht über einen Blick ins Dateisystem — Feedivo ist sandboxed und
/// darf weder `/Applications` noch `~/.cursor/` frei lesen. Aus demselben Grund kann hier NICHT
/// geprüft werden, ob eine Konfigurationsdatei existiert: Der Pfad ist eine Angabe, kein Befund.
enum MCPClientDetector {
    private struct Eintrag {
        let bundleIdentifier: String?
        let displayName: String
        let configPathComponents: [String]?
        let schema: MCPClientConfigSchema
    }

    /// Pfade und Schemata: Claude Desktop und VS Code wurden auf dem Entwicklungsrechner
    /// eingesehen, Cursor, Windsurf und Zed stammen aus einer Web-Recherche vom 2026-08-16 und
    /// sind gegen keine echte Installation geprüft. Die Bundle-Kennungen der letzten drei sind
    /// der unsicherste Teil — schlägt die Erkennung fehl, fehlt nur das Häkchen.
    private static let eintraege: [Eintrag] = [
        Eintrag(
            bundleIdentifier: "com.anthropic.claudefordesktop",
            displayName: "Claude Desktop",
            configPathComponents: ["Library", "Application Support", "Claude", "claude_desktop_config.json"],
            schema: .mcpServers
        ),
        Eintrag(
            bundleIdentifier: "com.todesktop.230313mzl4w4u92",
            displayName: "Cursor",
            configPathComponents: [".cursor", "mcp.json"],
            schema: .mcpServers
        ),
        Eintrag(
            bundleIdentifier: "com.exafunction.windsurf",
            displayName: "Windsurf",
            configPathComponents: [".codeium", "windsurf", "mcp_config.json"],
            schema: .mcpServers
        ),
        Eintrag(
            bundleIdentifier: "com.microsoft.VSCode",
            displayName: "VS Code",
            configPathComponents: ["Library", "Application Support", "Code", "User", "mcp.json"],
            schema: .servers
        ),
        Eintrag(
            bundleIdentifier: "dev.zed.Zed",
            displayName: "Zed",
            configPathComponents: [".config", "zed", "settings.json"],
            schema: .contextServers
        ),
        Eintrag(
            bundleIdentifier: nil,
            displayName: "Claude Code",
            configPathComponents: nil,
            schema: .commandLine
        ),
    ]

    /// Alle unterstützten Clients, installierte zuerst. Innerhalb beider Gruppen bleibt die
    /// Reihenfolge des Verzeichnisses erhalten, damit die Liste zwischen zwei Aufrufen stabil ist.
    static func allClients(
        lookup: (String) -> Bool = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
    ) -> [MCPClient] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let clients = eintraege.map { eintrag in
            MCPClient(
                id: eintrag.displayName,
                displayName: eintrag.displayName,
                configPath: eintrag.configPathComponents.map { komponenten in
                    komponenten.reduce(home) { $0.appendingPathComponent($1) }.path
                },
                schema: eintrag.schema,
                isInstalled: eintrag.bundleIdentifier.map(lookup) ?? false
            )
        }
        return clients.filter(\.isInstalled) + clients.filter { !$0.isInstalled }
    }
}
