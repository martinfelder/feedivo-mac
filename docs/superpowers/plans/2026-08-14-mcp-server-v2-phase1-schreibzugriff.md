# MCP-Server V2 Phase 1: Schreibzugriff-Fundament Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Der `FeedivoMCPServer` bekommt einen zweiten, standardmäßig deaktivierten Schreibzugriff-Schalter sowie drei Schreib-Tools (`update_article_status`, `assign_tag`, `remove_tag`), plus eine Cross-Process-Live-Refresh-Kette, damit eine laufende Feedivo-App Änderungen von Claude sofort sichtbar macht.

**Architecture:** Eine zweite, schreibbare `DatabasePool`-Verbindung (`FeedivoMCPServerWritableDatabase`) wird nur geöffnet, wenn `MCPServerSettingsStore.isWriteAccessEnabled()` zusätzlich zum bestehenden Hauptschalter `true` liefert — die bestehende readonly-Verbindung bleibt für alle Lese-Tools unverändert. Die drei neuen Tools validieren Eingabe-IDs zuerst auf der readonly-Verbindung (da die Schreib-Store-Methoden unbekannte IDs teils still ignorieren statt zu werfen), schreiben dann über bereits bestehende, geteilte `ArticleStatusStore`/`TagStore`-Methoden. Nach jedem erfolgreichen Schreib-Tool-Aufruf postet der Server eine Darwin-Notification, die eine laufende Feedivo-App über einen neuen Observer empfängt und daraufhin ihre bestehenden `@Observable`-Invalidierungssignale (`SQLiteDataInvalidation`, `SidebarBadgeInvalidation`) bumpt.

**Tech Stack:** Swift, GRDB (DatabasePool), `modelcontextprotocol/swift-sdk` (MCP), Swift Testing, CoreFoundation (`CFNotificationCenterGetDarwinNotifyCenter`).

## Global Constraints

- Zweiter Settings-Schalter "Schreibzugriff erlauben" ist standardmäßig AUS und nur bedienbar, wenn der bestehende Hauptschalter "KI-Zugriff" AN ist. Schaltet der Nutzer den Hauptschalter aus, wird der Schreibzugriff-Schalter automatisch mit auf AUS zurückgesetzt und persistiert.
- Die schreibbare Datenbankverbindung nutzt `DatabasePool` (nicht `DatabaseQueue`) und setzt explizit `PRAGMA foreign_keys = ON` — die bestehende readonly-Verbindung bleibt komplett unverändert.
- Schlägt das Öffnen der Schreibverbindung fehl, degradiert der Server auf reinen Lesezugriff (Warnung nach stderr, kein Absturz) statt zu verweigern.
- Die drei neuen Tools (`update_article_status`, `assign_tag`, `remove_tag`) erscheinen in `ListTools` NUR, wenn Schreibzugriff tatsächlich aktiv ist.
- Kein automatisches Tag-Anlegen — `assign_tag`/`remove_tag` wirken ausschließlich auf bereits existierende Tags und ausschließlich auf Artikel (nicht auf Feeds).
- Unbekannte `articleID`/`tagID` liefern immer eine explizite `isError: true`-Fehlermeldung, niemals einen stillen No-Op.
- Der Server selbst zeigt keine eigene Bestätigungs-UI für Schreibvorgänge — das ist Aufgabe des MCP-Clients.
- Cross-Process-Live-Refresh läuft über eine Darwin-Notification mit dem festen Namen `ch.martin.Feedivo.mcpServerDidWrite`, definiert als einzige Quelle der Wahrheit in einer neuen, von beiden Targets geteilten Datei (`MCPWriteNotificationName.swift`) — keine unabhängig gepflegten String-Literale auf Sender- und Empfängerseite.
- `FeedivoMCPServerTests` kann strukturell nicht per `xcodebuild test` laufen (TEST_HOST-Limitation für Command-Line-Tool-Targets, siehe ADR-011/Gotcha in CLAUDE.md) — Tests in diesem Target werden trotzdem als echter Swift-Testing-Code geschrieben, aber nur per `xcodebuild build` kompilierverifiziert, nicht laufzeitverifiziert. Tests in `FeedivoTests` (Haupt-App-Target) laufen dagegen ganz normal.
- Kommentare im Code auf Deutsch, konsistent mit dem restlichen Projekt.
- Neue Migrationen werden immer als neuer `migrator.registerMigration("vN_…")`-Block angehängt, nie werden bestehende Migrationen nachträglich verändert.

---

### Task 1: Migration v32 + `MCPServerSettingsStore`-Erweiterung für den Schreibzugriff-Schalter

**Files:**
- Modify: `Feedivo/Database/FeedivoDatabaseMigrator.swift:574-589` (nach `v31_create_mcp_server_settings` einfügen)
- Modify: `Feedivo/Stores/MCPServerSettingsStore.swift`
- Test: `FeedivoTests/Database/FeedivoDatabaseMigratorTests.swift`
- Test: `FeedivoTests/Stores/MCPServerSettingsStoreTests.swift`

**Interfaces:**
- Produces: `MCPServerSettingsStore.isWriteAccessEnabled() throws -> Bool` (Standard `false`), `MCPServerSettingsStore.setWriteAccessEnabled(_ isEnabled: Bool) throws`. Wird von Task 2 (Settings-UI) und Task 3 (`main.swift`-Gating) konsumiert.

- [ ] **Step 1: Fehlschlagenden Migrationstest schreiben**

In `FeedivoTests/Database/FeedivoDatabaseMigratorTests.swift`, direkt nach der bestehenden `migrationV31LegtMcpServerSettingsMitDeaktiviertemStandardwertAn`-Testfunktion (endet aktuell bei Zeile 333 mit der schließenden `}` der Testklasse — die neue Funktion kommt VOR diese letzte schließende `}`):

```swift
    @Test func migrationV32FuegtWriteAccessIsEnabledSpalteHinzu() throws {
        let queue = try DatabaseQueue()
        try FeedivoDatabaseMigrator.migrator.migrate(queue, upTo: "v31_create_mcp_server_settings")

        try FeedivoDatabaseMigrator.migrator.migrate(queue)

        let writeAccessIsEnabled = try queue.read { db in
            try Bool.fetchOne(db, sql: "SELECT writeAccessIsEnabled FROM mcp_server_settings WHERE id = 1")
        }
        #expect(writeAccessIsEnabled == false)
    }
```

- [ ] **Step 2: Build ausführen, um den Fehlschlag zu bestätigen**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED (der Test selbst kompiliert), aber `xcodebuild test -only-testing:FeedivoTests/FeedivoDatabaseMigratorTests/migrationV32FuegtWriteAccessIsEnabledSpalteHinzu` schlägt fehl mit "no such column: writeAccessIsEnabled" (bei Einzelmethoden-Selektoren zusätzlich `xcrun xcresulttool get test-results summary` auf das erzeugte `.xcresult`-Bundle prüfen, siehe bestehender Gotcha zu `-only-testing`-Fehlalarmen — im Zweifel den vollen Suiten-Selektor `-only-testing:FeedivoTests/FeedivoDatabaseMigratorTests` verwenden)

- [ ] **Step 3: Migration v32 implementieren**

In `Feedivo/Database/FeedivoDatabaseMigrator.swift`, direkt nach dem bestehenden `v31_create_mcp_server_settings`-Block (nach der schließenden `}` bei Zeile 589, vor `return migrator` bei Zeile 591):

```swift
        migrator.registerMigration("v32_add_mcp_server_write_access") { database in
            // Zweiter, vom Hauptschalter unabhängiger Flag — Schreibzugriff ist ein
            // bewusst separates Opt-in mit größerer Vertrauensgrenze als reines Lesen
            // (siehe MCP-Server-V2-Phase-1-Design). Standard `false`, ADD COLUMN mit
            // konstantem Bool-Default ist unproblematisch (anders als bei einem
            // Datums-/CURRENT_TIMESTAMP-Default, siehe bestehender Gotcha dazu).
            try database.alter(table: "mcp_server_settings") { table in
                table.add(column: "writeAccessIsEnabled", .boolean).notNull().defaults(to: false)
            }
        }
```

- [ ] **Step 4: Build + Migrationstest erneut ausführen, um den Erfolg zu bestätigen**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' test -only-testing:FeedivoTests/FeedivoDatabaseMigratorTests`
Expected: TEST SUCCEEDED, alle Tests in dieser Suite grün (inkl. der neuen Funktion)

- [ ] **Step 5: Fehlschlagende Store-Tests schreiben**

In `FeedivoTests/Stores/MCPServerSettingsStoreTests.swift`, nach der bestehenden `setEnabledPersistiertWert`-Testfunktion (vor `fehlendeTabelleWirdFailClosedAlsFalseBehandelt`):

```swift
    @Test("Standardwert für Schreibzugriff nach Migration ist deaktiviert")
    func standardwertSchreibzugriffIstDeaktiviert() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = MCPServerSettingsStore(database: database)

        #expect(try store.isWriteAccessEnabled() == false)
    }

    @Test("setWriteAccessEnabled persistiert den neuen Wert unabhängig vom Hauptschalter")
    func setWriteAccessEnabledPersistiertWert() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = MCPServerSettingsStore(database: database)

        try store.setWriteAccessEnabled(true)
        #expect(try store.isWriteAccessEnabled() == true)
        // Hauptschalter bleibt vom Schreibzugriff-Flag unberührt.
        #expect(try store.isEnabled() == false)

        try store.setWriteAccessEnabled(false)
        #expect(try store.isWriteAccessEnabled() == false)
    }
```

- [ ] **Step 6: Build ausführen, um den Fehlschlag zu bestätigen**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' build`
Expected: BUILD FAILED mit "value of type 'MCPServerSettingsStore' has no member 'isWriteAccessEnabled'"

- [ ] **Step 7: `MCPServerSettingsStore` erweitern**

In `Feedivo/Stores/MCPServerSettingsStore.swift`, nach der bestehenden `setEnabled(_:)`-Methode (vor der schließenden `}` der Struct):

```swift
    func isWriteAccessEnabled() throws -> Bool {
        try database.read { db in
            try Bool.fetchOne(db, sql: "SELECT writeAccessIsEnabled FROM mcp_server_settings WHERE id = 1") ?? false
        }
    }

    func setWriteAccessEnabled(_ isEnabled: Bool) throws {
        try database.write { db in
            try db.execute(sql: "UPDATE mcp_server_settings SET writeAccessIsEnabled = ? WHERE id = 1", arguments: [isEnabled])
        }
    }
```

- [ ] **Step 8: Build + Tests ausführen, um den Erfolg zu bestätigen**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' test -only-testing:FeedivoTests/MCPServerSettingsStoreTests`
Expected: TEST SUCCEEDED, alle Tests grün

- [ ] **Step 9: Commit**

```bash
git add Feedivo/Database/FeedivoDatabaseMigrator.swift Feedivo/Stores/MCPServerSettingsStore.swift FeedivoTests/Database/FeedivoDatabaseMigratorTests.swift FeedivoTests/Stores/MCPServerSettingsStoreTests.swift
git commit -m "feat(mcp-server): Migration v32 + Schreibzugriff-Flag in MCPServerSettingsStore"
```

---

### Task 2: Settings-UI — Toggle "Schreibzugriff erlauben"

**Files:**
- Modify: `Feedivo/Views/Settings/SettingsView.swift:1639-1743` (`MCPServerSettingsView`)
- Modify: `Feedivo/Resources/L10n.swift:518-523`
- Modify: `Feedivo/Resources/Localizable.xcstrings:144-172` (nach dem bestehenden `settings.mcpServer.snippetDescription`-Block)

**Interfaces:**
- Consumes: `MCPServerSettingsStore.isWriteAccessEnabled()`/`.setWriteAccessEnabled(_:)` aus Task 1.

Kein automatisierter Test möglich — reine SwiftUI-View ohne ViewInspector im Projekt (bestehende Konvention, siehe CLAUDE.md). Build-Verifikation + eine manuelle Live-Verifikations-Notiz am Ende dieser Task.

- [ ] **Step 1: Neue L10n-Keys ergänzen**

In `Feedivo/Resources/L10n.swift`, direkt nach Zeile 523 (`settingsMCPServerSnippetDescription`):

```swift
    static let settingsMCPServerWriteAccessToggleTitle = LocalizedStringKey("settings.mcpServer.writeAccessToggleTitle")
    static let settingsMCPServerWriteAccessToggleDescription = LocalizedStringKey("settings.mcpServer.writeAccessToggleDescription")
```

- [ ] **Step 2: xcstrings-Einträge manuell ergänzen (NICHT per `json.load`/`json.dump` roundtripen, siehe Gotcha)**

In `Feedivo/Resources/Localizable.xcstrings`, den exakten, eindeutigen Textblock

```
            "value" : "Incolla questa voce nel file di configurazione del tuo client IA (per Claude Desktop: ~/Library/Application Support/Claude/claude_desktop_config.json)."
          }
        }
      }
    },
    "" : {
```

ersetzen durch (fügt die zwei neuen Einträge dazwischen ein, lässt alles andere unverändert):

```
            "value" : "Incolla questa voce nel file di configurazione del tuo client IA (per Claude Desktop: ~/Library/Application Support/Claude/claude_desktop_config.json)."
          }
        }
      }
    },
    "settings.mcpServer.writeAccessToggleDescription" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Erlaubt Claude, Artikelstatus (Gelesen/Stern/Versteckt) zu ändern und Tags zuzuweisen. Erfordert vorher aktivierten KI-Zugriff."
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Allows Claude to change article status (read, starred, hidden) and assign tags. Requires AI Access to be enabled first."
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Permet à Claude de modifier le statut des articles (lu, favori, masqué) et d'attribuer des tags. Nécessite que l'accès IA soit activé au préalable."
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Consente a Claude di modificare lo stato degli articoli (letto, preferito, nascosto) e di assegnare tag. Richiede che l'accesso IA sia già attivo."
          }
        }
      }
    },
    "settings.mcpServer.writeAccessToggleTitle" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Schreibzugriff erlauben"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Allow Write Access"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Autoriser l'accès en écriture"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Consenti accesso in scrittura"
          }
        }
      }
    },
    "" : {
```

Nach dem Einfügen per `git diff --stat` verifizieren, dass NUR Insertions entstanden sind (keine oder kaum Deletions) — siehe bestehender Gotcha.

- [ ] **Step 3: `MCPServerSettingsView` um den zweiten Schalter erweitern**

In `Feedivo/Views/Settings/SettingsView.swift`, die komplette bestehende `MCPServerSettingsView`-Struct (Zeilen 1639-1743) ersetzen durch:

```swift
private struct MCPServerSettingsView: View {
    @Environment(\.feedivoDatabase) private var feedivoDatabase

    @State private var isEnabled = false
    @State private var isWriteAccessEnabled = false
    @State private var isLoaded = false
    @State private var saveErrorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GeneralSettingsSection(label: Text(L10n.settingsMCPServerSectionTitle)) {
                Toggle(isOn: isEnabledBinding) {
                    Text(L10n.settingsMCPServerToggleTitle)
                        .font(.system(size: 13))
                }
                .toggleStyle(.checkbox)
                .tint(Color.settingsBoldAccent)
                .disabled(!isLoaded)
                GeneralSettingsHelp(L10n.settingsMCPServerToggleDescription)

                Toggle(isOn: isWriteAccessEnabledBinding) {
                    Text(L10n.settingsMCPServerWriteAccessToggleTitle)
                        .font(.system(size: 13))
                }
                .toggleStyle(.checkbox)
                .tint(Color.settingsBoldAccent)
                .disabled(!isLoaded || !isEnabled)
                .padding(.leading, 20)
                GeneralSettingsHelp(L10n.settingsMCPServerWriteAccessToggleDescription)
                    .padding(.leading, 20)

                if let saveErrorMessage {
                    Text(saveErrorMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }

                GeneralSettingsRow(title: L10n.settingsMCPServerConnectionRowTitle) {
                    Button(L10n.settingsMCPServerCopyButton) {
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
                GeneralSettingsHelp(L10n.settingsMCPServerSnippetDescription)
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

    // Custom Binding statt `$isEnabled` + `.onChange(of:)` (Task-3-Review-Fix, 2026-08-14):
    // `load()` setzt `isEnabled` programmatisch VOR `isLoaded = true`, beides im selben
    // synchronen Ausführungsschritt (die Store-Methode `isEnabled()` ist nicht suspendierend).
    // Ein `.onChange(of: isEnabled)`-Handler liest `isLoaded` aber erst beim tatsächlichen
    // Feuern des Callbacks — also potenziell NACH beiden Zuweisungen, nicht zum Zeitpunkt des
    // `isEnabled`-Sprungs eingefroren. War der Schalter beim Öffnen bereits aktiviert, hätte
    // der `guard isLoaded else { return }`-Schutz dadurch nicht zuverlässig gegriffen und
    // `saveEnabled(true)` wäre unnötig beim reinen Laden aufgerufen worden (harmlos, aber bei
    // einem transienten DB-Fehler wäre die Fehlermeldung ganz ohne Nutzerinteraktion
    // aufgeblitzt). Der Setter dieses Bindings feuert dagegen AUSSCHLIESSLICH bei echter
    // Nutzerinteraktion über den `Toggle` — `load()` schreibt `isEnabled` direkt als
    // `@State`-Property, nicht über dieses Binding, und löst den Setter deshalb nie aus.
    private var isEnabledBinding: Binding<Bool> {
        Binding(
            get: { isEnabled },
            set: { newValue in
                isEnabled = newValue
                guard isLoaded else { return }
                saveEnabled(newValue)

                // Schaltet der Nutzer den Hauptschalter aus, muss der Schreibzugriff-Schalter
                // mit zurückgesetzt werden — sonst bliebe ein still im Hintergrund weiter
                // aktiver Schreib-Flag bestehen, der beim erneuten Einschalten des
                // Hauptschalters überraschend wieder wirksam würde, ohne dass der Nutzer sich
                // daran erinnert, ihn selbst gesetzt zu haben.
                if !newValue, isWriteAccessEnabled {
                    isWriteAccessEnabled = false
                    saveWriteAccessEnabled(false)
                }
            }
        )
    }

    private var isWriteAccessEnabledBinding: Binding<Bool> {
        Binding(
            get: { isWriteAccessEnabled },
            set: { newValue in
                isWriteAccessEnabled = newValue
                guard isLoaded else { return }
                saveWriteAccessEnabled(newValue)
            }
        )
    }

    private func load() async {
        guard let feedivoDatabase else { return }
        let store = MCPServerSettingsStore(database: feedivoDatabase)
        isEnabled = (try? store.isEnabled()) ?? false
        isWriteAccessEnabled = (try? store.isWriteAccessEnabled()) ?? false
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

    private func saveWriteAccessEnabled(_ newValue: Bool) {
        guard let feedivoDatabase else { return }
        let store = MCPServerSettingsStore(database: feedivoDatabase)
        do {
            try store.setWriteAccessEnabled(newValue)
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

- [ ] **Step 4: Build ausführen**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Views/Settings/SettingsView.swift Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings
git commit -m "feat(mcp-server): Schreibzugriff-Toggle in den KI-Zugriff-Einstellungen"
```

**Hinweis für die manuelle Live-Verifikation am Ende von Task 7:** Schreibzugriff-Schalter ist ausgegraut, solange Hauptschalter aus ist; wird beim Ausschalten des Hauptschalters automatisch mit deaktiviert; bleibt nach App-Neustart korrekt persistiert.

---

### Task 3: `FeedivoMCPServerWritableDatabase` + `main.swift`-Gating

**Files:**
- Create: `FeedivoMCPServer/FeedivoMCPServerWritableDatabase.swift`
- Modify: `FeedivoMCPServer/main.swift`
- Test: `FeedivoMCPServerTests/FeedivoMCPServerWritableDatabaseTests.swift`

**Interfaces:**
- Consumes: `FeedivoMCPServerDatabaseError` (bestehend, aus `FeedivoMCPServerDatabase.swift`), `FeedivoContainerDatabaseLocation.databaseURL()` (bestehend), `MCPServerSettingsStore.isWriteAccessEnabled()` aus Task 1.
- Produces: `struct FeedivoMCPServerWritableDatabase { let core: FeedivoDatabase; static func open(at: URL = ...) throws -> FeedivoMCPServerWritableDatabase }`. Wird von Task 4/5 (Tools) und Task 6 (main.swift-Dispatch) konsumiert. `main.swift` deklariert ab dieser Task `var writableDatabase: FeedivoMCPServerWritableDatabase?` und `var availableTools: [Tool]` (vorher `let`).

- [ ] **Step 1: Testdatei schreiben (dokumentiert erwartetes Verhalten, wird build- statt laufzeitverifiziert — siehe Global Constraints zur `FeedivoMCPServerTests`-TEST_HOST-Limitation)**

`FeedivoMCPServerTests/FeedivoMCPServerWritableDatabaseTests.swift`:

```swift
import Testing
import Foundation
import GRDB
@testable import FeedivoMCPServer

@Suite("FeedivoMCPServerWritableDatabase")
struct FeedivoMCPServerWritableDatabaseTests {
    @Test("Öffnet eine bestehende, migrierte Feedivo-Datenbank schreibbar")
    func oeffnetBestehendeDatenbankSchreibbar() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let dbURL = tempDir.appendingPathComponent("feedivo.sqlite")

        _ = try FeedivoDatabase.open(at: dbURL)

        let server = try FeedivoMCPServerWritableDatabase.open(at: dbURL)
        try server.core.write { db in
            try db.execute(sql: "DELETE FROM feeds")
        }
        let count = try server.core.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM feeds") ?? -1
        }
        #expect(count == 0)
    }

    @Test("Setzt PRAGMA foreign_keys — Fremdschlüsselverletzung schlägt fehl")
    func setztForeignKeysPragma() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let dbURL = tempDir.appendingPathComponent("feedivo.sqlite")
        _ = try FeedivoDatabase.open(at: dbURL)

        let server = try FeedivoMCPServerWritableDatabase.open(at: dbURL)

        #expect(throws: (any Error).self) {
            try server.core.write { db in
                try db.execute(
                    sql: "INSERT INTO article_tags (articleID, tagID, assignedAt) VALUES (?, ?, ?)",
                    arguments: ["does-not-exist", "does-not-exist", Date()]
                )
            }
        }
    }

    @Test("Wirft databaseFileNotFound, wenn die Datei nicht existiert")
    func wirftFehlerBeiFehlenderDatei() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString).sqlite")

        #expect(throws: FeedivoMCPServerDatabaseError.self) {
            try FeedivoMCPServerWritableDatabase.open(at: missing)
        }
    }
}
```

- [ ] **Step 2: Build ausführen, um zu bestätigen, dass der Test NICHT kompiliert (Typ existiert noch nicht)**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme FeedivoMCPServer -destination 'platform=macOS' build`
Expected: BUILD FAILED mit "cannot find 'FeedivoMCPServerWritableDatabase' in scope"

- [ ] **Step 3: `FeedivoMCPServerWritableDatabase` implementieren**

`FeedivoMCPServer/FeedivoMCPServerWritableDatabase.swift`:

```swift
import Foundation
import GRDB

/// Schreibbarer Zugriff auf die Feedivo-Datenbank für Schreib-Tools (Phase 1 des
/// MCP-Server-V2-Plans) — nur genutzt, wenn der Nutzer den Schreibzugriff-Schalter in den
/// Einstellungen ZUSÄTZLICH zum Hauptschalter aktiviert hat (siehe MCPServerSettingsStore).
///
/// Nutzt DatabasePool (nicht DatabaseQueue) — matcht den Schreib-Modus der Haupt-App (siehe
/// FeedivoDatabase.swift) und erlaubt echte WAL-Parallelität zur ggf. gleichzeitig laufenden
/// Feedivo-App. `PRAGMA foreign_keys = ON` wird explizit gesetzt (anders als bei
/// FeedivoMCPServerDatabase.openReadOnly, die das nie braucht) — die Schreib-Tools verlassen
/// sich auf Fremdschlüssel-Verletzungen, um Schreibvorgänge mit ungültigen IDs zuverlässig
/// abzulehnen. Führt bewusst NIE FeedivoDatabaseMigrator aus, wie die readonly-Verbindung auch.
struct FeedivoMCPServerWritableDatabase {
    let core: FeedivoDatabase

    static func open(
        at fileURL: URL = FeedivoContainerDatabaseLocation.databaseURL()
    ) throws -> FeedivoMCPServerWritableDatabase {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw FeedivoMCPServerDatabaseError.databaseFileNotFound(fileURL)
        }

        var configuration = Configuration()
        configuration.busyMode = .timeout(5)
        configuration.prepareDatabase { database in
            try database.execute(sql: "PRAGMA foreign_keys = ON")
        }

        do {
            let pool = try DatabasePool(path: fileURL.path, configuration: configuration)
            return FeedivoMCPServerWritableDatabase(core: FeedivoDatabase(writer: pool))
        } catch {
            throw FeedivoMCPServerDatabaseError.openFailed(description: "\(error)")
        }
    }
}
```

- [ ] **Step 4: Build ausführen, um die erfolgreiche Kompilierung zu bestätigen**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme FeedivoMCPServer -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: `main.swift` um das Gating für den Schreibzugriff erweitern**

In `FeedivoMCPServer/main.swift`, den Block

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

let server = Server(
```

ersetzen durch:

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
```

Und den Block

```swift
let availableTools: [Tool] = [
```

ersetzen durch:

```swift
var availableTools: [Tool] = [
```

(Nur das eine Schlüsselwort `let` → `var` ändert sich, der Rest des Arrays bleibt unverändert — die drei Schreib-Tools werden erst in Task 4/5 bedingt angehängt.)

- [ ] **Step 6: Build ausführen**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme FeedivoMCPServer -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED (keine funktionale Änderung sichtbar, da noch keine Schreib-Tools existieren — reine Vorbereitung)

- [ ] **Step 7: Commit**

```bash
git add FeedivoMCPServer/FeedivoMCPServerWritableDatabase.swift FeedivoMCPServer/main.swift FeedivoMCPServerTests/FeedivoMCPServerWritableDatabaseTests.swift
git commit -m "feat(mcp-server): schreibbare DatabasePool-Verbindung + main.swift-Gating fuer Schreibzugriff"
```

---

### Task 4: Tool `update_article_status`

**Files:**
- Create: `FeedivoMCPServer/Tools/UpdateArticleStatusTool.swift`
- Modify: `FeedivoMCPServer/main.swift`
- Test: `FeedivoMCPServerTests/UpdateArticleStatusToolTests.swift`

**Interfaces:**
- Consumes: `FeedivoMCPServerDatabase`/`FeedivoMCPServerWritableDatabase` aus Task 3, bestehende `ArticleDatabase(database:).readerArticle(id:) throws -> ArticleReaderSnapshot?`, bestehende `ArticleStatusStore(database:).setRead(_:articleID:at:)`/`.setStarred(_:articleID:at:)`/`.setHidden(_:articleID:at:)`.
- Produces: `UpdateArticleStatusTool.definition: Tool`, `UpdateArticleStatusTool.call(readDatabase:writeDatabase:arguments:) throws -> CallTool.Result`. Wird von Task 6 (Cross-Process-Notify-Liste) referenziert.

- [ ] **Step 1: Testdatei schreiben**

`FeedivoMCPServerTests/UpdateArticleStatusToolTests.swift`:

```swift
import Testing
import Foundation
import GRDB
import MCP
@testable import FeedivoMCPServer

@Suite("UpdateArticleStatusTool")
struct UpdateArticleStatusToolTests {
    @Test("Setzt isRead und persistiert den neuen Status")
    func setztIsRead() throws {
        let core = try FeedivoDatabase.inMemoryForTests()
        let articleID = try makeArticle(in: core)
        let readDatabase = FeedivoMCPServerDatabase(core: core)
        let writeDatabase = FeedivoMCPServerWritableDatabase(core: core)

        let result = try UpdateArticleStatusTool.call(
            readDatabase: readDatabase,
            writeDatabase: writeDatabase,
            arguments: ["articleID": .string(articleID), "isRead": .bool(true)]
        )

        #expect(result.isError == false)
        let status = try ArticleStatusStore(database: core).status(articleID: articleID)
        #expect(status?.isRead == true)
    }

    @Test("Setzt mehrere Felder in einem Aufruf")
    func setztMehrereFelder() throws {
        let core = try FeedivoDatabase.inMemoryForTests()
        let articleID = try makeArticle(in: core)
        let readDatabase = FeedivoMCPServerDatabase(core: core)
        let writeDatabase = FeedivoMCPServerWritableDatabase(core: core)

        let result = try UpdateArticleStatusTool.call(
            readDatabase: readDatabase,
            writeDatabase: writeDatabase,
            arguments: [
                "articleID": .string(articleID),
                "isRead": .bool(true),
                "isStarred": .bool(true),
            ]
        )

        #expect(result.isError == false)
        let status = try ArticleStatusStore(database: core).status(articleID: articleID)
        #expect(status?.isRead == true)
        #expect(status?.isStarred == true)
    }

    @Test("Liefert einen Fehler bei unbekannter Artikel-ID")
    func liefertFehlerBeiUnbekannterID() throws {
        let core = try FeedivoDatabase.inMemoryForTests()
        let readDatabase = FeedivoMCPServerDatabase(core: core)
        let writeDatabase = FeedivoMCPServerWritableDatabase(core: core)

        let result = try UpdateArticleStatusTool.call(
            readDatabase: readDatabase,
            writeDatabase: writeDatabase,
            arguments: ["articleID": .string("does-not-exist"), "isRead": .bool(true)]
        )

        #expect(result.isError == true)
    }

    @Test("Liefert einen Fehler, wenn kein Statusfeld gesetzt ist")
    func liefertFehlerOhneStatusfeld() throws {
        let core = try FeedivoDatabase.inMemoryForTests()
        let articleID = try makeArticle(in: core)
        let readDatabase = FeedivoMCPServerDatabase(core: core)
        let writeDatabase = FeedivoMCPServerWritableDatabase(core: core)

        let result = try UpdateArticleStatusTool.call(
            readDatabase: readDatabase,
            writeDatabase: writeDatabase,
            arguments: ["articleID": .string(articleID)]
        )

        #expect(result.isError == true)
    }

    @Test("Liefert einen Fehler bei fehlendem articleID-Parameter")
    func liefertFehlerBeiFehlendemParameter() throws {
        let core = try FeedivoDatabase.inMemoryForTests()
        let readDatabase = FeedivoMCPServerDatabase(core: core)
        let writeDatabase = FeedivoMCPServerWritableDatabase(core: core)

        let result = try UpdateArticleStatusTool.call(
            readDatabase: readDatabase,
            writeDatabase: writeDatabase,
            arguments: [:]
        )

        #expect(result.isError == true)
    }

    private func makeArticle(in core: FeedivoDatabase) throws -> String {
        let feedID = try core.write { db -> String in
            var feed = FeedRecord(url: "https://example.com/feed", title: "Test-Feed")
            try feed.insert(db)
            return feed.id
        }
        return try ArticleStore(database: core).upsert(
            ArticleUpsertInput(feedID: feedID, title: "Testartikel", content: "<p>Inhalt</p>", arrivedAt: Date())
        )
    }
}
```

- [ ] **Step 2: Build ausführen, um zu bestätigen, dass der Test NICHT kompiliert**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme FeedivoMCPServer -destination 'platform=macOS' build`
Expected: BUILD FAILED mit "cannot find 'UpdateArticleStatusTool' in scope"

- [ ] **Step 3: `UpdateArticleStatusTool` implementieren**

`FeedivoMCPServer/Tools/UpdateArticleStatusTool.swift`:

```swift
import MCP
import Foundation

enum UpdateArticleStatusTool {
    static let definition = Tool(
        name: "update_article_status",
        description: """
            Setzt Gelesen-/Stern-/Versteckt-Status eines Artikels. Mindestens eines der \
            drei optionalen Felder muss gesetzt sein.
            """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "articleID": .object([
                    "type": .string("string"),
                    "description": .string("Die Artikel-ID aus search_articles oder get_article"),
                ]),
                "isRead": .object([
                    "type": .string("boolean"),
                    "description": .string("Optional: Gelesen-Status setzen"),
                ]),
                "isStarred": .object([
                    "type": .string("boolean"),
                    "description": .string("Optional: Stern-Status setzen"),
                ]),
                "isHidden": .object([
                    "type": .string("boolean"),
                    "description": .string("Optional: Versteckt-Status setzen"),
                ]),
            ]),
            "required": .array([.string("articleID")]),
        ])
    )

    static func call(
        readDatabase: FeedivoMCPServerDatabase,
        writeDatabase: FeedivoMCPServerWritableDatabase,
        arguments: [String: Value]?
    ) throws -> CallTool.Result {
        guard let articleID = arguments?["articleID"]?.stringValue else {
            return .init(content: [.text("Fehlender Parameter: articleID")], isError: true)
        }

        let isRead = arguments?["isRead"]?.boolValue
        let isStarred = arguments?["isStarred"]?.boolValue
        let isHidden = arguments?["isHidden"]?.boolValue

        guard isRead != nil || isStarred != nil || isHidden != nil else {
            return .init(content: [.text("Mindestens eines von isRead, isStarred, isHidden muss gesetzt sein.")], isError: true)
        }

        // Existenz-Check auf der readonly-Verbindung, BEVOR geschrieben wird — setRead/
        // setStarred/setHidden führen intern nur ein UPDATE ... WHERE articleID = ? aus und
        // werfen bei unbekannter ID keinen Fehler (0 betroffene Zeilen bleibt still), deshalb
        // hier explizit prüfen statt uns auf einen Store-Fehler zu verlassen.
        let articleDatabase = ArticleDatabase(database: readDatabase.core)
        guard try articleDatabase.readerArticle(id: articleID) != nil else {
            return .init(content: [.text("Kein Artikel mit ID \(articleID) gefunden.")], isError: true)
        }

        let statusStore = ArticleStatusStore(database: writeDatabase.core)
        let now = Date()
        var changedFields: [String] = []

        if let isRead {
            try statusStore.setRead(isRead, articleID: articleID, at: now)
            changedFields.append("isRead=\(isRead)")
        }
        if let isStarred {
            try statusStore.setStarred(isStarred, articleID: articleID, at: now)
            changedFields.append("isStarred=\(isStarred)")
        }
        if let isHidden {
            try statusStore.setHidden(isHidden, articleID: articleID, at: now)
            changedFields.append("isHidden=\(isHidden)")
        }

        return .init(content: [.text("Artikel \(articleID) aktualisiert: \(changedFields.joined(separator: ", "))")], isError: false)
    }
}
```

- [ ] **Step 4: Tool im Server registrieren**

In `FeedivoMCPServer/main.swift`, das `availableTools`-Array (siehe Task 3) erweitern — direkt nach dem `if isWriteAccessEnabled { do { writableDatabase = ... } catch { ... } }`-Block einen neuen Block ergänzen:

```swift
if let writableDatabase {
    availableTools.append(UpdateArticleStatusTool.definition)
}
```

(WICHTIG: Dieser Block muss NACH der Deklaration von `availableTools` stehen, also nach dem `var availableTools: [Tool] = [ ... ]`-Array-Literal, nicht davor — sonst schlägt die Referenz auf `availableTools` fehl.)

Im `CallTool`-Dispatch (`switch params.name { ... }`), direkt vor dem `default:`-Fall:

```swift
    case "update_article_status":
        guard let writableDatabase else {
            return .init(content: [.text("Schreibzugriff ist nicht aktiviert.")], isError: true)
        }
        return try UpdateArticleStatusTool.call(readDatabase: database, writeDatabase: writableDatabase, arguments: params.arguments)
```

- [ ] **Step 5: Build ausführen, um die erfolgreiche Kompilierung zu bestätigen**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme FeedivoMCPServer -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add FeedivoMCPServer/Tools/UpdateArticleStatusTool.swift FeedivoMCPServer/main.swift FeedivoMCPServerTests/UpdateArticleStatusToolTests.swift
git commit -m "feat(mcp-server): Tool update_article_status (Gelesen/Stern/Versteckt setzen)"
```

---

### Task 5: Tools `assign_tag` / `remove_tag`

**Files:**
- Create: `FeedivoMCPServer/Tools/AssignTagTool.swift`
- Create: `FeedivoMCPServer/Tools/RemoveTagTool.swift`
- Modify: `FeedivoMCPServer/main.swift`
- Test: `FeedivoMCPServerTests/AssignRemoveTagToolTests.swift`

**Interfaces:**
- Consumes: `ArticleDatabase(database:).readerArticle(id:)`, `TagStore(database:).sidebarTags() throws -> [TagSidebarSnapshot]` (bestehend, `.id`/`.name` Felder), `TagStore(database:).tags(articleID:) throws -> [TagRecord]` (bestehend, `.id` Feld), `TagStore(database:).assignTag(tagID:toArticleID:at:)`/`.removeTag(tagID:fromArticleID:)` (bestehend).
- Produces: `AssignTagTool.definition`/`.call(...)`, `RemoveTagTool.definition`/`.call(...)` — identische Signatur wie `UpdateArticleStatusTool.call(readDatabase:writeDatabase:arguments:)`. Wird von Task 6 referenziert.

- [ ] **Step 1: Testdatei schreiben**

`FeedivoMCPServerTests/AssignRemoveTagToolTests.swift`:

```swift
import Testing
import Foundation
import GRDB
import MCP
@testable import FeedivoMCPServer

@Suite("AssignTagTool und RemoveTagTool")
struct AssignRemoveTagToolTests {
    @Test("assign_tag weist einen bestehenden Tag einem Artikel zu")
    func assignTagWeistTagZu() throws {
        let core = try FeedivoDatabase.inMemoryForTests()
        let articleID = try makeArticle(in: core)
        let tagID = try makeTag(in: core, name: "Swift")
        let readDatabase = FeedivoMCPServerDatabase(core: core)
        let writeDatabase = FeedivoMCPServerWritableDatabase(core: core)

        let result = try AssignTagTool.call(
            readDatabase: readDatabase,
            writeDatabase: writeDatabase,
            arguments: ["articleID": .string(articleID), "tagID": .string(tagID)]
        )

        #expect(result.isError == false)
        let tags = try TagStore(database: core).tags(articleID: articleID)
        #expect(tags.contains { $0.id == tagID })
    }

    @Test("assign_tag liefert einen Fehler bei unbekannter tagID")
    func assignTagFehlerBeiUnbekannterTagID() throws {
        let core = try FeedivoDatabase.inMemoryForTests()
        let articleID = try makeArticle(in: core)
        let readDatabase = FeedivoMCPServerDatabase(core: core)
        let writeDatabase = FeedivoMCPServerWritableDatabase(core: core)

        let result = try AssignTagTool.call(
            readDatabase: readDatabase,
            writeDatabase: writeDatabase,
            arguments: ["articleID": .string(articleID), "tagID": .string("does-not-exist")]
        )

        #expect(result.isError == true)
    }

    @Test("assign_tag liefert einen Fehler bei unbekannter articleID")
    func assignTagFehlerBeiUnbekannterArticleID() throws {
        let core = try FeedivoDatabase.inMemoryForTests()
        let tagID = try makeTag(in: core, name: "Swift")
        let readDatabase = FeedivoMCPServerDatabase(core: core)
        let writeDatabase = FeedivoMCPServerWritableDatabase(core: core)

        let result = try AssignTagTool.call(
            readDatabase: readDatabase,
            writeDatabase: writeDatabase,
            arguments: ["articleID": .string("does-not-exist"), "tagID": .string(tagID)]
        )

        #expect(result.isError == true)
    }

    @Test("remove_tag entfernt einen zugewiesenen Tag")
    func removeTagEntferntTag() throws {
        let core = try FeedivoDatabase.inMemoryForTests()
        let articleID = try makeArticle(in: core)
        let tagID = try makeTag(in: core, name: "Swift")
        try TagStore(database: core).assignTag(tagID: tagID, toArticleID: articleID, at: Date())
        let readDatabase = FeedivoMCPServerDatabase(core: core)
        let writeDatabase = FeedivoMCPServerWritableDatabase(core: core)

        let result = try RemoveTagTool.call(
            readDatabase: readDatabase,
            writeDatabase: writeDatabase,
            arguments: ["articleID": .string(articleID), "tagID": .string(tagID)]
        )

        #expect(result.isError == false)
        let tags = try TagStore(database: core).tags(articleID: articleID)
        #expect(!tags.contains { $0.id == tagID })
    }

    @Test("remove_tag ist idempotent, wenn der Tag gar nicht zugewiesen war")
    func removeTagIstIdempotent() throws {
        let core = try FeedivoDatabase.inMemoryForTests()
        let articleID = try makeArticle(in: core)
        let tagID = try makeTag(in: core, name: "Swift")
        let readDatabase = FeedivoMCPServerDatabase(core: core)
        let writeDatabase = FeedivoMCPServerWritableDatabase(core: core)

        let result = try RemoveTagTool.call(
            readDatabase: readDatabase,
            writeDatabase: writeDatabase,
            arguments: ["articleID": .string(articleID), "tagID": .string(tagID)]
        )

        #expect(result.isError == false)
    }

    @Test("remove_tag liefert einen Fehler bei unbekannter tagID")
    func removeTagFehlerBeiUnbekannterTagID() throws {
        let core = try FeedivoDatabase.inMemoryForTests()
        let articleID = try makeArticle(in: core)
        let readDatabase = FeedivoMCPServerDatabase(core: core)
        let writeDatabase = FeedivoMCPServerWritableDatabase(core: core)

        let result = try RemoveTagTool.call(
            readDatabase: readDatabase,
            writeDatabase: writeDatabase,
            arguments: ["articleID": .string(articleID), "tagID": .string("does-not-exist")]
        )

        #expect(result.isError == true)
    }

    private func makeArticle(in core: FeedivoDatabase) throws -> String {
        let feedID = try core.write { db -> String in
            var feed = FeedRecord(url: "https://example.com/feed", title: "Test-Feed")
            try feed.insert(db)
            return feed.id
        }
        return try ArticleStore(database: core).upsert(
            ArticleUpsertInput(feedID: feedID, title: "Testartikel", content: "<p>Inhalt</p>", arrivedAt: Date())
        )
    }

    private func makeTag(in core: FeedivoDatabase, name: String) throws -> String {
        var tag = TagRecord(name: name)
        try core.write { db in try tag.insert(db) }
        return tag.id
    }
}
```

- [ ] **Step 2: Build ausführen, um zu bestätigen, dass der Test NICHT kompiliert**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme FeedivoMCPServer -destination 'platform=macOS' build`
Expected: BUILD FAILED mit "cannot find 'AssignTagTool' in scope"

- [ ] **Step 3: `AssignTagTool` implementieren**

`FeedivoMCPServer/Tools/AssignTagTool.swift`:

```swift
import MCP
import Foundation

enum AssignTagTool {
    static let definition = Tool(
        name: "assign_tag",
        description: """
            Weist einen bestehenden Tag einem Artikel zu. Der Tag muss bereits existieren \
            (siehe list_tags) — legt keine neuen Tags an.
            """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "articleID": .object([
                    "type": .string("string"),
                    "description": .string("Die Artikel-ID aus search_articles oder get_article"),
                ]),
                "tagID": .object([
                    "type": .string("string"),
                    "description": .string("Die Tag-ID aus list_tags"),
                ]),
            ]),
            "required": .array([.string("articleID"), .string("tagID")]),
        ])
    )

    static func call(
        readDatabase: FeedivoMCPServerDatabase,
        writeDatabase: FeedivoMCPServerWritableDatabase,
        arguments: [String: Value]?
    ) throws -> CallTool.Result {
        guard let articleID = arguments?["articleID"]?.stringValue else {
            return .init(content: [.text("Fehlender Parameter: articleID")], isError: true)
        }
        guard let tagID = arguments?["tagID"]?.stringValue else {
            return .init(content: [.text("Fehlender Parameter: tagID")], isError: true)
        }

        // Explizite Existenz-Checks auf der readonly-Verbindung: TagStore.assignTag nutzt
        // `insert(db, onConflict: .ignore)` — SQLite unterdrückt damit STILL auch
        // Fremdschlüssel-Verletzungen (nicht nur Unique-/PK-Konflikte), ein Aufruf mit
        // ungültiger articleID/tagID würde also klaglos nichts tun statt zu werfen.
        let articleDatabase = ArticleDatabase(database: readDatabase.core)
        guard try articleDatabase.readerArticle(id: articleID) != nil else {
            return .init(content: [.text("Kein Artikel mit ID \(articleID) gefunden.")], isError: true)
        }

        let tagStore = TagStore(database: readDatabase.core)
        guard try tagStore.sidebarTags().contains(where: { $0.id == tagID }) else {
            return .init(content: [.text("Kein Tag mit ID \(tagID) gefunden.")], isError: true)
        }

        try TagStore(database: writeDatabase.core).assignTag(tagID: tagID, toArticleID: articleID, at: Date())

        return .init(content: [.text("Tag \(tagID) wurde Artikel \(articleID) zugewiesen.")], isError: false)
    }
}
```

- [ ] **Step 4: `RemoveTagTool` implementieren**

`FeedivoMCPServer/Tools/RemoveTagTool.swift`:

```swift
import MCP
import Foundation

enum RemoveTagTool {
    static let definition = Tool(
        name: "remove_tag",
        description: "Entfernt einen Tag von einem Artikel. Kein Fehler, falls der Tag dem Artikel ohnehin nicht zugewiesen war.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "articleID": .object([
                    "type": .string("string"),
                    "description": .string("Die Artikel-ID aus search_articles oder get_article"),
                ]),
                "tagID": .object([
                    "type": .string("string"),
                    "description": .string("Die Tag-ID aus list_tags"),
                ]),
            ]),
            "required": .array([.string("articleID"), .string("tagID")]),
        ])
    )

    static func call(
        readDatabase: FeedivoMCPServerDatabase,
        writeDatabase: FeedivoMCPServerWritableDatabase,
        arguments: [String: Value]?
    ) throws -> CallTool.Result {
        guard let articleID = arguments?["articleID"]?.stringValue else {
            return .init(content: [.text("Fehlender Parameter: articleID")], isError: true)
        }
        guard let tagID = arguments?["tagID"]?.stringValue else {
            return .init(content: [.text("Fehlender Parameter: tagID")], isError: true)
        }

        let articleDatabase = ArticleDatabase(database: readDatabase.core)
        guard try articleDatabase.readerArticle(id: articleID) != nil else {
            return .init(content: [.text("Kein Artikel mit ID \(articleID) gefunden.")], isError: true)
        }

        let tagStore = TagStore(database: readDatabase.core)
        guard try tagStore.sidebarTags().contains(where: { $0.id == tagID }) else {
            return .init(content: [.text("Kein Tag mit ID \(tagID) gefunden.")], isError: true)
        }

        try TagStore(database: writeDatabase.core).removeTag(tagID: tagID, fromArticleID: articleID)

        return .init(content: [.text("Tag \(tagID) wurde von Artikel \(articleID) entfernt.")], isError: false)
    }
}
```

- [ ] **Step 5: Tools im Server registrieren**

In `FeedivoMCPServer/main.swift`, den in Task 4 eingefügten Block

```swift
if let writableDatabase {
    availableTools.append(UpdateArticleStatusTool.definition)
}
```

erweitern zu:

```swift
if let writableDatabase {
    availableTools.append(contentsOf: [
        UpdateArticleStatusTool.definition,
        AssignTagTool.definition,
        RemoveTagTool.definition,
    ])
}
```

Im `CallTool`-Dispatch, direkt nach dem in Task 4 ergänzten `case "update_article_status":`-Fall, vor `default:`:

```swift
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
```

- [ ] **Step 6: Build ausführen, um die erfolgreiche Kompilierung zu bestätigen**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme FeedivoMCPServer -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Commit**

```bash
git add FeedivoMCPServer/Tools/AssignTagTool.swift FeedivoMCPServer/Tools/RemoveTagTool.swift FeedivoMCPServer/main.swift FeedivoMCPServerTests/AssignRemoveTagToolTests.swift
git commit -m "feat(mcp-server): Tools assign_tag und remove_tag"
```

---

### Task 6: Cross-Process-Live-Refresh (Darwin-Notification)

**Files:**
- Create: `Feedivo/Services/MCPWriteNotificationName.swift` (geteilte Konstante, [MANUELL] Xcode-Target-Membership-Schritt nötig)
- Create: `FeedivoMCPServer/MCPWriteNotifier.swift`
- Create: `Feedivo/Services/MCPWriteObserver.swift`
- Modify: `Feedivo/App/FeedivoAppDelegate.swift`
- Modify: `FeedivoMCPServer/main.swift`
- Test: `FeedivoTests/Services/MCPWriteObserverTests.swift` (läuft echt, siehe unten)
- Test: `FeedivoMCPServerTests/MCPWriteNotifierTests.swift` (build-verifiziert)

**Interfaces:**
- Produces: `MCPWriteNotificationName.darwin: CFString`, `MCPWriteNotifier.writeToolNames: Set<String>`, `MCPWriteNotifier.notifyDidWrite()`, `MCPWriteObserver.startObserving()`.
- Consumes: `SQLiteDataInvalidation.shared.bumpStatusVersion()`, `SidebarBadgeInvalidation.shared.bumpDirectTagVersion()` (beide bestehend).

- [ ] **Step 1: Geteilte Notification-Name-Konstante anlegen**

`Feedivo/Services/MCPWriteNotificationName.swift`:

```swift
import Foundation

/// Gemeinsam von FeedivoMCPServer (Sender, siehe MCPWriteNotifier.swift) und Feedivo
/// (Empfänger, siehe MCPWriteObserver.swift) genutzter Name für die Darwin-Notification, die
/// nach jedem erfolgreichen Schreib-Tool-Aufruf gepostet wird. In einer eigenen, von beiden
/// Targets geteilten Datei definiert, damit Sender und Empfänger nicht unabhängig voneinander
/// denselben String-Literal pflegen (Tippfehler-Risiko würde die gesamte Live-Refresh-Kette
/// lautlos brechen, ohne dass irgendwo ein Fehler sichtbar würde).
enum MCPWriteNotificationName {
    static let darwin = "ch.martin.Feedivo.mcpServerDidWrite" as CFString
}
```

- [ ] **Step 2 [MANUELL — erfordert Xcode-GUI]: Datei zur FeedivoMCPServer-Target-Membership hinzufügen**

Diese Datei muss — wie bereits `Stores/MCPServerSettingsStore.swift` beim Schalter-Feature — zusätzlich zum Haupt-Target `Feedivo` auch dem Target `FeedivoMCPServer` sichtbar gemacht werden (sonst kompiliert `FeedivoMCPServer/MCPWriteNotifier.swift` in Step 4 nicht):

1. In Xcode im Project Navigator `Feedivo/Services/MCPWriteNotificationName.swift` auswählen
2. Im Datei-Inspector (⌥⌘1, rechte Seitenleiste) unter "Target Membership" zusätzlich die Checkbox `FeedivoMCPServer` aktivieren (neben der bereits aktivierten `Feedivo`-Checkbox)
3. Bestätigen: `xcodebuild -project Feedivo.xcodeproj -scheme FeedivoMCPServer -destination 'platform=macOS' build` schlägt NICHT mehr mit "cannot find 'MCPWriteNotificationName' in scope" fehl, sobald Step 4 die Datei tatsächlich referenziert

- [ ] **Step 3: Commit des ersten Teils**

```bash
git add Feedivo/Services/MCPWriteNotificationName.swift Feedivo.xcodeproj/project.pbxproj
git commit -m "feat(mcp-server): geteilte Darwin-Notification-Namenskonstante angelegt"
```

- [ ] **Step 4: `MCPWriteNotifier` (Sender-Seite, Server) implementieren**

`FeedivoMCPServer/MCPWriteNotifier.swift`:

```swift
import Foundation

/// Postet eine Darwin-Notification nach jedem erfolgreichen Schreib-Tool-Aufruf, damit eine
/// ggf. laufende Feedivo-App ihre UI aktualisiert — siehe Feedivo/Services/MCPWriteObserver.swift
/// (Empfänger-Seite) für die volle Erklärung, warum Darwin Notifications statt regulärem
/// NotificationCenter genutzt werden (funktioniert prozess-/sandbox-übergreifend ohne App Group).
enum MCPWriteNotifier {
    /// Namen aller Tools, nach deren erfolgreichem Aufruf main.swift notifyDidWrite() auslöst.
    static let writeToolNames: Set<String> = ["update_article_status", "assign_tag", "remove_tag"]

    static func notifyDidWrite() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(MCPWriteNotificationName.darwin),
            nil,
            nil,
            true
        )
    }
}
```

- [ ] **Step 5: `MCPWriteObserver` (Empfänger-Seite, App) implementieren**

`Feedivo/Services/MCPWriteObserver.swift`:

```swift
import Foundation

/// Beobachtet die Darwin-Notification, die FeedivoMCPServer nach jedem erfolgreichen
/// Schreib-Tool-Aufruf postet (siehe FeedivoMCPServer/MCPWriteNotifier.swift), und stößt bei
/// Empfang ein Neuladen der betroffenen Views an. Nutzt CFNotificationCenterGetDarwinNotifyCenter
/// (nicht NotificationCenter.default) — funktioniert prozess-/sandbox-übergreifend ohne App
/// Group, im Gegensatz zu regulären NotificationCenter-Postings, die pro Prozess isoliert sind.
///
/// Bumpt bewusst BEIDE bestehenden Invalidierungssignale (statusVersion UND
/// directTagVersion), unabhängig davon, welches der drei Schreib-Tools tatsächlich
/// aufgerufen wurde — die Darwin-Notification selbst trägt keine Nutzdaten (nur ein reiner
/// "Ping"), ein bisschen überflüssiges Neuladen ist laut bestehender Architektur bereits als
/// harmlos dokumentiert (siehe die @Observable-Migration vom 2026-08-05 in CLAUDE.md).
enum MCPWriteObserver {
    /// Einmalig beim App-Start aufrufen (siehe FeedivoAppDelegate.applicationDidFinishLaunching).
    /// Der Callback ist ein nicht-capturing @convention(c)-Funktionszeiger (CFNotificationCenter
    /// verlangt das) — referenziert deshalb bewusst nur globale/statische Symbole, kein `self`.
    static func startObserving() {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            { _, _, _, _, _ in
                Task { @MainActor in
                    SQLiteDataInvalidation.shared.bumpStatusVersion()
                    SidebarBadgeInvalidation.shared.bumpDirectTagVersion()
                }
            },
            MCPWriteNotificationName.darwin,
            nil,
            .deliverImmediately
        )
    }
}
```

- [ ] **Step 6: Observer beim App-Start registrieren**

In `Feedivo/App/FeedivoAppDelegate.swift`, in `applicationDidFinishLaunching(_:)` direkt nach der bestehenden Zeile `TextEditingFocusMonitor.shared.startObserving()`:

```swift
        MCPWriteObserver.startObserving()
```

- [ ] **Step 7: Runnable Test für die Empfänger-Seite schreiben**

`FeedivoTests/Services/MCPWriteObserverTests.swift`:

```swift
import Testing
import Foundation
@testable import Feedivo

@Suite("MCPWriteObserver")
struct MCPWriteObserverTests {
    @Test("Bumpt statusVersion und directTagVersion nach Empfang der Darwin-Notification")
    @MainActor
    func bumptVersionenNachNotification() async throws {
        SQLiteDataInvalidation.shared.reset()
        SidebarBadgeInvalidation.shared.reset()
        MCPWriteObserver.startObserving()

        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(MCPWriteNotificationName.darwin),
            nil,
            nil,
            true
        )

        // Darwin-Notifications werden über notifyd zugestellt — nicht garantiert synchron
        // innerhalb desselben Runloop-Tick, deshalb kurze Wartezeit statt sofortiger Assertion.
        try await Task.sleep(for: .milliseconds(300))

        #expect(SQLiteDataInvalidation.shared.statusVersion > 0)
        #expect(SidebarBadgeInvalidation.shared.directTagVersion > 0)
    }
}
```

- [ ] **Step 8: Build + Test ausführen, um den Erfolg zu bestätigen**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' test -only-testing:FeedivoTests/MCPWriteObserverTests`
Expected: TEST SUCCEEDED

- [ ] **Step 9: main.swift refaktorieren — Ergebnis abfangen und nach erfolgreichem Schreib-Tool-Aufruf benachrichtigen**

In `FeedivoMCPServer/main.swift`, den kompletten `await server.withMethodHandler(CallTool.self) { params in ... }`-Block (enthält inzwischen 10 `case`-Zweige aus Tasks 4/5) ersetzen durch:

```swift
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
```

- [ ] **Step 10: Build-verifizierten Test für `MCPWriteNotifier` schreiben**

`FeedivoMCPServerTests/MCPWriteNotifierTests.swift`:

```swift
import Testing
@testable import FeedivoMCPServer

@Suite("MCPWriteNotifier")
struct MCPWriteNotifierTests {
    @Test("writeToolNames enthält genau die drei Schreib-Tools")
    func writeToolNamesEnthaeltDieDreiSchreibTools() {
        #expect(MCPWriteNotifier.writeToolNames == ["update_article_status", "assign_tag", "remove_tag"])
    }
}
```

- [ ] **Step 11: Build ausführen (beide Schemes)**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' build`
Run: `xcodebuild -project Feedivo.xcodeproj -scheme FeedivoMCPServer -destination 'platform=macOS' build`
Expected: beide BUILD SUCCEEDED

- [ ] **Step 12: Commit**

```bash
git add FeedivoMCPServer/MCPWriteNotifier.swift Feedivo/Services/MCPWriteObserver.swift Feedivo/App/FeedivoAppDelegate.swift FeedivoMCPServer/main.swift FeedivoTests/Services/MCPWriteObserverTests.swift FeedivoMCPServerTests/MCPWriteNotifierTests.swift
git commit -m "feat(mcp-server): Cross-Process-Live-Refresh via Darwin-Notification"
```

---

### Task 7: Finaler Regressionslauf, Live-Smoke-Test, CLAUDE.md-Update

**Files:**
- Modify: `CLAUDE.md` (neuer Eintrag unter "Aktuell in Arbeit")

**Interfaces:**
- Consumes: alle Tasks 1-6.

- [ ] **Step 1: Vollen Debug-Build für beide Schemes ausführen**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' build`
Run: `xcodebuild -project Feedivo.xcodeproj -scheme FeedivoMCPServer -destination 'platform=macOS' build`
Expected: beide BUILD SUCCEEDED, 0 Fehler

- [ ] **Step 2: Gezielten Regressionslauf über alle in diesem Plan berührten `FeedivoTests`-Suiten ausführen**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO test -only-testing:FeedivoTests/FeedivoDatabaseMigratorTests -only-testing:FeedivoTests/MCPServerSettingsStoreTests -only-testing:FeedivoTests/MCPWriteObserverTests`
Expected: TEST SUCCEEDED, alle Tests grün

- [ ] **Step 3: Release-Build ausführen (deckt u. a. ab, dass die neuen `Localizable.xcstrings`-Einträge korrekt formatiert sind)**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -configuration Release build`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Echten Live-stdio-JSON-RPC-Smoke-Test gegen eine Scratch-Kopie der Datenbank durchführen (NICHT gegen die echte Produktions-DB)**

Dieser Schritt verifiziert `FeedivoMCPServer` end-to-end (Schreibzugriff aktiviert, `tools/list` zeigt 10 Tools, `update_article_status` schreibt tatsächlich), ohne die echten Nutzerdaten anzufassen:

```bash
# 1. Scratch-Kopie der Produktions-DB anlegen (read-only Quelle, nie beschrieben)
SCRATCH_DIR=$(mktemp -d)
cp ~/Library/Containers/ch.martin.Feedivo/Data/Library/Application\ Support/ch.martin.Feedivo/Feedivo/feedivo.sqlite "$SCRATCH_DIR/feedivo.sqlite"
cp ~/Library/Containers/ch.martin.Feedivo/Data/Library/Application\ Support/ch.martin.Feedivo/Feedivo/feedivo.sqlite-wal "$SCRATCH_DIR/feedivo.sqlite-wal" 2>/dev/null || true
cp ~/Library/Containers/ch.martin.Feedivo/Data/Library/Application\ Support/ch.martin.Feedivo/Feedivo/feedivo.sqlite-shm "$SCRATCH_DIR/feedivo.sqlite-shm" 2>/dev/null || true

# 2. In der Scratch-Kopie den Schreibzugriff-Schalter aktivieren
sqlite3 "$SCRATCH_DIR/feedivo.sqlite" "UPDATE mcp_server_settings SET isEnabled = 1, writeAccessIsEnabled = 1 WHERE id = 1"

# 3. Eine Artikel-ID aus der Scratch-Kopie für den Smoke-Test merken
TEST_ARTICLE_ID=$(sqlite3 "$SCRATCH_DIR/feedivo.sqlite" "SELECT id FROM articles LIMIT 1")
echo "Test-Artikel-ID: $TEST_ARTICLE_ID"
```

Danach den gebauten `FeedivoMCPServer`-Prozess (aus dem Debug-Build unter DerivedData) manuell mit einer echten `initialize`→`notifications/initialized`→`tools/list`→`tools/call`-JSON-RPC-Sequenz starten (analog zum bereits etablierten Live-Verifikations-Vorgehen aus ADR-011/v1). `tools/list` muss jetzt 10 Tools zeigen (7 Lese- + 3 Schreib-Tools), `tools/call` mit `update_article_status`/`articleID: $TEST_ARTICLE_ID`/`isRead: true` muss `isError: false` liefern. Danach per `sqlite3` auf der Scratch-Kopie verifizieren, dass `article_statuses.isRead` für diese ID tatsächlich `1` ist.

Scratch-Verzeichnis am Ende aufräumen: `rm -rf "$SCRATCH_DIR"`.

- [ ] **Step 5 [MANUELL — erfordert eine laufende Feedivo-App + Claude Desktop]: Live-Verifikation durch den Nutzer**

Folgende Punkte kann nur der Nutzer selbst am eigenen Mac verifizieren (kein computer-use für native macOS-Apps in dieser Umgebung verfügbar):

1. Feedivo starten, Einstellungen → KI-Zugriff öffnen — Schreibzugriff-Schalter ist ausgegraut, solange der Hauptschalter aus ist.
2. Hauptschalter einschalten — Schreibzugriff-Schalter wird bedienbar.
3. Schreibzugriff-Schalter einschalten, App neu starten — beide Schalter bleiben korrekt AN (Persistenz-Check).
4. Hauptschalter wieder ausschalten — Schreibzugriff-Schalter springt automatisch mit auf AUS (sowohl visuell als auch nach App-Neustart bestätigt).
5. Beide Schalter wieder einschalten, Claude Desktop neu starten (damit es den neu gestarteten `FeedivoMCPServer`-Prozess mit aktivem Schreibzugriff verbindet).
6. In Claude Desktop einen Artikel per `update_article_status` als gelesen markieren, während Feedivo im Vordergrund offen ist und genau diesen Artikel in der Artikelliste zeigt — **entscheidender Test:** die Artikelliste/der Ungelesen-Punkt aktualisiert sich sichtbar, OHNE dass der Nutzer manuell den Ordner wechselt oder die App neu startet.
7. Denselben Test für `assign_tag`/`remove_tag` wiederholen — Sidebar-Tag-Badges aktualisieren sich sichtbar.
8. Einen Schreibversuch mit einer offensichtlich falschen `articleID` ausprobieren — Claude bekommt eine verständliche Fehlermeldung zurück, kein stiller Fehlschlag.
9. Schreibzugriff-Schalter wieder ausschalten, Claude Desktop neu starten — die drei Schreib-Tools sind in Claudes Tool-Liste nicht mehr vorhanden (nur noch die 7 Lese-Tools).

- [ ] **Step 6: CLAUDE.md aktualisieren**

In `CLAUDE.md`, im Abschnitt "Aktuell in Arbeit" einen neuen Eintrag ganz oben (vor dem bisher ersten Eintrag) ergänzen, der Folgendes festhält: Datum, dass dies Phase 1 des MCP-Server-V2-Plans ist (Schreibzugriff-Fundament: zweiter Schalter, `update_article_status`/`assign_tag`/`remove_tag`, Cross-Process-Live-Refresh via Darwin-Notification), Verweis auf Spec (`docs/superpowers/specs/2026-08/2026-08-14-mcp-server-v2-phase1-schreibzugriff-design.md`) und Plan (`docs/superpowers/plans/2026-08-14-mcp-server-v2-phase1-schreibzugriff.md`), den Stand der automatisierten Verifikation (Build grün beide Schemes, gezielter Testlauf grün, Live-stdio-Smoke-Test gegen Scratch-DB erfolgreich), und dass die manuelle 9-Punkte-Live-Checkliste aus Step 5 noch aussteht. Ebenfalls ergänzen: Phasen 2-4 (Feed-Verwaltung, neue Lese-Tools, Such-Verbesserungen) sind eigene, noch nicht begonnene Folge-Zyklen.

- [ ] **Step 7: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: MCP-Server V2 Phase 1 (Schreibzugriff-Fundament) in CLAUDE.md dokumentiert"
```
