# Live-Verbindungsstatus im KI-Zugriff-Tab — Implementierungsplan

> **Für agentische Worker:** REQUIRED SUB-SKILL: Nutze superpowers:subagent-driven-development (empfohlen) oder superpowers:executing-plans, um diesen Plan Task für Task umzusetzen. Schritte nutzen Checkbox-Syntax (`- [ ]`).

**Goal:** Der Einstellungen-Tab „KI-Zugriff" zeigt, ob gerade ein KI-Client verbunden ist, benennt ihn, und hält sich selbst aktuell, solange der Tab sichtbar ist.

**Architecture:** Der Serverprozess trägt sich beim Start in eine neue Tabelle `mcp_server_sessions` ein und aktualisiert dort alle 15 Sekunden einen Heartbeat. Die App liest alle 5 Sekunden, welche Sitzungen frisch sind (jünger als 40 Sekunden), und zeigt sie gruppiert an. Den Client-Namen leitet der Server aus dem Pfad seines Elternprozesses ab.

**Tech Stack:** Swift 6, SwiftUI (macOS 14+), Darwin/libproc (`getppid`, `proc_pidpath`), GRDB/SQLite, Swift Testing.

## Global Constraints

- Code-Kommentare und Testnamen auf **Deutsch** (Projektkonvention). UI-Texte laufen ausschließlich über `L10n`-Konstanten bzw. `String(localized:)` + `Localizable.xcstrings`, nie als rohe String-Literale in der View.
- Neue Migrationen werden **immer angehängt**, bestehende nie geändert. Letzte Migration ist `v35_add_mcp_server_last_connection` — vor dem Anlegen mit `grep -n registerMigration Feedivo/Database/FeedivoDatabaseMigrator.swift` gegenprüfen, nicht dieser Zeile vertrauen.
- Der Server schreibt Sitzungseintrag und Heartbeat **unabhängig vom Schreibzugriff-Schalter**. Die Zusage „rein lesend" gilt weiterhin uneingeschränkt für Inhalte (Artikel, Tags, Status, Feeds).
- Ein fehlgeschlagener Sitzungseintrag oder Heartbeat darf den Serverstart **nie** blockieren — Fehler auf stderr protokollieren und verschlucken.
- Die App zeigt bei jedem Lesefehler **„Nicht verbunden"**. Sie behauptet im Zweifel nie eine Verbindung.
- Tests immer gezielt mit **Suiten**-Selektoren (`-only-testing:FeedivoTests/<SuiteName>`) und `-parallel-testing-enabled NO`. Ein unscoped `xcodebuild test` deadlockt in diesem Projekt; ein Einzelmethoden-Selektor kann „TEST SUCCEEDED" bei `totalTestCount: 0` melden.
- Nach jedem Task müssen **beide** Schemes bauen: `Feedivo` und `FeedivoMCPServer`.
- SourceKit-/IDE-Diagnosen sind hier notorisch falsch („No such module 'GRDB'"). Nur echte `xcodebuild`-Läufe zählen.
- Neue `L10n`-Keys erzeugen **keinen** automatischen Eintrag in `Localizable.xcstrings`. Jeder neue Key muss manuell ergänzt und mit `grep -c "<punkt.key>" Feedivo/Resources/Localizable.xcstrings` verifiziert werden (muss > 0 sein).
- `Localizable.xcstrings` **niemals** per `json.load`/`json.dump` roundtripen. Nur Text-Einfügung am Anker `  "strings" : {`, danach `git diff --stat` prüfen (nahezu nur Insertions). Alle `settings.mcpServer.*`-Keys haben vier Sprachen (de/en/fr/it) — neue Keys ebenso anlegen.
- Neue Dateien unter `Feedivo/`, die der Server braucht, müssen dem Target `FeedivoMCPServer` per `membershipExceptions` in `Feedivo.xcodeproj/project.pbxproj` hinzugefügt werden (alphabetisch, Tab-Einrückung wie die Nachbarzeilen).

## Dateistruktur

| Datei | Verantwortung |
|---|---|
| `Feedivo/Database/FeedivoDatabaseMigrator.swift` | Migration v36 |
| `Feedivo/Stores/MCPServerSessionStore.swift` (neu) | Sitzungen eintragen, Heartbeat schreiben, aktive Sitzungen lesen |
| `Feedivo/Services/MCPClientNameResolver.swift` (neu) | Aus einem Programmpfad einen Anzeigenamen ableiten |
| `FeedivoMCPServer/FeedivoMCPServerConnectionRecorder.swift` | Zusätzlich: Sitzung eintragen, Heartbeat-Schleife, Elternprozess ermitteln |
| `Feedivo/Services/MCPConnectionStatusText.swift` | Zusätzlich: Zeilen für aktive Sitzungen |
| `Feedivo/Views/Settings/SettingsView.swift` | `MCPServerSettingsView` um Live-Anzeige erweitern |
| `Feedivo/Resources/L10n.swift` + `Localizable.xcstrings` | Neue Texte |

---

### Task 1: Migration v36 und Sitzungs-Store

**Files:**
- Modify: `Feedivo/Database/FeedivoDatabaseMigrator.swift` (neuer Block nach `v35_add_mcp_server_last_connection`, vor `return migrator`)
- Create: `Feedivo/Stores/MCPServerSessionStore.swift`
- Test: `FeedivoTests/Database/FeedivoDatabaseMigratorTests.swift`
- Test: `FeedivoTests/Stores/MCPServerSessionStoreTests.swift` (neu)

**Interfaces:**
- Consumes: `FeedivoDatabase`
- Produces:
  - `struct MCPServerSession: Equatable { let pid: Int; let clientName: String; let startedAt: Date; let toolCount: Int; let lastHeartbeatAt: Date }`
  - `struct MCPServerSessionStore { init(database: FeedivoDatabase) }`
  - `func startSession(pid: Int, clientName: String, at date: Date, toolCount: Int) throws`
  - `func recordHeartbeat(pid: Int, at date: Date) throws`
  - `func deleteSessions(lastSeenBefore cutoff: Date) throws`
  - `func activeSessions(now: Date, tolerance: TimeInterval) throws -> [MCPServerSession]`
  - `static let MCPServerSessionStore.heartbeatTolerance: TimeInterval = 40`
  - Migration `"v36_create_mcp_server_sessions"`

- [ ] **Schritt 1: Failing Test für die Migration**

Ans Ende der Suite in `FeedivoTests/Database/FeedivoDatabaseMigratorTests.swift`:

```swift
    @Test func migrationV36LegtSitzungstabelleAn() throws {
        let queue = try DatabaseQueue()
        try FeedivoDatabaseMigrator.migrator.migrate(queue, upTo: "v35_add_mcp_server_last_connection")

        try FeedivoDatabaseMigrator.migrator.migrate(queue)

        // Die Tabelle startet leer: Sitzungen entstehen erst, wenn ein Serverprozess laeuft.
        let spalten = try queue.read { db in
            try db.columns(in: "mcp_server_sessions").map(\.name).sorted()
        }
        #expect(spalten == ["clientName", "lastHeartbeatAt", "pid", "startedAt", "toolCount"])
    }
```

- [ ] **Schritt 2: Test ausführen, Fehlschlag bestätigen**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/FeedivoDatabaseMigratorTests 2>&1 | grep -E "Test run with|recorded an issue|error:" | head -5
```

Erwartet: FAIL — „no such table: mcp_server_sessions".

- [ ] **Schritt 3: Migration implementieren**

In `Feedivo/Database/FeedivoDatabaseMigrator.swift` nach dem v35-Block, vor `return migrator`:

```swift
        migrator.registerMigration("v36_create_mcp_server_sessions") { database in
            // Eine Zeile je LAUFENDEM Serverprozess. Ergaenzt die v35-Spalten, ersetzt sie nicht:
            // `mcp_server_settings.lastConnectedAt` beantwortet "wann zuletzt" (auch wenn gerade
            // niemand verbunden ist), diese Tabelle beantwortet "wer jetzt".
            //
            // `pid` als Primaerschluessel mit spaeterem INSERT OR REPLACE: Das Betriebssystem
            // vergibt Prozess-IDs wieder — ein neuer Prozess mit alter ID ueberschreibt so sauber
            // die tote Zeile, statt eine Dublette zu erzeugen.
            try database.create(table: "mcp_server_sessions") { table in
                table.column("pid", .integer).primaryKey()
                table.column("clientName", .text).notNull()
                table.column("startedAt", .datetime).notNull()
                table.column("toolCount", .integer).notNull()
                table.column("lastHeartbeatAt", .datetime).notNull()
            }
        }
```

- [ ] **Schritt 4: Migrations-Test grün**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/FeedivoDatabaseMigratorTests 2>&1 | grep -E "Test run with|recorded an issue" | head -3
```

Erwartet: PASS.

- [ ] **Schritt 5: Failing Tests für den Store**

Neue Datei `FeedivoTests/Stores/MCPServerSessionStoreTests.swift`:

```swift
import Foundation
import Testing
import GRDB
@testable import Feedivo

@Suite("MCPServerSessionStore")
struct MCPServerSessionStoreTests {
    private let jetzt = Date(timeIntervalSince1970: 1_786_800_000)

    @Test("Ohne Sitzungen ist die Liste leer")
    func ohneSitzungenLeer() throws {
        let store = MCPServerSessionStore(database: try FeedivoDatabase.inMemoryForTests())

        #expect(try store.activeSessions(now: jetzt, tolerance: 40).isEmpty)
    }

    @Test("Eine frisch eingetragene Sitzung gilt als aktiv")
    func frischeSitzungIstAktiv() throws {
        let store = MCPServerSessionStore(database: try FeedivoDatabase.inMemoryForTests())

        try store.startSession(pid: 4711, clientName: "Claude", at: jetzt, toolCount: 10)

        let aktive = try store.activeSessions(now: jetzt, tolerance: 40)
        #expect(aktive.count == 1)
        #expect(aktive.first?.pid == 4711)
        #expect(aktive.first?.clientName == "Claude")
        #expect(aktive.first?.toolCount == 10)
    }

    @Test("Eine Sitzung ohne frischen Heartbeat gilt nicht mehr als aktiv")
    func alteSitzungIstNichtAktiv() throws {
        let store = MCPServerSessionStore(database: try FeedivoDatabase.inMemoryForTests())
        try store.startSession(pid: 4711, clientName: "Claude", at: jetzt, toolCount: 10)

        // 41 Sekunden spaeter: knapp jenseits der Toleranz von 40 Sekunden.
        let aktive = try store.activeSessions(now: jetzt.addingTimeInterval(41), tolerance: 40)

        #expect(aktive.isEmpty)
    }

    @Test("Ein Heartbeat haelt die Sitzung am Leben")
    func heartbeatHaeltSitzungAmLeben() throws {
        let store = MCPServerSessionStore(database: try FeedivoDatabase.inMemoryForTests())
        try store.startSession(pid: 4711, clientName: "Claude", at: jetzt, toolCount: 10)

        try store.recordHeartbeat(pid: 4711, at: jetzt.addingTimeInterval(30))

        let aktive = try store.activeSessions(now: jetzt.addingTimeInterval(41), tolerance: 40)
        #expect(aktive.count == 1)
        // startedAt bleibt der urspruengliche Startzeitpunkt, nur das Lebenszeichen wandert.
        #expect(abs((aktive.first?.startedAt ?? .distantPast).timeIntervalSince(jetzt)) < 1)
    }

    @Test("Ein erneuter Start mit derselben Prozess-ID ersetzt die alte Zeile")
    func gleicheProzessIDErsetztZeile() throws {
        let store = MCPServerSessionStore(database: try FeedivoDatabase.inMemoryForTests())

        // Prozess-IDs werden vom System wiederverwendet — sonst entstuenden Dubletten.
        try store.startSession(pid: 4711, clientName: "Claude", at: jetzt, toolCount: 7)
        try store.startSession(pid: 4711, clientName: "Cursor", at: jetzt, toolCount: 10)

        let aktive = try store.activeSessions(now: jetzt, tolerance: 40)
        #expect(aktive.count == 1)
        #expect(aktive.first?.clientName == "Cursor")
        #expect(aktive.first?.toolCount == 10)
    }

    @Test("deleteSessions entfernt nur Zeilen ohne Lebenszeichen seit dem Stichtag")
    func deleteSessionsEntferntNurAlteZeilen() throws {
        let store = MCPServerSessionStore(database: try FeedivoDatabase.inMemoryForTests())
        try store.startSession(pid: 1, clientName: "Alt", at: jetzt.addingTimeInterval(-3600), toolCount: 7)
        try store.startSession(pid: 2, clientName: "Neu", at: jetzt, toolCount: 10)

        try store.deleteSessions(lastSeenBefore: jetzt.addingTimeInterval(-600))

        let aktive = try store.activeSessions(now: jetzt, tolerance: 40)
        #expect(aktive.map(\.clientName) == ["Neu"])
    }

    @Test("Aktive Sitzungen sind stabil nach Name und Werkzeug-Anzahl sortiert")
    func aktiveSitzungenSindSortiert() throws {
        let store = MCPServerSessionStore(database: try FeedivoDatabase.inMemoryForTests())
        // Reihenfolge des Eintragens bewusst gegen die erwartete Sortierung.
        try store.startSession(pid: 3, clientName: "Cursor", at: jetzt, toolCount: 7)
        try store.startSession(pid: 1, clientName: "Claude", at: jetzt, toolCount: 10)
        try store.startSession(pid: 2, clientName: "Claude", at: jetzt, toolCount: 7)

        let aktive = try store.activeSessions(now: jetzt, tolerance: 40)

        #expect(aktive.map { "\($0.clientName)/\($0.toolCount)" } == ["Claude/7", "Claude/10", "Cursor/7"])
    }
}
```

- [ ] **Schritt 6: Test ausführen, Fehlschlag bestätigen**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/MCPServerSessionStoreTests 2>&1 | grep -E "error:|Test run with" | head -5
```

Erwartet: Compile-Fehler „cannot find 'MCPServerSessionStore' in scope".

- [ ] **Schritt 7: Store implementieren**

Neue Datei `Feedivo/Stores/MCPServerSessionStore.swift`:

```swift
import Foundation
import GRDB

/// Eine laufende Verbindung eines KI-Clients zum MCP-Server.
struct MCPServerSession: Equatable {
    let pid: Int
    /// Anzeigename des Clients, abgeleitet aus dem Elternprozess (siehe `MCPClientNameResolver`).
    let clientName: String
    let startedAt: Date
    /// Werkzeuge, die GENAU DIESER Prozess anbietet — nicht, was die aktuellen Schalter ergäben.
    let toolCount: Int
    let lastHeartbeatAt: Date
}

/// Liest und schreibt die Tabelle `mcp_server_sessions`.
///
/// Der Serverprozess trägt sich beim Start ein und aktualisiert danach regelmäßig sein
/// Lebenszeichen; die App wertet aus, welche Sitzungen frisch genug sind, um als „verbunden" zu
/// gelten. Eine sandboxed App kann fremde Prozesse nicht zuverlässig beobachten — dieser Umweg
/// über die gemeinsame Datenbank ist der einzige verlässliche Weg.
struct MCPServerSessionStore {
    /// Wie alt ein Lebenszeichen höchstens sein darf, damit die Sitzung als verbunden gilt:
    /// zwei verpasste Intervalle (15 s) plus Puffer.
    static let heartbeatTolerance: TimeInterval = 40

    private let database: FeedivoDatabase

    init(database: FeedivoDatabase) {
        self.database = database
    }

    /// Trägt eine neue Sitzung ein. `INSERT OR REPLACE`, weil das Betriebssystem Prozess-IDs
    /// wiederverwendet — eine alte Zeile derselben ID gehört überschrieben, nicht dupliziert.
    func startSession(pid: Int, clientName: String, at date: Date, toolCount: Int) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO mcp_server_sessions
                        (pid, clientName, startedAt, toolCount, lastHeartbeatAt)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: [pid, clientName, date, toolCount, date]
            )
        }
    }

    func recordHeartbeat(pid: Int, at date: Date) throws {
        try database.write { db in
            try db.execute(
                sql: "UPDATE mcp_server_sessions SET lastHeartbeatAt = ? WHERE pid = ?",
                arguments: [date, pid]
            )
        }
    }

    /// Räumt Zeilen von Prozessen weg, die sich nie ordentlich abgemeldet haben (etwa nach einem
    /// harten Abbruch). Wird vom Server beim Start aufgerufen, damit die Tabelle nicht wächst.
    func deleteSessions(lastSeenBefore cutoff: Date) throws {
        try database.write { db in
            try db.execute(
                sql: "DELETE FROM mcp_server_sessions WHERE lastHeartbeatAt < ?",
                arguments: [cutoff]
            )
        }
    }

    /// Sitzungen mit frischem Lebenszeichen, stabil sortiert nach Name und Werkzeug-Anzahl —
    /// sonst könnte die Anzeige zwischen zwei Aktualisierungen die Reihenfolge tauschen.
    func activeSessions(
        now: Date,
        tolerance: TimeInterval = MCPServerSessionStore.heartbeatTolerance
    ) throws -> [MCPServerSession] {
        try database.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT pid, clientName, startedAt, toolCount, lastHeartbeatAt
                    FROM mcp_server_sessions
                    WHERE lastHeartbeatAt >= ?
                    ORDER BY clientName COLLATE NOCASE, toolCount, pid
                    """,
                arguments: [now.addingTimeInterval(-tolerance)]
            ).map { row in
                MCPServerSession(
                    pid: row["pid"],
                    clientName: row["clientName"],
                    startedAt: row["startedAt"],
                    toolCount: row["toolCount"],
                    lastHeartbeatAt: row["lastHeartbeatAt"]
                )
            }
        }
    }
}
```

- [ ] **Schritt 8: Tests grün**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/MCPServerSessionStoreTests -only-testing:FeedivoTests/FeedivoDatabaseMigratorTests 2>&1 | grep -E "Test run with|recorded an issue" | head -3
```

Erwartet: PASS.

- [ ] **Schritt 9: Target-Membership für den Server ergänzen**

Der Server braucht diesen Store. In `Feedivo.xcodeproj/project.pbxproj` im `membershipExceptions`-Array des `FeedivoMCPServer`-Targets (beginnt bei Zeile ~106 mit `Database/FeedivoDatabase.swift`) alphabetisch einfügen — `Stores/MCPServerSessionStore.swift` kommt **vor** `Stores/MCPServerSettingsStore.swift` („Session" vor „Settings"), Tab-Einrückung exakt wie die Nachbarzeilen:

```
				Stores/MCPServerSessionStore.swift,
```

- [ ] **Schritt 10: Builds prüfen und committen**

```bash
xcodebuild build -scheme Feedivo -configuration Debug 2>&1 | tail -2 && xcodebuild build -scheme FeedivoMCPServer -configuration Debug 2>&1 | tail -2
```

```bash
git add Feedivo/Database/FeedivoDatabaseMigrator.swift Feedivo/Stores/MCPServerSessionStore.swift FeedivoTests/Database/FeedivoDatabaseMigratorTests.swift FeedivoTests/Stores/MCPServerSessionStoreTests.swift Feedivo.xcodeproj/project.pbxproj
git commit -m "feat(mcp-server): Sitzungstabelle fuer laufende Verbindungen (Migration v36)"
```

---

### Task 2: Client-Namen aus dem Programmpfad ableiten

**Files:**
- Create: `Feedivo/Services/MCPClientNameResolver.swift`
- Test: `FeedivoTests/Services/MCPClientNameResolverTests.swift` (neu)

**Interfaces:**
- Consumes: nichts
- Produces: `static func MCPClientNameResolver.clientName(forExecutablePath path: String) -> String`

**Warum in `Feedivo/Services/` statt im Server-Target:** Das Test-Target `FeedivoMCPServerTests` läuft in diesem Projekt strukturell nie (`Could not find test host` bei Command-Line-Tool-Targets). Eine Funktion dort wäre nie laufzeitgeprüft. Hier läuft sie über das normale App-Test-Target.

- [ ] **Schritt 1: Failing Tests schreiben**

Neue Datei `FeedivoTests/Services/MCPClientNameResolverTests.swift`:

```swift
import Foundation
import Testing
@testable import Feedivo

@Suite("MCPClientNameResolver")
struct MCPClientNameResolverTests {
    @Test("Aus einem App-Bundle-Pfad wird der App-Name")
    func appBundleWirdZuAppName() {
        // Genau dieser Pfad wurde am 2026-08-16 auf dem Rechner des Nutzers beobachtet:
        // Claude Desktop startet den Server ueber einen Hilfsprozess.
        let name = MCPClientNameResolver.clientName(
            forExecutablePath: "/Applications/Claude.app/Contents/Helpers/disclaimer"
        )

        #expect(name == "Claude")
    }

    @Test("Bei verschachtelten Bundles gewinnt das aeussere")
    func aeusseresBundleGewinnt() {
        // Das aeussere Bundle ist die App, die der Nutzer kennt — ein inneres Helper-Bundle
        // traegt einen technischen Namen, der ihm nichts sagt.
        let name = MCPClientNameResolver.clientName(
            forExecutablePath: "/Applications/Cursor.app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper"
        )

        #expect(name == "Cursor")
    }

    @Test("Ohne Bundle wird der Dateiname genutzt")
    func ohneBundleDateiname() {
        let name = MCPClientNameResolver.clientName(forExecutablePath: "/opt/homebrew/bin/node")

        #expect(name == "node")
    }

    @Test("Ein leerer Pfad ergibt einen Platzhalter")
    func leererPfadErgibtPlatzhalter() {
        // Tritt auf, wenn die Ermittlung des Elternprozesses fehlschlaegt.
        #expect(MCPClientNameResolver.clientName(forExecutablePath: "") == "Unbekannt")
    }
}
```

- [ ] **Schritt 2: Test ausführen, Fehlschlag bestätigen**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/MCPClientNameResolverTests 2>&1 | grep -E "error:|Test run with" | head -5
```

Erwartet: Compile-Fehler „cannot find 'MCPClientNameResolver' in scope".

- [ ] **Schritt 3: Implementieren**

Neue Datei `Feedivo/Services/MCPClientNameResolver.swift`:

```swift
import Foundation

/// Leitet aus dem Pfad eines Programms einen Anzeigenamen für den KI-Client ab.
///
/// Bewusst pfadbasiert statt über eine Liste bekannter Clients: So wird auch ein Client korrekt
/// benannt, den dieses Projekt gar nicht kennt, und die Ableitung kann nicht veralten.
///
/// Der Name wird ausschließlich zur Anzeige gespeichert — der vollständige Pfad NIE, er könnte
/// Verzeichnisnamen des Nutzers enthalten.
enum MCPClientNameResolver {
    /// Wird angezeigt, wenn der Elternprozess nicht ermittelt werden konnte. Bewusst nicht
    /// lokalisiert: Der Wert wird vom Serverprozess geschrieben, der die Lokalisierung des
    /// App-Bundles nicht zur Verfügung hat.
    static let unknownClientName = "Unbekannt"

    static func clientName(forExecutablePath path: String) -> String {
        let komponenten = path.split(separator: "/", omittingEmptySubsequences: true)

        // Das AEUSSERE Bundle gewinnt: bei "Cursor.app/.../Helper.app/..." ist "Cursor" die App,
        // die der Nutzer kennt — "Helper" saehe aus wie ein fremdes Programm.
        if let bundle = komponenten.first(where: { $0.hasSuffix(".app") }) {
            return String(bundle.dropLast(".app".count))
        }

        return komponenten.last.map(String.init) ?? unknownClientName
    }
}
```

- [ ] **Schritt 4: Tests grün**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/MCPClientNameResolverTests 2>&1 | grep -E "Test run with|recorded an issue" | head -3
```

Erwartet: PASS (4 Tests).

- [ ] **Schritt 5: Target-Membership ergänzen**

Der Server ruft diese Funktion in Task 3 auf. In `Feedivo.xcodeproj/project.pbxproj` im `membershipExceptions`-Array des `FeedivoMCPServer`-Targets alphabetisch einfügen — zwischen `Services/FeedService.swift` und `Services/MCPWriteNotificationName.swift`:

```
				Services/MCPClientNameResolver.swift,
```

- [ ] **Schritt 6: Builds prüfen und committen**

```bash
xcodebuild build -scheme Feedivo -configuration Debug 2>&1 | tail -2 && xcodebuild build -scheme FeedivoMCPServer -configuration Debug 2>&1 | tail -2
```

```bash
git add Feedivo/Services/MCPClientNameResolver.swift FeedivoTests/Services/MCPClientNameResolverTests.swift Feedivo.xcodeproj/project.pbxproj
git commit -m "feat(mcp-server): Client-Name aus dem Elternprozess-Pfad ableiten"
```

---

### Task 3: Server trägt Sitzung ein und hält sie am Leben

**Files:**
- Modify: `FeedivoMCPServer/FeedivoMCPServerConnectionRecorder.swift`
- Modify: `FeedivoMCPServer/main.swift` (nur prüfen — die bestehende Aufrufzeile bleibt unverändert)

**Interfaces:**
- Consumes: `MCPServerSessionStore` (Task 1), `MCPClientNameResolver.clientName(forExecutablePath:)` (Task 2), bestehendes `MCPServerSettingsStore.recordConnection(at:toolCount:)`
- Produces: `static func FeedivoMCPServerConnectionRecorder.record(toolCount:at:)` behält Namen und Signatur — nur das Verhalten wächst

**Hinweis zur Nebenläufigkeit:** Der Heartbeat-Task fängt bewusst den `DatabasePool` ein (GRDB-eigener Typ, nebenläufigkeitssicher) und baut die `FeedivoDatabase`-Hülle innerhalb der Schleife neu. Das umgeht jede Frage, ob die Hülle selbst über Task-Grenzen getragen werden darf.

- [ ] **Schritt 1: Recorder erweitern**

`FeedivoMCPServer/FeedivoMCPServerConnectionRecorder.swift` vollständig ersetzen durch:

```swift
import Darwin
import Foundation
import GRDB

/// Hält beim Serverstart fest, dass ein KI-Client verbunden ist und mit wie vielen Werkzeugen —
/// und meldet danach regelmäßig, dass die Verbindung noch besteht.
///
/// **Bewusst unabhängig vom Schreibzugriff-Schalter:** Ohne diesen Vermerk kann der
/// Einstellungen-Tab „KI-Zugriff" nicht anzeigen, ob eine Verbindung besteht — am 2026-08-15
/// lief ein Serverprozess stundenlang mit einer veralteten Werkzeugliste, ohne dass das sichtbar
/// war. Die Zusage „rein lesend" gilt weiterhin uneingeschränkt für INHALTE (Artikel, Tags,
/// Status, Feeds); geschrieben werden ausschließlich Verbindungsmetadaten.
///
/// Nutzt eine eigene Verbindung statt `FeedivoMCPServerWritableDatabase`: jene wird nur bei
/// aktiviertem Schreibzugriff geöffnet und prüft zusätzlich eine Precondition, die hier keine
/// Rolle spielt.
enum FeedivoMCPServerConnectionRecorder {
    /// Abstand zwischen zwei Lebenszeichen. Die App wertet eine Sitzung als beendet, wenn das
    /// letzte Lebenszeichen älter als `MCPServerSessionStore.heartbeatTolerance` ist.
    static let heartbeatInterval: TimeInterval = 15

    /// Ab wann eine Sitzungszeile beim Start weggeräumt wird. Großzügig gewählt: Sie darf nur
    /// Prozesse treffen, die nachweislich nicht mehr laufen.
    static let staleSessionCutoff: TimeInterval = 600

    /// Schluckt jeden Fehler bewusst (nach Protokollierung auf stderr): Ein fehlender
    /// Verbindungsvermerk ist ein kosmetisches Problem und darf den Dienst nie blockieren.
    /// Das gilt auch für eine veraltete Datenbank ohne Tabelle `mcp_server_sessions` — der
    /// Server führt den Migrator nie aus (ADR-011).
    static func record(toolCount: Int, at fileURL: URL = FeedivoContainerDatabaseLocation.databaseURL()) {
        do {
            var configuration = Configuration()
            configuration.busyMode = .timeout(5)
            let pool = try DatabasePool(path: fileURL.path, configuration: configuration)
            let database = FeedivoDatabase(writer: pool)
            let jetzt = Date()
            let prozessID = Int(getpid())

            try MCPServerSettingsStore(database: database)
                .recordConnection(at: jetzt, toolCount: toolCount)

            let sitzungen = MCPServerSessionStore(database: database)
            try sitzungen.deleteSessions(lastSeenBefore: jetzt.addingTimeInterval(-staleSessionCutoff))
            try sitzungen.startSession(
                pid: prozessID,
                clientName: MCPClientNameResolver.clientName(forExecutablePath: parentExecutablePath()),
                at: jetzt,
                toolCount: toolCount
            )

            startHeartbeat(pool: pool, pid: prozessID)
        } catch {
            let message = "Feedivo MCP Server: Verbindungsvermerk konnte nicht geschrieben werden (\(error)).\n"
            FileHandle.standardError.write(Data(message.utf8))
        }
    }

    /// Faengt bewusst den `DatabasePool` ein (GRDB-eigener, nebenlaeufigkeitssicherer Typ) und
    /// baut die Huelle in der Schleife neu — so muss nichts anderes ueber die Task-Grenze.
    private static func startHeartbeat(pool: DatabasePool, pid: Int) {
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(heartbeatInterval))
                // Fehler werden hier still verschluckt: Ein einzelnes verpasstes Lebenszeichen
                // laesst die Anzeige hoechstens kurz auf "nicht verbunden" springen; den Dienst
                // dafuer mit Logzeilen zu fluten, waere unverhaeltnismaessig.
                try? MCPServerSessionStore(database: FeedivoDatabase(writer: pool))
                    .recordHeartbeat(pid: pid, at: Date())
            }
        }
    }

    /// Pfad des Prozesses, der diesen Server gestartet hat — bei Claude Desktop ein Hilfsprogramm
    /// innerhalb des App-Bundles. Leerer String, wenn das fehlschlaegt; der Aufrufer bildet das
    /// auf einen Platzhalternamen ab.
    private static func parentExecutablePath() -> String {
        var puffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let laenge = proc_pidpath(getppid(), &puffer, UInt32(MAXPATHLEN))
        guard laenge > 0 else { return "" }
        return String(cString: puffer)
    }
}
```

- [ ] **Schritt 2: Server-Build prüfen**

```bash
xcodebuild build -scheme FeedivoMCPServer -configuration Debug 2>&1 | grep -E "error:|BUILD" | tail -3
```

Erwartet: `** BUILD SUCCEEDED **`.

Schlägt der Build an `proc_pidpath` fehl („cannot find in scope"), fehlt der libproc-Header — dann `import Darwin.libproc` statt `import Darwin` verwenden. Meldet der Compiler bei `&puffer` einen Zeigertyp-Fehler, stattdessen:

```swift
        let laenge = puffer.withUnsafeMutableBufferPointer { zeiger in
            proc_pidpath(getppid(), zeiger.baseAddress, UInt32(MAXPATHLEN))
        }
```

- [ ] **Schritt 3: Aufrufstelle in `main.swift` prüfen**

Die bestehende Zeile bleibt unverändert:

```swift
FeedivoMCPServerConnectionRecorder.record(toolCount: availableTools.count)
```

Verifizieren, dass sie noch da ist und der umgebende Kommentar weiterhin stimmt:

```bash
grep -n -B 5 "FeedivoMCPServerConnectionRecorder.record" FeedivoMCPServer/main.swift
```

- [ ] **Schritt 4: Live-Nachweis gegen die echte Datenbank**

Der Server lässt sich nicht auf eine Testdatenbank umlenken (`FeedivoContainerDatabaseLocation.databaseURL()` ist fest verdrahtet, `homeDirectoryForCurrentUser` ignoriert `$HOME` — empirisch belegt am 2026-08-14). Der Nachweis läuft deshalb gegen die echte Datenbank; geschrieben werden dabei ausschließlich Verbindungsmetadaten, keine Inhalte.

**Voraussetzung:** Feedivo muss mindestens einmal mit Migration v36 gelaufen sein, sonst fehlt die Tabelle.

```bash
BIN="$(xcodebuild -scheme Feedivo -configuration Debug -showBuildSettings 2>/dev/null | awk '/BUILT_PRODUCTS_DIR/{print $3}')/Feedivo.app/Contents/MacOS/FeedivoMCPServer"
DB="$HOME/Library/Containers/ch.martin.Feedivo/Data/Library/Application Support/ch.martin.Feedivo/Feedivo/feedivo.sqlite"
"$BIN" < /dev/null > /tmp/mcp-heartbeat.log 2>&1 &
PID=$!
for i in $(seq 1 200); do [ -n "$(sqlite3 "$DB" 'SELECT pid FROM mcp_server_sessions;')" ] && break; done
sqlite3 "$DB" "SELECT pid, clientName, toolCount FROM mcp_server_sessions;"
kill $PID 2>/dev/null; wait $PID 2>/dev/null
cat /tmp/mcp-heartbeat.log
```

Erwartet: eine Zeile mit der Prozess-ID, einem Client-Namen (hier `sh` oder `bash` — der Server wurde ja von der Shell gestartet, nicht von einem KI-Client) und der Werkzeug-Anzahl. Leere stderr-Ausgabe. Dass der Name bei einem echten Client `Claude` lautet, deckt die manuelle Verifikation in Task 6 ab.

- [ ] **Schritt 5: Committen**

```bash
git add FeedivoMCPServer/FeedivoMCPServerConnectionRecorder.swift
git commit -m "feat(mcp-server): Sitzung eintragen und per Heartbeat am Leben halten"
```

---

### Task 4: Statuszeilen für aktive Sitzungen

**Files:**
- Modify: `Feedivo/Services/MCPConnectionStatusText.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`
- Test: `FeedivoTests/Services/MCPConnectionStatusTextTests.swift`

**Interfaces:**
- Consumes: `MCPServerSession` (Task 1)
- Produces: `static func MCPConnectionStatusText.activeLines(for sessions: [MCPServerSession]) -> [String]`

- [ ] **Schritt 1: Failing Tests schreiben**

Ans Ende der Suite in `FeedivoTests/Services/MCPConnectionStatusTextTests.swift`:

```swift
    private func sitzung(_ pid: Int, _ name: String, _ toolCount: Int) -> MCPServerSession {
        let zeitpunkt = Date(timeIntervalSince1970: 1_786_800_000)
        return MCPServerSession(
            pid: pid,
            clientName: name,
            startedAt: zeitpunkt,
            toolCount: toolCount,
            lastHeartbeatAt: zeitpunkt
        )
    }

    @Test("Ohne aktive Sitzungen gibt es keine Zeilen")
    func ohneSitzungenKeineZeilen() {
        #expect(MCPConnectionStatusText.activeLines(for: []).isEmpty)
    }

    @Test("Eine Sitzung ergibt eine Zeile mit Name und Werkzeug-Anzahl")
    func eineSitzungEineZeile() {
        let zeilen = MCPConnectionStatusText.activeLines(for: [sitzung(1, "Claude", 10)])

        #expect(zeilen.count == 1)
        #expect(zeilen[0].contains("Claude"))
        #expect(zeilen[0].contains("10"))
    }

    @Test("Zwei Sitzungen desselben Clients werden zu einer Zeile mit Anzahl")
    func gleicherClientWirdZusammengefasst() {
        // Beobachtet am 2026-08-16: Claude Desktop startet zwei Serverprozesse gleichzeitig.
        // Zwei identische Zeilen waeren nur verwirrend.
        let zeilen = MCPConnectionStatusText.activeLines(for: [
            sitzung(1, "Claude", 10),
            sitzung(2, "Claude", 10),
        ])

        #expect(zeilen.count == 1)
        #expect(zeilen[0].contains("2"))
    }

    @Test("Unterschiedliche Werkzeug-Anzahlen bleiben getrennte Zeilen")
    func unterschiedlicheWerkzeugzahlBleibtGetrennt() {
        // Genau dieser Unterschied ist die interessante Information: ein Prozess sitzt noch auf
        // einer veralteten Werkzeugliste.
        let zeilen = MCPConnectionStatusText.activeLines(for: [
            sitzung(1, "Claude", 7),
            sitzung(2, "Claude", 10),
        ])

        #expect(zeilen.count == 2)
    }

    @Test("Mehrere Clients ergeben mehrere Zeilen")
    func mehrereClientsMehrereZeilen() {
        let zeilen = MCPConnectionStatusText.activeLines(for: [
            sitzung(1, "Claude", 10),
            sitzung(2, "Cursor", 7),
        ])

        #expect(zeilen.count == 2)
        #expect(zeilen[0].contains("Claude"))
        #expect(zeilen[1].contains("Cursor"))
    }
```

- [ ] **Schritt 2: Test ausführen, Fehlschlag bestätigen**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/MCPConnectionStatusTextTests 2>&1 | grep -E "error:|Test run with" | head -5
```

Erwartet: Compile-Fehler „type 'MCPConnectionStatusText' has no member 'activeLines'".

- [ ] **Schritt 3: Implementieren**

In `Feedivo/Services/MCPConnectionStatusText.swift` ans Ende des `enum` ergänzen:

```swift
    /// Eine Zeile je Gruppe aktiver Sitzungen.
    ///
    /// Gruppiert wird nach Client-Name UND Werkzeug-Anzahl: Ein Client startet durchaus mehrere
    /// Serverprozesse gleichzeitig (am 2026-08-16 beobachtet), zwei identische Zeilen wären nur
    /// verwirrend. Unterscheiden sich die Werkzeug-Anzahlen dagegen, bleiben es getrennte Zeilen
    /// — dann sitzt einer der Prozesse noch auf einer veralteten Liste, und genau das ist die
    /// Information, die der Nutzer sehen soll.
    ///
    /// Die Reihenfolge stammt aus der Sortierung von `MCPServerSessionStore.activeSessions`.
    static func activeLines(for sessions: [MCPServerSession]) -> [String] {
        var reihenfolge: [String] = []
        var anzahlProGruppe: [String: Int] = [:]
        var beispielProGruppe: [String: MCPServerSession] = [:]

        for sitzung in sessions {
            let schluessel = "\(sitzung.clientName)\u{0}\(sitzung.toolCount)"
            if anzahlProGruppe[schluessel] == nil {
                reihenfolge.append(schluessel)
                beispielProGruppe[schluessel] = sitzung
            }
            anzahlProGruppe[schluessel, default: 0] += 1
        }

        return reihenfolge.compactMap { schluessel in
            guard let sitzung = beispielProGruppe[schluessel],
                  let anzahl = anzahlProGruppe[schluessel] else { return nil }

            if anzahl > 1 {
                return String(
                    format: String(localized: "settings.mcpServer.status.sessionGrouped"),
                    sitzung.clientName,
                    anzahl,
                    sitzung.toolCount
                )
            }
            return String(
                format: String(localized: "settings.mcpServer.status.session"),
                sitzung.clientName,
                sitzung.toolCount
            )
        }
    }
```

- [ ] **Schritt 4: L10n-Einträge ergänzen**

Drei Einträge per Text-Einfügung direkt nach dem Anker `  "strings" : {` in `Feedivo/Resources/Localizable.xcstrings`, im Format der Nachbarn (`"key" : { "localizations" : { "de" : { "stringUnit" : { "state" : "translated", "value" : "…" } }, … } }`), alle vier Sprachen:

| Schlüssel | de | en | fr | it |
|---|---|---|---|---|
| `settings.mcpServer.status.session` | `%1$@ — %2$d Werkzeuge` | `%1$@ — %2$d tools` | `%1$@ — %2$d outils` | `%1$@ — %2$d strumenti` |
| `settings.mcpServer.status.sessionGrouped` | `%1$@ (%2$d Verbindungen) — %3$d Werkzeuge` | `%1$@ (%2$d connections) — %3$d tools` | `%1$@ (%2$d connexions) — %3$d outils` | `%1$@ (%2$d connessioni) — %3$d strumenti` |
| `settings.mcpServer.status.notConnected` | `Nicht verbunden` | `Not connected` | `Non connecté` | `Non connesso` |

Danach verifizieren:

```bash
for k in session sessionGrouped notConnected; do echo -n "$k: "; grep -c "settings.mcpServer.status.$k\"" Feedivo/Resources/Localizable.xcstrings; done; git diff --stat Feedivo/Resources/Localizable.xcstrings
```

Erwartet: jeweils ≥ 1, und im Diff nahezu ausschließlich Insertions.

- [ ] **Schritt 5: Tests grün**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/MCPConnectionStatusTextTests 2>&1 | grep -E "Test run with|recorded an issue" | head -3
```

Erwartet: PASS (8 Tests — 3 bestehende plus 5 neue).

- [ ] **Schritt 6: Builds prüfen und committen**

```bash
xcodebuild build -scheme Feedivo -configuration Debug 2>&1 | tail -2 && xcodebuild build -scheme FeedivoMCPServer -configuration Debug 2>&1 | tail -2
```

```bash
git add Feedivo/Services/MCPConnectionStatusText.swift FeedivoTests/Services/MCPConnectionStatusTextTests.swift Feedivo/Resources/Localizable.xcstrings
git commit -m "feat(settings): Statuszeilen fuer aktive KI-Verbindungen"
```

---

### Task 5: Live-Anzeige im Tab

**Files:**
- Modify: `Feedivo/Views/Settings/SettingsView.swift` (`MCPServerSettingsView`)

**Interfaces:**
- Consumes: `MCPServerSessionStore.activeSessions(now:tolerance:)` (Task 1), `MCPConnectionStatusText.activeLines(for:)` (Task 4)
- Produces: nichts für spätere Tasks

- [ ] **Schritt 1: State und Aktualisierungsschleife ergänzen**

Zur bestehenden `@State`-Liste von `MCPServerSettingsView` hinzufügen (nach `detectedClient`):

```swift
    @State private var activeSessions: [MCPServerSession] = []
```

Direkt nach dem bestehenden `.task { await load() }` eine zweite `.task` anhängen:

```swift
        .task {
            // Haelt die Verbindungsanzeige aktuell, solange der Tab sichtbar ist. SwiftUI bricht
            // diese Schleife ab, sobald die Ansicht verschwindet — bei geschlossenen
            // Einstellungen laeuft nichts.
            while !Task.isCancelled {
                reloadActiveSessions()
                try? await Task.sleep(for: .seconds(5))
            }
        }
```

- [ ] **Schritt 2: Ladefunktion ergänzen**

Neben `load()` einfügen:

```swift
    private func reloadActiveSessions() {
        guard let feedivoDatabase else { return }
        // Fail-safe: Bei einem Lesefehler bleibt die Liste leer, die Anzeige sagt also
        // "Nicht verbunden" — sie behauptet im Zweifel nie eine Verbindung.
        activeSessions = (try? MCPServerSessionStore(database: feedivoDatabase)
            .activeSessions(now: Date())) ?? []
    }
```

- [ ] **Schritt 3: Statusbereich umbauen**

Den bestehenden Block

```swift
                GeneralSettingsRow(title: L10n.settingsMCPServerStatusRowTitle) {
                    Text(verbatim: MCPConnectionStatusText.text(
                        for: lastConnection,
                        isWriteAccessEnabled: isWriteAccessEnabled
                    ))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
```

ersetzen durch:

```swift
                GeneralSettingsRow(title: L10n.settingsMCPServerStatusRowTitle) {
                    VStack(alignment: .leading, spacing: 4) {
                        let zeilen = MCPConnectionStatusText.activeLines(for: activeSessions)
                        if zeilen.isEmpty {
                            connectionStatusLine(
                                text: String(localized: "settings.mcpServer.status.notConnected"),
                                isConnected: false
                            )
                            // Bei bestehender Verbindung waere dieser Text redundant — er
                            // beantwortet "wann zuletzt", nicht "wer jetzt".
                            Text(verbatim: MCPConnectionStatusText.text(
                                for: lastConnection,
                                isWriteAccessEnabled: isWriteAccessEnabled
                            ))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        } else {
                            ForEach(zeilen, id: \.self) { zeile in
                                connectionStatusLine(text: zeile, isConnected: true)
                            }
                        }
                    }
                }
```

Und als neue Hilfsfunktion im selben `struct` (neben `reloadActiveSessions()`):

```swift
    @ViewBuilder
    private func connectionStatusLine(text: String, isConnected: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isConnected ? Color.green : Color.secondary.opacity(0.5))
                .frame(width: 8, height: 8)
            Text(verbatim: text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
```

- [ ] **Schritt 4: Build prüfen**

```bash
xcodebuild build -scheme Feedivo -configuration Debug 2>&1 | grep -E "error:|BUILD" | tail -3
```

Erwartet: `** BUILD SUCCEEDED **`.

Meldet der Compiler in `body` einen Typprüfungs-Timeout („unable to type-check this expression in reasonable time"), den Statusbereich in eine eigene private `@ViewBuilder`-Property `connectionStatusSection` auslagern und im `body` nur diese aufrufen — dasselbe Muster, das `SparkleUpdatePresentationModifier` in diesem Projekt bereits nutzt.

- [ ] **Schritt 5: Source-Sniffing-Tests gegenprüfen**

```bash
grep -n "mcpServer\|MCPServer" FeedivoTests/App/FeedivoAppSceneConfigurationTests.swift
```

Trifft eine Assertion einen geänderten Ausdruck, auf den neuen Wortlaut anpassen — **nicht** die View-Struktur zurückbauen. Diese Suite hat ~25 vorbestehende, nicht zu diesem Task gehörende Fehlschläge; vor der Änderung Baseline notieren.

- [ ] **Schritt 6: Committen**

```bash
git add Feedivo/Views/Settings/SettingsView.swift
git commit -m "feat(settings): Live-Anzeige verbundener KI-Clients im Tab"
```

---

### Task 6: Abschluss

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Schritt 1: Regressionslauf**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/MCPServerSessionStoreTests -only-testing:FeedivoTests/MCPClientNameResolverTests -only-testing:FeedivoTests/MCPConnectionStatusTextTests -only-testing:FeedivoTests/MCPServerSettingsStoreTests -only-testing:FeedivoTests/MCPClientDetectorTests -only-testing:FeedivoTests/FeedivoDatabaseMigratorTests 2>&1 | grep -E "Test run with|recorded an issue" | head -3
```

Erwartet: alle grün.

- [ ] **Schritt 2: Release-Builds**

```bash
xcodebuild build -scheme Feedivo -configuration Release 2>&1 | tail -2 && xcodebuild build -scheme FeedivoMCPServer -configuration Release 2>&1 | tail -2
```

- [ ] **Schritt 3: Migrations-Tabelle in `CLAUDE.md`**

```markdown
| v36_create_mcp_server_sessions | Tabelle `mcp_server_sessions` (eine Zeile je laufendem `FeedivoMCPServer`-Prozess: `pid`, `clientName`, `startedAt`, `toolCount`, `lastHeartbeatAt`) — Grundlage der Live-Verbindungsanzeige im Tab „KI-Zugriff"; der Server schreibt alle 15 s ein Lebenszeichen, die App wertet Sitzungen jünger als 40 s als verbunden |
```

- [ ] **Schritt 4: Eintrag unter „Aktuell in Arbeit"**

Inhalt: Anlass (der Tab zeigte nur „zuletzt verbunden", nicht ob gerade eine Verbindung besteht; beim Testen liefen unbemerkt zwei Serverprozesse), das Heartbeat-Verfahren samt Begründung gegen Prozessabfrage (App Sandbox) und gegen Ping/Pong über Darwin-Notifications (bräuchte eine `CFRunLoop` im Server), die pfadbasierte Namensableitung inklusive der Folge, dass „Claude" statt „Claude Desktop" erscheint, die Gruppierung nach Name und Werkzeug-Anzahl, sowie die bewusst hingenommene Verzögerung von ~40 Sekunden beim Trennen. Ausdrücklich festhalten, dass der Einrichtungsassistent für weitere Clients (Dropdown, Anleitung oder Eintragen per Dateiauswahl) ein abgetrenntes Folgevorhaben ist.

Ausstehende manuelle Verifikation:

1. Tab öffnen, während Claude Desktop läuft → grüner Punkt, „Claude — 10 Werkzeuge".
2. Claude Desktop beenden, Tab offen lassen → Anzeige springt binnen ~40 s auf „Nicht verbunden", darunter erscheint der Zeitpunkt der letzten Verbindung.
3. Claude Desktop starten, Tab weiterhin offen → Anzeige springt binnen ~20 s zurück auf verbunden, ohne dass das Fenster geschlossen werden muss.
4. Laufen mehrere Prozesse desselben Clients, erscheint eine Zeile mit Anzahl statt mehrerer identischer Zeilen.

- [ ] **Schritt 5: Committen**

```bash
git add CLAUDE.md
git commit -m "docs: Live-Verbindungsstatus in CLAUDE.md dokumentiert"
```

- [ ] **Schritt 6: Push-Entscheidung vorlegen**

Laut Projektkonvention **nie ohne ausdrückliche Bestätigung** pushen. Dem Nutzer die Commit-Anzahl und die vier offenen Verifikationspunkte melden.

---

## Self-Review

**Spec-Abdeckung:** Migration v36 mit Sitzungstabelle → Task 1 ✔; `INSERT OR REPLACE` wegen PID-Wiederverwendung → Task 1, Schritt 7 ✔; Aufräumen alter Zeilen beim Serverstart → Task 1 (Methode) und Task 3 (Aufruf) ✔; Client-Erkennung über Elternprozess mit äußerem Bundle, Dateiname-Fallback und Platzhalter → Task 2 ✔; nur der Name wird gespeichert, nie der Pfad → Task 1 (kein Pfadfeld) und Task 2 (Doc-Kommentar) ✔; Heartbeat alle 15 s über gehaltene Verbindung → Task 3 ✔; Toleranz 40 s → Task 1 (`heartbeatTolerance`) ✔; Gruppierung nach Name und Werkzeug-Anzahl mit Anzahl-Anzeige → Task 4 ✔; grüner/grauer Punkt, „Zuletzt verbunden" nur ohne aktive Sitzung → Task 5 ✔; Aktualisierung alle 5 s nur bei sichtbarem Tab → Task 5 ✔; Fehler serverseitig verschlucken, App-seitig fail-safe → Task 3 und Task 5 ✔; kein Task berührt die Out-of-Scope-Punkte (Einrichtungsassistent, Werkzeuglisten-Warnung, Verbindungsdauer) ✔.

**Platzhalter-Scan:** Keine „TBD"/„später"-Verweise; alle Codeblöcke vollständig; alle UI-Texte im Wortlaut angegeben; für beide vorhersehbaren Compilerprobleme (libproc-Import, Typprüfungs-Timeout) steht die konkrete Ausweichlösung im jeweiligen Schritt.

**Typ-Konsistenz:** `MCPServerSession` (Task 1) wird in Task 3, 4 und 5 mit denselben Feldnamen (`pid`, `clientName`, `startedAt`, `toolCount`, `lastHeartbeatAt`) verwendet. `MCPServerSessionStore.activeSessions(now:tolerance:)` wird in Task 5 ohne `tolerance` aufgerufen — der Standardwert `heartbeatTolerance` deckt das ab. `MCPClientNameResolver.clientName(forExecutablePath:)` (Task 2) passt zur Nutzung in Task 3. `MCPConnectionStatusText.activeLines(for:)` (Task 4) passt zur Nutzung in Task 5. Migrationsname `"v36_create_mcp_server_sessions"` ist in Task 1 und Task 6 identisch.

**Bekannte Einschränkung:** Der Platzhaltername `Unbekannt` in `MCPClientNameResolver` ist nicht lokalisiert — er wird vom Serverprozess in die Datenbank geschrieben, der keine Lokalisierung des App-Bundles zur Verfügung hat. Er erscheint nur, wenn die Ermittlung des Elternprozesses fehlschlägt.
