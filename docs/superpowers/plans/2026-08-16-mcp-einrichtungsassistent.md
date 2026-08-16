# Einrichtungsassistent für KI-Clients — Implementierungsplan

> **Für agentische Worker:** REQUIRED SUB-SKILL: Nutze superpowers:subagent-driven-development (empfohlen) oder superpowers:executing-plans, um diesen Plan Task für Task umzusetzen. Schritte nutzen Checkbox-Syntax (`- [ ]`).

**Goal:** Der Einrichtungsbereich des Tabs „KI-Zugriff" bietet ein Dropdown mit sechs KI-Clients, zeigt für den gewählten Client Pfad und passend formatierten Schnipsel, und trägt den Eintrag dort, wo das Format es sicher zulässt, nach Dateiauswahl selbst ein.

**Architecture:** Vier neue, isoliert testbare Bausteine: das erweiterte Client-Verzeichnis (`MCPClientDetector`), die Schnipsel-Erzeugung je Schema (`MCPClientConfigSnippet`), das Zusammenführen bestehender Konfigurationen (`MCPConfigMerger`, reine Funktion über `Data`) und das Schreiben mit Sicherungskopie (`MCPConfigWriter`, gegen ein echtes temporäres Verzeichnis testbar). Die View verdrahtet sie und steuert das `NSOpenPanel` bei.

**Tech Stack:** Swift 6, SwiftUI (macOS 14+), AppKit (`NSWorkspace`, `NSOpenPanel`, `NSPasteboard`), `JSONSerialization`, Swift Testing.

## Global Constraints

- Code-Kommentare und Testnamen auf **Deutsch** (Projektkonvention). UI-Texte laufen ausschließlich über `L10n`-Konstanten bzw. `String(localized:)` + `Localizable.xcstrings`, nie als rohe String-Literale in der View.
- **Feedivo ist sandboxed.** Es darf fremde Konfigurationsdateien weder lesen noch schreiben, bevor der Nutzer sie über ein `NSOpenPanel` freigegeben hat. Kein Task darf prüfen, ob eine Konfigurationsdatei existiert.
- **Keine Aussage über den Zustand fremder Dateien.** Der Pfad wird als Angabe gezeigt („hier gehört es hin"), nie als Befund („gefunden", „bereits eingetragen").
- **Nicht installierte Clients bleiben wählbar.** Die Bundle-Identifikatoren von Cursor, Windsurf und Zed sind unverifiziert; eine falsche Kennung darf einen Client höchstens das Häkchen kosten.
- **VS Code, Zed und Claude Code bekommen keinen Eintragen-Knopf.** Die ersten beiden erlauben Kommentare in ihren Dateien (ein JSON-Roundtrip würde sie löschen), Claude Code speichert in `~/.claude.json` den kompletten CLI-Zustand.
- Vor jedem Schreiben eine **Sicherungskopie**; schlägt sie fehl, wird gar nicht geschrieben.
- Tests immer gezielt mit **Suiten**-Selektoren (`-only-testing:FeedivoTests/<SuiteName>`) und `-parallel-testing-enabled NO`. Ein unscoped `xcodebuild test` deadlockt in diesem Projekt; ein Einzelmethoden-Selektor kann „TEST SUCCEEDED" bei `totalTestCount: 0` melden.
- Nach jedem Task müssen **beide** Schemes bauen: `Feedivo` und `FeedivoMCPServer`.
- SourceKit-/IDE-Diagnosen sind hier notorisch falsch („No such module 'GRDB'"). Nur echte `xcodebuild`-Läufe zählen.
- Neue `L10n`-Keys erzeugen **keinen** automatischen Eintrag in `Localizable.xcstrings`; jeder Key muss manuell ergänzt und per `grep -c` verifiziert werden (muss > 0 sein).
- `Localizable.xcstrings` **niemals** per `json.load`/`json.dump` roundtripen. Nur Text-Einfügung am Anker `  "strings" : {`, danach `git diff --stat` prüfen. Erscheinen dabei Tausende geänderte Zeilen, hat Xcode die Datei zwischenzeitlich selbst umformatiert — dann `git checkout -- Feedivo/Resources/Localizable.xcstrings`, Einfügung wiederholen, erneut prüfen (am 2026-08-16 genau so passiert).
- Alle `settings.mcpServer.*`-Keys haben vier Sprachen (de/en/fr/it) — neue Keys ebenso anlegen.

## Dateistruktur

| Datei | Verantwortung |
|---|---|
| `Feedivo/Services/MCPClientNameResolver.swift` | unverändert (Client-Name aus Prozesspfad, gehört zum Statusbereich) |
| `Feedivo/Services/MCPClientDetector.swift` | Client-Verzeichnis: alle Clients mit Pfad, Schema, Installationskennzeichen |
| `Feedivo/Services/MCPClientConfigSnippet.swift` (neu) | Schnipsel bzw. Terminal-Befehl je Schema |
| `Feedivo/Services/MCPConfigMerger.swift` (neu) | Bestehende Konfiguration + eigener Eintrag → neuer Dateiinhalt |
| `Feedivo/Services/MCPConfigWriter.swift` (neu) | Sicherungskopie anlegen, zusammengeführten Inhalt schreiben |
| `Feedivo/Views/Settings/SettingsView.swift` | Dropdown, Eintragen-Knopf, `NSOpenPanel` |
| `Feedivo/Resources/L10n.swift` + `Localizable.xcstrings` | Neue Texte |

---

### Task 1: Client-Verzeichnis

**Files:**
- Modify: `Feedivo/Services/MCPClientDetector.swift`
- Modify: `Feedivo/Views/Settings/SettingsView.swift` (nur die eine Aufrufstelle in `load()`)
- Test: `FeedivoTests/Services/MCPClientDetectorTests.swift`

**Interfaces:**
- Consumes: `NSWorkspace` (AppKit)
- Produces:
  - `enum MCPClientConfigSchema: Equatable { case mcpServers, servers, contextServers, commandLine }` mit `var rootKey: String?`
  - `struct MCPClient: Equatable, Identifiable { let id: String; let displayName: String; let configPath: String?; let schema: MCPClientConfigSchema; let isInstalled: Bool }`
  - `var MCPClient.supportsAutomaticEntry: Bool`
  - `static func MCPClientDetector.allClients(lookup: (String) -> Bool = …) -> [MCPClient]`

**Hinweis:** Die bisherige `installedClients(lookup:)` entfällt; ihre einzige Aufrufstelle
(`MCPServerSettingsView.load()`) wird in Schritt 4 mit umgestellt. `configPath` ist optional,
weil Claude Code keine Datei hat.

- [ ] **Schritt 1: Failing Tests schreiben**

`FeedivoTests/Services/MCPClientDetectorTests.swift` vollständig ersetzen durch:

```swift
import Foundation
import Testing
@testable import Feedivo

@Suite("MCPClientDetector")
struct MCPClientDetectorTests {
    @Test("Alle sechs unterstuetzten Clients erscheinen, auch nicht installierte")
    func alleClientsErscheinen() {
        // Nicht installierte Clients bleiben waehlbar: Die Bundle-Kennungen von Cursor,
        // Windsurf und Zed sind unverifiziert — eine veraltete Kennung darf einen Client
        // hoechstens das Haekchen kosten, nicht seine Verfuegbarkeit.
        let clients = MCPClientDetector.allClients { _ in false }

        #expect(clients.count == 6)
        #expect(clients.allSatisfy { !$0.isInstalled })
    }

    @Test("Installierte Clients stehen vorn")
    func installierteStehenVorn() {
        let clients = MCPClientDetector.allClients { $0 == "dev.zed.Zed" }

        #expect(clients.first?.displayName == "Zed")
        #expect(clients.first?.isInstalled == true)
        #expect(clients.dropFirst().allSatisfy { !$0.isInstalled })
    }

    @Test("Claude Desktop hat Pfad und flaches mcpServers-Schema")
    func claudeDesktopHatPfadUndSchema() {
        let claude = MCPClientDetector.allClients { _ in true }
            .first { $0.displayName == "Claude Desktop" }

        #expect(claude?.schema == .mcpServers)
        #expect(claude?.configPath?.hasSuffix("Claude/claude_desktop_config.json") == true)
        #expect(claude?.configPath?.hasPrefix("/") == true)
        #expect(claude?.supportsAutomaticEntry == true)
    }

    @Test("Zed nutzt context_servers und erlaubt kein automatisches Eintragen")
    func zedErlaubtKeinAutomatischesEintragen() {
        // Zeds settings.json darf Kommentare enthalten; ein JSON-Roundtrip wuerde sie loeschen.
        let zed = MCPClientDetector.allClients { _ in true }.first { $0.displayName == "Zed" }

        #expect(zed?.schema == .contextServers)
        #expect(zed?.supportsAutomaticEntry == false)
    }

    @Test("VS Code nutzt servers und erlaubt kein automatisches Eintragen")
    func vsCodeErlaubtKeinAutomatischesEintragen() {
        let code = MCPClientDetector.allClients { _ in true }.first { $0.displayName == "VS Code" }

        #expect(code?.schema == .servers)
        #expect(code?.supportsAutomaticEntry == false)
    }

    @Test("Claude Code hat keinen Pfad und gilt nie als installiert")
    func claudeCodeOhnePfad() {
        // Claude Code ist ein Kommandozeilenprogramm ohne App-Bundle — LaunchServices kennt es
        // nicht, es ist deshalb grundsaetzlich nicht erkennbar.
        let cli = MCPClientDetector.allClients { _ in true }
            .first { $0.displayName == "Claude Code" }

        #expect(cli?.configPath == nil)
        #expect(cli?.schema == .commandLine)
        #expect(cli?.isInstalled == false)
        #expect(cli?.supportsAutomaticEntry == false)
    }
}
```

- [ ] **Schritt 2: Test ausführen, Fehlschlag bestätigen**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/MCPClientDetectorTests 2>&1 | grep -E "error:|Test run with" | head -5
```

Erwartet: Compile-Fehler „type 'MCPClientDetector' has no member 'allClients'".

- [ ] **Schritt 3: Verzeichnis implementieren**

`Feedivo/Services/MCPClientDetector.swift` vollständig ersetzen durch:

```swift
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
```

- [ ] **Schritt 4: Aufrufstelle in der View anpassen**

In `Feedivo/Views/Settings/SettingsView.swift`, Methode `load()`, die Zeile

```swift
        detectedClient = MCPClientDetector.installedClients().first
```

ersetzen durch:

```swift
        detectedClient = MCPClientDetector.allClients().first
```

Das hält die Datei kompilierfähig; das Dropdown selbst kommt in Task 5.

- [ ] **Schritt 5: Tests grün und Builds prüfen**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/MCPClientDetectorTests 2>&1 | grep -E "Test run with|recorded an issue|error:" | head -4
```

Erwartet: PASS (6 Tests).

```bash
xcodebuild build -scheme Feedivo -configuration Debug 2>&1 | tail -2 && xcodebuild build -scheme FeedivoMCPServer -configuration Debug 2>&1 | tail -2
```

- [ ] **Schritt 6: Committen**

```bash
git add Feedivo/Services/MCPClientDetector.swift FeedivoTests/Services/MCPClientDetectorTests.swift Feedivo/Views/Settings/SettingsView.swift
git commit -m "feat(settings): Client-Verzeichnis mit Schema und Installationskennzeichen"
```

---

### Task 2: Schnipsel und Terminal-Befehl

**Files:**
- Create: `Feedivo/Services/MCPClientConfigSnippet.swift`
- Test: `FeedivoTests/Services/MCPClientConfigSnippetTests.swift` (neu)

**Interfaces:**
- Consumes: `MCPClientConfigSchema` (Task 1)
- Produces:
  - `static let MCPClientConfigSnippet.serverName = "feedivo"`
  - `static func MCPClientConfigSnippet.text(for schema: MCPClientConfigSchema, executablePath: String) -> String`

- [ ] **Schritt 1: Failing Tests schreiben**

Neue Datei `FeedivoTests/Services/MCPClientConfigSnippetTests.swift`:

```swift
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
```

- [ ] **Schritt 2: Test ausführen, Fehlschlag bestätigen**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/MCPClientConfigSnippetTests 2>&1 | grep -E "error:|Test run with" | head -5
```

Erwartet: Compile-Fehler „cannot find 'MCPClientConfigSnippet' in scope".

- [ ] **Schritt 3: Implementieren**

Neue Datei `Feedivo/Services/MCPClientConfigSnippet.swift`:

```swift
import Foundation

/// Erzeugt den Text, den der Nutzer in die Konfiguration seines KI-Clients übernimmt.
///
/// Bewusst von Hand zusammengesetzt statt über `JSONSerialization`: Der Text wird zum Kopieren
/// angeboten und soll so aussehen, wie ein Mensch ihn schreiben würde — mit Einrückung und in
/// stabiler Reihenfolge. `JSONSerialization` sortiert Schlüssel nicht verlässlich und liefert
/// ohne `.prettyPrinted` eine einzige Zeile.
enum MCPClientConfigSnippet {
    /// Der Name, unter dem Feedivo in der Konfiguration des Clients steht.
    static let serverName = "feedivo"

    static func text(for schema: MCPClientConfigSchema, executablePath: String) -> String {
        switch schema {
        case .commandLine:
            return "claude mcp add \(serverName) \(executablePath)"

        case .contextServers:
            return """
            {
              "context_servers": {
                "\(serverName)": {
                  "command": {
                    "path": "\(executablePath)",
                    "args": []
                  }
                }
              }
            }
            """

        case .mcpServers, .servers:
            // Beide unterscheiden sich nur im äußeren Schlüssel.
            let schluessel = schema.rootKey ?? "mcpServers"
            return """
            {
              "\(schluessel)": {
                "\(serverName)": { "command": "\(executablePath)" }
              }
            }
            """
        }
    }
}
```

- [ ] **Schritt 4: Tests grün**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/MCPClientConfigSnippetTests 2>&1 | grep -E "Test run with|recorded an issue|error:" | head -4
```

Erwartet: PASS (5 Tests).

- [ ] **Schritt 5: Committen**

```bash
git add Feedivo/Services/MCPClientConfigSnippet.swift FeedivoTests/Services/MCPClientConfigSnippetTests.swift
git commit -m "feat(settings): Konfigurationsschnipsel je Client-Schema"
```

---

### Task 3: Konfiguration zusammenführen

**Files:**
- Create: `Feedivo/Services/MCPConfigMerger.swift`
- Test: `FeedivoTests/Services/MCPConfigMergerTests.swift` (neu)

**Interfaces:**
- Consumes: `MCPClientConfigSchema` (Task 1), `MCPClientConfigSnippet.serverName` (Task 2)
- Produces:
  - `enum MCPConfigMergeError: Error, Equatable { case invalidJSON, unsupportedSchema }`
  - `static func MCPConfigMerger.merged(existing: Data, schema: MCPClientConfigSchema, executablePath: String) throws -> Data`

- [ ] **Schritt 1: Failing Tests schreiben**

Neue Datei `FeedivoTests/Services/MCPConfigMergerTests.swift`:

```swift
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
```

- [ ] **Schritt 2: Test ausführen, Fehlschlag bestätigen**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/MCPConfigMergerTests 2>&1 | grep -E "error:|Test run with" | head -5
```

Erwartet: Compile-Fehler „cannot find 'MCPConfigMerger' in scope".

- [ ] **Schritt 3: Implementieren**

Neue Datei `Feedivo/Services/MCPConfigMerger.swift`:

```swift
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
```

- [ ] **Schritt 4: Tests grün**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/MCPConfigMergerTests 2>&1 | grep -E "Test run with|recorded an issue|error:" | head -4
```

Erwartet: PASS (7 Tests).

- [ ] **Schritt 5: Committen**

```bash
git add Feedivo/Services/MCPConfigMerger.swift FeedivoTests/Services/MCPConfigMergerTests.swift
git commit -m "feat(settings): Client-Konfiguration zusammenfuehren ohne fremde Schluessel zu verlieren"
```

---

### Task 4: Schreiben mit Sicherungskopie

**Files:**
- Create: `Feedivo/Services/MCPConfigWriter.swift`
- Test: `FeedivoTests/Services/MCPConfigWriterTests.swift` (neu)

**Interfaces:**
- Consumes: `MCPConfigMerger.merged(existing:schema:executablePath:)` und `MCPConfigMergeError` (Task 3)
- Produces:
  - `static let MCPConfigWriter.backupSuffix = ".feedivo-backup"`
  - `static func MCPConfigWriter.write(to url: URL, schema: MCPClientConfigSchema, executablePath: String) throws`

**Warum gegen echte Dateien getestet wird:** Die Sicherungskopie ist der Kern dieses Bausteins;
ein Test gegen eine Attrappe würde genau das nicht prüfen. Die Tests arbeiten in einem eigenen
temporären Verzeichnis, das sie danach wieder entfernen — nie in echten Konfigurationsordnern.

- [ ] **Schritt 1: Failing Tests schreiben**

Neue Datei `FeedivoTests/Services/MCPConfigWriterTests.swift`:

```swift
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
```

- [ ] **Schritt 2: Test ausführen, Fehlschlag bestätigen**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/MCPConfigWriterTests 2>&1 | grep -E "error:|Test run with" | head -5
```

Erwartet: Compile-Fehler „cannot find 'MCPConfigWriter' in scope".

- [ ] **Schritt 3: Implementieren**

Neue Datei `Feedivo/Services/MCPConfigWriter.swift`:

```swift
import Foundation

/// Schreibt Feedivos Servereintrag in die Konfigurationsdatei eines KI-Clients.
///
/// Der Aufrufer muss die Datei zuvor über ein `NSOpenPanel` vom Nutzer freigeben lassen — ohne
/// diese Freigabe verweigert die App-Sandbox jeden Zugriff auf fremde Konfigurationsordner.
///
/// Reihenfolge ist Absicht: erst lesen, dann zusammenführen, dann sichern, erst zuletzt
/// schreiben. Schlägt einer der Schritte fehl, bleibt die Originaldatei unangetastet.
enum MCPConfigWriter {
    /// Endung der Sicherungskopie, die neben der Originaldatei entsteht.
    static let backupSuffix = ".feedivo-backup"

    static func write(to url: URL, schema: MCPClientConfigSchema, executablePath: String) throws {
        // Eine noch nicht vorhandene Datei ist kein Fehler — dann wird sie neu angelegt.
        let vorhanden = (try? Data(contentsOf: url)) ?? Data()

        let neu = try MCPConfigMerger.merged(
            existing: vorhanden,
            schema: schema,
            executablePath: executablePath
        )

        if !vorhanden.isEmpty {
            // Ueberschreibt eine aeltere Kopie bewusst: Sonst schluege jeder zweite Durchlauf
            // fehl, und die interessante Sicherung ist die vom letzten Stand.
            try vorhanden.write(to: url.appendingPathExtension(String(backupSuffix.dropFirst())))
        }

        try neu.write(to: url)
    }
}
```

- [ ] **Schritt 4: Tests grün**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/MCPConfigWriterTests 2>&1 | grep -E "Test run with|recorded an issue|error:" | head -4
```

Erwartet: PASS (4 Tests).

Schlägt `legtSicherungskopieAn` fehl, weil die Kopie `mcp.json.feedivo-backup` nicht gefunden
wird, prüfen, was `appendingPathExtension` tatsächlich erzeugt hat — der Test erwartet exakt
`<dateiname>.feedivo-backup`.

- [ ] **Schritt 5: Committen**

```bash
git add Feedivo/Services/MCPConfigWriter.swift FeedivoTests/Services/MCPConfigWriterTests.swift
git commit -m "feat(settings): Konfiguration schreiben mit Sicherungskopie"
```

---

### Task 5: Dropdown und Eintragen-Knopf

**Files:**
- Modify: `Feedivo/Views/Settings/SettingsView.swift` (`MCPServerSettingsView`)
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `MCPClientDetector.allClients()` (Task 1), `MCPClientConfigSnippet.text(for:executablePath:)` (Task 2), `MCPConfigWriter.write(to:schema:executablePath:)` (Task 4)
- Produces: nichts für spätere Tasks

- [ ] **Schritt 1: Neue L10n-Keys anlegen**

In `Feedivo/Resources/L10n.swift` nach `settingsMCPServerStatusRowTitle`:

```swift
    static let settingsMCPServerClientPickerLabel = LocalizedStringKey("settings.mcpServer.clientPicker")
    static let settingsMCPServerEnterButton = LocalizedStringKey("settings.mcpServer.enterButton")
    static let settingsMCPServerStepRun = LocalizedStringKey("settings.mcpServer.step.run")
```

Katalogeinträge per Text-Einfügung am Anker `  "strings" : {`, alle vier Sprachen. Die beiden
letzten Schlüssel werden über `String(localized:)` gelesen und brauchen deshalb keine
`L10n`-Konstante:

| Schlüssel | de | en | fr | it |
|---|---|---|---|---|
| `settings.mcpServer.clientPicker` | `KI-Client` | `AI client` | `Client IA` | `Client IA` |
| `settings.mcpServer.enterButton` | `Automatisch eintragen…` | `Enter automatically…` | `Saisir automatiquement…` | `Inserisci automaticamente…` |
| `settings.mcpServer.step.run` | `2. Befehl im Terminal ausführen` | `2. Run the command in Terminal` | `2. Exécuter la commande dans le Terminal` | `2. Esegui il comando nel Terminale` |
| `settings.mcpServer.installedSuffix` | `(installiert)` | `(installed)` | `(installé)` | `(installato)` |
| `settings.mcpServer.enterSuccess` | `Eingetragen. Eine Sicherungskopie der bisherigen Datei liegt daneben.` | `Entered. A backup of the previous file is next to it.` | `Saisi. Une copie de sauvegarde du fichier précédent se trouve à côté.` | `Inserito. Una copia di backup del file precedente si trova accanto.` |

Der bestehende Schlüssel `settings.mcpServer.noClientFound` wird nicht mehr verwendet
(nicht installierte Clients bleiben ja wählbar). Konstante und Katalogeintrag **bleiben
bestehen** — Entfernen wäre eigener Scope.

Verifizieren:

```bash
for k in clientPicker enterButton step.run installedSuffix enterSuccess; do echo -n "$k: "; grep -c "settings.mcpServer.$k\"" Feedivo/Resources/Localizable.xcstrings; done; git diff --stat Feedivo/Resources/Localizable.xcstrings
```

Erwartet: jeweils ≥ 1, im Diff nahezu ausschließlich Insertions. Erscheinen Tausende geänderte
Zeilen, hat Xcode die Datei zwischenzeitlich umformatiert — dann `git checkout --` auf die Datei
und die Einfügung wiederholen.

- [ ] **Schritt 2: State umstellen**

In `MCPServerSettingsView` die Zeile

```swift
    @State private var detectedClient: MCPClient?
```

ersetzen durch:

```swift
    @State private var clients: [MCPClient] = []
    @State private var selectedClientID: String?
    @State private var enterResultMessage: String?
```

In `load()` die Zeile `detectedClient = MCPClientDetector.allClients().first` ersetzen durch:

```swift
        clients = MCPClientDetector.allClients()
        // Vorausgewaehlt ist der erste installierte Client; `allClients()` sortiert installierte
        // nach vorn, der erste Eintrag ist also die beste Vermutung.
        selectedClientID = clients.first?.id
```

- [ ] **Schritt 3: Einrichtungsbereich umbauen**

Den kompletten Block von `if let detectedClient {` bis zu dessen `}` (einschließlich des
`else`-Zweigs mit `GeneralSettingsHelp(L10n.settingsMCPServerNoClientFound)`) ersetzen durch:

```swift
                if let client = selectedClient {
                    GeneralSettingsRow(title: L10n.settingsMCPServerConnectionRowTitle) {
                        Picker(L10n.settingsMCPServerClientPickerLabel, selection: $selectedClientID) {
                            ForEach(clients) { eintrag in
                                Text(verbatim: clientLabel(eintrag)).tag(Optional(eintrag.id))
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 220)
                    }

                    Text(L10n.settingsMCPServerStepCopy)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(configSnippet(for: client))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    HStack(spacing: 8) {
                        Button(L10n.settingsMCPServerCopyButton) {
                            copyToPasteboard(configSnippet(for: client))
                        }
                        if client.supportsAutomaticEntry {
                            Button(L10n.settingsMCPServerEnterButton) {
                                enterConfiguration(for: client)
                            }
                        }
                    }

                    if let configPath = client.configPath {
                        Text(L10n.settingsMCPServerStepPaste)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text(verbatim: configPath)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    } else {
                        // Claude Code hat keine Datei — der Befehl aus Schritt 1 wird direkt
                        // im Terminal ausgefuehrt.
                        Text(L10n.settingsMCPServerStepRun)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Text(L10n.settingsMCPServerStepRestart)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    if let enterResultMessage {
                        Text(verbatim: enterResultMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
```

- [ ] **Schritt 4: Hilfsfunktionen ergänzen**

Die bestehende private Property `configSnippet` (die fest das Claude-Desktop-Format erzeugte)
**entfernen** und stattdessen neben `reloadActiveSessions()` einfügen:

```swift
    private var selectedClient: MCPClient? {
        clients.first { $0.id == selectedClientID } ?? clients.first
    }

    private func clientLabel(_ client: MCPClient) -> String {
        guard client.isInstalled else { return client.displayName }
        return "\(client.displayName) \(String(localized: "settings.mcpServer.installedSuffix"))"
    }

    private func configSnippet(for client: MCPClient) -> String {
        MCPClientConfigSnippet.text(for: client.schema, executablePath: mcpServerExecutablePath)
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Öffnet die Dateiauswahl auf der Konfigurationsdatei des Clients. Erst die Bestätigung des
    /// Nutzers verschafft Feedivo Schreibrecht — die Sandbox lässt keinen anderen Weg zu.
    private func enterConfiguration(for client: MCPClient) {
        guard let configPath = client.configPath else { return }

        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: configPath).deletingLastPathComponent()
        panel.nameFieldStringValue = URL(fileURLWithPath: configPath).lastPathComponent
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        // Ohne das bleiben Ordner wie ~/.cursor unsichtbar.
        panel.showsHiddenFiles = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try MCPConfigWriter.write(
                to: url,
                schema: client.schema,
                executablePath: mcpServerExecutablePath
            )
            enterResultMessage = String(localized: "settings.mcpServer.enterSuccess")
        } catch {
            enterResultMessage = error.localizedDescription
        }
    }
```

Die bestehende Methode `copyConfigSnippet()` wird durch `copyToPasteboard(_:)` ersetzt — mit

```bash
grep -n "copyConfigSnippet" Feedivo/Views/Settings/SettingsView.swift
```

prüfen, ob sie noch woanders aufgerufen wird, und diese Stellen mit umstellen.

- [ ] **Schritt 5: Build und Source-Sniffing-Tests prüfen**

```bash
xcodebuild build -scheme Feedivo -configuration Debug 2>&1 | grep -E "error:|BUILD" | tail -3
```

Meldet der Compiler „unable to type-check this expression in reasonable time", den
Einrichtungsbereich in eine eigene private `@ViewBuilder`-Property `setupSection` auslagern und
im `body` nur diese aufrufen.

```bash
grep -n "mcpServer\|MCPServer" FeedivoTests/App/FeedivoAppSceneConfigurationTests.swift
```

Trifft eine Assertion einen geänderten Ausdruck, auf den neuen Wortlaut anpassen — nicht die
View-Struktur zurückbauen.

- [ ] **Schritt 6: Committen**

```bash
git add Feedivo/Views/Settings/SettingsView.swift Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings
git commit -m "feat(settings): Client-Auswahl mit Anleitung und automatischem Eintragen"
```

---

### Task 6: Abschluss

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Schritt 1: Regressionslauf**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/MCPClientDetectorTests -only-testing:FeedivoTests/MCPClientConfigSnippetTests -only-testing:FeedivoTests/MCPConfigMergerTests -only-testing:FeedivoTests/MCPConfigWriterTests -only-testing:FeedivoTests/MCPClientNameResolverTests -only-testing:FeedivoTests/MCPConnectionStatusTextTests -only-testing:FeedivoTests/MCPServerSessionStoreTests 2>&1 | grep -E "Test run with|recorded an issue" | head -3
```

Erwartet: alle grün.

- [ ] **Schritt 2: Release-Builds**

```bash
xcodebuild build -scheme Feedivo -configuration Release 2>&1 | tail -2 && xcodebuild build -scheme FeedivoMCPServer -configuration Release 2>&1 | tail -2
```

- [ ] **Schritt 3: Eintrag unter „Aktuell in Arbeit" in `CLAUDE.md`**

Inhalt: die sechs unterstützten Clients mit ihren drei Schema-Varianten; dass Pfade und Formate
von Cursor, Windsurf und Zed aus einer Web-Recherche vom 2026-08-16 stammen und deren
Bundle-Kennungen unverifiziert sind; dass die Sandbox verbietet zu prüfen, ob eine
Konfigurationsdatei existiert (daher „hier gehört es hin" statt „gefunden"); warum VS Code, Zed
und Claude Code bewusst keinen Eintragen-Knopf haben (Kommentare in der Datei bzw. kompletter
CLI-Zustand in `~/.claude.json`); und dass vor jedem Schreiben eine Sicherungskopie
`<datei>.feedivo-backup` entsteht.

Ausstehende manuelle Verifikation:

1. Dropdown zeigt sechs Clients, installierte oben mit „(installiert)".
2. Wechsel des Clients ändert Schnipsel **und** Pfad; bei Zed erscheint das verschachtelte
   `command`-Objekt, bei VS Code der Schlüssel `servers`, bei Claude Code der Terminal-Befehl.
3. „Automatisch eintragen…" erscheint nur bei Claude Desktop, Cursor und Windsurf.
4. Eintragen bei Claude Desktop: Dateiauswahl öffnet im richtigen Ordner, nach Bestätigung steht
   der Eintrag in der Datei, die übrigen Schlüssel sind unverändert, und daneben liegt
   `claude_desktop_config.json.feedivo-backup`.
5. Abbrechen der Dateiauswahl hinterlässt keine Meldung und ändert nichts.

- [ ] **Schritt 4: Committen**

```bash
git add CLAUDE.md
git commit -m "docs: Einrichtungsassistent in CLAUDE.md dokumentiert"
```

- [ ] **Schritt 5: Push-Entscheidung vorlegen**

Laut Projektkonvention **nie ohne ausdrückliche Bestätigung** pushen. Dem Nutzer die
Commit-Anzahl und die fünf offenen Verifikationspunkte melden.

---

## Self-Review

**Spec-Abdeckung:** Client-Verzeichnis mit sechs Einträgen, Schema und Installationskennzeichen → Task 1 ✔; nicht installierte bleiben wählbar → Task 1, Test `alleClientsErscheinen` ✔; Claude Code ohne Pfad und nie installiert → Task 1 ✔; Schnipsel je Schema samt Terminal-Befehl → Task 2 ✔; Zusammenführen mit Erhalt fremder Schlüssel, Ersetzen des eigenen Eintrags, Fehler bei ungültigem JSON → Task 3 ✔; Sicherungskopie vor dem Schreiben und unveränderte Originaldatei im Fehlerfall → Task 4 ✔; Dropdown mit Vorauswahl, Kopier-Weg für alle, Eintragen-Knopf nur bei `mcpServers` → Task 5 ✔; Dateiauswahl als einziger Weg zum Schreibrecht → Task 5, `enterConfiguration` ✔; Abbruch ohne Meldung → Task 5 (`guard panel.runModal() == .OK`) ✔; kein Task prüft die Existenz einer fremden Datei ✔; kein Task berührt die Out-of-Scope-Punkte (Eintrag entfernen, Client neu starten, Codex/ChatGPT/Ollama/Warp, projektbezogene Konfigurationen) ✔.

**Placeholder-Scan:** Keine „TBD"/„später"-Verweise; alle Codeblöcke vollständig; alle UI-Texte im Wortlaut mit allen vier Sprachen; für beide vorhersehbaren Probleme (Typprüfungs-Timeout, von Xcode umformatierter String-Katalog) steht die konkrete Ausweichlösung im jeweiligen Schritt.

**Typ-Konsistenz:** `MCPClientConfigSchema` mit seinen vier Fällen und `rootKey` (Task 1) wird in Task 2, 3 und 5 unverändert verwendet. `MCPClient` (Task 1) liefert `id`, `displayName`, `configPath`, `schema`, `isInstalled`, `supportsAutomaticEntry` — alle sechs werden in Task 5 genutzt. `MCPClientConfigSnippet.serverName` (Task 2) wird von Task 3 mitverwendet, sodass Schnipsel und automatischer Eintrag denselben Schlüssel `feedivo` schreiben. `MCPConfigMergeError` (Task 3) wird in Task 4 im Test erwartet. `MCPConfigWriter.write(to:schema:executablePath:)` (Task 4) passt zur Nutzung in Task 5.

**Bekannte Einschränkung:** Die Bundle-Kennungen von Cursor (`com.todesktop.230313mzl4w4u92`), Windsurf (`com.exafunction.windsurf`) und Zed (`dev.zed.Zed`) sind nicht verifizierbar, solange diese Programme auf dem Entwicklungsrechner fehlen. Eine falsche Kennung kostet den betroffenen Client nur das „(installiert)"-Kennzeichen; er bleibt wählbar und sein Schnipsel bleibt korrekt.
