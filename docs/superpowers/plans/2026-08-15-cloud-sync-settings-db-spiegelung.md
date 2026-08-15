# iCloud-Sync-Aktiv-Flag über die Datenbank spiegeln — Implementierungsplan

> **Für agentische Worker:** REQUIRED SUB-SKILL: Nutze superpowers:subagent-driven-development (empfohlen) oder superpowers:executing-plans, um diesen Plan Task für Task umzusetzen. Schritte nutzen Checkbox-Syntax (`- [ ]`) zur Fortschrittsverfolgung.

**Goal:** Die 8 Store-seitigen „ist iCloud Sync aktiv?"-Gates lesen das Flag aus der SQLite-Datenbank statt aus `UserDefaults.standard`, damit auch Schreibvorgänge aus dem unsandboxed `FeedivoMCPServer`-Prozess korrekt in die Sync-Warteschlange eingereiht werden.

**Architecture:** Neue Single-Row-Tabelle `cloud_sync_settings` (Migration v33, Standard `0`) plus `CloudSyncSettingsStore`. `UserDefaults` (`CloudSyncSettings.isEnabledKey`) bleibt die **Quelle der Wahrheit** für den Nutzer-Schalter; die DB-Zeile ist ein **Spiegel**, der bei jedem App-Start und bei jedem Umlegen des Schalters abgeglichen wird (selbstheilend). Die Gates lesen über die **bereits offene Transaktions-Verbindung** (`db: Database`), nicht über eine neue.

**Tech Stack:** Swift 6, SwiftUI (macOS 14+), GRDB/SQLite, Swift Testing (kein XCTest).

## Global Constraints

- Code-Kommentare auf **Deutsch**, Testnamen auf Deutsch (Projektkonvention).
- Neue Migrationen werden **immer als neuer Block angehängt**, bestehende nie nachträglich geändert. Letzte existierende Migration ist `v32_add_mcp_server_write_access` (verifiziert per `grep -n registerMigration Feedivo/Database/FeedivoDatabaseMigrator.swift`) — die neue heißt `v33_create_cloud_sync_settings`.
- **`CloudSyncSettings` (das Enum) bleibt komplett unverändert.** Es bleibt zuständig für die `@AppStorage`-Bindung, `statusLocalizationKey`, `pendingFirstActivationKey` und `shouldAutoStartSyncEngineAtLaunch`.
- **Nicht anfassen:** `FeedivoApp.swift:107` (`CloudSyncSettings.isEnabled()` im `shouldAutoStartSyncEngineAtLaunch`-Aufruf) und `CloudSyncEngine.swift:179` (`CloudSyncSettings.isEnabled(in: userDefaults)`) — beide laufen ausschließlich im App-Prozess, `UserDefaults` ist dort korrekt und die Quelle der Wahrheit.
- **Nie `database.read`/`database.write` von innerhalb eines bestehenden `db: Database`-Blocks aufrufen.** GRDB erzwingt das mit `GRDBPrecondition(currentReader == nil, "Database methods are not reentrant.")` (`DatabasePool.swift:340`, dokumentiert für `DatabaseQueue.swift:445`) — es crasht zur Laufzeit, in Tests (`inMemoryForTests()` = `DatabaseQueue`) garantiert bei jedem Aufruf.
- Tests immer gezielt ausführen (`-only-testing:FeedivoTests/<SuiteName>`) und mit `-parallel-testing-enabled NO`. Ein unscoped `xcodebuild test` deadlockt in diesem Projekt reproduzierbar.
- Nach jedem Task: `xcodebuild build -scheme Feedivo -configuration Debug` **und** `xcodebuild build -scheme FeedivoMCPServer -configuration Debug` müssen beide grün sein.
- Bekannte, **vorbestehende** Testfehlschläge (nicht als Regression behandeln, aber auch nicht neu einführen): ~25 Tests in `FeedivoAppSceneConfigurationTests.swift`, sowie flaky-unter-Last Tests in `SQLiteFeedArticleListStateTests.swift` und `FeedViewModelTests.swift`.

## Abweichungen von der Design-Spec (bewusst, mit Begründung)

Die Spec (`docs/superpowers/specs/2026-08/2026-08-15-cloud-sync-settings-db-spiegelung-design.md`) wird an drei Punkten korrigiert:

1. **Gate-Aufruf:** Spec schlug `CloudSyncSettingsStore(database: self.database).isEnabled()` vor und nannte die Umstellung „rein mechanisch". Das ist falsch — alle 8 Gates laufen innerhalb einer offenen `database.write`-Transaktion mit `db: Database` als Parameter. Der Spec-Vorschlag würde GRDBs Reentranz-Precondition verletzen und garantiert crashen. **Stattdessen:** `CloudSyncSettingsStore.isEnabled(in: db)` — eine statische Funktion auf der bereits vorhandenen Verbindung. Nebeneffekt: atomar konsistent mit der Mutation, keine zusätzliche Connection.
2. **Backfill-Ort (Nutzerentscheidung 2026-08-15):** Spec wollte den `UserDefaults`-Wert direkt in Migration v33 backfillen. **Stattdessen:** Migration legt die Zeile hart mit `0` an; der Abgleich passiert bei jedem App-Start in `FeedivoApp.init()`. Gründe: (a) die Database-Schicht bleibt frei von `UserDefaults`-Wissen, (b) `inMemoryForTests()` führt den Migrator aus — ein Backfill dort würde in **jedem** Test den globalen `UserDefaults.standard` des Testprozesses lesen und das bereits dokumentierte UserDefaults-Race bei paralleler Testausführung verstärken. Mit dieser Variante liefert eine frische Test-DB deterministisch `false`.
3. **Umfang der Testdatei-Umstellung:** Spec nannte „17 Testdateien". Tatsächlich gezählt (`grep -c "set(true, forKey: CloudSyncSettings.isEnabledKey)"`): **15 Dateien** mit aktivierenden Stellen. Die weiteren in der Spec genannten Kandidaten sind unbetroffen und werden **nicht** angefasst (verifiziert):
   - `FeedivoAppSceneConfigurationTests.swift` — nur ein Source-Sniffing-String `"@AppStorage(CloudSyncSettings.isEnabledKey)"`.
   - `CloudSyncEngineResetTests.swift` — nur `set(false, ...)` auf einer eigenen `UserDefaults`-Instanz, testet `CloudSyncEngine`, nicht ein Store-Gate.
   - `ArticleListDisplaySettingsTests.swift`, `SpotlightIndexing*Tests.swift`, `BackgroundRefreshServiceTests.swift` — referenzieren `isEnabledKey` **anderer** Settings-Typen (`NativeArticleListSettings`, `SpotlightIndexingSettings`, `ArticleRetentionSettings`).
   - `CloudSyncSettingsTests.swift` — testet `CloudSyncSettings` selbst (bleibt unverändert). In Task 3 einmal explizit gegenprüfen, nicht blind ändern.

---

### Task 1: Migration v33 + `CloudSyncSettingsStore`

**Files:**
- Modify: `Feedivo/Database/FeedivoDatabaseMigrator.swift` (neuer Migrationsblock direkt nach `v32_add_mcp_server_write_access`, aktuell Zeile 591–600, vor dem `return migrator`)
- Create: `Feedivo/Stores/CloudSyncSettingsStore.swift`
- Modify: `Feedivo.xcodeproj/project.pbxproj` (Target-Membership für `FeedivoMCPServer`)
- Test: `FeedivoTests/Database/FeedivoDatabaseMigratorTests.swift` (neue Tests am Ende der Suite)
- Test: `FeedivoTests/Stores/CloudSyncSettingsStoreTests.swift` (neu)

**Interfaces:**
- Consumes: `FeedivoDatabase` (`read`/`write`), `FeedivoDatabaseMigrator.migrator`
- Produces:
  - `struct CloudSyncSettingsStore { init(database: FeedivoDatabase) }`
  - `static func isEnabled(in db: Database) -> Bool` — **nicht** werfend, fail-closed. Das ist die Funktion, die Tasks 3–6 in den Gates verwenden.
  - `func isEnabled() throws -> Bool`
  - `func setEnabled(_ isEnabled: Bool) throws`
  - `func mirrorFromUserDefaults(_ defaults: UserDefaults = .standard) throws`
  - Migration `"v33_create_cloud_sync_settings"` — Tasks, die `migrate(queue, upTo:)` nutzen, verweisen ab jetzt auf `"v32_add_mcp_server_write_access"` als Vorgänger.

- [ ] **Schritt 1: Failing Test für die Migration schreiben**

Ans Ende von `FeedivoTests/Database/FeedivoDatabaseMigratorTests.swift` einfügen (vor der schließenden `}` der Suite, nach `migrationV32FuegtWriteAccessIsEnabledSpalteHinzu`):

```swift
    @Test func migrationV33LegtCloudSyncSettingsMitDeaktiviertemStandardwertAn() throws {
        let queue = try DatabaseQueue()
        try FeedivoDatabaseMigrator.migrator.migrate(queue, upTo: "v32_add_mcp_server_write_access")

        try FeedivoDatabaseMigrator.migrator.migrate(queue)

        let isEnabled = try queue.read { db in
            try Bool.fetchOne(db, sql: "SELECT isEnabled FROM cloud_sync_settings WHERE id = 1")
        }
        #expect(isEnabled == false)

        let rowCount = try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM cloud_sync_settings")
        }
        #expect(rowCount == 1)
    }

    @Test func migrationV33IgnoriertUserDefaultsUndBleibtDeterministisch() throws {
        // Bewusste Abweichung von der urspruenglichen Design-Spec: der Backfill des
        // bestehenden UserDefaults-Werts passiert NICHT hier, sondern beim App-Start
        // (siehe CloudSyncSettingsStore.mirrorFromUserDefaults / FeedivoApp.init).
        // Dadurch liefert eine frische Test-Datenbank IMMER false, unabhaengig davon,
        // was ein anderer, parallel laufender Test gerade in UserDefaults.standard
        // hinterlassen hat.
        UserDefaults.standard.set(true, forKey: CloudSyncSettings.isEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey) }

        let queue = try DatabaseQueue()
        try FeedivoDatabaseMigrator.migrator.migrate(queue)

        let isEnabled = try queue.read { db in
            try Bool.fetchOne(db, sql: "SELECT isEnabled FROM cloud_sync_settings WHERE id = 1")
        }
        #expect(isEnabled == false)
    }
```

- [ ] **Schritt 2: Test ausführen, Fehlschlag bestätigen**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/FeedivoDatabaseMigratorTests 2>&1 | tail -30
```

Erwartet: FAIL — „no such table: cloud_sync_settings".

Falls stattdessen ein verdächtig unverändertes „TEST SUCCEEDED" mit alter Testanzahl kommt: `xcodebuild clean` + `build-for-testing` gegenprüfen (bekannter Stale-Bundle-Gotcha in diesem Projekt).

- [ ] **Schritt 3: Migration v33 implementieren**

In `Feedivo/Database/FeedivoDatabaseMigrator.swift` direkt nach dem `v32_add_mcp_server_write_access`-Block (endet aktuell Zeile 600) und **vor** `return migrator` einfügen:

```swift
        migrator.registerMigration("v33_create_cloud_sync_settings") { database in
            // Spiegel des iCloud-Sync-Aktiv-Flags fuer Cross-Process-Zugriff. Quelle der
            // Wahrheit bleibt UserDefaults (CloudSyncSettings.isEnabledKey, an den UI-Schalter
            // gebunden) — diese Zeile wird bei jedem App-Start und bei jedem Umlegen des
            // Schalters abgeglichen (CloudSyncSettingsStore.mirrorFromUserDefaults).
            //
            // Grund: FeedivoMCPServer ist bewusst unsandboxed (ADR-011), sein
            // UserDefaults.standard zeigt auf eine andere Preferences-Domaene als die der
            // sandboxed App. Die Store-Gates (TagStore/ArticleStatusStore/... enqueuePendingSync)
            // lasen deshalb dort immer `false` und haben MCP-Schreibvorgaenge nie in die
            // Sync-Warteschlange eingereiht — waehrend statusSyncUpdatedAt trotzdem gesetzt
            // wurde, was zusaetzlich eingehende Remote-Aenderungen per Last-Write-Wins
            // dauerhaft unterdrueckt haette.
            //
            // Standard bewusst hart 0 statt eines UserDefaults-Backfills: haelt die
            // Database-Schicht frei von UserDefaults-Wissen und macht `inMemoryForTests()`
            // deterministisch (der Migrator laeuft dort in jedem Test).
            try database.create(table: "cloud_sync_settings") { table in
                table.column("id", .integer).primaryKey()
                table.column("isEnabled", .boolean).notNull().defaults(to: false)
            }
            try database.execute(sql: "INSERT INTO cloud_sync_settings (id, isEnabled) VALUES (1, 0)")
        }
```

- [ ] **Schritt 4: Migrations-Tests ausführen, GREEN bestätigen**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/FeedivoDatabaseMigratorTests 2>&1 | tail -20
```

Erwartet: PASS, Testanzahl um 2 höher als vorher.

- [ ] **Schritt 5: Failing Test für den Store schreiben**

Neue Datei `FeedivoTests/Stores/CloudSyncSettingsStoreTests.swift`:

```swift
import Testing
import GRDB
@testable import Feedivo

@Suite("CloudSyncSettingsStore")
struct CloudSyncSettingsStoreTests {
    @Test("Standardwert nach Migration ist deaktiviert")
    func standardwertIstDeaktiviert() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = CloudSyncSettingsStore(database: database)

        #expect(try store.isEnabled() == false)
    }

    @Test("setEnabled persistiert den neuen Wert")
    func setEnabledPersistiertWert() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = CloudSyncSettingsStore(database: database)

        try store.setEnabled(true)
        #expect(try store.isEnabled() == true)

        try store.setEnabled(false)
        #expect(try store.isEnabled() == false)
    }

    @Test("isEnabled(in:) liest ueber eine bereits offene Transaktions-Verbindung")
    func isEnabledInTransaktionLiestAktuellenWert() throws {
        // Genau der Aufrufweg, den die Store-Gates (enqueuePendingSync) nutzen: sie stehen
        // bereits INNERHALB eines database.write-Blocks. Ein dortiger database.read-Aufruf
        // wuerde GRDBs Reentranz-Precondition verletzen ("Database methods are not
        // reentrant.") — dieser Test sichert ab, dass der Lesepfad ueber `db` laeuft.
        let database = try FeedivoDatabase.inMemoryForTests()
        try CloudSyncSettingsStore(database: database).setEnabled(true)

        let gelesen = try database.write { db in
            CloudSyncSettingsStore.isEnabled(in: db)
        }
        #expect(gelesen == true)
    }

    @Test("Fehlende Tabelle wird fail-closed als false behandelt")
    func fehlendeTabelleWirdFailClosedAlsFalseBehandelt() throws {
        // Simuliert eine Datenbank, die nur bis vor Migration v33 migriert wurde. Ein Gate,
        // das im Zweifel NICHT synct, ist sicherer als eines, das im Zweifel synct: der Wert
        // wird dann hoechstens verzoegert gepusht, es geht nichts verloren.
        let queue = try DatabaseQueue()
        try FeedivoDatabaseMigrator.migrator.migrate(queue, upTo: "v32_add_mcp_server_write_access")
        let database = FeedivoDatabase(writer: queue)

        let ueberTransaktion = try database.write { db in
            CloudSyncSettingsStore.isEnabled(in: db)
        }
        #expect(ueberTransaktion == false)

        let ueberInstanz = (try? CloudSyncSettingsStore(database: database).isEnabled()) ?? false
        #expect(ueberInstanz == false)
    }

    @Test("mirrorFromUserDefaults uebernimmt einen bestehenden UserDefaults-Wert")
    func mirrorUebernimmtBestehendenWert() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = CloudSyncSettingsStore(database: database)
        let suiteName = "CloudSyncSettingsStoreTests.mirror"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.removePersistentDomain(forName: suiteName)

        defaults.set(true, forKey: CloudSyncSettings.isEnabledKey)
        try store.mirrorFromUserDefaults(defaults)
        #expect(try store.isEnabled() == true)

        defaults.set(false, forKey: CloudSyncSettings.isEnabledKey)
        try store.mirrorFromUserDefaults(defaults)
        #expect(try store.isEnabled() == false)
    }

    @Test("mirrorFromUserDefaults faellt ohne gesetzten Schluessel auf den Standard zurueck")
    func mirrorNutztStandardOhneGesetztenSchluessel() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = CloudSyncSettingsStore(database: database)
        try store.setEnabled(true)

        let suiteName = "CloudSyncSettingsStoreTests.mirrorLeer"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.removePersistentDomain(forName: suiteName)

        try store.mirrorFromUserDefaults(defaults)
        #expect(try store.isEnabled() == CloudSyncSettings.defaultIsEnabled)
    }
}
```

- [ ] **Schritt 6: Store-Test ausführen, Fehlschlag bestätigen**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/CloudSyncSettingsStoreTests 2>&1 | tail -30
```

Erwartet: Compile-Fehler „cannot find 'CloudSyncSettingsStore' in scope".

- [ ] **Schritt 7: `CloudSyncSettingsStore` implementieren**

Neue Datei `Feedivo/Stores/CloudSyncSettingsStore.swift`:

```swift
import Foundation
import GRDB

/// Datenbank-Spiegel des iCloud-Sync-Aktiv-Flags.
///
/// **Quelle der Wahrheit bleibt UserDefaults** (`CloudSyncSettings.isEnabledKey`, direkt an den
/// `@AppStorage`-Schalter in `SyncSettingsView` gebunden). Diese Tabelle ist ein reiner Spiegel,
/// der bei jedem App-Start (`FeedivoApp.init`) und bei jedem Umlegen des Schalters
/// (`SyncSettingsView.onChange`) abgeglichen wird — dadurch selbstheilend, falls beide je
/// auseinanderlaufen.
///
/// **Warum ueberhaupt gespiegelt:** `FeedivoMCPServer` laeuft bewusst unsandboxed (ADR-011),
/// sein `UserDefaults.standard` zeigt auf eine andere Preferences-Domaene als die der sandboxed
/// Feedivo-App. `CloudSyncSettings.isEnabled()` liefert dort praktisch immer `false` — die
/// Store-Gates (`enqueuePendingSync`) haetten MCP-Schreibvorgaenge deshalb nie in die
/// Sync-Warteschlange eingereiht, waehrend `statusSyncUpdatedAt` trotzdem gesetzt wurde
/// (Last-Write-Wins haette eingehende Remote-Aenderungen dauerhaft unterdrueckt).
struct CloudSyncSettingsStore {
    private let database: FeedivoDatabase

    init(database: FeedivoDatabase) {
        self.database = database
    }

    /// Liest das Flag ueber eine **bereits offene** Transaktions-Verbindung.
    ///
    /// Das ist die Variante, die alle `enqueuePendingSync`-Gates verwenden: sie laufen bereits
    /// innerhalb eines `database.write`-Blocks. Ein `database.read`/`database.write` von dort
    /// aus verletzt GRDBs Reentranz-Precondition ("Database methods are not reentrant.",
    /// `DatabasePool.swift`/`DatabaseQueue.swift`) und crasht zur Laufzeit. Nebeneffekt des
    /// Lesens ueber `db`: das Gate sieht garantiert denselben Datenbankzustand wie die
    /// Mutation, die es begleitet.
    ///
    /// Fail-closed: jeder Fehler (fehlende Tabelle, Lesefehler) liefert `false`. Nicht zu
    /// synchronisieren ist sicherer als faelschlich zu synchronisieren — es geht nichts
    /// verloren, der Push passiert beim naechsten erfolgreichen Lesen.
    static func isEnabled(in db: Database) -> Bool {
        do {
            return try Bool.fetchOne(db, sql: "SELECT isEnabled FROM cloud_sync_settings WHERE id = 1") ?? false
        } catch {
            return false
        }
    }

    func isEnabled() throws -> Bool {
        try database.read { db in
            try Bool.fetchOne(db, sql: "SELECT isEnabled FROM cloud_sync_settings WHERE id = 1") ?? false
        }
    }

    func setEnabled(_ isEnabled: Bool) throws {
        try database.write { db in
            try db.execute(sql: "UPDATE cloud_sync_settings SET isEnabled = ? WHERE id = 1", arguments: [isEnabled])
        }
    }

    /// Gleicht den Spiegel gegen die Quelle der Wahrheit ab. Wird bei jedem App-Start und bei
    /// jedem Umlegen des Schalters aufgerufen — bewusst unbedingt (nicht einmalig gated), damit
    /// ein einmal auseinandergelaufener Zustand sich beim naechsten Start von selbst repariert.
    func mirrorFromUserDefaults(_ defaults: UserDefaults = .standard) throws {
        try setEnabled(CloudSyncSettings.isEnabled(in: defaults))
    }
}
```

- [ ] **Schritt 8: Target-Membership für `FeedivoMCPServer` ergänzen**

`Feedivo/Stores/CloudSyncSettingsStore.swift` wird ab Task 3 von `TagStore.swift` (bereits im MCP-Target) referenziert — ohne diesen Schritt bricht der `FeedivoMCPServer`-Build.

In `Feedivo.xcodeproj/project.pbxproj` im `membershipExceptions`-Array ab Zeile 106 (das mit `target = ... FeedivoMCPServer`) **eine einzige Zeile** alphabetisch korrekt zwischen `Stores/CloudSyncPendingChangeStore.swift,` und `Stores/FeedFolderStore.swift,` einfügen:

```
				Stores/CloudSyncSettingsStore.swift,
```

Einrückung ist **Tab-basiert** (4 Tabs), exakt wie die Nachbarzeilen. Vorbild für genau diesen Edit: Commit `707297a` (`Services/MCPWriteNotificationName.swift`).

Verifikation:

```bash
grep -n "Stores/CloudSyncPendingChangeStore.swift" -A 2 Feedivo.xcodeproj/project.pbxproj
```

Erwartet: `CloudSyncSettingsStore.swift` steht direkt darunter, `FeedFolderStore.swift` darunter.

- [ ] **Schritt 9: Tests ausführen, GREEN bestätigen**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/CloudSyncSettingsStoreTests -only-testing:FeedivoTests/FeedivoDatabaseMigratorTests 2>&1 | tail -20
```

Erwartet: PASS (6 neue Store-Tests + die Migrator-Suite).

- [ ] **Schritt 10: Beide Builds prüfen**

```bash
xcodebuild build -scheme Feedivo -configuration Debug 2>&1 | tail -5
```

```bash
xcodebuild build -scheme FeedivoMCPServer -configuration Debug 2>&1 | tail -5
```

Erwartet: beide `** BUILD SUCCEEDED **`.

- [ ] **Schritt 11: Commit**

```bash
git add Feedivo/Database/FeedivoDatabaseMigrator.swift Feedivo/Stores/CloudSyncSettingsStore.swift Feedivo.xcodeproj/project.pbxproj FeedivoTests/Database/FeedivoDatabaseMigratorTests.swift FeedivoTests/Stores/CloudSyncSettingsStoreTests.swift
git commit -m "feat(sync): Migration v33 + CloudSyncSettingsStore als DB-Spiegel des Sync-Flags"
```

---

### Task 2: Spiegelung verdrahten (App-Start + Schalter)

**Warum vor Tasks 3–6:** Ab Task 3 lesen die Gates die DB. Ohne diesen Task würde die Zeile nie geschrieben — iCloud Sync wäre zwischen den Commits funktional tot. Dieser Task muss deshalb zwingend vorher landen.

**Files:**
- Modify: `Feedivo/App/FeedivoApp.swift` (im `init`, innerhalb des `if databaseOpenResult.errorDescription == nil`-Blocks, aktuell Zeile 92–95)
- Modify: `Feedivo/Views/Settings/SettingsView.swift` (`.onChange(of: cloudSyncIsEnabled)`, aktuell ab Zeile 1286)
- Test: `FeedivoTests/App/FeedivoAppSceneConfigurationTests.swift` (Source-Sniffing, Projekt-Muster)

**Interfaces:**
- Consumes: `CloudSyncSettingsStore.mirrorFromUserDefaults(_:)` und `.setEnabled(_:)` aus Task 1, `logIfThrows(context:_:)` aus `Feedivo/Extensions/SilentErrorLogging.swift`
- Produces: nichts, was spätere Tasks aufrufen — stellt nur sicher, dass `cloud_sync_settings.isEnabled` zur Laufzeit korrekt gefüllt ist.

- [ ] **Schritt 1: Failing Source-Sniffing-Tests schreiben**

Ans Ende der Suite in `FeedivoTests/App/FeedivoAppSceneConfigurationTests.swift` einfügen. Die Datei lädt Quelltexte bereits für vergleichbare Tests (z. B. Zeile 489: `settingsSource.contains("@AppStorage(CloudSyncSettings.isEnabledKey)")`). **Vor dem Schreiben** nachsehen, wie `settingsSource` dort beschafft wird (Hilfsfunktion vs. inline `String(contentsOf:)`) und exakt dasselbe Muster übernehmen — nur den `contains`-Ausdruck ersetzen. Analog für die `FeedivoApp.swift`-Quelle; existiert dafür noch kein Lader, den vorhandenen nach demselben Vorbild um einen Eintrag für `Feedivo/App/FeedivoApp.swift` erweitern.

```swift
    @Test func appInitSpiegeltCloudSyncFlagInDieDatenbank() throws {
        // Ohne diesen Aufruf bliebe cloud_sync_settings bei einem Bestandsnutzer, der iCloud
        // Sync laengst aktiviert hat, nach dem Update auf 0 stehen — alle Store-Gates wuerden
        // stillschweigend aufhoeren zu synchronisieren.
        let source = try appSource()
        #expect(source.contains("mirrorFromUserDefaults()"))
    }

    @Test func syncSettingsSpiegeltSchalterAenderungInDieDatenbank() throws {
        let source = try settingsSource()
        #expect(source.contains("CloudSyncSettingsStore(database: feedivoDatabase).setEnabled(cloudSyncIsEnabled)"))
    }
```

- [ ] **Schritt 2: Test ausführen, Fehlschlag bestätigen**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/FeedivoAppSceneConfigurationTests 2>&1 | grep -E "appInitSpiegelt|syncSettingsSpiegelt|Test Suite|failed" | tail -20
```

Erwartet: genau die beiden neuen Tests schlagen fehl. Die ~25 vorbestehenden Fehlschläge dieser Suite sind erwartet und **kein** Grund zum Nachbessern — vorher einmal die Baseline notieren (Anzahl + Namen), um sie danach vergleichen zu können.

- [ ] **Schritt 3: App-Start-Spiegelung implementieren**

In `Feedivo/App/FeedivoApp.swift` den bestehenden Block

```swift
        if databaseOpenResult.errorDescription == nil {
            self.appDelegate.configureMenubarController(feedivoDatabase: database, feedViewModel: feedViewModel)
            self.localExtensionBridgeServer.start()
        }
```

ersetzen durch:

```swift
        if databaseOpenResult.errorDescription == nil {
            // Spiegelt das iCloud-Sync-Flag aus UserDefaults (Quelle der Wahrheit, an den
            // UI-Schalter gebunden) in die Datenbank — von dort lesen es die Store-Gates,
            // damit auch der unsandboxed FeedivoMCPServer-Prozess den korrekten Wert sieht
            // (siehe CloudSyncSettingsStore). Bewusst VOR localExtensionBridgeServer.start():
            // der Bridge-Server kann Feeds anlegen und damit Store-Mutationen ausloesen, die
            // das Flag bereits lesen.
            logIfThrows(context: "CloudSync-Flag in Datenbank spiegeln") {
                try CloudSyncSettingsStore(database: database).mirrorFromUserDefaults()
            }
            self.appDelegate.configureMenubarController(feedivoDatabase: database, feedViewModel: feedViewModel)
            self.localExtensionBridgeServer.start()
        }
```

- [ ] **Schritt 4: Schalter-Spiegelung implementieren**

In `Feedivo/Views/Settings/SettingsView.swift` im `.onChange(of: cloudSyncIsEnabled)`-Handler (beginnt aktuell Zeile 1286) **als allererste Anweisung** im Closure, vor dem bestehenden `if cloudSyncIsEnabled {`, einfügen:

```swift
            // Spiegelt den Schalter sofort in die Datenbank — von dort lesen die Store-Gates
            // (siehe CloudSyncSettingsStore). Muss vor cloudSyncEngine?.stop() bzw. vor dem
            // Erst-Aktivierungs-Sheet laufen, damit keine Mutation dazwischen noch den alten
            // Wert sieht.
            if let feedivoDatabase {
                logIfThrows(context: "CloudSync-Flag in Datenbank spiegeln") {
                    try CloudSyncSettingsStore(database: feedivoDatabase).setEnabled(cloudSyncIsEnabled)
                }
            }
```

Der bestehende Rest des Handlers (`CloudSyncSettings.setPendingFirstActivation(...)`, `showingFirstActivationSheet = true`, `cloudSyncEngine?.stop()`) bleibt **unverändert** darunter stehen.

- [ ] **Schritt 5: Tests ausführen, GREEN bestätigen**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/FeedivoAppSceneConfigurationTests 2>&1 | grep -E "appInitSpiegelt|syncSettingsSpiegelt|failed" | tail -20
```

Erwartet: die beiden neuen Tests bestehen; die Fehlschlagsliste ist ansonsten identisch zur in Schritt 2 notierten Baseline.

- [ ] **Schritt 6: Beide Builds prüfen**

```bash
xcodebuild build -scheme Feedivo -configuration Debug 2>&1 | tail -5
```

```bash
xcodebuild build -scheme FeedivoMCPServer -configuration Debug 2>&1 | tail -5
```

Erwartet: beide `** BUILD SUCCEEDED **`.

- [ ] **Schritt 7: Commit**

```bash
git add Feedivo/App/FeedivoApp.swift Feedivo/Views/Settings/SettingsView.swift FeedivoTests/App/FeedivoAppSceneConfigurationTests.swift
git commit -m "feat(sync): Sync-Flag beim App-Start und beim Umlegen des Schalters in die DB spiegeln"
```

---

### Task 3: `TagStore`-Gate umstellen

Ab hier folgen alle Tasks demselben Schema. **Ersetzungsmuster im Produktivcode:**

```swift
// vorher
guard CloudSyncSettings.isEnabled() else { return }
// nachher
guard CloudSyncSettingsStore.isEnabled(in: db) else { return }
```

**Ersetzungsmuster in den Tests:**

```swift
// vorher
UserDefaults.standard.set(true, forKey: CloudSyncSettings.isEnabledKey)
defer { UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey) }
// nachher (kein defer noetig — die In-Memory-DB ist pro Test frisch)
try CloudSyncSettingsStore(database: database).setEnabled(true)
```

Zeilen der Form `UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey)` in **negativen** Tests („synct nicht, wenn deaktiviert") werden **ersatzlos entfernt** — nach Migration v33 ist `false` bereits der Standard einer frischen Test-Datenbank, der bisherige Aufruf diente nur dazu, prozess-globalen `UserDefaults`-Zustand aus anderen Tests wegzuräumen. Genau das entfällt jetzt.

**Files:**
- Modify: `Feedivo/Stores/TagStore.swift:21`
- Test: `FeedivoTests/Stores/SQLiteTagStoreTests.swift` (1 aktivierende Stelle)
- Test: `FeedivoTests/Stores/TagStoreChangedFieldsTests.swift` (3 aktivierende Stellen)

**Interfaces:**
- Consumes: `CloudSyncSettingsStore.isEnabled(in:)` und `.setEnabled(_:)` aus Task 1
- Produces: nichts Neues

- [ ] **Schritt 1: Tests auf den Store umstellen (RED)**

Alle betroffenen Stellen finden:

```bash
grep -n "CloudSyncSettings.isEnabledKey" FeedivoTests/Stores/SQLiteTagStoreTests.swift FeedivoTests/Stores/TagStoreChangedFieldsTests.swift
```

Jede gefundene Stelle nach dem oben gezeigten Muster umstellen. Konkretes Beispiel aus `SQLiteTagStoreTests.swift:235-245` — vorher:

```swift
    @Test func saveMarkiertTagAlsPendingSyncWennAktiviert() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        UserDefaults.standard.set(true, forKey: CloudSyncSettings.isEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey) }
        let store = TagStore(database: database)
```

nachher:

```swift
    @Test func saveMarkiertTagAlsPendingSyncWennAktiviert() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try CloudSyncSettingsStore(database: database).setEnabled(true)
        let store = TagStore(database: database)
```

und der negative Test `saveMarkiertNichtsWennSyncDeaktiviert` (Zeile 247-255) verliert seine `removeObject`-Zeile ersatzlos:

```swift
    @Test func saveMarkiertNichtsWennSyncDeaktiviert() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        // Standard einer frischen Datenbank ist bereits "aus" (Migration v33).
        let store = TagStore(database: database)
```

- [ ] **Schritt 2: Tests ausführen, Fehlschlag bestätigen**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/SQLiteTagStoreTests -only-testing:FeedivoTests/TagStoreChangedFieldsTests 2>&1 | tail -30
```

Erwartet: FAIL — die aktivierenden Tests finden keine Pending-Changes mehr, weil das Gate noch `UserDefaults` liest (dort steht jetzt nichts mehr).

- [ ] **Schritt 3: Gate umstellen**

In `Feedivo/Stores/TagStore.swift`, `enqueuePendingSync` (Zeile 20-23):

```swift
    private func enqueuePendingSync(_ db: Database, tagID: String, changeType: CloudSyncChangeType, changedFields: [String]? = nil) throws {
        guard CloudSyncSettingsStore.isEnabled(in: db) else { return }
        try CloudSyncPendingChangeStore.enqueue(db, recordType: CloudSyncTagMapping.recordType, recordName: tagID, changeType: changeType, changedFields: changedFields)
    }
```

Zusätzlich den bestehenden Doc-Kommentar direkt darüber (er erklärt bereits die Transaktions-Atomarität) um diese Zeilen ergänzen:

```
    /// Liest das Aktiv-Flag ueber `db` aus `cloud_sync_settings` statt aus UserDefaults, damit
    /// auch Mutationen aus dem unsandboxed FeedivoMCPServer-Prozess korrekt greifen (siehe
    /// CloudSyncSettingsStore).
```

- [ ] **Schritt 4: Tests ausführen, GREEN bestätigen**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/SQLiteTagStoreTests -only-testing:FeedivoTests/TagStoreChangedFieldsTests 2>&1 | tail -20
```

Erwartet: PASS.

- [ ] **Schritt 5: `CloudSyncSettingsTests` gegenprüfen (nicht blind ändern)**

```bash
grep -n "isEnabledKey" -B 3 -A 6 FeedivoTests/Services/CloudSync/CloudSyncSettingsTests.swift
```

Wenn die Stelle nur `CloudSyncSettings.isEnabled(in:)` selbst testet: **unverändert lassen** und das im Task-Report festhalten. Nur falls sie tatsächlich einen Store-Gate-Pfad testet, nach demselben Muster umstellen.

- [ ] **Schritt 6: Builds prüfen und committen**

```bash
xcodebuild build -scheme Feedivo -configuration Debug 2>&1 | tail -5 && xcodebuild build -scheme FeedivoMCPServer -configuration Debug 2>&1 | tail -5
```

```bash
git add Feedivo/Stores/TagStore.swift FeedivoTests/Stores/SQLiteTagStoreTests.swift FeedivoTests/Stores/TagStoreChangedFieldsTests.swift
git commit -m "refactor(sync): TagStore-Gate liest Sync-Flag aus der Datenbank"
```

---

### Task 4: `ArticleStatusStore` + `CloudSyncArticleStatusMapping` umstellen

Diese beiden zusammen, weil sie denselben Record-Typ betreffen (Artikelstatus-Push und dessen Löschpropagierung) und `CloudSyncArticleStatusMappingTests` beide Pfade abdeckt.

**Files:**
- Modify: `Feedivo/Stores/ArticleStatusStore.swift:142`
- Modify: `Feedivo/Services/CloudSync/CloudSyncArticleStatusMapping.swift:186`
- Test: `FeedivoTests/Stores/SQLiteArticleStatusStoreTests.swift` (2 aktivierende Stellen)
- Test: `FeedivoTests/Services/CloudSync/CloudSyncArticleStatusMappingTests.swift` (1)
- Test: `FeedivoTests/ViewModels/SQLiteFeedArticleListStateTests.swift` (1)
- Test: `FeedivoTests/Services/ArticleRetentionCleanupServiceTests.swift` (1)

**Interfaces:**
- Consumes: `CloudSyncSettingsStore.isEnabled(in:)`, `.setEnabled(_:)`
- Produces: nichts Neues

- [ ] **Schritt 1: Tests auf den Store umstellen (RED)**

```bash
grep -n "CloudSyncSettings.isEnabledKey" FeedivoTests/Stores/SQLiteArticleStatusStoreTests.swift FeedivoTests/Services/CloudSync/CloudSyncArticleStatusMappingTests.swift FeedivoTests/ViewModels/SQLiteFeedArticleListStateTests.swift FeedivoTests/Services/ArticleRetentionCleanupServiceTests.swift
```

Jede Stelle nach dem in Task 3 gezeigten Muster umstellen (`set(true, ...)` + `defer`-Zeile → `try CloudSyncSettingsStore(database: database).setEnabled(true)`; reine `removeObject`-Zeilen ersatzlos entfernen).

Achtung: In diesen Suiten heißt die Datenbank-Variable nicht überall `database`. Vor dem Ersetzen jeweils prüfen, wie die im betroffenen Test verwendete `FeedivoDatabase`-Instanz benannt ist, und diesen Namen einsetzen.

- [ ] **Schritt 2: Tests ausführen, Fehlschlag bestätigen**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/SQLiteArticleStatusStoreTests -only-testing:FeedivoTests/CloudSyncArticleStatusMappingTests 2>&1 | tail -30
```

Erwartet: FAIL bei den aktivierenden Tests.

- [ ] **Schritt 3: Beide Gates umstellen**

`Feedivo/Stores/ArticleStatusStore.swift`, `enqueuePendingSync` (Zeile 141-142):

```swift
    private func enqueuePendingSync(_ db: Database, articleIDs: [String], changeType: CloudSyncChangeType) throws {
        guard CloudSyncSettingsStore.isEnabled(in: db), !articleIDs.isEmpty else { return }
```

`Feedivo/Services/CloudSync/CloudSyncArticleStatusMapping.swift`, `enqueueDeletionIfSynced` (Zeile 185-186):

```swift
    static func enqueueDeletionIfSynced(articleIDs: [String], db: Database) throws {
        guard CloudSyncSettingsStore.isEnabled(in: db), !articleIDs.isEmpty else { return }
```

Der Rest beider Methodenkörper bleibt unverändert.

- [ ] **Schritt 4: Tests ausführen, GREEN bestätigen**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/SQLiteArticleStatusStoreTests -only-testing:FeedivoTests/CloudSyncArticleStatusMappingTests -only-testing:FeedivoTests/ArticleRetentionCleanupServiceTests -only-testing:FeedivoTests/SQLiteFeedArticleListStateTests 2>&1 | tail -25
```

Erwartet: PASS. `SQLiteFeedArticleListStateTests` ist als flaky-unter-Last bekannt — bei einem Fehlschlag dort die Suite isoliert erneut laufen lassen, bevor er als Regression gewertet wird.

- [ ] **Schritt 5: Builds prüfen und committen**

```bash
xcodebuild build -scheme Feedivo -configuration Debug 2>&1 | tail -5 && xcodebuild build -scheme FeedivoMCPServer -configuration Debug 2>&1 | tail -5
```

```bash
git add Feedivo/Stores/ArticleStatusStore.swift Feedivo/Services/CloudSync/CloudSyncArticleStatusMapping.swift FeedivoTests/Stores/SQLiteArticleStatusStoreTests.swift FeedivoTests/Services/CloudSync/CloudSyncArticleStatusMappingTests.swift FeedivoTests/ViewModels/SQLiteFeedArticleListStateTests.swift FeedivoTests/Services/ArticleRetentionCleanupServiceTests.swift
git commit -m "refactor(sync): Artikelstatus-Gates lesen Sync-Flag aus der Datenbank"
```

---

### Task 5: `FeedStore` + `FeedFolderStore` umstellen

Zusammen, weil `FeedFolderStore.enqueueFeedPendingSync` beim Ordner-Umbenennen Feed-Records einreiht und beide Suiten sich dabei überschneiden.

**Files:**
- Modify: `Feedivo/Stores/FeedStore.swift:16`
- Modify: `Feedivo/Stores/FeedFolderStore.swift:33` und `:42` (**zwei** Gates: `enqueuePendingSync` und `enqueueFeedPendingSync`)
- Test: `FeedivoTests/Stores/SQLiteFeedStoreTests.swift` (6 aktivierende Stellen)
- Test: `FeedivoTests/Stores/FeedStoreChangedFieldsTests.swift` (3)
- Test: `FeedivoTests/Stores/FeedFolderStoreTests.swift` (5)
- Test: `FeedivoTests/Stores/FeedFolderStoreChangedFieldsTests.swift` (3)

**Interfaces:**
- Consumes: `CloudSyncSettingsStore.isEnabled(in:)`, `.setEnabled(_:)`
- Produces: nichts Neues

- [ ] **Schritt 1: Tests auf den Store umstellen (RED)**

```bash
grep -n "CloudSyncSettings.isEnabledKey" FeedivoTests/Stores/SQLiteFeedStoreTests.swift FeedivoTests/Stores/FeedStoreChangedFieldsTests.swift FeedivoTests/Stores/FeedFolderStoreTests.swift FeedivoTests/Stores/FeedFolderStoreChangedFieldsTests.swift
```

Alle gefundenen Stellen nach dem Muster aus Task 3 umstellen (17 aktivierende Stellen plus die zugehörigen `removeObject`-Zeilen).

- [ ] **Schritt 2: Tests ausführen, Fehlschlag bestätigen**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/SQLiteFeedStoreTests -only-testing:FeedivoTests/FeedStoreChangedFieldsTests -only-testing:FeedivoTests/FeedFolderStoreTests -only-testing:FeedivoTests/FeedFolderStoreChangedFieldsTests 2>&1 | tail -30
```

Erwartet: FAIL bei allen aktivierenden Tests.

- [ ] **Schritt 3: Alle drei Gates umstellen**

`Feedivo/Stores/FeedStore.swift` (Zeile 15-16):

```swift
    private func enqueuePendingSync(_ db: Database, feedID: String, changeType: CloudSyncChangeType, changedFields: [String]? = nil) throws {
        guard CloudSyncSettingsStore.isEnabled(in: db) else { return }
```

`Feedivo/Stores/FeedFolderStore.swift` (Zeile 32-33):

```swift
    private func enqueuePendingSync(_ db: Database, folderID: String, changeType: CloudSyncChangeType, changedFields: [String]? = nil) throws {
        guard CloudSyncSettingsStore.isEnabled(in: db) else { return }
```

`Feedivo/Stores/FeedFolderStore.swift` (Zeile 41-42):

```swift
    private func enqueueFeedPendingSync(_ db: Database, feedID: String) throws {
        guard CloudSyncSettingsStore.isEnabled(in: db) else { return }
```

- [ ] **Schritt 4: Tests ausführen, GREEN bestätigen**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/SQLiteFeedStoreTests -only-testing:FeedivoTests/FeedStoreChangedFieldsTests -only-testing:FeedivoTests/FeedFolderStoreTests -only-testing:FeedivoTests/FeedFolderStoreChangedFieldsTests 2>&1 | tail -20
```

Erwartet: PASS.

- [ ] **Schritt 5: Builds prüfen und committen**

```bash
xcodebuild build -scheme Feedivo -configuration Debug 2>&1 | tail -5 && xcodebuild build -scheme FeedivoMCPServer -configuration Debug 2>&1 | tail -5
```

```bash
git add Feedivo/Stores/FeedStore.swift Feedivo/Stores/FeedFolderStore.swift FeedivoTests/Stores/SQLiteFeedStoreTests.swift FeedivoTests/Stores/FeedStoreChangedFieldsTests.swift FeedivoTests/Stores/FeedFolderStoreTests.swift FeedivoTests/Stores/FeedFolderStoreChangedFieldsTests.swift
git commit -m "refactor(sync): Feed- und Ordner-Gates lesen Sync-Flag aus der Datenbank"
```

---

### Task 6: `SQLiteRuleStore` + `SQLiteSmartFolderStore` umstellen

**Files:**
- Modify: `Feedivo/Stores/SQLiteRuleStore.swift:15`
- Modify: `Feedivo/Stores/SQLiteSmartFolderStore.swift:16`
- Test: `FeedivoTests/Stores/SQLiteRuleStoreTests.swift` (6 aktivierende Stellen)
- Test: `FeedivoTests/Stores/SQLiteRuleStoreChangedFieldsTests.swift` (6)
- Test: `FeedivoTests/Stores/SQLiteSmartFolderStoreTests.swift` (11)
- Test: `FeedivoTests/Stores/SQLiteSmartFolderStoreChangedFieldsTests.swift` (7)

**Interfaces:**
- Consumes: `CloudSyncSettingsStore.isEnabled(in:)`, `.setEnabled(_:)`
- Produces: nichts Neues

- [ ] **Schritt 1: Tests auf den Store umstellen (RED)**

```bash
grep -n "CloudSyncSettings.isEnabledKey" FeedivoTests/Stores/SQLiteRuleStoreTests.swift FeedivoTests/Stores/SQLiteRuleStoreChangedFieldsTests.swift FeedivoTests/Stores/SQLiteSmartFolderStoreTests.swift FeedivoTests/Stores/SQLiteSmartFolderStoreChangedFieldsTests.swift
```

Alle gefundenen Stellen nach dem Muster aus Task 3 umstellen (30 aktivierende Stellen plus die zugehörigen `removeObject`-Zeilen).

- [ ] **Schritt 2: Tests ausführen, Fehlschlag bestätigen**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/SQLiteRuleStoreTests -only-testing:FeedivoTests/SQLiteSmartFolderStoreTests 2>&1 | tail -30
```

Erwartet: FAIL bei den aktivierenden Tests.

- [ ] **Schritt 3: Beide Gates umstellen**

`Feedivo/Stores/SQLiteRuleStore.swift` (Zeile 14-15):

```swift
    private func enqueuePendingSync(_ db: Database, recordType: String, recordName: String, changeType: CloudSyncChangeType, changedFields: [String]? = nil) throws {
        guard CloudSyncSettingsStore.isEnabled(in: db) else { return }
```

`Feedivo/Stores/SQLiteSmartFolderStore.swift` (Zeile 15-16):

```swift
    private func enqueuePendingSync(_ db: Database, recordType: String, recordName: String, changeType: CloudSyncChangeType, changedFields: [String]? = nil) throws {
        guard CloudSyncSettingsStore.isEnabled(in: db) else { return }
```

- [ ] **Schritt 4: Tests ausführen, GREEN bestätigen**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/SQLiteRuleStoreTests -only-testing:FeedivoTests/SQLiteRuleStoreChangedFieldsTests -only-testing:FeedivoTests/SQLiteSmartFolderStoreTests -only-testing:FeedivoTests/SQLiteSmartFolderStoreChangedFieldsTests 2>&1 | tail -20
```

Erwartet: PASS.

- [ ] **Schritt 5: Verifizieren, dass kein Gate mehr auf UserDefaults liest**

```bash
grep -rn "CloudSyncSettings.isEnabled" Feedivo --include="*.swift"
```

Erwartet: **genau vier** verbleibende Treffer — `Feedivo/App/FeedivoApp.swift:107`, `Feedivo/Services/CloudSync/CloudSyncEngine.swift:179` (beide laut Global Constraints bewusst unangetastet), die `@AppStorage(CloudSyncSettings.isEnabledKey)`-Zeile in `SettingsView.swift` und der Doc-Kommentar in `CloudSyncEngine.swift:283` (kein Code). Jeder weitere Treffer in `Feedivo/Stores/` oder `Feedivo/Services/CloudSync/*Mapping.swift` ist ein vergessenes Gate.

- [ ] **Schritt 6: Builds prüfen und committen**

```bash
xcodebuild build -scheme Feedivo -configuration Debug 2>&1 | tail -5 && xcodebuild build -scheme FeedivoMCPServer -configuration Debug 2>&1 | tail -5
```

```bash
git add Feedivo/Stores/SQLiteRuleStore.swift Feedivo/Stores/SQLiteSmartFolderStore.swift FeedivoTests/Stores/SQLiteRuleStoreTests.swift FeedivoTests/Stores/SQLiteRuleStoreChangedFieldsTests.swift FeedivoTests/Stores/SQLiteSmartFolderStoreTests.swift FeedivoTests/Stores/SQLiteSmartFolderStoreChangedFieldsTests.swift
git commit -m "refactor(sync): Regel- und Smart-Folder-Gates lesen Sync-Flag aus der Datenbank"
```

---

### Task 7: Abschluss — Regressionslauf, Release-Build, Dokumentation

**Files:**
- Modify: `CLAUDE.md` (Migrations-Tabelle, Gotcha-Abschnitt, Eintrag unter „Aktuell in Arbeit")
- Kein Produktivcode.

**Interfaces:**
- Consumes: alles aus Tasks 1–6
- Produces: nichts

- [ ] **Schritt 1: Gezielter Regressionslauf über alle berührten Suiten**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/CloudSyncSettingsStoreTests -only-testing:FeedivoTests/FeedivoDatabaseMigratorTests -only-testing:FeedivoTests/SQLiteTagStoreTests -only-testing:FeedivoTests/TagStoreChangedFieldsTests -only-testing:FeedivoTests/SQLiteArticleStatusStoreTests -only-testing:FeedivoTests/CloudSyncArticleStatusMappingTests 2>&1 | tail -25
```

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/SQLiteFeedStoreTests -only-testing:FeedivoTests/FeedStoreChangedFieldsTests -only-testing:FeedivoTests/FeedFolderStoreTests -only-testing:FeedivoTests/FeedFolderStoreChangedFieldsTests -only-testing:FeedivoTests/SQLiteRuleStoreTests -only-testing:FeedivoTests/SQLiteRuleStoreChangedFieldsTests 2>&1 | tail -25
```

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/SQLiteSmartFolderStoreTests -only-testing:FeedivoTests/SQLiteSmartFolderStoreChangedFieldsTests -only-testing:FeedivoTests/CloudSyncSettingsTests -only-testing:FeedivoTests/CloudSyncEngineResetTests -only-testing:FeedivoTests/ArticleRetentionCleanupServiceTests -only-testing:FeedivoTests/SQLiteFeedArticleListStateTests 2>&1 | tail -25
```

Erwartet: alle drei Läufe grün. Einzige zulässige Ausnahme: bekannte flaky-unter-Last Tests in `SQLiteFeedArticleListStateTests` — bei einem Fehlschlag dort die Suite isoliert erneut laufen lassen und das Ergebnis im Report festhalten.

- [ ] **Schritt 2: Release-Build**

```bash
xcodebuild build -scheme Feedivo -configuration Release 2>&1 | tail -5
```

```bash
xcodebuild build -scheme FeedivoMCPServer -configuration Release 2>&1 | tail -5
```

Erwartet: beide `** BUILD SUCCEEDED **`.

- [ ] **Schritt 3: Migrations-Tabelle in `CLAUDE.md` ergänzen**

Im Abschnitt „Datenbank-Schema (GRDB-Migrationen)" eine Zeile anhängen:

```markdown
| v33_create_cloud_sync_settings | Single-Row-Tabelle `cloud_sync_settings` — DB-Spiegel des iCloud-Sync-Aktiv-Flags, damit der unsandboxed `FeedivoMCPServer`-Prozess den echten Wert sieht (UserDefaults bleibt Quelle der Wahrheit, Abgleich bei App-Start + Schalter-Umlegen) |
```

- [ ] **Schritt 4: Neuen Gotcha in `CLAUDE.md` ergänzen**

Im Abschnitt „Bekannte Gotchas & Fallstricke":

```markdown
- **GRDB-Datenbankzugriffe sind nicht reentrant — ein `database.read`/`database.write` von
  innerhalb eines bestehenden `db: Database`-Blocks crasht zur Laufzeit:** GRDB erzwingt das
  mit `GRDBPrecondition(currentReader == nil, "Database methods are not reentrant.")`
  (`DatabasePool.swift:340`, für `DatabaseQueue` in `DatabaseQueue.swift:445` dokumentiert).
  Aufgefallen beim Planen der iCloud-Sync-Settings-DB-Spiegelung (2026-08-15): die Design-Spec
  schlug vor, die 8 `enqueuePendingSync`-Gates auf
  `CloudSyncSettingsStore(database: self.database).isEnabled()` umzustellen, und nannte das
  „rein mechanisch" — tatsächlich laufen alle diese Gates bereits INNERHALB einer offenen
  `database.write`-Transaktion (Parameter `db: Database`), der Vorschlag wäre in jedem Test
  (`inMemoryForTests()` = `DatabaseQueue`, eine einzige serialisierte Verbindung) sofort
  gecrasht. **Lehre:** Bei jeder neuen Hilfsfunktion, die aus einer bestehenden Store-Methode
  heraus die Datenbank lesen will, zuerst prüfen, ob die aufrufende Methode einen
  `db: Database`-Parameter hat — wenn ja, MUSS die Hilfsfunktion diesen `db` entgegennehmen
  (`static func isEnabled(in db: Database)`) statt sich eine eigene Verbindung zu holen. Das
  ist zugleich fachlich richtiger: der Lesevorgang sieht garantiert denselben Zustand wie die
  Mutation, die er begleitet.
```

- [ ] **Schritt 5: Eintrag unter „Aktuell in Arbeit" in `CLAUDE.md`**

Als neuen ersten Eintrag einfügen. Inhalt: Datum, Root Cause (unsandboxed MCP-Prozess sieht eine andere Preferences-Domäne), die 8 umgestellten Gates, die bewusst nicht umgestellten Stellen (`FeedivoApp.swift:107`, `CloudSyncEngine.swift:179`), die drei Spec-Abweichungen samt Begründung (GRDB-Reentranz; Backfill beim App-Start statt in der Migration; 15 statt 17 Testdateien), sowie die noch **ausstehende manuelle Live-Verifikation**:

1. iCloud Sync in den Einstellungen einschalten → `sqlite3` auf die Produktions-DB: `SELECT isEnabled FROM cloud_sync_settings;` muss `1` liefern; ausschalten → `0`.
2. App **beenden**, MCP-Schreibzugriff aktiv, über Claude Desktop `update_article_status` auf einen Artikel → danach `SELECT COUNT(*) FROM cloud_sync_pending_changes WHERE recordType = 'ArticleStatus';` muss > 0 sein (vor diesem Fix: immer 0).
3. App starten → CloudKit-Dashboard-„Logs"-Tab zeigt ein `RecordSave` mit `overallStatus: SUCCESS` für den Record-Typ `ArticleStatus`.
4. Bestandsnutzer-/Selbstheilungs-Fall: Sync eingeschaltet lassen, App beenden, `UPDATE cloud_sync_settings SET isEnabled = 0;` von Hand setzen, App starten → Wert steht danach wieder auf `1`.

- [ ] **Schritt 6: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: iCloud-Sync-Settings-DB-Spiegelung in CLAUDE.md dokumentiert"
```

- [ ] **Schritt 7: Push-Entscheidung dem Nutzer vorlegen**

Laut Projektkonvention **nie ohne explizite Bestätigung** nach `origin/main` pushen. Dem Nutzer melden: Anzahl der Commits dieses Plans, den weiterhin offenen Rückstand aus früheren Sessions (Stand vor diesem Plan: 13 unpushed Commits), sowie die vier offenen Punkte der manuellen Live-Verifikation aus Schritt 5.

---

## Self-Review

**Spec-Abdeckung:**
- Migration v33 + Tabelle → Task 1 ✔
- `CloudSyncSettingsStore` (isEnabled/setEnabled) → Task 1 ✔
- `CloudSyncSettings` bleibt unverändert → Global Constraints ✔
- Spiegelung im `onChange`-Handler → Task 2 ✔
- Backfill des Bestandswerts → Task 2 (verlagert vom Migrator, Nutzerentscheidung dokumentiert) ✔
- Alle 8 Gates umgestellt (Spec nannte 7 — `FeedFolderStore` hat tatsächlich zwei) → Tasks 3–6 ✔
- Fail-closed-Fehlerbehandlung → Task 1, Schritt 7 + eigener Test ✔
- Testdatei-Umstellung → Tasks 3–6, mit korrigierter Liste (15 statt 17 Dateien, unbetroffene Kandidaten einzeln verifiziert) ✔
- Regressionslauf + Debug-/Release-Build → Task 7 ✔
- Out of Scope (kein Re-Sync-Trigger, keine Änderung an `pendingFirstActivationKey`) → eingehalten ✔

**Platzhalter-Scan:** Keine „TBD"/„später"-Verweise. Das Ersetzungsmuster für Tests steht in Task 3 vollständig ausgeschrieben; Tasks 4–6 verweisen darauf, geben aber jeweils den vollständigen Produktivcode und die exakten `grep`-Befehle zum Auffinden aller Stellen an — bei ~50 nahezu identischen Test-Stellen wäre wörtliches Wiederholen jeder einzelnen reine Redundanz ohne Informationsgewinn.

**Typ-Konsistenz:** `CloudSyncSettingsStore.isEnabled(in: db)` (statisch, nicht werfend, `Bool`) wird in Tasks 3–6 exakt so aufgerufen wie in Task 1 definiert. `setEnabled(_:) throws` und `mirrorFromUserDefaults(_:) throws` ebenso. Der Migrationsname `"v33_create_cloud_sync_settings"` ist über Task 1 und Task 7 identisch.
