import Foundation
import Testing
@testable import Feedivo

@Suite("MCPConfigWriter")
struct MCPConfigWriterTests {
    private let pfad = "/Applications/Feedivo.app/Contents/MacOS/FeedivoMCPServer"

    /// Eigenes temporaeres Verzeichnis je Test — niemals ein echter Konfigurationsordner.
    private func temporaeresVerzeichnis() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-writer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Schreibt in eine noch nicht vorhandene Datei")
    func schreibtNeueDatei() throws {
        let ordner = try temporaeresVerzeichnis()
        defer { try? FileManager.default.removeItem(at: ordner) }
        let ziel = ordner.appendingPathComponent("mcp.json")

        try MCPConfigWriter.write(to: ziel, schema: .mcpServers, executablePath: pfad)

        let inhalt = try JSONSerialization.jsonObject(with: Data(contentsOf: ziel)) as? [String: Any]
        #expect((inhalt?["mcpServers"] as? [String: Any])?["feedivo"] != nil)
    }

    @Test("Legt vor dem Ueberschreiben eine Sicherungskopie an")
    func legtSicherungskopieAn() throws {
        let ordner = try temporaeresVerzeichnis()
        defer { try? FileManager.default.removeItem(at: ordner) }
        let ziel = ordner.appendingPathComponent("mcp.json")
        let original = #"{"mcpServers":{"anderer":{"command":"/usr/bin/andere"}}}"#
        try Data(original.utf8).write(to: ziel)

        try MCPConfigWriter.write(to: ziel, schema: .mcpServers, executablePath: pfad)

        let kopie = ordner.appendingPathComponent("mcp.json.feedivo-backup")
        #expect(FileManager.default.fileExists(atPath: kopie.path))
        #expect(try String(contentsOf: kopie, encoding: .utf8) == original)
    }

    @Test("Eine zweite Sicherungskopie ueberschreibt die erste")
    func zweiteSicherungskopieUeberschreibt() throws {
        // Sonst schluege jeder zweite Durchlauf fehl, weil die Kopie schon existiert.
        let ordner = try temporaeresVerzeichnis()
        defer { try? FileManager.default.removeItem(at: ordner) }
        let ziel = ordner.appendingPathComponent("mcp.json")
        try Data("{}".utf8).write(to: ziel)

        try MCPConfigWriter.write(to: ziel, schema: .mcpServers, executablePath: pfad)
        try MCPConfigWriter.write(to: ziel, schema: .mcpServers, executablePath: pfad)

        let inhalt = try JSONSerialization.jsonObject(with: Data(contentsOf: ziel)) as? [String: Any]
        #expect((inhalt?["mcpServers"] as? [String: Any])?["feedivo"] != nil)
    }

    @Test("Bei ungueltigem JSON bleibt die Originaldatei unveraendert")
    func ungueltigesJSONLaesstOriginalUnveraendert() throws {
        let ordner = try temporaeresVerzeichnis()
        defer { try? FileManager.default.removeItem(at: ordner) }
        let ziel = ordner.appendingPathComponent("settings.json")
        let original = "{ // Kommentar\n \"servers\": {} }"
        try Data(original.utf8).write(to: ziel)

        #expect(throws: MCPConfigMergeError.invalidJSON) {
            try MCPConfigWriter.write(to: ziel, schema: .servers, executablePath: pfad)
        }
        #expect(try String(contentsOf: ziel, encoding: .utf8) == original)
    }
}
