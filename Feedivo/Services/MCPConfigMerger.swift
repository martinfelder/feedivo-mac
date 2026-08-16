import Foundation

enum MCPConfigMergeError: Error, Equatable {
    /// Die vorhandene Datei ist kein gültiges JSON-Objekt — etwa weil sie Kommentare enthält.
    case invalidJSON
    /// Für dieses Schema gibt es keine Konfigurationsdatei (Claude Code).
    case unsupportedSchema
}

/// Fügt Feedivos Servereintrag in eine bestehende Client-Konfiguration ein.
///
/// Reine Funktion über `Data` — sie berührt kein Dateisystem und ist dadurch vollständig
/// testbar. Das Schreiben mitsamt Sicherungskopie übernimmt `MCPConfigWriter`.
///
/// **Alles außerhalb des eigenen Eintrags bleibt unangetastet.** Die Konfigurationsdateien der
/// Clients enthalten weit mehr als MCP-Server: In der `claude_desktop_config.json` dieses
/// Entwicklungsrechners standen daneben Fensterzustände, Ordnerfreigaben und Konten.
enum MCPConfigMerger {
    static func merged(
        existing: Data,
        schema: MCPClientConfigSchema,
        executablePath: String
    ) throws -> Data {
        guard let rootKey = schema.rootKey else { throw MCPConfigMergeError.unsupportedSchema }

        // Eine leere Datei ist kein Fehler, sondern der Normalfall bei noch nie genutzter
        // Konfiguration — auf diesem Rechner war die mcp.json von VS Code 0 Bytes gross.
        var wurzel: [String: Any]
        if existing.isEmpty {
            wurzel = [:]
        } else {
            guard let geparst = try? JSONSerialization.jsonObject(with: existing) as? [String: Any] else {
                throw MCPConfigMergeError.invalidJSON
            }
            wurzel = geparst
        }

        var server = wurzel[rootKey] as? [String: Any] ?? [:]
        server[MCPClientConfigSnippet.serverName] = eintrag(for: schema, executablePath: executablePath)
        wurzel[rootKey] = server

        // `sortedKeys` haelt das Ergebnis zwischen zwei Laeufen stabil, `prettyPrinted` haelt die
        // Datei fuer den Nutzer lesbar — er soll sie danach noch selbst bearbeiten koennen.
        return try JSONSerialization.data(
            withJSONObject: wurzel,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
    }

    private static func eintrag(for schema: MCPClientConfigSchema, executablePath: String) -> Any {
        switch schema {
        case .contextServers:
            return ["command": ["path": executablePath, "args": [String]()]]
        default:
            return ["command": executablePath]
        }
    }
}
