import Foundation
import Testing
@testable import Feedivo

@Suite("MCPClientConfigSnippet")
struct MCPClientConfigSnippetTests {
    private let pfad = "/Applications/Feedivo.app/Contents/MacOS/FeedivoMCPServer"

    @Test("mcpServers-Schema erzeugt gueltiges JSON mit flachem command")
    func mcpServersErzeugtFlachesJSON() throws {
        let text = MCPClientConfigSnippet.text(for: .mcpServers, executablePath: pfad)

        let objekt = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        let server = (objekt?["mcpServers"] as? [String: Any])?["feedivo"] as? [String: Any]
        #expect(server?["command"] as? String == pfad)
    }

    @Test("servers-Schema nutzt denselben Aufbau unter anderem Schluessel")
    func serversNutztAnderenSchluessel() throws {
        let text = MCPClientConfigSnippet.text(for: .servers, executablePath: pfad)

        let objekt = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        #expect(objekt?["mcpServers"] == nil)
        let server = (objekt?["servers"] as? [String: Any])?["feedivo"] as? [String: Any]
        #expect(server?["command"] as? String == pfad)
    }

    @Test("context_servers-Schema verschachtelt den Befehl")
    func contextServersVerschachteltBefehl() throws {
        // Zed erwartet ein Objekt mit path und args statt eines flachen Strings.
        let text = MCPClientConfigSnippet.text(for: .contextServers, executablePath: pfad)

        let objekt = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        let server = (objekt?["context_servers"] as? [String: Any])?["feedivo"] as? [String: Any]
        let befehl = server?["command"] as? [String: Any]
        #expect(befehl?["path"] as? String == pfad)
        #expect((befehl?["args"] as? [String])?.isEmpty == true)
    }

    @Test("commandLine-Schema liefert einen Terminal-Befehl, kein JSON")
    func commandLineLiefertBefehl() {
        let text = MCPClientConfigSnippet.text(for: .commandLine, executablePath: pfad)

        #expect(text == "claude mcp add feedivo \(pfad)")
    }

    @Test("Der Schnipsel ist mehrzeilig und dadurch lesbar")
    func schnipselIstEingerueckt() {
        // Der Text wird zum Kopieren angeboten — eine einzige lange Zeile waere unbrauchbar.
        let text = MCPClientConfigSnippet.text(for: .mcpServers, executablePath: pfad)

        #expect(text.contains("\n"))
    }
}
