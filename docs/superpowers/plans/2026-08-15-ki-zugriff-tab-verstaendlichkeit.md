# KI-Zugriff-Tab verständlicher gestalten — Implementierungsplan

> **Für agentische Worker:** REQUIRED SUB-SKILL: Nutze superpowers:subagent-driven-development (empfohlen) oder superpowers:executing-plans, um diesen Plan Task für Task umzusetzen. Schritte nutzen Checkbox-Syntax (`- [ ]`).

**Goal:** Der Einstellungen-Tab „KI-Zugriff" erklärt in Alltagssprache, was er tut, führt in drei nummerierten Schritten durch die Einrichtung des erkannten KI-Clients und zeigt, wann zuletzt eine Verbindung bestand und mit welchem Funktionsumfang.

**Architecture:** Drei neue, isoliert testbare Bausteine — `MCPClientDetector` (Client-Erkennung über LaunchServices), zwei neue Spalten auf `mcp_server_settings` samt Store-Methoden (Verbindungsvermerk), und `MCPConnectionStatusText` (reine Textformatierung). `MCPServerSettingsView` verdrahtet sie zu drei Bereichen; der Server schreibt den Vermerk bei jedem Start.

**Tech Stack:** Swift 6, SwiftUI (macOS 14+), AppKit (`NSWorkspace`), GRDB/SQLite, Swift Testing.

## Global Constraints

- Code-Kommentare und Testnamen auf **Deutsch** (Projektkonvention). UI-Texte laufen ausschließlich über `L10n`-Konstanten bzw. `String(localized:)` + `Localizable.xcstrings`, nie als rohe String-Literale in der View.
- Neue Migrationen werden **immer angehängt**, bestehende nie geändert. Letzte Migration ist `v34_cleanup_orphaned_article_status_pending_changes` — vor dem Anlegen mit `grep -n registerMigration Feedivo/Database/FeedivoDatabaseMigrator.swift` gegenprüfen, nicht dieser Zeile vertrauen.
- **Nur Claude Desktop** wird als Client unterstützt (`com.anthropic.claudefordesktop`). ChatGPT und Ollama sind auf dem Rechner installiert, werden aber bewusst **nicht** erkannt — für sie ist kein Konfigurationsweg gesichert.
- Die Erkennung läuft über `NSWorkspace.urlForApplication(withBundleIdentifier:)` (LaunchServices), **niemals** über Dateizugriff auf `/Applications` — Feedivo ist sandboxed.
- Der Server schreibt den Verbindungsvermerk **unabhängig vom Schreibzugriff-Schalter**. Die Zusage „rein lesend" gilt weiterhin uneingeschränkt für Inhalte (Artikel, Tags, Status, Feeds).
- Ein fehlgeschlagener Verbindungsvermerk darf den Serverstart **nie** blockieren.
- Tests immer gezielt mit **Suiten**-Selektoren (`-only-testing:FeedivoTests/<SuiteName>`) und `-parallel-testing-enabled NO`. Ein unscoped `xcodebuild test` deadlockt in diesem Projekt; ein Einzelmethoden-Selektor kann „TEST SUCCEEDED" bei `totalTestCount: 0` melden.
- Nach jedem Task müssen **beide** Schemes bauen: `Feedivo` und `FeedivoMCPServer`.
- SourceKit-/IDE-Diagnosen sind hier notorisch falsch („No such module 'GRDB'"). Nur echte `xcodebuild`-Läufe zählen.
- Neue `L10n`-Keys erzeugen **keinen** automatischen Eintrag in `Localizable.xcstrings` (nur direkte String-Literale tun das). Jeder neue Key muss manuell ergänzt und mit `grep -c "<punkt.key>" Feedivo/Resources/Localizable.xcstrings` verifiziert werden (muss > 0 sein).
- `Localizable.xcstrings` **niemals** per `json.load`/`json.dump` roundtripen — das formatiert die ~31000-Zeilen-Datei um. Nur Text-Einfügung an einem stabilen Anker, danach `git diff --stat` prüfen (nahezu nur Insertions).

## Dateistruktur

| Datei | Verantwortung |
|---|---|
| `Feedivo/Services/MCPClientDetector.swift` (neu) | Welche unterstützten KI-Clients sind installiert, und wo liegt ihre Konfiguration? |
| `Feedivo/Services/MCPConnectionStatusText.swift` (neu) | Aus Zeitstempel + Werkzeug-Anzahl + Schreibzugriff einen Anzeigetext bauen |
| `Feedivo/Stores/MCPServerSettingsStore.swift` | Zusätzlich: Verbindungsvermerk lesen/schreiben |
| `Feedivo/Database/FeedivoDatabaseMigrator.swift` | Migration v35 |
| `FeedivoMCPServer/FeedivoMCPServerConnectionRecorder.swift` (neu) | Eigene, kurzlebige Schreibverbindung für den Vermerk |
| `FeedivoMCPServer/main.swift` | Vermerk beim Start auslösen |
| `Feedivo/Views/Settings/SettingsView.swift` | `MCPServerSettingsView` in drei Bereiche umbauen |
| `Feedivo/Resources/L10n.swift` + `Localizable.xcstrings` | Neue und geänderte Texte |

---

### Task 1: Migration v35 + Verbindungsvermerk im Store

**Files:**
- Modify: `Feedivo/Database/FeedivoDatabaseMigrator.swift` (neuer Block nach `v34_cleanup_orphaned_article_status_pending_changes`, vor `return migrator`)
- Modify: `Feedivo/Stores/MCPServerSettingsStore.swift`
- Test: `FeedivoTests/Database/FeedivoDatabaseMigratorTests.swift`
- Test: `FeedivoTests/Stores/MCPServerSettingsStoreTests.swift`

**Interfaces:**
- Consumes: `FeedivoDatabase`, bestehende Tabelle `mcp_server_settings` (Single-Row, `id = 1`)
- Produces:
  - `struct MCPConnectionRecord: Equatable { let connectedAt: Date; let toolCount: Int }`
  - `func lastConnection() throws -> MCPConnectionRecord?` — `nil`, wenn nie verbunden
  - `func recordConnection(at date: Date, toolCount: Int) throws`
  - Migration `"v35_add_mcp_server_last_connection"`

- [ ] **Schritt 1: Failing Test für die Migration**

Ans Ende der Suite in `FeedivoTests/Database/FeedivoDatabaseMigratorTests.swift`:

```swift
    @Test func migrationV35FuegtVerbindungsspaltenHinzu() throws {
        let queue = try DatabaseQueue()
        try FeedivoDatabaseMigrator.migrator.migrate(queue, upTo: "v34_cleanup_orphaned_article_status_pending_changes")

        try FeedivoDatabaseMigrator.migrator.migrate(queue)

        // Beide Spalten sind bewusst nullable: "noch nie verbunden" ist ein eigener,
        // anzuzeigender Zustand und darf nicht als "verbunden am 1.1.1970" erscheinen.
        let zeile = try queue.read { db in
            try Row.fetchOne(db, sql: "SELECT lastConnectedAt, lastConnectedToolCount FROM mcp_server_settings WHERE id = 1")
        }
        #expect(zeile != nil)
        #expect(zeile?["lastConnectedAt"] == nil)
        #expect(zeile?["lastConnectedToolCount"] == nil)
    }
```

- [ ] **Schritt 2: Test ausführen, Fehlschlag bestätigen**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/FeedivoDatabaseMigratorTests 2>&1 | grep -E "Test run with|recorded an issue|error:" | head -5
```

Erwartet: FAIL — „no such column: lastConnectedAt".

- [ ] **Schritt 3: Migration implementieren**

In `Feedivo/Database/FeedivoDatabaseMigrator.swift` nach dem v34-Block, vor `return migrator`:

```swift
        migrator.registerMigration("v35_add_mcp_server_last_connection") { database in
            // Verbindungsnachweis fuer den Einstellungen-Tab "KI-Zugriff": Der Nutzer konnte
            // bisher nicht erkennen, ob je ein KI-Client verbunden war. Am 2026-08-15 lief ein
            // Serverprozess stundenlang mit einer veralteten Werkzeugliste (7 statt 10), ohne
            // dass das irgendwo sichtbar war.
            //
            // Beide Spalten nullable: "noch nie verbunden" ist ein eigener Zustand, den die UI
            // anders darstellt als eine tatsaechliche Verbindung.
            //
            // `lastConnectedToolCount` haelt fest, wie viele Werkzeuge der Server beim LETZTEN
            // START angeboten hat — nicht, wie viele er nach den aktuellen Schaltern anbieten
            // wuerde. Genau die Differenz zeigt dem Nutzer, dass ein laufender Client noch auf
            // einer veralteten Liste sitzt und neu gestartet werden muss.
            try database.alter(table: "mcp_server_settings") { table in
                table.add(column: "lastConnectedAt", .datetime)
                table.add(column: "lastConnectedToolCount", .integer)
            }
        }
```

- [ ] **Schritt 4: Migrations-Test grün**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/FeedivoDatabaseMigratorTests 2>&1 | grep -E "Test run with|recorded an issue" | head -3
```

Erwartet: PASS.

- [ ] **Schritt 5: Failing Tests für die Store-Methoden**

Ans Ende der Suite in `FeedivoTests/Stores/MCPServerSettingsStoreTests.swift`:

```swift
    @Test("Ohne Verbindungsvermerk liefert lastConnection nil")
    func ohneVermerkLiefertNil() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = MCPServerSettingsStore(database: database)

        #expect(try store.lastConnection() == nil)
    }

    @Test("recordConnection speichert Zeitpunkt und Werkzeug-Anzahl")
    func recordConnectionSpeichertBeideWerte() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = MCPServerSettingsStore(database: database)
        let zeitpunkt = Date(timeIntervalSince1970: 1_786_800_000)

        try store.recordConnection(at: zeitpunkt, toolCount: 10)

        let vermerk = try store.lastConnection()
        #expect(vermerk?.toolCount == 10)
        // Sekundengenauer Vergleich: GRDB speichert DATETIME mit Millisekunden, ein exakter
        // Date-Vergleich waere unnoetig bruechig.
        #expect(abs((vermerk?.connectedAt ?? .distantPast).timeIntervalSince(zeitpunkt)) < 1)
    }

    @Test("Ein zweiter Vermerk ersetzt den ersten")
    func zweiterVermerkErsetztDenErsten() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = MCPServerSettingsStore(database: database)

        try store.recordConnection(at: Date(timeIntervalSince1970: 1_786_800_000), toolCount: 7)
        try store.recordConnection(at: Date(timeIntervalSince1970: 1_786_900_000), toolCount: 10)

        #expect(try store.lastConnection()?.toolCount == 10)
    }

    @Test("Fehlende Spalten werden als nie verbunden behandelt")
    func fehlendeSpaltenWerdenAlsNieVerbundenBehandelt() throws {
        // Fail-safe: Ein Lesefehler darf den Tab nicht unbedienbar machen — er zeigt dann
        // denselben Zustand wie "noch nie verbunden".
        let queue = try DatabaseQueue()
        try FeedivoDatabaseMigrator.migrator.migrate(queue, upTo: "v30_backfill_article_estimated_reading_minutes")
        let database = FeedivoDatabase(writer: queue)

        let vermerk = try? MCPServerSettingsStore(database: database).lastConnection()
        #expect((vermerk ?? nil) == nil)
    }
```

- [ ] **Schritt 6: Test ausführen, Fehlschlag bestätigen**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/MCPServerSettingsStoreTests 2>&1 | grep -E "error:|Test run with" | head -5
```

Erwartet: Compile-Fehler „value of type 'MCPServerSettingsStore' has no member 'lastConnection'".

- [ ] **Schritt 7: Store-Methoden implementieren**

In `Feedivo/Stores/MCPServerSettingsStore.swift` — den neuen Typ **oberhalb** von `struct MCPServerSettingsStore` einfügen:

```swift
/// Vermerk über die letzte Verbindung eines KI-Clients: wann der Serverprozess zuletzt startete
/// und wie viele Werkzeuge er dabei anbot.
struct MCPConnectionRecord: Equatable {
    let connectedAt: Date
    let toolCount: Int
}
```

Die beiden Methoden ans Ende des Structs (nach `setWriteAccessEnabled`):

```swift
    /// Letzter Verbindungsvermerk, oder `nil`, wenn noch nie ein Client verbunden war.
    func lastConnection() throws -> MCPConnectionRecord? {
        try database.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT lastConnectedAt, lastConnectedToolCount FROM mcp_server_settings WHERE id = 1"
            ) else { return nil }
            guard let connectedAt: Date = row["lastConnectedAt"],
                  let toolCount: Int = row["lastConnectedToolCount"] else { return nil }
            return MCPConnectionRecord(connectedAt: connectedAt, toolCount: toolCount)
        }
    }

    /// Hält fest, dass ein Client den Server gestartet hat. Wird vom `FeedivoMCPServer`-Prozess
    /// aufgerufen — bewusst unabhängig vom Schreibzugriff-Schalter: die Zusage „rein lesend"
    /// gilt für Inhalte (Artikel, Tags, Status, Feeds), nicht für diesen Verbindungsvermerk.
    func recordConnection(at date: Date, toolCount: Int) throws {
        try database.write { db in
            try db.execute(
                sql: "UPDATE mcp_server_settings SET lastConnectedAt = ?, lastConnectedToolCount = ? WHERE id = 1",
                arguments: [date, toolCount]
            )
        }
    }
```

- [ ] **Schritt 8: Tests grün**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/MCPServerSettingsStoreTests -only-testing:FeedivoTests/FeedivoDatabaseMigratorTests 2>&1 | grep -E "Test run with|recorded an issue" | head -3
```

Erwartet: PASS.

- [ ] **Schritt 9: Builds prüfen und committen**

```bash
xcodebuild build -scheme Feedivo -configuration Debug 2>&1 | tail -2 && xcodebuild build -scheme FeedivoMCPServer -configuration Debug 2>&1 | tail -2
```

```bash
git add Feedivo/Database/FeedivoDatabaseMigrator.swift Feedivo/Stores/MCPServerSettingsStore.swift FeedivoTests/Database/FeedivoDatabaseMigratorTests.swift FeedivoTests/Stores/MCPServerSettingsStoreTests.swift
git commit -m "feat(mcp-server): Verbindungsvermerk in mcp_server_settings (Migration v35)"
```

---

### Task 2: `MCPClientDetector`

**Files:**
- Create: `Feedivo/Services/MCPClientDetector.swift`
- Test: `FeedivoTests/Services/MCPClientDetectorTests.swift` (neu)

**Interfaces:**
- Consumes: `NSWorkspace` (AppKit)
- Produces:
  - `struct MCPClient: Equatable { let displayName: String; let configPath: String }`
  - `static func installedClients(lookup: (String) -> Bool = …) -> [MCPClient]`

- [ ] **Schritt 1: Failing Tests schreiben**

Neue Datei `FeedivoTests/Services/MCPClientDetectorTests.swift`:

```swift
import Foundation
import Testing
@testable import Feedivo

@Suite("MCPClientDetector")
struct MCPClientDetectorTests {
    @Test("Erkennt Claude Desktop, wenn installiert")
    func erkenntClaudeDesktop() {
        let clients = MCPClientDetector.installedClients { bundleID in
            bundleID == "com.anthropic.claudefordesktop"
        }

        #expect(clients.count == 1)
        #expect(clients.first?.displayName == "Claude Desktop")
        #expect(clients.first?.configPath.hasSuffix("claude_desktop_config.json") == true)
    }

    @Test("Liefert nichts, wenn kein unterstuetzter Client installiert ist")
    func ohneInstallationLeer() {
        // Deckt den Fall ab, in dem der Einrichtungsbereich durch einen Hinweis ersetzt wird —
        // ein Konfigurationsschnipsel ohne Ziel hilft niemandem.
        let clients = MCPClientDetector.installedClients { _ in false }

        #expect(clients.isEmpty)
    }

    @Test("Konfigurationspfad ist absolut, nicht mit Tilde abgekuerzt")
    func konfigurationspfadIstAbsolut() {
        // Der Pfad wird im Tab zum Kopieren angeboten und muss direkt verwendbar sein.
        let clients = MCPClientDetector.installedClients { _ in true }

        #expect(clients.first?.configPath.hasPrefix("/") == true)
    }
}
```

- [ ] **Schritt 2: Test ausführen, Fehlschlag bestätigen**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/MCPClientDetectorTests 2>&1 | grep -E "error:|Test run with" | head -5
```

Erwartet: Compile-Fehler „cannot find 'MCPClientDetector' in scope".

- [ ] **Schritt 3: Detektor implementieren**

Neue Datei `Feedivo/Services/MCPClientDetector.swift`:

```swift
import AppKit
import Foundation

/// Ein KI-Client, der Feedivos MCP-Server über eine Konfigurationsdatei einbinden kann.
struct MCPClient: Equatable {
    let displayName: String
    /// Absoluter Pfad zur Konfigurationsdatei des Clients — wird im Einstellungen-Tab als
    /// Einrichtungsschritt angezeigt und muss deshalb direkt verwendbar sein (keine Tilde).
    let configPath: String
}

/// Ermittelt, welche unterstützten KI-Clients auf diesem Mac installiert sind.
///
/// Die Abfrage läuft über **LaunchServices** (`NSWorkspace.urlForApplication(
/// withBundleIdentifier:)`), nicht über einen Blick in `/Applications` — Feedivo ist sandboxed
/// und darf dort nicht frei lesen, die LaunchServices-Abfrage ist dagegen erlaubt.
///
/// **Bewusst nur Claude Desktop:** Auf einem Entwicklungsrechner sind typischerweise weitere
/// KI-Apps installiert (ChatGPT, Ollama). Für sie ist weder gesichert, ob sie MCP über eine
/// Konfigurationsdatei einbinden, noch wo diese läge — sie zu erkennen, ohne einen Pfad nennen
/// zu können, würde nur falsche Erwartungen wecken. Ein weiterer Client ist später eine
/// zusätzliche Zeile in `supportedClients`.
enum MCPClientDetector {
    private struct SupportedClient {
        let bundleIdentifier: String
        let displayName: String
        let configPathComponents: [String]
    }

    private static let supportedClients: [SupportedClient] = [
        SupportedClient(
            bundleIdentifier: "com.anthropic.claudefordesktop",
            displayName: "Claude Desktop",
            configPathComponents: ["Library", "Application Support", "Claude", "claude_desktop_config.json"]
        )
    ]

    /// `lookup` ist injizierbar, damit die Auswertung ohne tatsächlich installierte App testbar
    /// bleibt — der Standardwert fragt LaunchServices.
    static func installedClients(
        lookup: (String) -> Bool = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
    ) -> [MCPClient] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return supportedClients
            .filter { lookup($0.bundleIdentifier) }
            .map { client in
                let url = client.configPathComponents.reduce(home) { $0.appendingPathComponent($1) }
                return MCPClient(displayName: client.displayName, configPath: url.path)
            }
    }
}
```

- [ ] **Schritt 4: Tests grün**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/MCPClientDetectorTests 2>&1 | grep -E "Test run with|recorded an issue" | head -3
```

Erwartet: PASS (3 Tests).

- [ ] **Schritt 5: Server-Build gegenprüfen**

Der Detektor wird **nur von der App** genutzt, nicht vom Server — ein pbxproj-Eintrag für `FeedivoMCPServer` ist deshalb nicht nötig:

```bash
xcodebuild build -scheme FeedivoMCPServer -configuration Debug 2>&1 | grep -E "error:|BUILD" | tail -2
```

Erwartet: `** BUILD SUCCEEDED **`. Schlägt er mit „cannot find 'MCPClientDetector'" fehl, hat eine gemeinsam genutzte Datei den Typ doch referenziert — dann `Services/MCPClientDetector.swift` alphabetisch in das `membershipExceptions`-Array des `FeedivoMCPServer`-Targets in `Feedivo.xcodeproj/project.pbxproj` einfügen (zwischen `Services/FeedService.swift` und `Services/MCPWriteNotificationName.swift`), Tab-Einrückung wie die Nachbarzeilen.

- [ ] **Schritt 6: Committen**

```bash
git add Feedivo/Services/MCPClientDetector.swift FeedivoTests/Services/MCPClientDetectorTests.swift
git commit -m "feat(settings): MCPClientDetector erkennt installierte KI-Clients"
```

---

### Task 3: Statustext als reine Funktion

**Files:**
- Create: `Feedivo/Services/MCPConnectionStatusText.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`
- Test: `FeedivoTests/Services/MCPConnectionStatusTextTests.swift` (neu)

**Interfaces:**
- Consumes: `MCPConnectionRecord` aus Task 1
- Produces: `static func text(for record: MCPConnectionRecord?, isWriteAccessEnabled: Bool, locale: Locale = .current) -> String`

**Warum eigene Datei:** Die Formatierung ist die einzige Stelle mit echter Logik im Statusbereich. Als reine Funktion ist sie ohne View-Test abzudecken — die View ruft sie nur auf.

- [ ] **Schritt 1: Failing Tests schreiben**

Neue Datei `FeedivoTests/Services/MCPConnectionStatusTextTests.swift`:

```swift
import Foundation
import Testing
@testable import Feedivo

@Suite("MCPConnectionStatusText")
struct MCPConnectionStatusTextTests {
    @Test("Ohne Vermerk wird zur Einrichtung aufgefordert")
    func ohneVermerkFordertZurEinrichtungAuf() {
        let text = MCPConnectionStatusText.text(for: nil, isWriteAccessEnabled: false)

        #expect(text.contains("Noch nie verbunden"))
    }

    @Test("Mit Vermerk erscheinen Werkzeug-Anzahl und Umfang")
    func mitVermerkErscheintAnzahlUndUmfang() {
        let vermerk = MCPConnectionRecord(connectedAt: Date(timeIntervalSince1970: 1_786_800_000), toolCount: 10)

        let text = MCPConnectionStatusText.text(
            for: vermerk,
            isWriteAccessEnabled: true,
            locale: Locale(identifier: "de_DE")
        )

        #expect(text.contains("10"))
        #expect(text.contains("Schreibzugriff"))
    }

    @Test("Ohne Schreibzugriff wird der Umfang als nur lesend benannt")
    func ohneSchreibzugriffNurLesend() {
        let vermerk = MCPConnectionRecord(connectedAt: Date(timeIntervalSince1970: 1_786_800_000), toolCount: 7)

        let text = MCPConnectionStatusText.text(
            for: vermerk,
            isWriteAccessEnabled: false,
            locale: Locale(identifier: "de_DE")
        )

        #expect(text.contains("7"))
        #expect(text.contains("lesend"))
        #expect(!text.contains("Schreibzugriff"))
    }
}
```

- [ ] **Schritt 2: Test ausführen, Fehlschlag bestätigen**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/MCPConnectionStatusTextTests 2>&1 | grep -E "error:|Test run with" | head -5
```

Erwartet: Compile-Fehler „cannot find 'MCPConnectionStatusText' in scope".

- [ ] **Schritt 3: Implementieren**

Neue Datei `Feedivo/Services/MCPConnectionStatusText.swift`:

```swift
import Foundation

/// Baut den Statustext des Einstellungen-Tabs „KI-Zugriff".
///
/// Bewusst als reine Funktion getrennt von der View: Sie ist die einzige Stelle des
/// Statusbereichs mit echter Logik und dadurch ohne View-Test abzudecken.
///
/// Die Werkzeug-Anzahl stammt aus dem LETZTEN TATSÄCHLICHEN Serverstart, nicht aus den aktuell
/// gesetzten Schaltern — weicht sie vom erwarteten Umfang ab, sitzt ein laufender Client noch
/// auf einer veralteten Liste und muss neu gestartet werden. Genau dieser Fall blieb am
/// 2026-08-15 stundenlang unbemerkt.
enum MCPConnectionStatusText {
    static func text(
        for record: MCPConnectionRecord?,
        isWriteAccessEnabled: Bool,
        locale: Locale = .current
    ) -> String {
        guard let record else {
            return String(localized: "settings.mcpServer.status.neverConnected")
        }

        var formatStyle = Date.FormatStyle(date: .abbreviated, time: .shortened)
        formatStyle.locale = locale
        let zeitpunkt = record.connectedAt.formatted(formatStyle)

        let umfang = isWriteAccessEnabled
            ? String(localized: "settings.mcpServer.status.scopeWithWriteAccess")
            : String(localized: "settings.mcpServer.status.scopeReadOnly")

        return String(
            format: String(localized: "settings.mcpServer.status.connected"),
            zeitpunkt,
            record.toolCount,
            umfang
        )
    }
}
```

- [ ] **Schritt 4: L10n-Einträge ergänzen**

Diese Texte laufen über `String(localized:)` mit direkten Schlüsseln (nicht über `L10n`-Konstanten), weil sie zur Laufzeit formatiert werden. Vier Einträge in `Feedivo/Resources/Localizable.xcstrings` **per Text-Einfügung** direkt nach dem Anker `  "strings" : {` ergänzen — nicht per `json.dump`:

| Schlüssel | Deutsch | Englisch |
|---|---|---|
| `settings.mcpServer.status.neverConnected` | `Noch nie verbunden — Schritte oben ausführen.` | `Never connected — follow the steps above.` |
| `settings.mcpServer.status.connected` | `Zuletzt verbunden: %1$@ · %2$d Werkzeuge (%3$@)` | `Last connected: %1$@ · %2$d tools (%3$@)` |
| `settings.mcpServer.status.scopeReadOnly` | `nur lesend` | `read-only` |
| `settings.mcpServer.status.scopeWithWriteAccess` | `inkl. Schreibzugriff` | `incl. write access` |

Format exakt wie die Nachbarn (`"key" : { "localizations" : { "de" : { "stringUnit" : { "state" : "translated", "value" : "…" } }, … } }`), Doppelpunkt mit Leerzeichen **davor und dahinter**.

Danach verifizieren:

```bash
for k in neverConnected connected scopeReadOnly scopeWithWriteAccess; do echo -n "$k: "; grep -c "settings.mcpServer.status.$k" Feedivo/Resources/Localizable.xcstrings; done; git diff --stat Feedivo/Resources/Localizable.xcstrings
```

Erwartet: jeweils ≥ 1, und im Diff nahezu ausschließlich Insertions.

- [ ] **Schritt 5: Tests grün**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/MCPConnectionStatusTextTests 2>&1 | grep -E "Test run with|recorded an issue" | head -3
```

Erwartet: PASS (3 Tests).

- [ ] **Schritt 6: Builds prüfen und committen**

```bash
xcodebuild build -scheme Feedivo -configuration Debug 2>&1 | tail -2 && xcodebuild build -scheme FeedivoMCPServer -configuration Debug 2>&1 | tail -2
```

```bash
git add Feedivo/Services/MCPConnectionStatusText.swift FeedivoTests/Services/MCPConnectionStatusTextTests.swift Feedivo/Resources/Localizable.xcstrings
git commit -m "feat(settings): Statustext fuer KI-Zugriff-Verbindung"
```

---

### Task 4: Server vermerkt die Verbindung

**Files:**
- Create: `FeedivoMCPServer/FeedivoMCPServerConnectionRecorder.swift`
- Modify: `FeedivoMCPServer/main.swift` (nach dem `if let writableDatabase { … }`-Block, vor `await server.withMethodHandler(ListTools.self)`)

**Interfaces:**
- Consumes: `MCPServerSettingsStore.recordConnection(at:toolCount:)` aus Task 1, `FeedivoContainerDatabaseLocation.databaseURL()`
- Produces: `static func record(toolCount: Int, at fileURL: URL = …)` — schluckt alle Fehler bewusst

**Warum eine eigene Datei:** Der Vermerk braucht eine **eigene, kurzlebige Schreibverbindung**. `FeedivoMCPServerWritableDatabase.open()` ist dafür ungeeignet, weil es nur bei aktiviertem Schreibzugriff aufgerufen wird und zusätzlich eine `cloud_sync_settings`-Precondition prüft, die für einen Verbindungsvermerk keine Rolle spielt.

- [ ] **Schritt 1: Recorder implementieren**

Neue Datei `FeedivoMCPServer/FeedivoMCPServerConnectionRecorder.swift`:

```swift
import Foundation
import GRDB

/// Hält beim Serverstart fest, dass ein KI-Client verbunden ist und mit wie vielen Werkzeugen.
///
/// **Bewusst unabhängig vom Schreibzugriff-Schalter:** Ohne diesen Vermerk kann der
/// Einstellungen-Tab „KI-Zugriff" nicht anzeigen, ob je eine Verbindung bestand — am 2026-08-15
/// lief ein Serverprozess stundenlang mit einer veralteten Werkzeugliste, ohne dass das sichtbar
/// war. Die Zusage „rein lesend" gilt weiterhin uneingeschränkt für INHALTE (Artikel, Tags,
/// Status, Feeds); vermerkt wird ausschließlich, dass und womit sich ein Client verbunden hat.
///
/// Nutzt eine eigene, kurzlebige Verbindung statt `FeedivoMCPServerWritableDatabase`: jene wird
/// nur bei aktiviertem Schreibzugriff geöffnet und prüft zusätzlich eine Precondition, die für
/// diesen Vermerk keine Rolle spielt.
enum FeedivoMCPServerConnectionRecorder {
    /// Schluckt jeden Fehler bewusst (nach Protokollierung auf stderr): Ein fehlender
    /// Verbindungsvermerk ist ein kosmetisches Problem und darf den Dienst nie blockieren.
    static func record(toolCount: Int, at fileURL: URL = FeedivoContainerDatabaseLocation.databaseURL()) {
        do {
            var configuration = Configuration()
            configuration.busyMode = .timeout(5)
            let pool = try DatabasePool(path: fileURL.path, configuration: configuration)
            try MCPServerSettingsStore(database: FeedivoDatabase(writer: pool))
                .recordConnection(at: Date(), toolCount: toolCount)
        } catch {
            let message = "Feedivo MCP Server: Verbindungsvermerk konnte nicht geschrieben werden (\(error)).\n"
            FileHandle.standardError.write(Data(message.utf8))
        }
    }
}
```

- [ ] **Schritt 2: In `main.swift` aufrufen**

Direkt **nach** dem `if let writableDatabase { availableTools.append(contentsOf: […]) }`-Block und **vor** `await server.withMethodHandler(ListTools.self)`:

```swift
// Verbindungsvermerk fuer den Einstellungen-Tab: haelt fest, wann zuletzt ein Client den Server
// startete und wie viele Werkzeuge er dabei bekam. Die Anzahl stammt bewusst aus der TATSAECHLICH
// aufgebauten Liste — weicht sie spaeter von den Schaltern ab, sitzt der Client noch auf einer
// veralteten Liste und muss neu gestartet werden.
FeedivoMCPServerConnectionRecorder.record(toolCount: availableTools.count)
```

- [ ] **Schritt 3: Server-Build prüfen**

```bash
xcodebuild build -scheme FeedivoMCPServer -configuration Debug 2>&1 | grep -E "error:|BUILD" | tail -3
```

Erwartet: `** BUILD SUCCEEDED **`.

- [ ] **Schritt 4: Spalten- und Typprüfung gegen eine Kopie**

`FeedivoMCPServerTests` wird in diesem Projekt strukturell nie ausgeführt (siehe Global Constraints), und der Serverpfad ist fest verdrahtet (`FeedivoContainerDatabaseLocation.databaseURL()` ignoriert `$HOME`, empirisch belegt am 2026-08-14) — der Binary lässt sich also nicht auf eine Testdatenbank umlenken. Deshalb hier nur die Spalten-/Typprüfung gegen eine **Kopie**, niemals gegen die Produktionsdatenbank:

```bash
DB="$HOME/Library/Containers/ch.martin.Feedivo/Data/Library/Application Support/ch.martin.Feedivo/Feedivo/feedivo.sqlite"; cp "$DB" /tmp/mcp-verify.sqlite && sqlite3 /tmp/mcp-verify.sqlite "UPDATE mcp_server_settings SET lastConnectedAt = '2026-08-15 16:02:44.000', lastConnectedToolCount = 10; SELECT lastConnectedAt, lastConnectedToolCount FROM mcp_server_settings;"
```

Erwartet: `2026-08-15 16:02:44.000|10` — belegt, dass Spaltennamen und Typen zusammenpassen. Im Report festhalten, dass der Recorder selbst nicht im echten Prozess getestet wurde; das deckt die manuelle Verifikation in Task 6 ab.

- [ ] **Schritt 5: Committen**

```bash
git add FeedivoMCPServer/FeedivoMCPServerConnectionRecorder.swift FeedivoMCPServer/main.swift
git commit -m "feat(mcp-server): Verbindung beim Start vermerken"
```

---

### Task 5: Tab umbauen

**Files:**
- Modify: `Feedivo/Views/Settings/SettingsView.swift` (`MCPServerSettingsView`)
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`
- Test: `FeedivoTests/App/FeedivoAppSceneConfigurationTests.swift` (nur falls eine Assertion bricht, siehe Schritt 4)

**Interfaces:**
- Consumes: `MCPClientDetector.installedClients()` (Task 2), `MCPConnectionStatusText.text(for:isWriteAccessEnabled:)` (Task 3), `MCPServerSettingsStore.lastConnection()` (Task 1)
- Produces: nichts für spätere Tasks

- [ ] **Schritt 1: Geänderte Texte eintragen**

Bestehende Schlüssel behalten ihren Namen (kein Verwaisen), nur die Werte ändern sich:

| Schlüssel | Deutsch neu | Englisch neu |
|---|---|---|
| `settings.mcpServer.sectionTitle` | `KI-Zugriff:` | `AI Access:` |
| `settings.mcpServer.toggleTitle` | `Zugriff für KI-Assistenten erlauben` | `Allow access for AI assistants` |
| `settings.mcpServer.toggleDescription` | `Eine verbundene KI (z. B. Claude Desktop) darf deine Feeds, Ordner, Tags und Artikel lesen — auch Gelesen- und Stern-Status. Ändern darf sie nichts, solange du unten keinen Schreibzugriff erlaubst. Technisch läuft das über das Model Context Protocol (MCP).` | `A connected AI (e.g. Claude Desktop) may read your feeds, folders, tags, and articles — including read and starred status. It cannot change anything unless you allow write access below. Technically this runs over the Model Context Protocol (MCP).` |
| `settings.mcpServer.connectionRowTitle` | `Einrichtung` | `Setup` |

- [ ] **Schritt 2: Neue Keys anlegen**

In `Feedivo/Resources/L10n.swift` nach `settingsMCPServerWriteAccessToggleDescription`:

```swift
    static let settingsMCPServerStepCopy = LocalizedStringKey("settings.mcpServer.step.copy")
    static let settingsMCPServerStepPaste = LocalizedStringKey("settings.mcpServer.step.paste")
    static let settingsMCPServerStepRestart = LocalizedStringKey("settings.mcpServer.step.restart")
    static let settingsMCPServerNoClientFound = LocalizedStringKey("settings.mcpServer.noClientFound")
    static let settingsMCPServerStatusRowTitle = LocalizedStringKey("settings.mcpServer.statusRowTitle")
```

Zugehörige Katalogeinträge (per Text-Einfügung, nicht per `json.dump`):

| Schlüssel | Deutsch | Englisch |
|---|---|---|
| `settings.mcpServer.step.copy` | `1. Konfiguration kopieren` | `1. Copy the configuration` |
| `settings.mcpServer.step.paste` | `2. In diese Datei einfügen:` | `2. Paste it into this file:` |
| `settings.mcpServer.step.restart` | `3. KI-Client neu starten — sonst nutzt er weiter die alten Einstellungen.` | `3. Restart the AI client — otherwise it keeps using the old settings.` |
| `settings.mcpServer.noClientFound` | `Es wurde kein unterstützter KI-Client gefunden. Feedivo unterstützt derzeit Claude Desktop.` | `No supported AI client found. Feedivo currently supports Claude Desktop.` |
| `settings.mcpServer.statusRowTitle` | `Status` | `Status` |

`settings.mcpServer.snippetDescription` wird nicht mehr verwendet (der Pfad steht jetzt als Schritt 2). Konstante und Katalogeintrag **bleiben bestehen** — Entfernen wäre eigener Scope.

Verifizieren:

```bash
for k in step.copy step.paste step.restart noClientFound statusRowTitle; do echo -n "$k: "; grep -c "settings.mcpServer.$k" Feedivo/Resources/Localizable.xcstrings; done
```

Erwartet: jeweils ≥ 1.

- [ ] **Schritt 3: View umbauen**

Zwei neue `@State`-Properties zu `MCPServerSettingsView` ergänzen:

```swift
    @State private var lastConnection: MCPConnectionRecord?
    @State private var detectedClient: MCPClient?
```

In `load()` **vor** `isLoaded = true` ergänzen:

```swift
        lastConnection = try? store.lastConnection()
        detectedClient = MCPClientDetector.installedClients().first
```

Den Block ab `GeneralSettingsRow(title: L10n.settingsMCPServerConnectionRowTitle)` bis einschließlich `GeneralSettingsHelp(L10n.settingsMCPServerSnippetDescription)` **ersetzen** durch:

```swift
                if let detectedClient {
                    GeneralSettingsRow(title: L10n.settingsMCPServerConnectionRowTitle) {
                        Button(L10n.settingsMCPServerCopyButton) {
                            copyConfigSnippet()
                        }
                    }
                    Text(L10n.settingsMCPServerStepCopy)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(configSnippet)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Text(L10n.settingsMCPServerStepPaste)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(verbatim: detectedClient.configPath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    Text(L10n.settingsMCPServerStepRestart)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    GeneralSettingsHelp(L10n.settingsMCPServerNoClientFound)
                }

                GeneralSettingsRow(title: L10n.settingsMCPServerStatusRowTitle) {
                    Text(verbatim: MCPConnectionStatusText.text(
                        for: lastConnection,
                        isWriteAccessEnabled: isWriteAccessEnabled
                    ))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
```

- [ ] **Schritt 4: Build und Source-Sniffing-Tests prüfen**

```bash
xcodebuild build -scheme Feedivo -configuration Debug 2>&1 | grep -E "error:|BUILD" | tail -3
```

```bash
grep -n "mcpServer\|MCPServer" FeedivoTests/App/FeedivoAppSceneConfigurationTests.swift
```

Trifft eine Assertion einen entfernten Ausdruck, auf den neuen Wortlaut anpassen — **nicht** die View-Struktur zurückbauen. Diese Suite hat ~25 vorbestehende, nicht zu diesem Task gehörende Fehlschläge; vor der Änderung Baseline notieren.

- [ ] **Schritt 5: Testlauf und Commit**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/MCPClientDetectorTests -only-testing:FeedivoTests/MCPConnectionStatusTextTests -only-testing:FeedivoTests/MCPServerSettingsStoreTests 2>&1 | grep -E "Test run with|recorded an issue" | head -3
```

```bash
git add Feedivo/Views/Settings/SettingsView.swift Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings FeedivoTests/App/FeedivoAppSceneConfigurationTests.swift
git commit -m "feat(settings): KI-Zugriff-Tab in Zugriff, Einrichtung und Status gegliedert"
```

---

### Task 6: Abschluss

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Schritt 1: Regressionslauf**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/MCPClientDetectorTests -only-testing:FeedivoTests/MCPConnectionStatusTextTests -only-testing:FeedivoTests/MCPServerSettingsStoreTests -only-testing:FeedivoTests/FeedivoDatabaseMigratorTests -only-testing:FeedivoTests/MCPWriteObserverTests 2>&1 | grep -E "Test run with|recorded an issue" | head -3
```

Erwartet: alle grün.

- [ ] **Schritt 2: Release-Builds**

```bash
xcodebuild build -scheme Feedivo -configuration Release 2>&1 | tail -2 && xcodebuild build -scheme FeedivoMCPServer -configuration Release 2>&1 | tail -2
```

- [ ] **Schritt 3: Migrations-Tabelle in `CLAUDE.md`**

```markdown
| v35_add_mcp_server_last_connection | `lastConnectedAt` + `lastConnectedToolCount` auf `mcp_server_settings` — Verbindungsnachweis für den Einstellungen-Tab „KI-Zugriff"; der Server schreibt beide bei jedem Start, bewusst unabhängig vom Schreibzugriff-Schalter |
```

- [ ] **Schritt 4: Eintrag unter „Aktuell in Arbeit"**

Inhalt: Anlass (die Live-Verifikation vom 2026-08-15 deckte auf, dass ein Serverprozess stundenlang mit veralteter Werkzeugliste lief, ohne dass das sichtbar war), die drei Bereiche des Tabs, `MCPClientDetector` (nur Claude Desktop; LaunchServices statt Dateizugriff wegen der Sandbox), die bewusste Aufweichung der Read-Only-Zusage für den Verbindungsvermerk samt Begründung und Abgrenzung („gilt weiterhin für Inhalte"), sowie die ausstehende manuelle Verifikation:

1. Tab öffnen → „Claude Desktop" wird als erkannter Client genannt, der Pfad stimmt.
2. Claude Desktop neu starten → Statuszeile zeigt danach Zeitpunkt und Werkzeug-Anzahl.
3. Schreibzugriff umschalten, Client neu starten → Anzahl wechselt zwischen 7 und 10.
4. Bei **ausgeschaltetem** Schreibzugriff prüfen, dass der Vermerk trotzdem geschrieben wird.

- [ ] **Schritt 5: Committen**

```bash
git add CLAUDE.md
git commit -m "docs: KI-Zugriff-Tab-Ueberarbeitung in CLAUDE.md dokumentiert"
```

- [ ] **Schritt 6: Push-Entscheidung vorlegen**

Laut Projektkonvention **nie ohne ausdrückliche Bestätigung** pushen. Dem Nutzer die Commit-Anzahl und die vier offenen Verifikationspunkte melden.

---

## Self-Review

**Spec-Abdeckung:** Client-Erkennung → Task 2 ✔; Migration v35 + Store → Task 1 ✔; Server-Vermerk → Task 4 ✔; drei Tab-Bereiche → Task 5 ✔; Statustext mit Zeitpunkt *und* Umfang → Task 3 ✔; Hinweis statt Schnipsel ohne erkannten Client → Task 5, Schritt 3 ✔; Fehlerbehandlung (Server schluckt nach stderr-Protokoll, App fail-safe über `try?`) → Task 4 Schritt 1 und Task 5 Schritt 3 ✔; kein Task berührt die Out-of-Scope-Punkte ✔.

**Platzhalter-Scan:** Keine „TBD"/„später"-Verweise; alle Codeblöcke vollständig; alle UI-Texte im Wortlaut angegeben.

**Typ-Konsistenz:** `MCPConnectionRecord` (Task 1) wird in Task 3 und Task 5 mit denselben Feldnamen (`connectedAt`, `toolCount`) verwendet. `MCPClient.displayName`/`configPath` (Task 2) passen zur Nutzung in Task 5. `MCPConnectionStatusText.text(for:isWriteAccessEnabled:locale:)` wird in Task 5 ohne `locale` aufgerufen — der Standardwert `.current` deckt das ab. Migrationsname `"v35_add_mcp_server_last_connection"` ist in Task 1 und Task 6 identisch.

**Bekannte Einschränkung:** Task 4 kann den Recorder nicht im echten Serverprozess gegen eine Testdatenbank prüfen, weil `FeedivoContainerDatabaseLocation.databaseURL()` fest verdrahtet ist und `homeDirectoryForCurrentUser` die `$HOME`-Variable ignoriert (empirisch belegt am 2026-08-14). Die Absicherung erfolgt über die Spalten-/Typprüfung in Task 4 und die manuelle Verifikation in Task 6.
