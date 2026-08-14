# MCP-Server Ein/Aus-Schalter + Verbindungs-Hilfe Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Der Nutzer entscheidet über einen Schalter in Feedivo, ob `FeedivoMCPServer` überhaupt Daten herausgibt (Standard: deaktiviert). Derselbe neue Einstellungen-Tab zeigt zusätzlich den fertigen Claude-Desktop-Config-Snippet zum Kopieren.

**Architecture:** Neue, zweckgebundene SQLite-Tabelle `mcp_server_settings` (Migration v31) statt `UserDefaults` — GRDB/WAL bietet echte Cross-Process-Konsistenz, `UserDefaults`/`cfprefsd` nicht (siehe Design-Spec). `FeedivoMCPServer` prüft das Flag direkt nach dem Öffnen der DB, noch vor jeder Tool-Registrierung; fehlt die Tabelle/Zeile, wird das identisch wie „deaktiviert" behandelt (fail-closed).

**Tech Stack:** GRDB (SQLite-Migration + Store), SwiftUI (neuer Settings-Tab), `NSPasteboard` (Copy-Button) — keine neuen Abhängigkeiten.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08/2026-08-14-mcp-server-schalter-design.md`
- Standardwert des Schalters: **deaktiviert** (Opt-in).
- Speicherort: SQLite-Tabelle `mcp_server_settings` (NICHT `UserDefaults`) — Begründung: `cfprefsd`-Pufferung liefert keine Cross-Process-Konsistenzgarantie, GRDB/WAL bereits diese Session ausführlich verifiziert.
- Fail-closed: fehlende Tabelle/Zeile wird identisch wie „deaktiviert" behandelt, nie wie „aktiviert".
- Server prüft das Flag NACH dem Öffnen der DB (wird für die Prüfung selbst gebraucht), aber VOR jeder Tool-Registrierung und VOR dem Start des `StdioTransport`.
- Kein Live-Reconnect/Cross-Process-Benachrichtigung an einen bereits laufenden Server-Prozess — ein Neustart des MCP-Clients ist nötig, damit eine Änderung greift (v1-Limitation, dokumentiert im UI-Text).
- `FeedivoMCPServerTests` kann strukturell nicht per `xcodebuild test` ausgeführt werden (TEST_HOST-Limitation, siehe CLAUDE.md-Gotcha) — dort neue Tests werden als echter Swift-Testing-Quellcode geschrieben und nur per `xcodebuild build` kompilierverifiziert. `FeedivoTests` (Haupt-App-Target) hat dieses Problem NICHT — Store-/Migrations-Tests dort laufen ganz normal über `xcodebuild test`.
- Neue Dateien unter `Feedivo/Stores/` bekommen KEINE automatische `FeedivoMCPServer`-Target-Membership (nur Dateien direkt unter `FeedivoMCPServer/`/`FeedivoMCPServer/Tools/`/`FeedivoMCPServerTests/` profitieren von Xcodes automatischer Zuordnung für file-system-synchronisierte Gruppen) — muss manuell in Xcode ergänzt werden.

---

### Task 1: Migration v31 — `mcp_server_settings`-Tabelle

**Files:**
- Modify: `Feedivo/Database/FeedivoDatabaseMigrator.swift` (letzte bestehende Migration: `v30_backfill_article_estimated_reading_minutes`, direkt vor `return migrator`)
- Test: `FeedivoTests/Database/FeedivoDatabaseMigratorTests.swift`

**Interfaces:**
- Produces: Tabelle `mcp_server_settings` mit genau einer Zeile (`id = 1`, `isEnabled BOOLEAN NOT NULL DEFAULT 0`), nach der Migration bereits mit `isEnabled = false` befüllt.

- [ ] **Step 1: Fehlschlagenden Test schreiben**

In `FeedivoTests/Database/FeedivoDatabaseMigratorTests.swift`, direkt nach dem bestehenden `migrationV30...`-Test ergänzen:

```swift
@Test func migrationV31LegtMcpServerSettingsMitDeaktiviertemStandardwertAn() throws {
    let queue = try DatabaseQueue()
    try FeedivoDatabaseMigrator.migrator.migrate(queue, upTo: "v30_backfill_article_estimated_reading_minutes")

    try FeedivoDatabaseMigrator.migrator.migrate(queue)

    let isEnabled = try queue.read { db in
        try Bool.fetchOne(db, sql: "SELECT isEnabled FROM mcp_server_settings WHERE id = 1")
    }
    #expect(isEnabled == false)

    let rowCount = try queue.read { db in
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM mcp_server_settings")
    }
    #expect(rowCount == 1)
}
```

- [ ] **Step 2: Test ausführen, Fehlschlag verifizieren**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' test -only-testing:FeedivoTests/FeedivoDatabaseMigratorTests/migrationV31LegtMcpServerSettingsMitDeaktiviertemStandardwertAn`
Expected: FAIL mit „no such table: mcp_server_settings"

- [ ] **Step 3: Migration implementieren**

In `FeedivoDatabaseMigrator.swift`, direkt vor `return migrator` (nach der `v30_backfill_article_estimated_reading_minutes`-Migration) ergänzen:

```swift
        migrator.registerMigration("v31_create_mcp_server_settings") { database in
            // Zweckgebundene Single-Row-Tabelle statt einer generischen Key-Value-
            // Settings-Tabelle (YAGNI). Bewusst SQLite statt UserDefaults: UserDefaults-
            // Schreibvorgänge werden von cfprefsd gepuffert und nicht sofort auf die
            // Plist-Datei durchgeschrieben — FeedivoMCPServer (ein separater,
            // unsandboxed Prozess) könnte kurz nach einem Toggle-Wechsel noch den alten
            // Wert sehen. GRDB/WAL bietet dagegen eine bereits in diesem Projekt
            // ausführlich verifizierte Cross-Process-Konsistenzgarantie (siehe Gotcha
            // zu PRAGMA query_only in CLAUDE.md). Standard `isEnabled = false` —
            // Freigabe an einen externen KI-Prozess ist bewusstes Opt-in.
            try database.create(table: "mcp_server_settings") { table in
                table.column("id", .integer).primaryKey()
                table.column("isEnabled", .boolean).notNull().defaults(to: false)
            }
            try database.execute(sql: "INSERT INTO mcp_server_settings (id, isEnabled) VALUES (1, 0)")
        }

```

- [ ] **Step 4: Test erneut ausführen, Erfolg verifizieren**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' test -only-testing:FeedivoTests/FeedivoDatabaseMigratorTests/migrationV31LegtMcpServerSettingsMitDeaktiviertemStandardwertAn`
Expected: `TEST SUCCEEDED`

- [ ] **Step 5: Vollen Migrator-Testlauf gegen Regressionen prüfen**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' test -only-testing:FeedivoTests/FeedivoDatabaseMigratorTests -parallel-testing-enabled NO`
Expected: `TEST SUCCEEDED`, alle bisherigen Migrations-Tests weiterhin grün

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Database/FeedivoDatabaseMigrator.swift FeedivoTests/Database/FeedivoDatabaseMigratorTests.swift
git commit -m "feat(db): Migration v31 legt mcp_server_settings-Tabelle an

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2: `MCPServerSettingsStore`

**Files:**
- Create: `Feedivo/Stores/MCPServerSettingsStore.swift`
- Test: Create `FeedivoTests/Stores/MCPServerSettingsStoreTests.swift`

**Interfaces:**
- Consumes: `FeedivoDatabase.inMemoryForTests() throws -> FeedivoDatabase` (Testfixture), `FeedivoDatabase.read`/`.write` (bestehendes Muster, siehe `Feedivo/Stores/FeedLogStore.swift`)
- Produces: `MCPServerSettingsStore(database: FeedivoDatabase)`, `.isEnabled() throws -> Bool`, `.setEnabled(_ isEnabled: Bool) throws` — wird von Task 3 (Settings-UI) und Task 4 (Server-Flag-Prüfung) konsumiert.

- [x] **Step 1: Fehlschlagenden Test schreiben**

```swift
import Testing
import GRDB
@testable import Feedivo

@Suite("MCPServerSettingsStore")
struct MCPServerSettingsStoreTests {
    @Test("Standardwert nach Migration ist deaktiviert")
    func standardwertIstDeaktiviert() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = MCPServerSettingsStore(database: database)

        #expect(try store.isEnabled() == false)
    }

    @Test("setEnabled persistiert den neuen Wert")
    func setEnabledPersistiertWert() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = MCPServerSettingsStore(database: database)

        try store.setEnabled(true)
        #expect(try store.isEnabled() == true)

        try store.setEnabled(false)
        #expect(try store.isEnabled() == false)
    }
}
```

- [x] **Step 2: Test ausführen, Fehlschlag verifizieren**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' test -only-testing:FeedivoTests/MCPServerSettingsStoreTests`
Expected: FAIL mit „cannot find 'MCPServerSettingsStore' in scope"

- [x] **Step 3: Implementierung schreiben**

```swift
import Foundation
import GRDB

struct MCPServerSettingsStore {
    private let database: FeedivoDatabase

    init(database: FeedivoDatabase) {
        self.database = database
    }

    func isEnabled() throws -> Bool {
        try database.read { db in
            try Bool.fetchOne(db, sql: "SELECT isEnabled FROM mcp_server_settings WHERE id = 1") ?? false
        }
    }

    func setEnabled(_ isEnabled: Bool) throws {
        try database.write { db in
            try db.execute(sql: "UPDATE mcp_server_settings SET isEnabled = ? WHERE id = 1", arguments: [isEnabled])
        }
    }
}
```

- [x] **Step 4: Test erneut ausführen, Erfolg verifizieren**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' test -only-testing:FeedivoTests/MCPServerSettingsStoreTests`
Expected: `TEST SUCCEEDED`, beide Tests grün

- [x] **Step 5 [MANUELL — erfordert Xcode-GUI]: Target Membership für `FeedivoMCPServer` ergänzen** (committed: `af9a8a2`)

Neue Dateien unter `Feedivo/Stores/` bekommen KEINE automatische `FeedivoMCPServer`-Target-Membership (anders als Dateien direkt unter `FeedivoMCPServer/`). Task 4 braucht `MCPServerSettingsStore` aber auch im Server-Target.

In Xcode: `Feedivo/Stores/MCPServerSettingsStore.swift` im Projektnavigator auswählen → File Inspector (⌥⌘1) → Abschnitt „Target Membership" → Checkbox `FeedivoMCPServer` zusätzlich aktivieren (die Checkbox `Feedivo` bleibt aktiv).

Verifizieren:

```bash
xcodebuild -project Feedivo.xcodeproj -scheme FeedivoMCPServer -configuration Debug build
```

Expected: `BUILD SUCCEEDED` (schlägt vor dem Ergänzen der Target Membership mit „cannot find type 'MCPServerSettingsStore' in scope" fehl, sobald Task 4 den Typ referenziert — an dieser Stelle in Task 2 baut `FeedivoMCPServer` noch unverändert durch, da der Typ noch nirgends im Server-Target aufgerufen wird; die Membership trotzdem jetzt schon ergänzen, damit Task 4 nicht erneut zu Xcode wechseln muss).

- [x] **Step 6: Commit** (committed: `edf4999`)

```bash
git add Feedivo/Stores/MCPServerSettingsStore.swift FeedivoTests/Stores/MCPServerSettingsStoreTests.swift
git commit -m "feat(settings): MCPServerSettingsStore für den Ein/Aus-Schalter

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 3: Settings-Tab „KI-Zugriff" (Schalter + Copy-Config-Snippet)

**Files:**
- Modify: `Feedivo/Views/Settings/SettingsView.swift`

**Interfaces:**
- Consumes: `MCPServerSettingsStore(database: FeedivoDatabase)` (Task 2), `\.feedivoDatabase` Environment-Key (bestehend, siehe `CleanupSettingsView` in derselben Datei), `Color.settingsBoldAccent`, `GeneralSettingsSection`/`GeneralSettingsRow`/`GeneralSettingsHelp` (bestehende Bausteine in dieser Datei)
- Produces: `SettingsSection.mcpServer`-Fall, neuer Tab „KI-Zugriff" im Einstellungen-Fenster

**Hinweis zur Dateistruktur:** Alle bisherigen Settings-Tabs (`NotificationSettingsView`, `CleanupSettingsView`, `SyncSettingsView` etc.) liegen als `private struct` in DERSELBEN Datei `SettingsView.swift` (aktuell 2107 Zeilen) — kein separates Per-Tab-Datei-Muster in diesem Projekt. Der neue Tab folgt demselben, bereits etablierten Muster statt eine neue Datei anzulegen.

- [ ] **Step 1: `SettingsSection`-Fall ergänzen**

In `SettingsView.swift`, im `private enum SettingsSection`-Block (Zeile ~4-72), `case mcpServer` zwischen `case sync` und `case about` ergänzen (thematisch näher an „Über" als an den übrigen Tabs):

```swift
private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case appearance
    case articleList
    case menubar
    case shortcuts
    case readerToolbar
    case notifications
    case refresh
    case cleanup
    case sync
    case mcpServer
    case about
```

Im `title`-`switch` ergänzen:

```swift
        case .mcpServer:
            "KI-Zugriff"
```

Im `systemImage`-`switch` ergänzen:

```swift
        case .mcpServer:
            "sparkles"
```

- [ ] **Step 2: Fensterbreite defensiv erhöhen**

`SettingsView.swift` hat aktuell 11 Tabs bei `windowWidth = 960` (siehe Kommentar an `Layout.windowWidth`, Zeile ~76-89 — wurde bei jedem neuen Tab bisher proportional erhöht: 640→880→960). Mit dem neuen 12. Tab denselben Kommentarstil fortsetzen und auf `1040` erhöhen:

```swift
        // Erneut verbreitert 960→1040pt für den neuen "KI-Zugriff"-Tab (12. Tab,
        // 2026-08-14) — dieselbe defensive Anpassung wie bei jedem vorherigen neuen
        // Tab (640→880→960, siehe Kommentare oben). NICHT live verifiziert (kein
        // computer-use für native macOS-Apps in dieser Umgebung verfügbar) — falls
        // die Tab-Leiste trotzdem überläuft/Tabs abgeschnitten werden, muss der Wert
        // weiter erhöht werden.
        static let windowWidth: CGFloat = 1040
```

- [ ] **Step 3: Tab in `TabView`-Body und `settingsContent`-Switch registrieren**

In `body` (Zeile ~95-107), nach `settingsTab(.sync)` ergänzen:

```swift
            settingsTab(.mcpServer)
```

Im `settingsContent(for:)`-Switch (Zeile ~128-153), nach `case .sync:` ergänzen:

```swift
        case .mcpServer:
            MCPServerSettingsView()
```

- [ ] **Step 4: `MCPServerSettingsView` implementieren**

Direkt nach der bestehenden `private struct SyncSettingsView`-Definition (bzw. an beliebiger Stelle zwischen den anderen `private struct ...SettingsView`-Typen) einfügen:

```swift
private struct MCPServerSettingsView: View {
    @Environment(\.feedivoDatabase) private var feedivoDatabase

    @State private var isEnabled = false
    @State private var isLoaded = false
    @State private var saveErrorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GeneralSettingsSection(label: Text("KI-Zugriff (MCP):")) {
                Toggle(isOn: $isEnabled) {
                    Text("MCP-Server aktivieren")
                        .font(.system(size: 13))
                }
                .toggleStyle(.checkbox)
                .tint(Color.settingsBoldAccent)
                .disabled(!isLoaded)
                .onChange(of: isEnabled) { _, newValue in
                    guard isLoaded else { return }
                    saveEnabled(newValue)
                }
                GeneralSettingsHelp(
                    "Erlaubt einer angeschlossenen KI (z. B. Claude Desktop) lesenden Zugriff auf deine Feeds, Ordner, Tags und Artikel (inkl. Gelesen-/Stern-Status) über den Model Context Protocol. Rein lesend — die KI kann nichts ändern. Nach einer Änderung muss der KI-Client (z. B. Claude Desktop) neu gestartet werden, damit sie wirkt."
                )

                if let saveErrorMessage {
                    Text(saveErrorMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }

                GeneralSettingsRow(title: "Verbindung einrichten") {
                    Button("Kopieren") {
                        copyConfigSnippet()
                    }
                }
                Text(configSnippet)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                GeneralSettingsHelp(
                    "Diesen Eintrag in die Konfigurationsdatei deines KI-Clients einfügen (bei Claude Desktop: ~/Library/Application Support/Claude/claude_desktop_config.json)."
                )
            }
        }
        .task {
            await load()
        }
    }

    private var mcpServerExecutablePath: String {
        Bundle.main.bundlePath + "/Contents/MacOS/FeedivoMCPServer"
    }

    private var configSnippet: String {
        """
        {
          "mcpServers": {
            "feedivo": { "command": "\(mcpServerExecutablePath)" }
          }
        }
        """
    }

    private func load() async {
        guard let feedivoDatabase else { return }
        let store = MCPServerSettingsStore(database: feedivoDatabase)
        isEnabled = (try? store.isEnabled()) ?? false
        isLoaded = true
    }

    private func saveEnabled(_ newValue: Bool) {
        guard let feedivoDatabase else { return }
        let store = MCPServerSettingsStore(database: feedivoDatabase)
        do {
            try store.setEnabled(newValue)
            saveErrorMessage = nil
        } catch {
            saveErrorMessage = "Konnte Einstellung nicht speichern: \(error.localizedDescription)"
        }
    }

    private func copyConfigSnippet() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(configSnippet, forType: .string)
    }
}
```

- [ ] **Step 5: Build verifizieren**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -configuration Debug build`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Views/Settings/SettingsView.swift
git commit -m "feat(settings): Neuer Tab 'KI-Zugriff' — MCP-Server-Schalter + Config-Snippet zum Kopieren

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 4: Server-seitige Zugriffsprüfung (fail-closed)

**Files:**
- Modify: `FeedivoMCPServer/main.swift`
- Test: Create `FeedivoMCPServerTests/MCPServerAccessGateTests.swift`

**Interfaces:**
- Consumes: `MCPServerSettingsStore(database: FeedivoDatabase)` (Task 2, jetzt auch im `FeedivoMCPServer`-Target verfügbar), `FeedivoMCPServerDatabase.core: FeedivoDatabase` (bestehend)

- [ ] **Step 1: Fehlschlagende Tests schreiben**

```swift
import Testing
import GRDB
@testable import FeedivoMCPServer

@Suite("MCP-Server-Zugriffsprüfung")
struct MCPServerAccessGateTests {
    @Test("Deaktivierter Schalter wird korrekt als false gelesen")
    func deaktivierterSchalterWirdAlsFalseGelesen() throws {
        let core = try FeedivoDatabase.inMemoryForTests()
        let store = MCPServerSettingsStore(database: core)

        #expect(try store.isEnabled() == false)
    }

    @Test("Aktivierter Schalter wird korrekt als true gelesen")
    func aktivierterSchalterWirdAlsTrueGelesen() throws {
        let core = try FeedivoDatabase.inMemoryForTests()
        let store = MCPServerSettingsStore(database: core)
        try store.setEnabled(true)

        #expect(try store.isEnabled() == true)
    }

    @Test("Fehlende Tabelle wird fail-closed als false behandelt")
    func fehlendeTabelleWirdFailClosedAlsFalseBehandelt() throws {
        // Simuliert eine Datenbank, die nur bis vor Migration v31 migriert wurde
        // (z. B. weil Feedivo seit dem Update auf diese Version noch nicht
        // gestartet wurde) — die Store-Methode darf dabei NICHT crashen und
        // NICHT true zurückgeben.
        let queue = try DatabaseQueue()
        try FeedivoDatabaseMigrator.migrator.migrate(queue, upTo: "v30_backfill_article_estimated_reading_minutes")
        let core = FeedivoDatabase(writer: queue)
        let store = MCPServerSettingsStore(database: core)

        let isEnabled = (try? store.isEnabled()) ?? false
        #expect(isEnabled == false)
    }
}
```

- [ ] **Step 2: Tests ausführen, Fehlschlag verifizieren**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme FeedivoMCPServer -destination 'platform=macOS' test -only-testing:FeedivoMCPServerTests/MCPServerAccessGateTests`
Expected: FAIL mit „Could not find test host" (bekannte, akzeptierte TEST_HOST-Einschränkung, siehe Global Constraints) — der eigentliche RED-Nachweis für diese Task ist Step 3s Implementierung in `main.swift`, nicht dieser Test (der Test selbst referenziert nur bereits existierende Typen und ist schon vor Step 3 kompilierbar)

- [ ] **Step 3: Flag-Prüfung in `main.swift` einbauen**

In `FeedivoMCPServer/main.swift`, direkt nach dem bestehenden `do { database = try FeedivoMCPServerDatabase.openReadOnly() } catch { ... }`-Block und VOR `let server = Server(...)` einfügen:

```swift
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
```

Die vollständige Datei sieht danach so aus:

```swift
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

let server = Server(
    name: "feedivo-mcp-server",
    version: "1.0.0",
    capabilities: .init(
        tools: .init(listChanged: false)
    )
)

let availableTools: [Tool] = [
    ListFeedsTool.definition,
    ListFoldersTool.definition,
    ListTagsTool.definition,
    SearchArticlesTool.definition,
    GetArticleTool.definition,
    ListSmartFoldersTool.definition,
    GetSmartFolderArticlesTool.definition,
]

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
    default:
        return .init(content: [.text("Unbekanntes Tool: \(params.name)")], isError: true)
    }
}

let transport = StdioTransport()
try await server.start(transport: transport)
await server.waitUntilCompleted()
```

- [ ] **Step 4: Build verifizieren**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme FeedivoMCPServer -configuration Debug build`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Auch das Feedivo-App-Target build-verifizieren**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -configuration Debug build`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 6: Echten Live-Smoke-Test durchführen — deaktiviert vs. aktiviert**

Gebauten Server-Prozess direkt gegen die echte, konfigurierte Container-Datenbank starten (`FeedivoContainerDatabaseLocation.databaseURL()`, kein Override beim direkten Prozessaufruf) — Standardwert ist deaktiviert, das lässt sich also gefahrlos gegen die echte Installation nachvollziehen (keine Datenänderung, nur ein Lesezugriff auf das neue Flag):

```bash
BIN="$(find ~/Library/Developer/Xcode/DerivedData -path '*/Feedivo.app/Contents/MacOS/FeedivoMCPServer' | head -1)"
"$BIN"
```

Erwartet (bei noch nicht manuell aktiviertem Schalter): Prozess beendet sich sofort mit Exit-Code 1, stderr enthält „Feedivo MCP Server ist deaktiviert." Danach in der laufenden Feedivo-App den neuen Schalter „KI-Zugriff" aktivieren (kein Rebuild nötig — die Migration läuft automatisch beim nächsten App-Start bzw. ist durch den vorherigen `xcodebuild build` in Step 5 bereits initialisiert) und den Server erneut starten:

```bash
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"smoke","version":"1.0"}}}' | timeout 5 "$BIN"
```

Erwartet: eine echte JSON-RPC-`initialize`-Antwort (kein sofortiger Exit) — bestätigt, dass der Schalter nach Aktivierung tatsächlich greift. Schalter danach wieder in den ursprünglichen Zustand zurückstellen, falls er vor diesem Test AUS war.

- [ ] **Step 7: Commit**

```bash
git add FeedivoMCPServer/main.swift FeedivoMCPServerTests/MCPServerAccessGateTests.swift
git commit -m "feat(mcp-server): fail-closed Zugriffsprüfung gegen mcp_server_settings

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 5: Regressionslauf + manuelle Live-Verifikationscheckliste

**Files:** Keine neuen Änderungen — reine Abschluss-Verifikation.

- [ ] **Step 1: Vollen gezielten Regressionslauf über die neuen und angrenzenden Suiten**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' test -only-testing:FeedivoTests/FeedivoDatabaseMigratorTests -only-testing:FeedivoTests/MCPServerSettingsStoreTests -parallel-testing-enabled NO`
Expected: `TEST SUCCEEDED`

- [ ] **Step 2: Beide Schemes vollständig bauen**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -configuration Debug build`
Run: `xcodebuild -project Feedivo.xcodeproj -scheme FeedivoMCPServer -configuration Debug build`
Expected: beide `BUILD SUCCEEDED`

- [ ] **Step 3: Manuelle Live-Verifikationscheckliste (durch den Nutzer)**

1. Feedivo starten, Einstellungen → „KI-Zugriff" öffnen — Tab ist da, Tab-Leiste zeigt alle 12 Tabs ohne Abschneiden/Überlauf.
2. Schalter ist standardmäßig AUS (frisch migrierte bzw. bereits genutzte Bestands-Installation).
3. Schalter einschalten, Claude Desktop (falls verbunden) neu starten, eine Testfrage stellen (z. B. „Welche Feeds habe ich?") — funktioniert.
4. Schalter wieder ausschalten, Claude Desktop neu starten, dieselbe Frage stellen — Verbindung/Server-Start scheitert klar erkennbar (kein stiller Erfolg mit leeren Daten).
5. „Kopieren"-Button neben dem Config-Snippet klicken, Inhalt der Zwischenablage prüfen — enthält gültiges JSON mit dem tatsächlich existierenden Binary-Pfad (`file <Pfad>` bestätigt eine echte ausführbare Datei).
6. Hell-/Dunkelmodus: Tab sieht in beiden Darstellungen konsistent zu den übrigen Tabs aus.

- [ ] **Step 4: Nutzer bestätigt Checkliste abgeschlossen, danach Push (nur nach expliziter Bestätigung, siehe Projekt-Konvention)**
