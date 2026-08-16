import Foundation
import Testing
@testable import Feedivo

@Suite("MCPConfigMerger")
struct MCPConfigMergerTests {
    private let pfad = "/Applications/Feedivo.app/Contents/MacOS/FeedivoMCPServer"

    private func objekt(aus data: Data) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    @Test("Eine leere Datei ergibt ein neues Objekt mit einem Eintrag")
    func leereDateiErgibtNeuesObjekt() throws {
        // Tritt real auf: Die mcp.json von VS Code war auf dem Entwicklungsrechner 0 Bytes gross.
        let ergebnis = try MCPConfigMerger.merged(existing: Data(), schema: .mcpServers, executablePath: pfad)

        let server = (try objekt(aus: ergebnis)["mcpServers"] as? [String: Any])?["feedivo"] as? [String: Any]
        #expect(server?["command"] as? String == pfad)
    }

    @Test("Fremde Schluessel bleiben unangetastet")
    func fremdeSchluesselBleibenErhalten() throws {
        // Die claude_desktop_config.json enthaelt neben MCP-Eintraegen auch Fensterzustaende,
        // Ordnerfreigaben und Konten — nichts davon darf verlorengehen.
        let vorher = Data("""
        {"mcpServers":{"anderer":{"command":"/usr/bin/andere"}},"preferences":{"sidebarMode":"epitaxy"}}
        """.utf8)

        let ergebnis = try MCPConfigMerger.merged(existing: vorher, schema: .mcpServers, executablePath: pfad)

        let d = try objekt(aus: ergebnis)
        #expect((d["preferences"] as? [String: Any])?["sidebarMode"] as? String == "epitaxy")
        let server = d["mcpServers"] as? [String: Any]
        #expect(server?["anderer"] != nil)
        #expect(server?["feedivo"] != nil)
    }

    @Test("Ein vorhandener feedivo-Eintrag wird ersetzt")
    func vorhandenerEintragWirdErsetzt() throws {
        // Der Pfad aendert sich real — etwa beim Wechsel von einem Entwicklungs- auf einen
        // Installationsordner.
        let vorher = Data("""
        {"mcpServers":{"feedivo":{"command":"/alter/pfad"}}}
        """.utf8)

        let ergebnis = try MCPConfigMerger.merged(existing: vorher, schema: .mcpServers, executablePath: pfad)

        let server = (try objekt(aus: ergebnis)["mcpServers"] as? [String: Any])?["feedivo"] as? [String: Any]
        #expect(server?["command"] as? String == pfad)
    }

    @Test("Das servers-Schema legt unter dem eigenen Schluessel an")
    func serversSchemaNutztEigenenSchluessel() throws {
        let ergebnis = try MCPConfigMerger.merged(existing: Data(), schema: .servers, executablePath: pfad)

        let d = try objekt(aus: ergebnis)
        #expect(d["mcpServers"] == nil)
        #expect((d["servers"] as? [String: Any])?["feedivo"] != nil)
    }

    @Test("Das context_servers-Schema verschachtelt den Befehl")
    func contextServersVerschachtelt() throws {
        let ergebnis = try MCPConfigMerger.merged(existing: Data(), schema: .contextServers, executablePath: pfad)

        let server = (try objekt(aus: ergebnis)["context_servers"] as? [String: Any])?["feedivo"] as? [String: Any]
        #expect((server?["command"] as? [String: Any])?["path"] as? String == pfad)
    }

    @Test("Ungueltiges JSON fuehrt zu einem Fehler, nicht zu einem Rateversuch")
    func ungueltigesJSONWirftFehler() {
        // Genau dieser Fall tritt bei Dateien mit Kommentaren auf (VS Code, Zed). Lieber
        // abbrechen als eine fremde Konfiguration ueberschreiben.
        let vorher = Data("""
        { // Kommentar
          "servers": {} }
        """.utf8)

        #expect(throws: MCPConfigMergeError.invalidJSON) {
            try MCPConfigMerger.merged(existing: vorher, schema: .servers, executablePath: pfad)
        }
    }

    @Test("Das commandLine-Schema hat keine Datei und wird abgelehnt")
    func commandLineWirdAbgelehnt() {
        #expect(throws: MCPConfigMergeError.unsupportedSchema) {
            try MCPConfigMerger.merged(existing: Data(), schema: .commandLine, executablePath: pfad)
        }
    }
}
