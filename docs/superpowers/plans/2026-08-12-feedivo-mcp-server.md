# Feedivo MCP-Server (v1, read-only) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Achtung:** Die Tasks 2, 11 und 12 sind als `[MANUELL]` markiert — sie erfordern echte Xcode-GUI-Bedienung bzw. eine laufende Claude-Desktop-Installation und können NICHT von einem autonomen Subagent ausgeführt werden. Bei diesen Tasks muss die Ausführung pausieren und der menschliche Nutzer die Schritte selbst durchführen, bevor die nächste Task startet.

**Goal:** Ein stdio-basierter MCP-Server (`FeedivoMCPServer`), der die Feedivo-SQLite-Datenbank read-only öffnet und 7 Abfrage-Tools bereitstellt (Feeds/Ordner/Tags/Intelligente Ordner auflisten, Artikel suchen/lesen), damit eine KI (Claude Desktop, Claude Code) echte Feedivo-Daten abfragen kann.

**Architecture:** Neues Command-Line-Tool-Target `FeedivoMCPServer` im bestehenden `Feedivo.xcodeproj`, das die vorhandenen `Database`/`Stores`/`Records`/`Snapshots`/`Models`-Quelldateien per **Xcode Target Membership** mitnutzt (keine Code-Duplikation, keine Package-Extraktion — siehe Design-Spec, Abschnitt "Architektur", abgeändert nach Rücksprache mit dem Nutzer von "Swift Package" auf "Target Membership"). Die Protokoll-Anbindung läuft über das offizielle `modelcontextprotocol/swift-sdk` (Produkt `MCP`), `StdioTransport`. Die Datenbank wird read-only per eigener `DatabasePool`-Verbindung geöffnet, der Pfad zum sandboxed Container von `ch.martin.Feedivo` wird hart abgeleitet (kein `FileManager`-Environment-Zugriff, der als unsandboxed Prozess falsch aufgelöst würde).

**Tech Stack:** Swift 6, GRDB (bereits vorhanden), `modelcontextprotocol/swift-sdk` (neu, ab Version 0.12.0, Produkt "MCP"), Swift Testing (kein XCTest, Projekt-Konvention).

## Global Constraints

- Mindest-macOS: 14.0 Sonoma+ (Projektstandard, MCP-SDK verlangt nur 13.0+, also unkritisch).
- Kommentare im Code auf Deutsch (CLAUDE.md-Vorgabe).
- Tests mit Swift Testing (`import Testing`, `@Test`, `#expect`), keine XCTest-Suiten.
- Keine SwiftData — GRDB ist die alleinige Persistenz.
- `FeedivoMCPServer` liest die Datenbank **ausschließlich read-only**, führt niemals `FeedivoDatabaseMigrator.migrator.migrate(...)` gegen die reale App-Datenbank aus.
- Neue Xcode-Targets/Schemes werden vom Nutzer manuell angelegt (siehe Task 2) — keine automatisierten `project.pbxproj`-Texteditierungen, da dieses Repo bereits dokumentierte Vorfälle mit fehlerhaften manuellen pbxproj-Änderungen hatte (siehe CLAUDE.md-Gotchas).
- Jede Task endet mit einem grünen Build (`xcodebuild build` für das jeweils betroffene Scheme) und einem Commit.
- Bundle-Identifier-Konvention: `ch.martin.Feedivo.*` für neue Targets, falls ein Bundle-Identifier gebraucht wird (Command-Line-Tools brauchen i. d. R. keinen).

---

### Task 1: `ArticleSearchWindowState` aus der Views-Schicht in die Stores-Schicht verschieben

**Warum:** `ArticleStore.searchArticles(state:)` (wird in Task 8 von `FeedivoMCPServer` genutzt) nimmt `ArticleSearchWindowState` als Parameter. Diese Typen liegen aktuell in `Feedivo/Views/ArticleList/ArticleListQuery.swift` — reine Datei ohne SwiftUI-Import (nur `import Foundation`), aber am falschen Ort für eine UI-freie Schicht, die später auch vom Server-Target mitgenutzt werden soll. Verschieben nach `Feedivo/Stores/` ist eine reine Umbenennung/Verschiebung innerhalb desselben Xcode-Targets `Feedivo` — kein Code muss angepasst werden (7 referenzierende Dateien bleiben unverändert, da Swift innerhalb eines Targets nicht pfadbasiert importiert).

**Files:**
- Move: `Feedivo/Views/ArticleList/ArticleListQuery.swift` → `Feedivo/Stores/ArticleSearchQuery.swift`

**Interfaces:**
- Produces: `ArticleSearchField`, `ArticleSearchScope`, `ArticleSearchDateFilter`, `ArticleSearchStatusFilter`, `ArticleSearchTagMatchMode`, `ArticleSearchFilters`, `ArticleSearchQuery`, `ArticleSearchWindowState` — unverändert, nur der Dateipfad ändert sich.

- [ ] **Step 1: Datei verschieben**

```bash
git mv Feedivo/Views/ArticleList/ArticleListQuery.swift Feedivo/Stores/ArticleSearchQuery.swift
```

- [ ] **Step 2: Build verifizieren**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -configuration Debug build`
Expected: `BUILD SUCCEEDED` (keine Änderung am kompilierten Code, nur Dateipfad)

- [ ] **Step 3: Gezielten Regressionstest laufen lassen**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' test -only-testing:FeedivoTests/ArticleListQueryTests -parallel-testing-enabled NO`
Expected: alle Tests grün (falls diese Testklasse nicht existiert, stattdessen `-only-testing:FeedivoTests` mit Suchbegriff "ArticleSearch" im Testnamen identifizieren via `grep -rl "ArticleSearchWindowState" FeedivoTests/` und den passenden Suite-Namen einsetzen)

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor: ArticleSearchWindowState nach Stores/ verschoben

Reine Datei-Verschiebung ohne Code-Änderung — Vorbereitung für Task 8
(FeedivoMCPServer.search_articles nutzt ArticleStore.searchArticles(state:),
das diesen Typ als Parameter erwartet).

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2 [MANUELL — erfordert Xcode-GUI]: Neues Target `FeedivoMCPServer` anlegen

**⚠️ Diese Task kann nicht von einem autonomen Subagent ausgeführt werden.** Bitte selbst in Xcode durchführen, dann mit "fertig" bestätigen, bevor Task 3 startet.

**Ziel:** Ein neues Command-Line-Tool-Target, das (a) die MCP-Swift-SDK-Abhängigkeit hat, (b) Zugriff auf die bestehenden Database/Stores/Records/Snapshots/Models-Dateien per Target Membership bekommt, (c) NICHT App-Sandboxed ist (damit es den Container-Pfad von `Feedivo.app` von außen lesen kann), und (d) ein eigenes Test-Target hat.

**Schritte (in Xcode, `Feedivo.xcodeproj` geöffnet):**

1. **Neues Target anlegen:** `File → New → Target…` → macOS → **Command Line Tool** → Next.
   - Product Name: `FeedivoMCPServer`
   - Language: Swift
   - Team/Bundle-Identifier: wie vorgeschlagen übernehmen (Command-Line-Tools brauchen keinen eindeutigen Bundle-ID für die Funktion, ist aber unkritisch).
   - Nach dem Anlegen: im Projektnavigator prüfen, dass ein Ordner `FeedivoMCPServer/` mit einer `main.swift` entstanden ist.

2. **Deployment Target angleichen:** Projekt auswählen → Target `FeedivoMCPServer` → Tab "General" → "Minimum Deployments" auf **macOS 14.0** setzen (matcht den Rest des Projekts).

3. **Sicherstellen, dass KEINE App-Sandbox aktiv ist:** Target `FeedivoMCPServer` → Tab "Signing & Capabilities" → es sollte dort keine "App Sandbox"-Capability aufgelistet sein (Command-Line-Tool-Targets bekommen das standardmäßig nicht). Falls doch eine Entitlements-Datei automatisch angelegt wurde und `com.apple.security.app-sandbox` enthält: diese Capability entfernen (Minus-Button). Das ist wichtig — der Server muss als *unsandboxed* Prozess laufen, um den Container-Pfad von `Feedivo.app` lesen zu können (siehe Task 3).

4. **MCP-Swift-SDK als Paketabhängigkeit hinzufügen:** Projekt auswählen → Tab "Package Dependencies" → "+" → URL eingeben: `https://github.com/modelcontextprotocol/swift-sdk` → "Dependency Rule": **Up to Next Major Version**, "0.12.0" → Add Package.
   - Im folgenden Dialog ("Choose Package Products"): das Produkt **`MCP`** ausschließlich dem Target **`FeedivoMCPServer`** zuordnen (NICHT dem `Feedivo`-App-Target hinzufügen — die App braucht das SDK nicht).

5. **Target Membership für bestehende Dateien vergeben:** Im Projektnavigator folgende Ordner öffnen, jeweils **alle enthaltenen Dateien** (Rekursiv inkl. Unterordner) markieren (Shift-Klick / Cmd-Klick für Mehrfachauswahl), dann rechtes Seitenfenster "File Inspector" (⌥⌘1) öffnen und im Abschnitt "Target Membership" die Checkbox **`FeedivoMCPServer`** zusätzlich aktivieren (die Checkbox `Feedivo` bleibt weiterhin aktiv):
   - `Feedivo/Database/` — **alle Dateien außer `FeedivoDatabaseEnvironment.swift`** (diese Datei ist reines SwiftUI-Environment-Plumbing der App, wird vom Server nicht gebraucht — nicht mitauswählen). Inklusive des kompletten Unterordners `Feedivo/Database/Records/` (17 Dateien).
   - `Feedivo/Stores/` — alle 17 Dateien (inkl. der in Task 1 verschobenen `ArticleSearchQuery.swift`).
   - `Feedivo/Snapshots/` — alle Dateien.
   - `Feedivo/Models/` — alle Dateien. (Hinweis: mehrere dieser Dateien importieren SwiftUI wegen `LocalizedStringKey`-Anzeigetexten, z. B. über `L10n.swift`. Das ist für ein Command-Line-Tool unproblematisch — SwiftUI lässt sich dort verlinken, es wird nur nie eine UI gezeigt. Bewusste, risikoarme Vereinfachung statt einer Aufspaltung der Models-Dateien nach Import-Abhängigkeit.)

6. **Test-Target anlegen:** `File → New → Target…` → macOS → **Unit Testing Bundle** → Next.
   - Product Name: `FeedivoMCPServerTests`
   - "Target to be Tested": `FeedivoMCPServer`
   - Test Framework Auswahl (falls Xcode danach fragt): Swift Testing (nicht XCTest) — falls Xcode das nicht automatisch anbietet, wird das in Task 3 durch einen manuellen `import Testing` in der ersten Testdatei sichergestellt, das genügt.

7. **Scheme teilen:** `Product → Scheme → Manage Schemes…` → beim automatisch angelegten Scheme "FeedivoMCPServer" die Checkbox in der Spalte "Shared" aktivieren (damit spätere `xcodebuild -scheme FeedivoMCPServer …`-Aufrufe von Subagents/Terminal funktionieren, nicht nur aus der Xcode-GUI heraus).

8. **Smoke-Test:** In der von Xcode generierten `FeedivoMCPServer/main.swift` sollte bereits `print("Hello, world!")` stehen (Standard-Template). Direkt bauen:

```bash
xcodebuild -project Feedivo.xcodeproj -scheme FeedivoMCPServer -configuration Debug build
```

   Falls Fehler wie `cannot find type 'X' in scope` erscheinen: die betroffene Datei existiert im `Feedivo`-Target, wurde aber in Schritt 5 nicht mit ausgewählt — die fehlende Datei nachträglich per File Inspector → Target Membership ergänzen und erneut bauen. Wiederholen, bis `BUILD SUCCEEDED`.

- [x] **Nutzer bestätigt:** Alle 8 Schritte durchgeführt, `xcodebuild -scheme FeedivoMCPServer build` liefert `BUILD SUCCEEDED` (committed: `8975d2e`). `xcodebuild test` schlägt strukturell fehl (Command-Line-Tool-Target kein gültiger TEST_HOST) — laut Nutzerentscheid genügt der Build-Erfolg als Abschlusskriterium, siehe SDD-Ledger.

---

### Task 3: Datenbank-Pfad im sandboxed Container auflösen

**Files:**
- Create: `FeedivoMCPServer/FeedivoContainerDatabaseLocation.swift`
- Test: `FeedivoMCPServerTests/FeedivoContainerDatabaseLocationTests.swift`

**Interfaces:**
- Produces: `FeedivoContainerDatabaseLocation.databaseURL(homeDirectory: URL) -> URL`, `FeedivoContainerDatabaseLocation.bundleIdentifier: String`

- [ ] **Step 1: Fehlschlagenden Test schreiben**

```swift
import Testing
import Foundation
@testable import FeedivoMCPServer

@Suite("FeedivoContainerDatabaseLocation")
struct FeedivoContainerDatabaseLocationTests {
    @Test("Pfad zeigt auf den sandboxed Container von ch.martin.Feedivo")
    func pfadZeigtAufSandboxedContainer() {
        let home = URL(fileURLWithPath: "/Users/testuser")
        let url = FeedivoContainerDatabaseLocation.databaseURL(homeDirectory: home)

        #expect(
            url.path
                == "/Users/testuser/Library/Containers/ch.martin.Feedivo/Data/Library/Application Support/ch.martin.Feedivo/Feedivo/feedivo.sqlite"
        )
    }

    @Test("Nutzt standardmäßig das echte Home-Verzeichnis des aktuellen Nutzers")
    func nutztStandardmaessigEchtesHomeVerzeichnis() {
        let url = FeedivoContainerDatabaseLocation.databaseURL()
        let expectedPrefix = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(url.path.hasPrefix(expectedPrefix))
    }
}
```

- [ ] **Step 2: Test ausführen, Fehlschlag verifizieren**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme FeedivoMCPServer -destination 'platform=macOS' test -only-testing:FeedivoMCPServerTests/FeedivoContainerDatabaseLocationTests`
Expected: FAIL mit "cannot find 'FeedivoContainerDatabaseLocation' in scope"

- [ ] **Step 3: Implementierung schreiben**

```swift
import Foundation

/// Löst den Pfad zur Feedivo-Datenbank innerhalb des App-Sandbox-Containers auf.
///
/// Feedivo selbst (Target `Feedivo`) läuft mit `com.apple.security.app-sandbox`,
/// weshalb `FileManager.default.urls(for: .applicationSupportDirectory, ...)`
/// von INNERHALB der App auf den Container-Pfad umgeleitet wird. Ein separater,
/// unsandboxed Prozess wie `FeedivoMCPServer` bekommt diese Umleitung nicht
/// automatisch — der Pfad wird deshalb hier explizit nachgebaut, statt
/// `FileManager`s Standard-API zu verwenden (die von einem unsandboxed Prozess
/// aus fälschlich den NICHT-Container-Pfad liefern würde).
enum FeedivoContainerDatabaseLocation {
    static let bundleIdentifier = "ch.martin.Feedivo"

    static func databaseURL(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Containers", isDirectory: true)
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("Data", isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("Feedivo", isDirectory: true)
            .appendingPathComponent("feedivo.sqlite")
    }
}
```

- [ ] **Step 4: Test erneut ausführen, Erfolg verifizieren**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme FeedivoMCPServer -destination 'platform=macOS' test -only-testing:FeedivoMCPServerTests/FeedivoContainerDatabaseLocationTests`
Expected: `TEST SUCCEEDED`, beide Tests grün

- [ ] **Step 5: Commit**

```bash
git add FeedivoMCPServer/FeedivoContainerDatabaseLocation.swift FeedivoMCPServerTests/FeedivoContainerDatabaseLocationTests.swift
git commit -m "feat(mcp-server): Pfadauflösung für den sandboxed DB-Container

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 4: Read-only-Datenbankverbindung öffnen

**Files:**
- Create: `FeedivoMCPServer/FeedivoMCPServerDatabase.swift`
- Test: `FeedivoMCPServerTests/FeedivoMCPServerDatabaseTests.swift`

**Interfaces:**
- Consumes: `FeedivoContainerDatabaseLocation.databaseURL(homeDirectory:) -> URL` (Task 3); `FeedivoDatabase` (bestehend, `Feedivo/Database/FeedivoDatabase.swift`, Methoden `open(at:) throws -> FeedivoDatabase`, `read<Value>(_:) throws -> Value`, `write<Value>(_:) throws -> Value`, `init(writer: any DatabaseWriter)`)
- Produces: `FeedivoMCPServerDatabase` (struct, `core: FeedivoDatabase` Property), `FeedivoMCPServerDatabase.openReadOnly(at: URL) throws -> FeedivoMCPServerDatabase`, `FeedivoMCPServerDatabaseError` (enum, `.databaseFileNotFound(URL)`, `.openFailed(description: String)`)

- [ ] **Step 1: Fehlschlagende Tests schreiben**

```swift
import Testing
import Foundation
import GRDB
@testable import FeedivoMCPServer

@Suite("FeedivoMCPServerDatabase")
struct FeedivoMCPServerDatabaseTests {
    @Test("Öffnet eine bestehende, migrierte Feedivo-Datenbank read-only")
    func oeffnetBestehendeDatenbankReadOnly() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let dbURL = tempDir.appendingPathComponent("feedivo.sqlite")

        // Legt eine echte, vollständig migrierte Datenbank an — genau wie
        // FeedivoDatabase.open(at:) es beim echten App-Start tun würde.
        _ = try FeedivoDatabase.open(at: dbURL)

        let server = try FeedivoMCPServerDatabase.openReadOnly(at: dbURL)
        let count = try server.core.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM feeds") ?? -1
        }
        #expect(count == 0)
    }

    @Test("Wirft databaseFileNotFound, wenn die Datei nicht existiert")
    func wirftFehlerBeiFehlenderDatei() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString).sqlite")

        #expect(throws: FeedivoMCPServerDatabaseError.self) {
            try FeedivoMCPServerDatabase.openReadOnly(at: missing)
        }
    }

    @Test("Schreibversuche schlagen fehl, weil die Verbindung read-only ist")
    func schreibversucheSchlagenFehl() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let dbURL = tempDir.appendingPathComponent("feedivo.sqlite")
        _ = try FeedivoDatabase.open(at: dbURL)

        let server = try FeedivoMCPServerDatabase.openReadOnly(at: dbURL)

        #expect(throws: (any Error).self) {
            try server.core.write { db in
                try db.execute(sql: "DELETE FROM feeds")
            }
        }
    }
}
```

- [ ] **Step 2: Tests ausführen, Fehlschlag verifizieren**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme FeedivoMCPServer -destination 'platform=macOS' test -only-testing:FeedivoMCPServerTests/FeedivoMCPServerDatabaseTests`
Expected: FAIL mit "cannot find 'FeedivoMCPServerDatabase' in scope"

- [ ] **Step 3: Implementierung schreiben**

```swift
import Foundation
import GRDB

enum FeedivoMCPServerDatabaseError: Error, CustomStringConvertible, Equatable {
    case databaseFileNotFound(URL)
    case openFailed(description: String)

    var description: String {
        switch self {
        case .databaseFileNotFound(let url):
            return "Feedivo-Datenbank nicht gefunden unter \(url.path). Wurde Feedivo mindestens einmal gestartet?"
        case .openFailed(let description):
            return "Feedivo-Datenbank konnte nicht geöffnet werden: \(description)"
        }
    }

    static func == (lhs: FeedivoMCPServerDatabaseError, rhs: FeedivoMCPServerDatabaseError) -> Bool {
        lhs.description == rhs.description
    }
}

/// Read-only-Zugriff auf die Feedivo-Datenbank aus einem separaten,
/// unsandboxed Prozess heraus. Führt bewusst NIE `FeedivoDatabaseMigrator`
/// aus — die Datenbank wird als bereits existierend und aktuell vorausgesetzt
/// (gepflegt von der laufenden oder zuletzt gelaufenen Feedivo-App).
struct FeedivoMCPServerDatabase {
    let core: FeedivoDatabase

    static func openReadOnly(
        at fileURL: URL = FeedivoContainerDatabaseLocation.databaseURL()
    ) throws -> FeedivoMCPServerDatabase {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw FeedivoMCPServerDatabaseError.databaseFileNotFound(fileURL)
        }

        var configuration = Configuration()
        configuration.readonly = true
        configuration.busyMode = .timeout(5)

        do {
            let pool = try DatabasePool(path: fileURL.path, configuration: configuration)
            return FeedivoMCPServerDatabase(core: FeedivoDatabase(writer: pool))
        } catch {
            throw FeedivoMCPServerDatabaseError.openFailed(description: "\(error)")
        }
    }
}
```

- [ ] **Step 4: Tests erneut ausführen, Erfolg verifizieren**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme FeedivoMCPServer -destination 'platform=macOS' test -only-testing:FeedivoMCPServerTests/FeedivoMCPServerDatabaseTests`
Expected: `TEST SUCCEEDED`, alle 3 Tests grün

- [ ] **Step 5: Commit**

```bash
git add FeedivoMCPServer/FeedivoMCPServerDatabase.swift FeedivoMCPServerTests/FeedivoMCPServerDatabaseTests.swift
git commit -m "feat(mcp-server): Read-only-Datenbankverbindung mit Busy-Timeout

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 5: HTML-zu-Klartext-Konverter

**Warum eine eigene, kleine Implementierung statt Wiederverwendung von `ReaderContentRenderer`:** Der bestehende Renderer in `Feedivo/Views/Reader/ReaderContentRenderer.swift` ist auf strukturiertes Rendering (Bilder, Inline-Formatierung) für die Reader-UI ausgelegt und hat Abhängigkeiten (`ArticleResourceURLPolicy`), die für einen reinen Text-Export nicht gebraucht werden. Für `get_article` (Task 9) genügt eine kleine, selbstständige, Foundation-only Funktion.

**Files:**
- Create: `FeedivoMCPServer/HTMLPlainTextConverter.swift`
- Test: `FeedivoMCPServerTests/HTMLPlainTextConverterTests.swift`

**Interfaces:**
- Produces: `HTMLPlainTextConverter.plainText(fromHTML: String) -> String`

- [ ] **Step 1: Fehlschlagende Tests schreiben**

```swift
import Testing
@testable import FeedivoMCPServer

@Suite("HTMLPlainTextConverter")
struct HTMLPlainTextConverterTests {
    @Test("Entfernt HTML-Tags und wandelt Absätze in Zeilenumbrüche um")
    func entferntHTMLTagsUndAbsaetze() {
        let html = "<p>Erster Absatz mit <strong>fettem</strong> Text.</p><p>Zweiter Absatz &amp; mehr.</p>"
        let result = HTMLPlainTextConverter.plainText(fromHTML: html)
        #expect(result == "Erster Absatz mit fettem Text.\n\nZweiter Absatz & mehr.")
    }

    @Test("Wandelt <br> in Zeilenumbrüche um")
    func wandeltBrInZeilenumbruecheUm() {
        let html = "Zeile eins<br>Zeile zwei<br/>Zeile drei"
        let result = HTMLPlainTextConverter.plainText(fromHTML: html)
        #expect(result == "Zeile eins\nZeile zwei\nZeile drei")
    }

    @Test("Gibt leeren String bei leerem HTML zurück")
    func gibtLeerenStringBeiLeeremHTMLZurueck() {
        #expect(HTMLPlainTextConverter.plainText(fromHTML: "") == "")
    }

    @Test("Normalisiert mehrfache Leerzeilen auf maximal eine")
    func normalisiertMehrfacheLeerzeilen() {
        let html = "<p>Eins</p><p></p><p></p><p>Zwei</p>"
        let result = HTMLPlainTextConverter.plainText(fromHTML: html)
        #expect(result == "Eins\n\nZwei")
    }
}
```

- [ ] **Step 2: Tests ausführen, Fehlschlag verifizieren**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme FeedivoMCPServer -destination 'platform=macOS' test -only-testing:FeedivoMCPServerTests/HTMLPlainTextConverterTests`
Expected: FAIL mit "cannot find 'HTMLPlainTextConverter' in scope"

- [ ] **Step 3: Implementierung schreiben**

```swift
import Foundation

/// Minimaler, Foundation-only HTML-zu-Klartext-Konverter für den MCP-Server.
/// Bewusst keine Wiederverwendung von `ReaderContentRenderer` (Reader-UI-Code
/// mit zusätzlichen Bild-/Inline-Formatierungs-Abhängigkeiten) — hier reicht
/// eine einfache, deterministische Tag-Entfernung für Klartext-Ausgabe an eine KI.
enum HTMLPlainTextConverter {
    static func plainText(fromHTML html: String) -> String {
        var text = html

        let blockTags = [
            "</p>", "<br>", "<br/>", "<br />",
            "</div>", "</li>", "</h1>", "</h2>", "</h3>", "</h4>", "</h5>", "</h6>",
        ]
        for tag in blockTags {
            text = text.replacingOccurrences(of: tag, with: "\n", options: .caseInsensitive)
        }

        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

        let entities: [String: String] = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
            "&#39;": "'", "&apos;": "'", "&nbsp;": " ",
        ]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }

        text = text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\n[ \\t]*\n[ \\t\\n]*", with: "\n\n", options: .regularExpression)

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

- [ ] **Step 4: Tests erneut ausführen, Erfolg verifizieren**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme FeedivoMCPServer -destination 'platform=macOS' test -only-testing:FeedivoMCPServerTests/HTMLPlainTextConverterTests`
Expected: `TEST SUCCEEDED`, alle 4 Tests grün

- [ ] **Step 5: Commit**

```bash
git add FeedivoMCPServer/HTMLPlainTextConverter.swift FeedivoMCPServerTests/HTMLPlainTextConverterTests.swift
git commit -m "feat(mcp-server): HTML-zu-Klartext-Konverter für get_article

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 6: MCP-Server-Bootstrap (leere Toolliste, stdio-Transport)

**Files:**
- Modify: `FeedivoMCPServer/main.swift` (Xcode-generiertes Standard-Template ersetzen)
- Test: `FeedivoMCPServerTests/FeedivoMCPServerProcessTests.swift`

**Interfaces:**
- Consumes: `FeedivoMCPServerDatabase.openReadOnly() throws -> FeedivoMCPServerDatabase` (Task 4)
- Produces: `availableTools: [Tool]` (top-level `var` in `main.swift`, wird von Tasks 7–10 erweitert), `CallTool`-Dispatch-`switch` in `main.swift` (wird von Tasks 7–10 um je einen `case` ergänzt)

- [ ] **Step 1: `main.swift` durch den Bootstrap ersetzen**

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

let server = Server(
    name: "feedivo-mcp-server",
    version: "1.0.0",
    capabilities: .init(
        tools: .init(listChanged: false)
    )
)

// Tasks 7–10 ergänzen hier jeweils einen Eintrag.
var availableTools: [Tool] = []

await server.withMethodHandler(ListTools.self) { _ in
    .init(tools: availableTools)
}

await server.withMethodHandler(CallTool.self) { params in
    switch params.name {
    // Tasks 7–10 ergänzen hier jeweils einen case.
    default:
        return .init(content: [.text("Unbekanntes Tool: \(params.name)")], isError: true)
    }
}

let transport = StdioTransport()
try await server.start(transport: transport)
await server.waitUntilCompleted()
```

- [ ] **Step 2: Build verifizieren**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme FeedivoMCPServer -configuration Debug build`
Expected: `BUILD SUCCEEDED`

Falls Fehler zu `await`/Concurrency in Top-Level-Code auftreten: im Target `FeedivoMCPServer` unter Build Settings → "Swift Language Version" prüfen, dass "Swift 6" (oder "Upcoming Swift 6 Language Mode" je nach Xcode-Version) eingestellt ist — die MCP-SDK-Nutzung erfordert Swift 6 Tools, und `main.swift` unterstützt Top-Level-`await` nur im entsprechenden Concurrency-Modus.

- [ ] **Step 3: Integrationstest schreiben — startet den echten gebauten Prozess und spricht via stdio-Transport mit ihm**

```swift
import Testing
import Foundation
import MCP
#if canImport(System)
    import System
#else
    import SystemPackage
#endif

@Suite("FeedivoMCPServer Prozess-Integration")
struct FeedivoMCPServerProcessTests {
    @Test("Server startet als eigener Prozess und beantwortet tools/list ohne Absturz")
    func serverStartetUndAntwortetAufToolsList() async throws {
        let executableURL = try Self.builtExecutableURL()

        let process = Process()
        process.executableURL = executableURL
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        try process.run()
        defer { process.terminate() }

        let clientTransport = StdioTransport(
            input: FileDescriptor(rawValue: stdoutPipe.fileHandleForReading.fileDescriptor),
            output: FileDescriptor(rawValue: stdinPipe.fileHandleForWriting.fileDescriptor)
        )

        let client = Client(name: "FeedivoMCPServerTests", version: "1.0.0")
        try await client.connect(transport: clientTransport)

        let (tools, _) = try await client.listTools()
        #expect(tools.count >= 0)
    }

    private static func builtExecutableURL() throws -> URL {
        // Xcode legt das gebaute Produkt im selben Build-Ordner ab wie das
        // aktuell laufende Test-Bundle selbst.
        let testBundleURL = Bundle(for: BundleToken.self).bundleURL
        let buildProductsDir = testBundleURL.deletingLastPathComponent()
        return buildProductsDir.appendingPathComponent("FeedivoMCPServer")
    }
}

private final class BundleToken {}
```

**Wichtiger Hinweis für diesen Test:** Er braucht eine echte, für den aktuellen Nutzer erreichbare Feedivo-Datenbank (`FeedivoMCPServerDatabase.openReadOnly()` in `main.swift` schlägt sonst fehl und der Prozess beendet sich mit Exit-Code 1, bevor er auf stdio antwortet). Falls auf der Baumaschine (CI oder frischer Checkout) noch keine Feedivo-App je gestartet wurde, existiert die Datenbank nicht — in diesem Fall den Test-Body mit `guard FileManager.default.fileExists(atPath: FeedivoContainerDatabaseLocation.databaseURL().path) else { return }` am Anfang absichern, damit der Test lokal (mit Datenbank) aussagekräftig bleibt und auf einer frischen Maschine (ohne Datenbank) nicht fälschlich rot wird. Prüfen, ob die Datei existiert:

```bash
ls ~/Library/Containers/ch.martin.Feedivo/Data/Library/Application\ Support/ch.martin.Feedivo/Feedivo/feedivo.sqlite
```

- [ ] **Step 4: Test ausführen**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme FeedivoMCPServer -destination 'platform=macOS' test -only-testing:FeedivoMCPServerTests/FeedivoMCPServerProcessTests`
Expected: `TEST SUCCEEDED` (oder der Test kehrt früh zurück, falls keine lokale Feedivo-Datenbank existiert, siehe Step 3)

- [ ] **Step 5: Commit**

```bash
git add FeedivoMCPServer/main.swift FeedivoMCPServerTests/FeedivoMCPServerProcessTests.swift
git commit -m "feat(mcp-server): stdio-MCP-Bootstrap mit leerer Toolliste

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 7: Tools `list_feeds`, `list_folders`, `list_tags`

**Files:**
- Create: `FeedivoMCPServer/Tools/ListFeedsTool.swift`
- Create: `FeedivoMCPServer/Tools/ListFoldersTool.swift`
- Create: `FeedivoMCPServer/Tools/ListTagsTool.swift`
- Modify: `FeedivoMCPServer/main.swift` (Tools registrieren)
- Test: `FeedivoMCPServerTests/ListingToolsTests.swift`

**Interfaces:**
- Consumes: `FeedStore(database: FeedivoDatabase).feeds() throws -> [FeedRecord]`; `FeedFolderStore(database: FeedivoDatabase).folders() throws -> [FeedFolderRecord]`; `TagStore(database: FeedivoDatabase).sidebarTags() throws -> [TagSidebarSnapshot]`; `FeedivoMCPServerDatabase.core: FeedivoDatabase` (Task 4)
- Produces: `ListFeedsTool.definition: Tool`, `ListFeedsTool.call(database:) throws -> CallTool.Result` (analog für `ListFoldersTool`, `ListTagsTool`)

- [ ] **Step 1: Fehlschlagende Tests schreiben**

```swift
import Testing
import Foundation
import GRDB
@testable import FeedivoMCPServer

@Suite("Listing-Tools")
struct ListingToolsTests {
    @Test("list_feeds nennt Titel, Ordner und Ungelesen-Anzahl")
    func listFeedsNenntErwarteteFelder() throws {
        let core = try FeedivoDatabase.inMemoryForTests()
        try core.write { db in
            var feed = FeedRecord(url: "https://example.com/feed", title: "Swift Blog", folderName: "Tech", unreadCount: 3)
            try feed.insert(db)
        }
        let database = FeedivoMCPServerDatabase(core: core)

        let result = try ListFeedsTool.call(database: database)

        guard case .text(let text) = result.content.first else {
            Issue.record("Erwartete Text-Content")
            return
        }
        #expect(text.contains("Swift Blog"))
        #expect(text.contains("Tech"))
        #expect(text.contains("3"))
        #expect(result.isError == false)
    }

    @Test("list_folders nennt Ordnernamen")
    func listFoldersNenntOrdnernamen() throws {
        let core = try FeedivoDatabase.inMemoryForTests()
        try core.write { db in
            var folder = FeedFolderRecord(name: "Tech")
            try folder.insert(db)
        }
        let database = FeedivoMCPServerDatabase(core: core)

        let result = try ListFoldersTool.call(database: database)

        guard case .text(let text) = result.content.first else {
            Issue.record("Erwartete Text-Content")
            return
        }
        #expect(text.contains("Tech"))
    }

    @Test("list_tags nennt Tag-Namen")
    func listTagsNenntTagNamen() throws {
        let core = try FeedivoDatabase.inMemoryForTests()
        try core.write { db in
            var tag = TagRecord(name: "Dev")
            try tag.insert(db)
        }
        let database = FeedivoMCPServerDatabase(core: core)

        let result = try ListTagsTool.call(database: database)

        guard case .text(let text) = result.content.first else {
            Issue.record("Erwartete Text-Content")
            return
        }
        #expect(text.contains("Dev"))
    }
}
```

- [ ] **Step 2: Tests ausführen, Fehlschlag verifizieren**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme FeedivoMCPServer -destination 'platform=macOS' test -only-testing:FeedivoMCPServerTests/ListingToolsTests`
Expected: FAIL mit "cannot find 'ListFeedsTool' in scope" (und analog für die anderen beiden)

- [ ] **Step 3: `ListFeedsTool` implementieren**

```swift
import MCP

enum ListFeedsTool {
    static let definition = Tool(
        name: "list_feeds",
        description: "Listet alle abonnierten Feeds mit Ordner-Zuordnung und Ungelesen-Anzahl auf.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([:]),
        ])
    )

    static func call(database: FeedivoMCPServerDatabase) throws -> CallTool.Result {
        let store = FeedStore(database: database.core)
        let feeds = try store.feeds()

        if feeds.isEmpty {
            return .init(content: [.text("Keine Feeds abonniert.")], isError: false)
        }

        let lines = feeds.map { feed in
            "\(feed.title) (id: \(feed.id), Ordner: \(feed.folderName ?? "—"), ungelesen: \(feed.unreadCount))"
        }
        return .init(content: [.text(lines.joined(separator: "\n"))], isError: false)
    }
}
```

- [ ] **Step 4: `ListFoldersTool` implementieren**

```swift
import MCP

enum ListFoldersTool {
    static let definition = Tool(
        name: "list_folders",
        description: "Listet alle Feed-Ordner auf.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([:]),
        ])
    )

    static func call(database: FeedivoMCPServerDatabase) throws -> CallTool.Result {
        let store = FeedFolderStore(database: database.core)
        let folders = try store.folders()

        if folders.isEmpty {
            return .init(content: [.text("Keine Ordner angelegt.")], isError: false)
        }

        let lines = folders.map { "\($0.name) (id: \($0.id))" }
        return .init(content: [.text(lines.joined(separator: "\n"))], isError: false)
    }
}
```

- [ ] **Step 5: `ListTagsTool` implementieren**

```swift
import MCP

enum ListTagsTool {
    static let definition = Tool(
        name: "list_tags",
        description: "Listet alle Tags mit der Anzahl zugeordneter Artikel auf.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([:]),
        ])
    )

    static func call(database: FeedivoMCPServerDatabase) throws -> CallTool.Result {
        let store = TagStore(database: database.core)
        let tags = try store.sidebarTags()

        if tags.isEmpty {
            return .init(content: [.text("Keine Tags angelegt.")], isError: false)
        }

        let lines = tags.map { "\($0.name) (id: \($0.id), Artikel: \($0.articleCount))" }
        return .init(content: [.text(lines.joined(separator: "\n"))], isError: false)
    }
}
```

- [ ] **Step 6: Die drei Tools in `main.swift` registrieren**

In `FeedivoMCPServer/main.swift` die Zeile `var availableTools: [Tool] = []` ersetzen durch:

```swift
var availableTools: [Tool] = [
    ListFeedsTool.definition,
    ListFoldersTool.definition,
    ListTagsTool.definition,
]
```

Und im `CallTool`-`switch` den Kommentar `// Tasks 7–10 ergänzen hier jeweils einen case.` ersetzen durch:

```swift
case "list_feeds":
    return try ListFeedsTool.call(database: database)
case "list_folders":
    return try ListFoldersTool.call(database: database)
case "list_tags":
    return try ListTagsTool.call(database: database)
// Tasks 8–10 ergänzen hier weitere cases.
```

- [ ] **Step 7: Tests erneut ausführen, Erfolg verifizieren**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme FeedivoMCPServer -destination 'platform=macOS' test -only-testing:FeedivoMCPServerTests/ListingToolsTests`
Expected: `TEST SUCCEEDED`, alle 3 Tests grün

- [ ] **Step 8: Vollständigen Build verifizieren**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme FeedivoMCPServer -configuration Debug build`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 9: Commit**

```bash
git add FeedivoMCPServer/Tools/ListFeedsTool.swift FeedivoMCPServer/Tools/ListFoldersTool.swift FeedivoMCPServer/Tools/ListTagsTool.swift FeedivoMCPServer/main.swift FeedivoMCPServerTests/ListingToolsTests.swift
git commit -m "feat(mcp-server): Tools list_feeds, list_folders, list_tags

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 8: Tool `search_articles`

**Files:**
- Create: `FeedivoMCPServer/Tools/SearchArticlesTool.swift`
- Modify: `FeedivoMCPServer/main.swift`
- Test: `FeedivoMCPServerTests/SearchArticlesToolTests.swift`

**Interfaces:**
- Consumes: `ArticleStore(database: FeedivoDatabase).upsert(_ input: ArticleUpsertInput) throws -> String` (nur für Testfixtures); `ArticleUpsertInput(feedID: String, title: String, content: String?, publishedAt: Date?, arrivedAt: Date)` (Konstruktor mit Defaults); `ArticleDatabase(database: FeedivoDatabase).searchArticles(state: ArticleSearchWindowState, includeHidden: Bool, limit: Int) throws -> [ArticleListSnapshot]`; `ArticleSearchWindowState` + `ArticleSearchStatusFilter`/`ArticleSearchTagMatchMode`/`ArticleSearchDateFilter` (Task 1); `ArticleListSnapshot` (Properties: `id`, `feedID`, `feedTitle`, `title`, `summary`, `isRead`, `isStarred`)
- Produces: `SearchArticlesTool.definition: Tool`, `SearchArticlesTool.call(database:arguments:) throws -> CallTool.Result`

- [ ] **Step 1: Fehlschlagenden Test schreiben**

```swift
import Testing
import Foundation
import GRDB
import MCP
@testable import FeedivoMCPServer

@Suite("SearchArticlesTool")
struct SearchArticlesToolTests {
    @Test("Findet Artikel per Volltextsuche im Titel und liefert Kurztext statt Volltext")
    func findetArtikelPerVolltextsuche() throws {
        let core = try FeedivoDatabase.inMemoryForTests()
        let feedID = try core.write { db -> String in
            var feed = FeedRecord(url: "https://example.com/feed", title: "Swift Blog")
            try feed.insert(db)
            return feed.id
        }
        let articleStore = ArticleStore(database: core)
        _ = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: feedID,
                title: "Neuigkeiten zu Swift 6 Concurrency",
                content: "<p>Ein sehr langer Artikeltext über Concurrency in Swift 6, der hier absichtlich lang ist, damit der Kurztext-Grenzwert überprüft werden kann.</p>",
                arrivedAt: Date()
            )
        )
        _ = try articleStore.upsert(
            ArticleUpsertInput(feedID: feedID, title: "Ganz anderes Thema", arrivedAt: Date())
        )

        let database = FeedivoMCPServerDatabase(core: core)
        let arguments: [String: Value] = ["query": .string("Swift 6")]

        let result = try SearchArticlesTool.call(database: database, arguments: arguments)

        guard case .text(let text) = result.content.first else {
            Issue.record("Erwartete Text-Content")
            return
        }
        #expect(text.contains("Neuigkeiten zu Swift 6 Concurrency"))
        #expect(text.contains("Swift Blog"))
        #expect(!text.contains("Ganz anderes Thema"))
        #expect(result.isError == false)
    }

    @Test("Filtert nach Status ungelesen")
    func filtertNachStatusUngelesen() throws {
        let core = try FeedivoDatabase.inMemoryForTests()
        let feedID = try core.write { db -> String in
            var feed = FeedRecord(url: "https://example.com/feed", title: "Blog")
            try feed.insert(db)
            return feed.id
        }
        let articleStore = ArticleStore(database: core)
        let readID = try articleStore.upsert(
            ArticleUpsertInput(feedID: feedID, title: "Gelesener Artikel", arrivedAt: Date())
        )
        _ = try articleStore.upsert(
            ArticleUpsertInput(feedID: feedID, title: "Ungelesener Artikel", arrivedAt: Date())
        )
        try ArticleStatusStore(database: core).setRead(true, articleID: readID, at: Date())

        let database = FeedivoMCPServerDatabase(core: core)
        let arguments: [String: Value] = ["status": .string("unread")]

        let result = try SearchArticlesTool.call(database: database, arguments: arguments)

        guard case .text(let text) = result.content.first else {
            Issue.record("Erwartete Text-Content")
            return
        }
        #expect(text.contains("Ungelesener Artikel"))
        #expect(!text.contains("Gelesener Artikel"))
    }

    @Test("Liefert eine verständliche Meldung bei keinem Treffer")
    func liefertMeldungBeiKeinemTreffer() throws {
        let core = try FeedivoDatabase.inMemoryForTests()
        let database = FeedivoMCPServerDatabase(core: core)

        let result = try SearchArticlesTool.call(database: database, arguments: ["query": .string("nichts")])

        guard case .text(let text) = result.content.first else {
            Issue.record("Erwartete Text-Content")
            return
        }
        #expect(text.contains("Keine Artikel"))
        #expect(result.isError == false)
    }
}
```

- [ ] **Step 2: Test ausführen, Fehlschlag verifizieren**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme FeedivoMCPServer -destination 'platform=macOS' test -only-testing:FeedivoMCPServerTests/SearchArticlesToolTests`
Expected: FAIL mit "cannot find 'SearchArticlesTool' in scope"

- [ ] **Step 3: Implementierung schreiben**

```swift
import MCP
import Foundation

enum SearchArticlesTool {
    static let definition = Tool(
        name: "search_articles",
        description: """
            Durchsucht Artikel per Volltextsuche und Filtern (Status, Tags, Feed, Zeitraum). \
            Liefert Kurztext, keinen Volltext — für den vollen Inhalt eines Treffers get_article \
            mit der hier zurückgegebenen Artikel-ID aufrufen.
            """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "query": .object([
                    "type": .string("string"),
                    "description": .string("Suchtext, leer lassen für keine Volltextsuche"),
                ]),
                "status": .object([
                    "type": .string("string"),
                    "description": .string("all, unread, read, starred oder archived"),
                    "enum": .array([.string("all"), .string("unread"), .string("read"), .string("starred"), .string("archived")]),
                ]),
                "feedID": .object([
                    "type": .string("string"),
                    "description": .string("Nur Artikel dieses Feeds (optional, ID aus list_feeds)"),
                ]),
                "tagIDs": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")]),
                    "description": .string("Nur Artikel mit einem dieser Tags (optional, IDs aus list_tags)"),
                ]),
                "tagMatchMode": .object([
                    "type": .string("string"),
                    "enum": .array([.string("any"), .string("all")]),
                ]),
                "dateFilter": .object([
                    "type": .string("string"),
                    "enum": .array([.string("anytime"), .string("today"), .string("thisWeek")]),
                ]),
                "limit": .object([
                    "type": .string("integer"),
                    "description": .string("Maximale Anzahl Treffer, Standard 50"),
                ]),
            ]),
        ])
    )

    static func call(database: FeedivoMCPServerDatabase, arguments: [String: Value]?) throws -> CallTool.Result {
        var state = ArticleSearchWindowState(searchText: arguments?["query"]?.stringValue ?? "")

        if let statusRaw = arguments?["status"]?.stringValue,
            let status = ArticleSearchStatusFilter(rawValue: statusRaw)
        {
            state.statusFilter = status
        }
        state.feedID = (arguments?["feedID"]?.stringValue).flatMap { UUID(uuidString: $0) }
        if let tagIDStrings = arguments?["tagIDs"]?.arrayValue {
            state.tagIDs = Set(tagIDStrings.compactMap { $0.stringValue.flatMap { UUID(uuidString: $0) } })
        }
        if let tagMatchRaw = arguments?["tagMatchMode"]?.stringValue,
            let tagMatch = ArticleSearchTagMatchMode(rawValue: tagMatchRaw)
        {
            state.tagMatchMode = tagMatch
        }
        if let dateFilterRaw = arguments?["dateFilter"]?.stringValue,
            let dateFilter = ArticleSearchDateFilter(rawValue: dateFilterRaw)
        {
            state.dateFilter = dateFilter
        }
        let limit = arguments?["limit"]?.intValue ?? 50

        let articleDatabase = ArticleDatabase(database: database.core)
        let results = try articleDatabase.searchArticles(state: state, includeHidden: false, limit: limit)

        if results.isEmpty {
            return .init(content: [.text("Keine Artikel gefunden.")], isError: false)
        }

        let lines = results.map { article -> String in
            let statusMarker = article.isRead ? "gelesen" : "ungelesen"
            let starMarker = article.isStarred ? ", ★" : ""
            let excerpt = String((article.summary ?? "").prefix(200))
            return "[\(article.id)] \(article.title) — \(article.feedTitle) (\(statusMarker)\(starMarker))\n\(excerpt)"
        }
        return .init(content: [.text(lines.joined(separator: "\n\n"))], isError: false)
    }
}
```

- [ ] **Step 4: Tool in `main.swift` registrieren**

In `FeedivoMCPServer/main.swift`, `availableTools` um `SearchArticlesTool.definition` ergänzen und im `switch` einen weiteren `case` ergänzen:

```swift
case "search_articles":
    return try SearchArticlesTool.call(database: database, arguments: params.arguments)
```

- [ ] **Step 5: Test erneut ausführen, Erfolg verifizieren**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme FeedivoMCPServer -destination 'platform=macOS' test -only-testing:FeedivoMCPServerTests/SearchArticlesToolTests`
Expected: `TEST SUCCEEDED`, alle 3 Tests grün

- [ ] **Step 6: Vollständigen Build verifizieren**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme FeedivoMCPServer -configuration Debug build`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 7: Commit**

```bash
git add FeedivoMCPServer/Tools/SearchArticlesTool.swift FeedivoMCPServer/main.swift FeedivoMCPServerTests/SearchArticlesToolTests.swift
git commit -m "feat(mcp-server): Tool search_articles

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 9: Tool `get_article`

**Files:**
- Create: `FeedivoMCPServer/Tools/GetArticleTool.swift`
- Modify: `FeedivoMCPServer/main.swift`
- Test: `FeedivoMCPServerTests/GetArticleToolTests.swift`

**Interfaces:**
- Consumes: `ArticleDatabase(database: FeedivoDatabase).readerArticle(id: String) throws -> ArticleReaderSnapshot?`; `ArticleReaderSnapshot` (Properties: `title`, `feedTitle`, `link`, `author`, `content`, `summary`, `isRead`, `isStarred`, `tags: [ReaderArticleTagMetadata]`); `HTMLPlainTextConverter.plainText(fromHTML:) -> String` (Task 5)
- Produces: `GetArticleTool.definition: Tool`, `GetArticleTool.call(database:arguments:) throws -> CallTool.Result`

- [ ] **Step 1: Fehlschlagende Tests schreiben**

```swift
import Testing
import Foundation
import GRDB
import MCP
@testable import FeedivoMCPServer

@Suite("GetArticleTool")
struct GetArticleToolTests {
    @Test("Liefert bereinigten Klartext statt rohes HTML")
    func liefertBereinigtenKlartext() throws {
        let core = try FeedivoDatabase.inMemoryForTests()
        let feedID = try core.write { db -> String in
            var feed = FeedRecord(url: "https://example.com/feed", title: "Swift Blog")
            try feed.insert(db)
            return feed.id
        }
        let articleID = try ArticleStore(database: core).upsert(
            ArticleUpsertInput(
                feedID: feedID,
                title: "Ein Testartikel",
                content: "<p>Erster <strong>Absatz</strong>.</p><p>Zweiter Absatz.</p>",
                author: "Max Mustermann",
                arrivedAt: Date()
            )
        )
        let database = FeedivoMCPServerDatabase(core: core)

        let result = try GetArticleTool.call(database: database, arguments: ["articleID": .string(articleID)])

        guard case .text(let text) = result.content.first else {
            Issue.record("Erwartete Text-Content")
            return
        }
        #expect(text.contains("Ein Testartikel"))
        #expect(text.contains("Max Mustermann"))
        #expect(text.contains("Erster Absatz."))
        #expect(!text.contains("<p>"))
        #expect(!text.contains("<strong>"))
        #expect(result.isError == false)
    }

    @Test("Liefert einen Fehler bei unbekannter Artikel-ID")
    func liefertFehlerBeiUnbekannterID() throws {
        let core = try FeedivoDatabase.inMemoryForTests()
        let database = FeedivoMCPServerDatabase(core: core)

        let result = try GetArticleTool.call(database: database, arguments: ["articleID": .string("does-not-exist")])

        #expect(result.isError == true)
    }

    @Test("Liefert einen Fehler bei fehlendem articleID-Parameter")
    func liefertFehlerBeiFehlendemParameter() throws {
        let core = try FeedivoDatabase.inMemoryForTests()
        let database = FeedivoMCPServerDatabase(core: core)

        let result = try GetArticleTool.call(database: database, arguments: [:])

        #expect(result.isError == true)
    }
}
```

- [ ] **Step 2: Tests ausführen, Fehlschlag verifizieren**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme FeedivoMCPServer -destination 'platform=macOS' test -only-testing:FeedivoMCPServerTests/GetArticleToolTests`
Expected: FAIL mit "cannot find 'GetArticleTool' in scope"

- [ ] **Step 3: Implementierung schreiben**

```swift
import MCP

enum GetArticleTool {
    static let definition = Tool(
        name: "get_article",
        description: "Liest den vollständigen Inhalt eines einzelnen Artikels (als bereinigter Klartext) anhand seiner ID, wie von search_articles oder get_smart_folder_articles zurückgegeben.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "articleID": .object([
                    "type": .string("string"),
                    "description": .string("Die Artikel-ID aus search_articles"),
                ])
            ]),
            "required": .array([.string("articleID")]),
        ])
    )

    static func call(database: FeedivoMCPServerDatabase, arguments: [String: Value]?) throws -> CallTool.Result {
        guard let articleID = arguments?["articleID"]?.stringValue else {
            return .init(content: [.text("Fehlender Parameter: articleID")], isError: true)
        }

        let articleDatabase = ArticleDatabase(database: database.core)
        guard let article = try articleDatabase.readerArticle(id: articleID) else {
            return .init(content: [.text("Kein Artikel mit ID \(articleID) gefunden.")], isError: true)
        }

        let plainContent = HTMLPlainTextConverter.plainText(fromHTML: article.content ?? article.summary ?? "")
        let tagNames = article.tags.map(\.name).joined(separator: ", ")

        let text = """
            Titel: \(article.title)
            Feed: \(article.feedTitle)
            Link: \(article.link ?? "—")
            Autor: \(article.author ?? "—")
            Tags: \(tagNames.isEmpty ? "—" : tagNames)
            Gelesen: \(article.isRead ? "ja" : "nein"), Stern: \(article.isStarred ? "ja" : "nein")

            \(plainContent)
            """
        return .init(content: [.text(text)], isError: false)
    }
}
```

- [ ] **Step 4: Tool in `main.swift` registrieren**

`availableTools` um `GetArticleTool.definition` ergänzen, `switch` um folgenden `case` ergänzen:

```swift
case "get_article":
    return try GetArticleTool.call(database: database, arguments: params.arguments)
```

- [ ] **Step 5: Tests erneut ausführen, Erfolg verifizieren**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme FeedivoMCPServer -destination 'platform=macOS' test -only-testing:FeedivoMCPServerTests/GetArticleToolTests`
Expected: `TEST SUCCEEDED`, alle 3 Tests grün

- [ ] **Step 6: Vollständigen Build verifizieren**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme FeedivoMCPServer -configuration Debug build`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 7: Commit**

```bash
git add FeedivoMCPServer/Tools/GetArticleTool.swift FeedivoMCPServer/main.swift FeedivoMCPServerTests/GetArticleToolTests.swift
git commit -m "feat(mcp-server): Tool get_article

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 10: Tools `list_smart_folders`, `get_smart_folder_articles`

**Files:**
- Create: `FeedivoMCPServer/Tools/ListSmartFoldersTool.swift`
- Create: `FeedivoMCPServer/Tools/GetSmartFolderArticlesTool.swift`
- Modify: `FeedivoMCPServer/main.swift`
- Test: `FeedivoMCPServerTests/SmartFolderToolsTests.swift`

**Interfaces:**
- Consumes: `SQLiteSmartFolderStore(database: FeedivoDatabase).sidebarSnapshots() throws -> [SQLiteSmartFolderSnapshot]`; `SQLiteSmartFolderStore(database:).save(_ folder: SmartFolderRecord, conditions: [SmartFolderConditionRecord]) throws` (nur für Testfixtures); `TimelineStore(database: FeedivoDatabase).articles(scope: TimelineScope, searchText: String?, includeRead: Bool, includeHidden: Bool, sortOption: ArticleSortOption, limit: Int, offset: Int) throws -> [ArticleListSnapshot]`; `TimelineScope.smartFolder(SQLiteSmartFolderSnapshot)`; `SQLiteSmartFolderSnapshot` (Properties: `id`, `name`, `defaultKey`)
- Produces: `ListSmartFoldersTool.definition/call`, `GetSmartFolderArticlesTool.definition/call`

- [ ] **Step 1: Fehlschlagende Tests schreiben**

```swift
import Testing
import Foundation
import GRDB
import MCP
@testable import FeedivoMCPServer

@Suite("Smart-Folder-Tools")
struct SmartFolderToolsTests {
    @Test("list_smart_folders nennt Namen inkl. Standard-Markierung")
    func listSmartFoldersNenntNamenUndStandardMarkierung() throws {
        let core = try FeedivoDatabase.inMemoryForTests()
        let store = SQLiteSmartFolderStore(database: core)
        let customFolder = SmartFolderRecord(name: "Meine Auswahl", isDefault: false)
        try store.save(customFolder, conditions: [])
        let database = FeedivoMCPServerDatabase(core: core)

        let result = try ListSmartFoldersTool.call(database: database)

        guard case .text(let text) = result.content.first else {
            Issue.record("Erwartete Text-Content")
            return
        }
        #expect(text.contains("Meine Auswahl"))
    }

    @Test("get_smart_folder_articles liefert nur Artikel, die die Bedingung erfüllen")
    func getSmartFolderArticlesFiltertNachBedingung() throws {
        let core = try FeedivoDatabase.inMemoryForTests()
        let feedID = try core.write { db -> String in
            var feed = FeedRecord(url: "https://example.com/feed", title: "Blog")
            try feed.insert(db)
            return feed.id
        }
        let articleStore = ArticleStore(database: core)
        let unreadID = try articleStore.upsert(
            ArticleUpsertInput(feedID: feedID, title: "Ungelesener Artikel", arrivedAt: Date())
        )
        let readID = try articleStore.upsert(
            ArticleUpsertInput(feedID: feedID, title: "Gelesener Artikel", arrivedAt: Date())
        )
        try ArticleStatusStore(database: core).setRead(true, articleID: readID, at: Date())

        let smartFolderStore = SQLiteSmartFolderStore(database: core)
        let folder = SmartFolderRecord(name: "Nur ungelesen", isDefault: false)
        let condition = SmartFolderConditionRecord(
            smartFolderID: folder.id,
            field: SmartFolderConditionField.status.rawValue,
            conditionOperator: SmartFolderConditionOperator.`is`.rawValue,
            value: "unread"
        )
        try smartFolderStore.save(folder, conditions: [condition])

        let database = FeedivoMCPServerDatabase(core: core)
        let result = try GetSmartFolderArticlesTool.call(
            database: database,
            arguments: ["smartFolderID": .string(folder.id)]
        )

        guard case .text(let text) = result.content.first else {
            Issue.record("Erwartete Text-Content")
            return
        }
        #expect(text.contains(unreadID))
        #expect(!text.contains("Gelesener Artikel"))
    }

    @Test("get_smart_folder_articles liefert Fehler bei unbekannter ID")
    func getSmartFolderArticlesLiefertFehlerBeiUnbekannterID() throws {
        let core = try FeedivoDatabase.inMemoryForTests()
        let database = FeedivoMCPServerDatabase(core: core)

        let result = try GetSmartFolderArticlesTool.call(
            database: database,
            arguments: ["smartFolderID": .string("unbekannt")]
        )

        #expect(result.isError == true)
    }
}
```

- [ ] **Step 2: Tests ausführen, Fehlschlag verifizieren**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme FeedivoMCPServer -destination 'platform=macOS' test -only-testing:FeedivoMCPServerTests/SmartFolderToolsTests`
Expected: FAIL mit "cannot find 'ListSmartFoldersTool' in scope"

- [ ] **Step 3: `ListSmartFoldersTool` implementieren**

```swift
import MCP

enum ListSmartFoldersTool {
    static let definition = Tool(
        name: "list_smart_folders",
        description: "Listet alle Intelligenten Ordner (Standard + eigene) mit ihrer ID auf.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([:]),
        ])
    )

    static func call(database: FeedivoMCPServerDatabase) throws -> CallTool.Result {
        let store = SQLiteSmartFolderStore(database: database.core)
        let folders = try store.sidebarSnapshots()

        if folders.isEmpty {
            return .init(content: [.text("Keine Intelligenten Ordner vorhanden.")], isError: false)
        }

        let lines = folders.map { folder -> String in
            let suffix = folder.defaultKey != nil ? ", Standard" : ""
            return "\(folder.name) (id: \(folder.id)\(suffix))"
        }
        return .init(content: [.text(lines.joined(separator: "\n"))], isError: false)
    }
}
```

- [ ] **Step 4: `GetSmartFolderArticlesTool` implementieren**

```swift
import MCP

enum GetSmartFolderArticlesTool {
    static let definition = Tool(
        name: "get_smart_folder_articles",
        description: "Liest die Artikel eines Intelligenten Ordners (per ID aus list_smart_folders).",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "smartFolderID": .object(["type": .string("string")]),
                "limit": .object(["type": .string("integer")]),
            ]),
            "required": .array([.string("smartFolderID")]),
        ])
    )

    static func call(database: FeedivoMCPServerDatabase, arguments: [String: Value]?) throws -> CallTool.Result {
        guard let folderID = arguments?["smartFolderID"]?.stringValue else {
            return .init(content: [.text("Fehlender Parameter: smartFolderID")], isError: true)
        }

        let smartFolderStore = SQLiteSmartFolderStore(database: database.core)
        guard let snapshot = try smartFolderStore.sidebarSnapshots().first(where: { $0.id == folderID }) else {
            return .init(content: [.text("Kein Intelligenter Ordner mit ID \(folderID) gefunden.")], isError: true)
        }

        let limit = arguments?["limit"]?.intValue ?? 50
        let timeline = TimelineStore(database: database.core)
        let results = try timeline.articles(
            scope: .smartFolder(snapshot),
            includeRead: true,
            includeHidden: false,
            limit: limit
        )

        if results.isEmpty {
            return .init(content: [.text("Keine Artikel in \"\(snapshot.name)\".")], isError: false)
        }

        let lines = results.map { "[\($0.id)] \($0.title) — \($0.feedTitle)" }
        return .init(content: [.text(lines.joined(separator: "\n"))], isError: false)
    }
}
```

- [ ] **Step 5: Tools in `main.swift` registrieren**

```swift
var availableTools: [Tool] = [
    ListFeedsTool.definition,
    ListFoldersTool.definition,
    ListTagsTool.definition,
    SearchArticlesTool.definition,
    GetArticleTool.definition,
    ListSmartFoldersTool.definition,
    GetSmartFolderArticlesTool.definition,
]
```

Und im `switch`:

```swift
case "list_smart_folders":
    return try ListSmartFoldersTool.call(database: database)
case "get_smart_folder_articles":
    return try GetSmartFolderArticlesTool.call(database: database, arguments: params.arguments)
```

- [ ] **Step 6: Tests erneut ausführen, Erfolg verifizieren**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme FeedivoMCPServer -destination 'platform=macOS' test -only-testing:FeedivoMCPServerTests/SmartFolderToolsTests`
Expected: `TEST SUCCEEDED`, alle 3 Tests grün

- [ ] **Step 7: Vollständigen Regressionslauf über alle FeedivoMCPServerTests**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme FeedivoMCPServer -destination 'platform=macOS' test -parallel-testing-enabled NO`
Expected: `TEST SUCCEEDED`, alle bisherigen Tests aus Tasks 3–10 grün

- [ ] **Step 8: Auch das Feedivo-App-Target build-verifizieren (Target-Membership-Änderungen dürfen die App nicht kaputt gemacht haben)**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -configuration Debug build`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 9: Commit**

```bash
git add FeedivoMCPServer/Tools/ListSmartFoldersTool.swift FeedivoMCPServer/Tools/GetSmartFolderArticlesTool.swift FeedivoMCPServer/main.swift FeedivoMCPServerTests/SmartFolderToolsTests.swift
git commit -m "feat(mcp-server): Tools list_smart_folders, get_smart_folder_articles

Damit sind alle 7 v1-Tools aus der Design-Spec implementiert.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 11 [MANUELL — erfordert Xcode-GUI]: `FeedivoMCPServer` in `Feedivo.app` einbetten

**⚠️ Diese Task kann nicht von einem autonomen Subagent ausgeführt werden.**

**Ziel:** `FeedivoMCPServer` wird automatisch mitgebaut und landet im App-Bundle, sodass Sparkle-/Homebrew-Updates es künftig mitverteilen (siehe Design-Spec, Abschnitt "Distribution").

**Schritte (in Xcode):**

1. Projekt auswählen → Target `Feedivo` → Tab "Build Phases".
2. "+" → "New Copy Files Phase".
3. Neue Phase konfigurieren:
   - Name: "Embed MCP Server" (per Doppelklick auf den Phasennamen umbenennbar)
   - Destination: **Executables**
   - "+" unten in der Dateiliste → das Produkt `FeedivoMCPServer` (den Executable, nicht die Testsuite) auswählen und hinzufügen.
4. Target `Feedivo` → Tab "General" → Abschnitt "Frameworks, Libraries, and Embedded Content" ODER Tab "Build Phases" → "Target Dependencies": `FeedivoMCPServer` als Abhängigkeit von `Feedivo` ergänzen (falls nicht automatisch durch Schritt 3 bereits geschehen — Xcode fragt bei "Copy Files" mit einem ausführbaren Produkt manchmal direkt danach). Das stellt sicher, dass `FeedivoMCPServer` bei jedem `Feedivo`-Build automatisch mitgebaut wird.
5. Bauen und prüfen, dass die Binary im Bundle landet:

```bash
xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -configuration Debug build
find ~/Library/Developer/Xcode/DerivedData -path "*/Feedivo.app/Contents/MacOS/FeedivoMCPServer" 2>/dev/null
```

Expected: Der `find`-Befehl liefert genau einen Treffer.

- [x] **Nutzer bestätigt:** Copy-Files-Phase eingerichtet, Build erfolgreich, Binary im Bundle gefunden (verifiziert: gültiges signiertes Mach-O arm64, Team-ID `X72F89J699`, Hardened Runtime aktiv).

- [x] **Commit (durch den Nutzer selbst, da die pbxproj-Änderung nur in Xcode entstehen kann):** (committed: `ac2a3eb`)

```bash
git add Feedivo.xcodeproj/project.pbxproj
git commit -m "build: FeedivoMCPServer wird ins App-Bundle eingebettet

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 12 [MANUELL — erfordert Claude Desktop]: Live-Verifikation

**⚠️ Diese Task kann nicht von einem autonomen Subagent ausgeführt werden.**

**Schritte:**

1. Feedivo mindestens einmal starten (falls noch nicht geschehen), damit die Datenbank existiert und ein paar echte Feeds/Artikel vorhanden sind.
2. Pfad zur eingebetteten Binary ermitteln:

```bash
find ~/Library/Developer/Xcode/DerivedData -path "*/Feedivo.app/Contents/MacOS/FeedivoMCPServer" 2>/dev/null
```

   (Für einen echten Release-Test später: `/Applications/Feedivo.app/Contents/MacOS/FeedivoMCPServer`, sobald ein regulärer Release-Build existiert — für die erste Verifikation reicht der Debug-Build aus DerivedData.)

3. In Claude Desktops Konfigurationsdatei (`~/Library/Application Support/Claude/claude_desktop_config.json`) einen Eintrag ergänzen:

```json
{
  "mcpServers": {
    "feedivo": {
      "command": "/PFAD/AUS/SCHRITT/2/FeedivoMCPServer"
    }
  }
}
```

4. Claude Desktop neu starten.
5. Live-Testfragen stellen und Antworten mit dem tatsächlichen App-Inhalt (Feed-Liste in Feedivo selbst) abgleichen:
   - "Welche Feeds habe ich in Feedivo abonniert?" → sollte `list_feeds` nutzen, Ergebnis mit der Sidebar in Feedivo vergleichen.
   - "Zeig mir meine ungelesenen Artikel." → sollte `search_articles` mit `status: unread` nutzen.
   - "Fasse mir einen bestimmten Artikel zusammen." → sollte `search_articles` gefolgt von `get_article` nutzen.
   - "Welche Intelligenten Ordner habe ich?" → sollte `list_smart_folders` nutzen.
6. **Wichtiger Test:** Feedivo komplett beenden (⌘Q), die obigen Fragen erneut stellen — die Abfragen sollten weiterhin funktionieren (read-only Zugriff funktioniert auch ohne laufende App).
7. **Wichtiger Test:** Feedivo wieder öffnen, während Claude Desktop weiterhin verbunden ist, eine Abfrage stellen — sollte weiterhin funktionieren (paralleler Lesezugriff neben einer laufenden App, dank WAL-Modus).

- [x] **Nutzer bestätigt:** Alle 7 Schritte durchgeführt, Ergebnisse stimmen mit dem tatsächlichen Feedivo-Inhalt überein, funktioniert sowohl bei laufender als auch bei beendeter App (zusätzlich vom Koordinator unabhängig gegengeprüft, inkl. Beenden einer zweiten, an einen Xcode-Debugserver gehängten Feedivo-Instanz).

---

## Zusammenfassung nach Abschluss

Nach Task 12 ist v1 (read-only) vollständig: 7 Tools, eingebettet in `Feedivo.app`, verifiziert gegen eine echte Installation. Die Roadmap-Punkte aus der Design-Spec (Schreibzugriffe via Cross-Process-Notify, Feed-/Regel-Verwaltung) sind bewusst nicht Teil dieses Plans — für v2 wäre ein neuer Brainstorming→Spec→Plan-Zyklus nötig, sobald gewünscht.
