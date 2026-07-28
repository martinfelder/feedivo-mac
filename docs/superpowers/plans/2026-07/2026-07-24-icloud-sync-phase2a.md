# iCloud Sync Phase 2a (Struktur-Daten) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Erweitert den bestehenden `CKSyncEngine`-basierten iCloud-Sync (Phase 1, aktuell nur `tags`) auf Feeds, Feed-Ordner, Regeln (+Bedingungen) und benutzerdefinierte Intelligente Ordner (+Bedingungen).

**Architecture:** `CloudSyncEngine` wird von einer Tag-spezifischen Klasse zu einer generischen, Registry-basierten Engine umgebaut (neues `CloudSyncRecordMapping`-Protokoll, ein Mapping pro Tabelle). Jede `*Store`-Mutation markiert betroffene Zeilen in der bestehenden `CloudSyncPendingChangeStore`-Warteschlange und ruft `CloudSyncEngine.notifyPendingChangesAvailable(database:)` auf. Konflikte bleiben Last-Write-Wins wie in Phase 1.

**Tech Stack:** Swift, GRDB (SQLite), CloudKit (`CKSyncEngine`), Swift Testing (`@Test`/`#expect`, kein XCTest).

## Global Constraints

- Sync-Umfang `feeds`: NUR `url`, `title`, `originalTitle`, `websiteURL`, `faviconURL`, `folderName`, `sortIndex`, `refreshIntervalMinutes`, `isNotificationEnabled`, `articleRetentionOverridesGlobalSetting`, `articleRetentionIsEnabled`, `articleRetentionDays`, `articleRetentionMinimumArticles`, `articleRetentionIncludesProtectedArticles`. NIEMALS `lastRefreshedAt`/`lastETag`/`lastModified`/`lastBodyHash`/`lastHTTPStatusCode`/`unreadCount` syncen (gerätespezifisch).
- `feed_folders`, `rules`, `rule_conditions` syncen vollständig.
- `smart_folders`/`smart_folder_conditions` syncen **nur für `isDefault == false`** — eingebaute Ordner (`isDefault == true`) NIEMALS syncen (Duplikat-Risiko, siehe Design-Spec).
- Alle Records leben in derselben CloudKit-Zone `"FeedivoZone"` (keine neuen Zonen).
- Konfliktauflösung bleibt Last-Write-Wins (`.ifServerRecordUnchanged`-Speicherpolicy), wie in Phase 1.
- Sprache für Code-Kommentare: Deutsch (Projektkonvention).
- Migrationen NIE nachträglich ändern, immer neue `registerMigration(...)`-Blöcke anhängen. Aktueller letzter Stand vor diesem Plan: `v21_create_cloud_sync_pending_changes`.
- Tests: Swift Testing (`import Testing`, `@Test`, `#expect`), kein XCTest. Gezielt mit `-only-testing:FeedivoTests/<SuiteName>` laufen lassen (volle Suite hängt, siehe CLAUDE.md-Gotcha).
- Design-Referenz: `docs/superpowers/specs/2026-07-24-icloud-sync-phase2a-design.md`.

---

### Task 1: Migration v22 — `updatedAt` auf Bedingungstabellen + Record-Struct-Update

**Files:**
- Modify: `Feedivo/Database/FeedivoDatabaseMigrator.swift` (neuer Migrationsblock nach `v21_create_cloud_sync_pending_changes`, Zeile ~437)
- Modify: `Feedivo/Database/Records/RuleConditionRecord.swift`
- Modify: `Feedivo/Database/Records/SmartFolderConditionRecord.swift`
- Test: `FeedivoTests/FeedivoDatabaseMigratorTests.swift` (falls nicht vorhanden, neue Datei mit diesem Namen anlegen)

**Interfaces:**
- Produces: `RuleConditionRecord.updatedAt: Date` (Default `Date()`), `SmartFolderConditionRecord.updatedAt: Date` (Default `Date()`) — von Task 6/7 für Last-Write-Wins-Vergleich genutzt.

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import GRDB
import Testing
@testable import Feedivo

struct FeedivoDatabaseMigratorTests {
    @Test func migrationV22FuegtUpdatedAtZuBedingungstabellenHinzuUndBackfilledBestandszeilen() throws {
        let dbQueue = try DatabaseQueue()

        // Migriere nur bis v21 (vor der neuen Migration), lege eine Bestands-Regel mit
        // Bedingung OHNE updatedAt an, migriere dann weiter bis v22 und prüfe Backfill.
        var migratorUpToV21 = DatabaseMigrator()
        FeedivoDatabaseMigrator.registerAllMigrations(on: &migratorUpToV21, upTo: "v21_create_cloud_sync_pending_changes")
        try migratorUpToV21.migrate(dbQueue)

        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO rules (id, name, isEnabled, matchMode, action, notificationTemplate, notificationPriority, sortOrder, createdAt, updatedAt)
                VALUES ('rule-1', 'Test', 1, 'all', 'assignTag', '{Titel}', 'normal', 0, ?, ?)
                """, arguments: [Date(), Date()])
            try db.execute(sql: """
                INSERT INTO rule_conditions (id, ruleID, field, conditionOperator, value, sortOrder, groupIndex)
                VALUES ('cond-1', 'rule-1', 'title', 'contains', 'Test', 0, 0)
                """)
        }

        let fullMigrator = FeedivoDatabaseMigrator.make()
        try fullMigrator.migrate(dbQueue)

        let updatedAt = try dbQueue.read { db in
            try Date.fetchOne(db, sql: "SELECT updatedAt FROM rule_conditions WHERE id = 'cond-1'")
        }
        #expect(updatedAt != nil)
    }

    @Test func migrationV22BereinigtVeraltetenRecordTypeStringFuerTags() throws {
        let dbQueue = try DatabaseQueue()

        var migratorUpToV21 = DatabaseMigrator()
        FeedivoDatabaseMigrator.registerAllMigrations(on: &migratorUpToV21, upTo: "v21_create_cloud_sync_pending_changes")
        try migratorUpToV21.migrate(dbQueue)

        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO cloud_sync_pending_changes (id, recordType, changeType, queuedAt)
                VALUES ('tag-1', 'tag', 'save', ?)
                """, arguments: [Date()])
        }

        let fullMigrator = FeedivoDatabaseMigrator.make()
        try fullMigrator.migrate(dbQueue)

        let recordType = try dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT recordType FROM cloud_sync_pending_changes WHERE id = 'tag-1'")
        }
        #expect(recordType == "Tag")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoDatabaseMigratorTests 2>&1 | tail -40`
Expected: FAIL — `registerAllMigrations(on:upTo:)` existiert nicht auf `FeedivoDatabaseMigrator` (Compile-Fehler), da diese Hilfsfunktion für den Test neu gebaut werden muss.

> **Hinweis für den Implementierer:** Prüfe zuerst per `grep -n "static func make\|struct FeedivoDatabaseMigrator\|enum FeedivoDatabaseMigrator" Feedivo/Database/FeedivoDatabaseMigrator.swift`, wie die bestehende `make()`-Funktion aufgebaut ist, und ergänze `registerAllMigrations(on:upTo:)` als kleine Test-Hilfsfunktion (Zugriff auf dieselbe private Migrationsliste, nur mit einem `upTo`-Namensfilter, der nach Erreichen dieses Migrationsnamens abbricht), statt die komplette Migrationsliste zu duplizieren.

- [ ] **Step 3: Write minimal implementation**

In `Feedivo/Database/FeedivoDatabaseMigrator.swift`, füge nach dem `v21_create_cloud_sync_pending_changes`-Block (vor `return migrator`) ein:

```swift
        migrator.registerMigration("v22_add_updated_at_to_condition_tables") { database in
            try database.alter(table: "rule_conditions") { table in
                table.add(column: "updatedAt", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
            }
            try database.alter(table: "smart_folder_conditions") { table in
                table.add(column: "updatedAt", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
            }

            // Housekeeping im selben Zug: TagStore.enqueuePendingSync nutzte bisher den
            // Ad-hoc-String "tag" für CloudSyncPendingChangeRecord.recordType, während
            // CloudSyncTagMapping.recordType "Tag" ist (CKRecord-Typ). Die neue,
            // Registry-basierte CloudSyncEngine (Task 3) braucht denselben String-Raum für
            // beide Zwecke — bestehende, noch nicht hochgeladene Zeilen werden hier einmalig
            // vereinheitlicht.
            try database.execute(sql: "UPDATE cloud_sync_pending_changes SET recordType = 'Tag' WHERE recordType = 'tag'")
        }
```

Ergänze außerdem eine Test-Hilfsfunktion (z. B. direkt unterhalb von `make()` in derselben Datei):

```swift
    #if DEBUG
    /// Test-Hilfsfunktion: registriert alle Migrationen bis EINSCHLIESSLICH `upTo` (Name muss
    /// exakt einem `registerMigration`-Aufruf entsprechen). Nur für Migrationstests, die einen
    /// Zwischenstand vor einer neuen Migration brauchen.
    static func registerAllMigrations(on migrator: inout DatabaseMigrator, upTo targetName: String) {
        var reachedTarget = false
        let recordingMigrator = RecordingMigrator { name, migration in
            guard !reachedTarget else { return }
            migrator.registerMigration(name, migrate: migration)
            if name == targetName {
                reachedTarget = true
            }
        }
        _ = Self.make(into: recordingMigrator)
    }
    #endif
```

> Diese `RecordingMigrator`-Indirection ist nötig, WEIL `make()` intern direkt `migrator.registerMigration(...)` aufruft. Prüfe die tatsächliche Struktur von `make()` zuerst per Read — falls `make()` bereits als `static func make(into migrator: inout DatabaseMigrator)` oder ähnlich parametrisiert aufgebaut ist, entfällt die Indirection und `registerAllMigrations` kann direkter implementiert werden. Falls `make()` eine reine `-> DatabaseMigrator`-Funktion ohne Parameter ist, ist die einfachste robuste Lösung: `make()` intern in eine private `static func registerMigrations(_ migrator: inout DatabaseMigrator)` extrahieren (reiner Refactor, keine Verhaltensänderung), die sowohl von `make()` als auch von `registerAllMigrations(on:upTo:)` (mit einem Early-Return nach dem Ziel-Namen) aufgerufen wird.

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoDatabaseMigratorTests 2>&1 | tail -40`
Expected: PASS

- [ ] **Step 5: Update `RuleConditionRecord` and `SmartFolderConditionRecord` structs**

In `Feedivo/Database/Records/RuleConditionRecord.swift`, füge das Feld hinzu:

```swift
struct RuleConditionRecord: Codable, FetchableRecord, MutablePersistableRecord, Equatable, Sendable {
    static let databaseTableName = "rule_conditions"

    var id: String
    var ruleID: String
    var field: String
    var conditionOperator: String
    var value: String
    var sortOrder: Int
    var groupIndex: Int
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        ruleID: String,
        field: String,
        conditionOperator: String,
        value: String,
        sortOrder: Int = 0,
        groupIndex: Int = 0,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.ruleID = ruleID
        self.field = field
        self.conditionOperator = conditionOperator
        self.value = value
        self.sortOrder = sortOrder
        self.groupIndex = groupIndex
        self.updatedAt = updatedAt
    }
}
```

Analog in `Feedivo/Database/Records/SmartFolderConditionRecord.swift`:

```swift
struct SmartFolderConditionRecord: Codable, FetchableRecord, MutablePersistableRecord, Equatable, Sendable {
    static let databaseTableName = "smart_folder_conditions"

    var id: String
    var smartFolderID: String
    var field: String
    var conditionOperator: String
    var value: String
    var sortOrder: Int
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        smartFolderID: String,
        field: String,
        conditionOperator: String,
        value: String,
        sortOrder: Int = 0,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.smartFolderID = smartFolderID
        self.field = field
        self.conditionOperator = conditionOperator
        self.value = value
        self.sortOrder = sortOrder
        self.updatedAt = updatedAt
    }
}
```

- [ ] **Step 6: Build to verify existing call sites still compile**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -60`
Expected: BUILD SUCCEEDED — bestehende Call-Sites (`SQLiteRuleStore.duplicate`, `SQLiteSmartFolderStore.duplicate`/`restoreDefaultFolders`, Editor-Views) übergeben `updatedAt` nicht explizit und erhalten automatisch den Default `Date()`.

- [ ] **Step 7: Commit**

```bash
git add Feedivo/Database/FeedivoDatabaseMigrator.swift Feedivo/Database/Records/RuleConditionRecord.swift Feedivo/Database/Records/SmartFolderConditionRecord.swift FeedivoTests/FeedivoDatabaseMigratorTests.swift
git commit -m "Feature: Migration v22 - updatedAt auf Regel-/Smart-Folder-Bedingungen (iCloud Sync Phase 2a Task 1)"
```

---

### Task 2: Migration v23 — `feeds.configUpdatedAt` + `FeedRecord`-Struct-Update

**Files:**
- Modify: `Feedivo/Database/FeedivoDatabaseMigrator.swift` (neuer Migrationsblock nach v22)
- Modify: `Feedivo/Database/Records/FeedRecord.swift`
- Test: `FeedivoTests/FeedivoDatabaseMigratorTests.swift` (Ergänzung)

**Interfaces:**
- Produces: `FeedRecord.configUpdatedAt: Date` (Default `Date()`) — von Task 4 als Last-Write-Wins-Vergleichsfeld für den Feed-Sync genutzt, UNABHÄNGIG von `updatedAt` (das weiterhin bei JEDER lokalen Änderung inkl. reiner Refresh-Metadaten aktualisiert wird, siehe `FeedStore.updateAfterRefresh`).

**Warum ein separates Feld:** `FeedRecord.updatedAt` wird auch von `FeedStore.updateAfterRefresh(...)` bei JEDEM Feed-Refresh gesetzt (Refresh-Metadaten wie `lastETag`/`lastHTTPStatusCode` ändern sich, nicht die Sync-relevanten Konfigurationsfelder). Würde die Konfliktauflösung `updatedAt` nutzen, würde ein rein lokaler Refresh (alle 30 Min. pro Feed) das lokale Feed IMMER "neuer" erscheinen lassen als der CloudKit-Server-Stand — unabhängig davon, ob sich tatsächlich ein Konfigurationsfeld geändert hat. `configUpdatedAt` wird NUR von den Konfigurations-Mutationsmethoden aktualisiert (Task 4).

- [ ] **Step 1: Write the failing test**

Ergänze in `FeedivoTests/FeedivoDatabaseMigratorTests.swift`:

```swift
    @Test func migrationV23FuegtConfigUpdatedAtZuFeedsHinzuUndBackfilledBestandszeilen() throws {
        let dbQueue = try DatabaseQueue()

        var migratorUpToV22 = DatabaseMigrator()
        FeedivoDatabaseMigrator.registerAllMigrations(on: &migratorUpToV22, upTo: "v22_add_updated_at_to_condition_tables")
        try migratorUpToV22.migrate(dbQueue)

        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO feeds (id, url, title, originalTitle, sortIndex, refreshIntervalMinutes, isNotificationEnabled, articleRetentionOverridesGlobalSetting, articleRetentionIsEnabled, articleRetentionDays, articleRetentionMinimumArticles, articleRetentionIncludesProtectedArticles, unreadCount, createdAt, updatedAt)
                VALUES ('feed-1', 'https://example.com/feed', 'Test', 'Test', 0, 30, 0, 0, 0, 90, 20, 0, 0, ?, ?)
                """, arguments: [Date(), Date()])
        }

        let fullMigrator = FeedivoDatabaseMigrator.make()
        try fullMigrator.migrate(dbQueue)

        let configUpdatedAt = try dbQueue.read { db in
            try Date.fetchOne(db, sql: "SELECT configUpdatedAt FROM feeds WHERE id = 'feed-1'")
        }
        #expect(configUpdatedAt != nil)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoDatabaseMigratorTests 2>&1 | tail -40`
Expected: FAIL — Spalte `configUpdatedAt` existiert noch nicht.

- [ ] **Step 3: Write minimal implementation**

In `Feedivo/Database/FeedivoDatabaseMigrator.swift`, nach dem v22-Block:

```swift
        migrator.registerMigration("v23_add_feed_config_updated_at") { database in
            try database.alter(table: "feeds") { table in
                table.add(column: "configUpdatedAt", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
            }
        }
```

In `Feedivo/Database/Records/FeedRecord.swift`, Feld + Initializer-Parameter ergänzen (nach `updatedAt`):

```swift
    var createdAt: Date
    var updatedAt: Date
    var configUpdatedAt: Date

    init(
        id: String = UUID().uuidString,
        url: String,
        title: String,
        originalTitle: String? = nil,
        websiteURL: String? = nil,
        faviconURL: String? = nil,
        folderName: String? = nil,
        sortIndex: Int = 0,
        refreshIntervalMinutes: Int = 30,
        isNotificationEnabled: Bool = false,
        articleRetentionOverridesGlobalSetting: Bool = false,
        articleRetentionIsEnabled: Bool = false,
        articleRetentionDays: Int = 90,
        articleRetentionMinimumArticles: Int = 20,
        articleRetentionIncludesProtectedArticles: Bool = false,
        lastRefreshedAt: Date? = nil,
        lastETag: String? = nil,
        lastModified: String? = nil,
        lastBodyHash: String? = nil,
        lastHTTPStatusCode: Int? = nil,
        unreadCount: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        configUpdatedAt: Date = Date()
    ) {
        // ... (bestehende Zuweisungen unverändert) ...
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.configUpdatedAt = configUpdatedAt
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoDatabaseMigratorTests 2>&1 | tail -40`
Expected: PASS

- [ ] **Step 5: Build to verify existing call sites still compile**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -60`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Database/FeedivoDatabaseMigrator.swift Feedivo/Database/Records/FeedRecord.swift FeedivoTests/FeedivoDatabaseMigratorTests.swift
git commit -m "Feature: Migration v23 - feeds.configUpdatedAt fuer Sync-Konfliktaufloesung (iCloud Sync Phase 2a Task 2)"
```

---

### Task 3: `CloudSyncRecordMapping`-Protokoll + Registry-Umbau von `CloudSyncEngine`

**Files:**
- Create: `Feedivo/Services/CloudSync/CloudSyncRecordMapping.swift`
- Modify: `Feedivo/Stores/CloudSyncPendingChangeStore.swift` (neue Methode `pendingChange(recordName:)`)
- Modify: `Feedivo/Services/CloudSync/CloudSyncEngine.swift` (Registry-Dispatch statt Tag-Hardcodierung)
- Modify: `Feedivo/Services/CloudSync/CloudSyncTagMapping.swift` (Konformität zum neuen Protokoll)
- Modify: `Feedivo/Stores/TagStore.swift:22` (`recordType: "tag"` → `CloudSyncTagMapping.recordType`)
- Test: `FeedivoTests/CloudSyncEngineRegistryTests.swift` (neu)

**Interfaces:**
- Produces: `protocol CloudSyncRecordMapping` mit `static var recordType: String`, `static func recordID(forLocalID:) -> CKRecord.ID`, `static func makeCKRecord(fromLocalID:database:) throws -> CKRecord?`, `static func applyIncoming(_:database:) throws`, `static func applyIncomingDeletion(recordID:database:) throws`, `static func localUpdatedAt(forLocalID:database:) throws -> Date?`. `CloudSyncPendingChangeStore.pendingChange(recordName:) throws -> CloudSyncPendingChangeRecord?`.
- Consumes: nichts aus späteren Tasks — dieser Task ist reine Infrastruktur, verhält sich für Tags identisch zu Phase 1 (verifiziert über die bestehende Test-Suite `CloudSyncTagMappingTests`/`CloudSyncPendingChangeStoreTests`/`SQLiteTagStoreTests`, die unverändert grün bleiben müssen).

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import CloudKit
import Testing
@testable import Feedivo

struct CloudSyncEngineRegistryTests {
    @Test func registryLoestTagRecordTypeAufCloudSyncTagMappingAuf() {
        let mapping = CloudSyncEngine.mapping(forRecordType: "Tag")

        #expect(mapping is CloudSyncTagMapping.Type)
    }

    @Test func registryLiefertNilFuerUnbekanntenRecordType() {
        let mapping = CloudSyncEngine.mapping(forRecordType: "UnknownType")

        #expect(mapping == nil)
    }

    @Test func sortiertModificationsSoDassElternRecordsVorKindRecordsStehen() {
        let feedRecord = CKRecord(recordType: "RuleCondition", recordID: CKRecord.ID(recordName: "cond-1"))
        let ruleRecord = CKRecord(recordType: "Rule", recordID: CKRecord.ID(recordName: "rule-1"))
        let unsorted = [feedRecord, ruleRecord]

        let sorted = CloudSyncEngine.sortedByDependencyOrder(unsorted)

        #expect(sorted.map(\.recordType) == ["Rule", "RuleCondition"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CloudSyncEngineRegistryTests 2>&1 | tail -40`
Expected: FAIL — `CloudSyncEngine.mapping(forRecordType:)` und `CloudSyncEngine.sortedByDependencyOrder(_:)` existieren noch nicht (Compile-Fehler).

- [ ] **Step 3: Create `CloudSyncRecordMapping.swift`**

```swift
import Foundation
import CloudKit

/// Kontrakt für die Übersetzung zwischen einer lokalen GRDB-Zeile und einem `CKRecord`.
/// Ein konformer Typ pro syncbarer Tabelle — analog zum bestehenden `CloudSyncTagMapping`
/// (Phase 1), aber generisch abrufbar über `CloudSyncEngine`s Registry statt hart verdrahtet.
/// Alle Methoden sind statisch (die Konformität liegt auf einem `enum`/leeren `struct` pro
/// Tabelle, keine Instanzen nötig) — dadurch als Existential `any CloudSyncRecordMapping.Type`
/// in einer `[String: any CloudSyncRecordMapping.Type]`-Registry ablegbar.
protocol CloudSyncRecordMapping {
    /// CKRecord-Typname, z. B. `"Tag"`, `"Feed"`, `"RuleCondition"`. Dient gleichzeitig als
    /// Schlüssel in `CloudSyncPendingChangeRecord.recordType` — beide müssen denselben
    /// String-Raum teilen (siehe Migration v22, Task 1).
    static var recordType: String { get }

    /// CKRecord-ID für eine gegebene lokale ID, immer in der gemeinsamen `"FeedivoZone"`.
    static func recordID(forLocalID id: String) -> CKRecord.ID

    /// Lädt die aktuelle lokale Zeile und mapped sie zu einem `CKRecord` (für den Upload).
    /// Liefert `nil`, falls die Zeile lokal nicht mehr existiert (z. B. zwischenzeitlich
    /// gelöscht, aber noch in der Pending-Changes-Warteschlange).
    static func makeCKRecord(fromLocalID id: String, database: FeedivoDatabase) throws -> CKRecord?

    /// Übernimmt ein eingehendes `CKRecord` in die lokale Datenbank (Upsert).
    static func applyIncoming(_ record: CKRecord, database: FeedivoDatabase) throws

    /// Löscht die lokale Zeile mit dieser `recordID`, falls sie in DIESER Tabelle existiert.
    /// No-Op (kein Fehler), falls keine passende Zeile existiert — `CloudSyncEngine` ruft dies
    /// für ALLE registrierten Mappings auf, da eine eingehende `CKRecord.ID`-Löschung den
    /// Tabellennamen nicht mitträgt (alle Typen teilen sich dieselbe Zone). Lokale IDs sind
    /// UUIDs, Kollisionen über Tabellen hinweg praktisch ausgeschlossen.
    static func applyIncomingDeletion(recordID: CKRecord.ID, database: FeedivoDatabase) throws

    /// Lokaler Änderungszeitpunkt für die Last-Write-Wins-Konfliktauflösung, `nil` falls die
    /// Zeile nicht mehr existiert.
    static func localUpdatedAt(forLocalID id: String, database: FeedivoDatabase) throws -> Date?
}

extension CloudSyncRecordMapping {
    static func recordID(forLocalID id: String) -> CKRecord.ID {
        CKRecord.ID(recordName: id, zoneID: CKRecordZone.ID(zoneName: "FeedivoZone", ownerName: CKCurrentUserDefaultName))
    }
}
```

- [ ] **Step 4: Refactor `CloudSyncTagMapping` to conform**

In `Feedivo/Services/CloudSync/CloudSyncTagMapping.swift`, Konformität + die drei Protokoll-Methoden ergänzen, die vorher direkt in `CloudSyncEngine` lagen:

```swift
enum CloudSyncTagMapping: CloudSyncRecordMapping {
    static let recordType = "Tag"
    static let zoneName = "FeedivoZone"

    // ... bestehende `zoneID()`, `recordID(forTagID:)`, `makeCKRecord(from:existing:)`,
    // `tagRecord(from:)` bleiben UNVERÄNDERT ...

    static func recordID(forLocalID id: String) -> CKRecord.ID {
        recordID(forTagID: id)
    }

    static func makeCKRecord(fromLocalID id: String, database: FeedivoDatabase) throws -> CKRecord? {
        let tags = try TagStore(database: database).tags()
        guard let tag = tags.first(where: { $0.id == id }) else { return nil }
        return makeCKRecord(from: tag)
    }

    static func applyIncoming(_ record: CKRecord, database: FeedivoDatabase) throws {
        guard var incoming = tagRecord(from: record) else { return }
        try database.write { db in
            try incoming.save(db)
        }
    }

    static func applyIncomingDeletion(recordID: CKRecord.ID, database: FeedivoDatabase) throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM tags WHERE id = ?", arguments: [recordID.recordName])
        }
    }

    static func localUpdatedAt(forLocalID id: String, database: FeedivoDatabase) throws -> Date? {
        try TagStore(database: database).tags().first(where: { $0.id == id })?.updatedAt
    }
}
```

- [ ] **Step 5: Add `pendingChange(recordName:)` to `CloudSyncPendingChangeStore`**

In `Feedivo/Stores/CloudSyncPendingChangeStore.swift`, nach `pendingChanges()`:

```swift
    /// Liefert die Pending-Change-Zeile für eine einzelne `recordName`, falls vorhanden — nötig,
    /// um beim Ausliefern eines ausstehenden Batches (`nextRecordZoneChangeBatch`) den
    /// `recordType` zu einer bloßen `CKRecord.ID` zu ermitteln (die ID selbst trägt den Typ
    /// nicht mit).
    func pendingChange(recordName: String) throws -> CloudSyncPendingChangeRecord? {
        try database.read { db in
            try CloudSyncPendingChangeRecord.fetchOne(db, sql: """
                SELECT * FROM cloud_sync_pending_changes WHERE id = ?
                """, arguments: [recordName])
        }
    }
```

- [ ] **Step 6: Rewrite `CloudSyncEngine` to dispatch via registry**

In `Feedivo/Services/CloudSync/CloudSyncEngine.swift`, Registry + statische Hilfsfunktionen ergänzen und die Tag-spezifischen Methoden durch generische Dispatch-Varianten ersetzen:

```swift
    /// Registry aller syncbaren Tabellen, Schlüssel = `CloudSyncRecordMapping.recordType`.
    /// Erweitert in den Folge-Tasks um Feed/FeedFolder/Rule/RuleCondition/SmartFolder/
    /// SmartFolderCondition.
    private static let registry: [String: any CloudSyncRecordMapping.Type] = [
        CloudSyncTagMapping.recordType: CloudSyncTagMapping.self
    ]

    static func mapping(forRecordType recordType: String) -> (any CloudSyncRecordMapping.Type)? {
        registry[recordType]
    }

    /// Sortiert eingehende Records so, dass "Eltern"-Typen (die von keiner anderen Tabelle per
    /// Fremdschlüssel referenziert werden) vor ihren "Kind"-Typen stehen — `rule_conditions`/
    /// `smart_folder_conditions` haben einen `ON DELETE CASCADE`-Fremdschlüssel auf ihre
    /// Elterntabelle UND `PRAGMA foreign_keys = ON` ist aktiv (`FeedivoDatabase.swift`). Träfe
    /// eine Bedingungszeile lokal ein, BEVOR ihre Regel/ihr Intelligenter Ordner existiert,
    /// würde der Insert mit einem Fremdschlüssel-Fehler scheitern. `CKSyncEngine` garantiert
    /// innerhalb eines Batches keine Reihenfolge — dieses Sortieren deckt den Normalfall ab
    /// (Eltern + Kinder werden zusammen bearbeitet und kommen im selben Batch an).
    private static let childRecordTypes: Set<String> = ["RuleCondition", "SmartFolderCondition"]

    static func sortedByDependencyOrder(_ records: [CKRecord]) -> [CKRecord] {
        records.sorted { lhs, rhs in
            let lhsIsChild = childRecordTypes.contains(lhs.recordType)
            let rhsIsChild = childRecordTypes.contains(rhs.recordType)
            if lhsIsChild == rhsIsChild { return false }
            return !lhsIsChild
        }
    }
```

Ersetze `applyIncomingRecord`/`applyIncomingDeletion`/`record(forPendingChange:)`/`handleFailedSave` durch die generischen Varianten:

```swift
    private func record(forPendingChange recordID: CKRecord.ID) async -> CKRecord? {
        guard
            let pendingChange = try? pendingChangeStore.pendingChange(recordName: recordID.recordName),
            let mapping = Self.mapping(forRecordType: pendingChange.recordType)
        else {
            return nil
        }
        do {
            return try mapping.makeCKRecord(fromLocalID: recordID.recordName, database: database)
        } catch {
            AppLogger.dataAccess.error("iCloud Sync: CKRecord fuer ausstehende Aenderung konnte nicht gebaut werden: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func applyIncomingRecord(_ record: CKRecord) async {
        guard let mapping = Self.mapping(forRecordType: record.recordType) else { return }
        do {
            try mapping.applyIncoming(record, database: database)
        } catch {
            AppLogger.dataAccess.error("iCloud Sync: Eingehender \(record.recordType, privacy: .public)-Record konnte nicht gespeichert werden: \(error.localizedDescription, privacy: .public)")
            return
        }
        SQLiteDataInvalidation.bumpStatusVersion()
    }

    private func applyIncomingDeletion(_ recordID: CKRecord.ID) async {
        for mapping in Self.registry.values {
            do {
                try mapping.applyIncomingDeletion(recordID: recordID, database: database)
            } catch {
                AppLogger.dataAccess.error("iCloud Sync: Eingehende Loeschung (\(mapping.recordType, privacy: .public)) fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            }
        }
        SQLiteDataInvalidation.bumpStatusVersion()
    }
```

`handleEvent(.fetchedRecordZoneChanges:)` nutzt die Sortierung:

```swift
        case .fetchedRecordZoneChanges(let changes):
            for modification in Self.sortedByDependencyOrder(changes.modifications.map(\.record)) {
                await applyIncomingRecord(modification)
            }
            for deletion in changes.deletions {
                await applyIncomingDeletion(deletion.recordID)
            }
```

`handleFailedSave` generisch:

```swift
    private func handleFailedSave(_ failedSave: CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave) async {
        guard failedSave.error.code == .serverRecordChanged else {
            status.state = .error(failedSave.error.localizedDescription)
            AppLogger.dataAccess.error("iCloud Sync: Record-Save fehlgeschlagen: \(failedSave.error.localizedDescription, privacy: .public)")
            return
        }

        guard let serverRecord = failedSave.error.serverRecord,
              let mapping = Self.mapping(forRecordType: failedSave.record.recordType)
        else { return }

        let localUpdatedAt: Date?
        do {
            localUpdatedAt = try mapping.localUpdatedAt(forLocalID: failedSave.record.recordID.recordName, database: database)
        } catch {
            AppLogger.dataAccess.error("iCloud Sync: Lokaler Stand fuer Konfliktaufloesung konnte nicht geladen werden: \(error.localizedDescription, privacy: .public)")
            return
        }

        let serverIsNewer = (serverRecord.modificationDate ?? .distantPast) > (localUpdatedAt ?? .distantPast)

        if serverIsNewer {
            await applyIncomingRecord(serverRecord)
        } else {
            do {
                try pendingChangeStore.enqueue(recordType: mapping.recordType, recordName: failedSave.record.recordID.recordName, changeType: .save)
                Self.notifyPendingChangesAvailable(database: database)
            } catch {
                AppLogger.dataAccess.error("iCloud Sync: Erneuter Sync-Versuch nach Konflikt konnte nicht eingeplant werden: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
```

`notifyPendingChangesAvailable` dispatcht `recordID` jetzt über die Registry statt fest `CloudSyncTagMapping`:

```swift
        let changes: [CKSyncEngine.PendingRecordZoneChange] = pending.compactMap { change in
            guard let mapping = Self.mapping(forRecordType: change.recordType) else { return nil }
            let recordID = mapping.recordID(forLocalID: change.id)
            switch change.changeType {
            case .save:
                return .saveRecord(recordID)
            case .delete:
                return .deleteRecord(recordID)
            }
        }
```

- [ ] **Step 7: Fix the stale `"tag"` literal in `TagStore`**

In `Feedivo/Stores/TagStore.swift:22`, ändere:

```swift
        try CloudSyncPendingChangeStore.enqueue(db, recordType: CloudSyncTagMapping.recordType, recordName: tagID, changeType: changeType)
```

(vorher: `recordType: "tag"`)

- [ ] **Step 8: Run the new tests plus the existing Phase-1 CloudSync suite to verify no regression**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CloudSyncEngineRegistryTests -only-testing:FeedivoTests/CloudSyncTagMappingTests -only-testing:FeedivoTests/CloudSyncPendingChangeStoreTests -only-testing:FeedivoTests/CloudSyncSettingsTests -only-testing:FeedivoTests/SQLiteTagStoreTests -parallel-testing-enabled NO 2>&1 | tail -60`
Expected: alle PASS — Tag-Verhalten unverändert (behavior-preserving refactor).

- [ ] **Step 9: Full build**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -60`
Expected: BUILD SUCCEEDED

- [ ] **Step 10: Commit**

```bash
git add Feedivo/Services/CloudSync/CloudSyncRecordMapping.swift Feedivo/Services/CloudSync/CloudSyncEngine.swift Feedivo/Services/CloudSync/CloudSyncTagMapping.swift Feedivo/Stores/CloudSyncPendingChangeStore.swift Feedivo/Stores/TagStore.swift FeedivoTests/CloudSyncEngineRegistryTests.swift
git commit -m "Feature: CloudSyncRecordMapping-Protokoll + Registry-Umbau von CloudSyncEngine (iCloud Sync Phase 2a Task 3)"
```

---

### Task 4: `CloudSyncFeedMapping` + `FeedStore`-Wiring

**Files:**
- Create: `Feedivo/Services/CloudSync/CloudSyncFeedMapping.swift`
- Modify: `Feedivo/Stores/FeedStore.swift` (7 Konfigurations-Mutationsmethoden + `save`/`delete`)
- Modify: `Feedivo/Services/CloudSync/CloudSyncEngine.swift` (Registry-Eintrag `"Feed"`)
- Test: `FeedivoTests/CloudSyncFeedMappingTests.swift` (neu)
- Test: `FeedivoTests/SQLiteFeedStoreTests.swift` (Ergänzung um Requeue-Tests)

**Interfaces:**
- Consumes: `CloudSyncRecordMapping` (Task 3), `CloudSyncPendingChangeStore.enqueue(_:recordType:recordName:changeType:)` (bestehend), `CloudSyncEngine.notifyPendingChangesAvailable(database:)` (bestehend).
- Produces: `CloudSyncFeedMapping.recordType == "Feed"`, registriert in `CloudSyncEngine.registry`.

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import CloudKit
import Testing
@testable import Feedivo

struct CloudSyncFeedMappingTests {
    @Test func makeCKRecordMapptNurKonfigurationsfelder() {
        let feed = FeedRecord(
            id: "feed-1",
            url: "https://example.com/feed",
            title: "Beispiel",
            websiteURL: "https://example.com",
            folderName: "Tech",
            sortIndex: 2,
            refreshIntervalMinutes: 60,
            isNotificationEnabled: true,
            articleRetentionOverridesGlobalSetting: true,
            articleRetentionIsEnabled: true,
            articleRetentionDays: 30,
            articleRetentionMinimumArticles: 10,
            articleRetentionIncludesProtectedArticles: true,
            lastETag: "sollte-nicht-synct-werden",
            unreadCount: 42
        )

        let record = CloudSyncFeedMapping.makeCKRecord(from: feed)

        #expect(record.recordType == "Feed")
        #expect(record["url"] as? String == "https://example.com/feed")
        #expect(record["folderName"] as? String == "Tech")
        #expect(record["refreshIntervalMinutes"] as? Int == 60)
        #expect(record["articleRetentionDays"] as? Int == 30)
        #expect(record.allKeys().contains("lastETag") == false)
        #expect(record.allKeys().contains("unreadCount") == false)
    }

    @Test func feedConfigFromCKRecordLiefertNilBeiFehlendenPflichtfeldern() {
        let ckRecord = CKRecord(recordType: "Feed", recordID: CloudSyncFeedMapping.recordID(forLocalID: "feed-1"))

        #expect(CloudSyncFeedMapping.feedConfig(from: ckRecord) == nil)
    }

    @Test func feedConfigFromCKRecordMapptZurueck() {
        let feed = FeedRecord(id: "feed-1", url: "https://example.com/feed", title: "Beispiel", sortIndex: 1, refreshIntervalMinutes: 45)
        let record = CloudSyncFeedMapping.makeCKRecord(from: feed)

        let config = CloudSyncFeedMapping.feedConfig(from: record)

        #expect(config?.url == "https://example.com/feed")
        #expect(config?.refreshIntervalMinutes == 45)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CloudSyncFeedMappingTests 2>&1 | tail -40`
Expected: FAIL — `CloudSyncFeedMapping` existiert nicht.

- [ ] **Step 3: Create `CloudSyncFeedMapping.swift`**

```swift
import Foundation
import CloudKit

/// Mapping für die syncbare TEILMENGE der `feeds`-Tabelle. NUR Konfigurationsfelder syncen —
/// Refresh-Metadaten (`lastRefreshedAt`/`lastETag`/`lastModified`/`lastBodyHash`/
/// `lastHTTPStatusCode`) und `unreadCount` bleiben bewusst rein lokal (siehe Design-Spec
/// `docs/superpowers/specs/2026-07-24-icloud-sync-phase2a-design.md`).
enum CloudSyncFeedMapping: CloudSyncRecordMapping {
    static let recordType = "Feed"

    /// Reine, aus einem `CKRecord` gelesene Konfigurationswerte — Zwischenformat für
    /// `applyIncoming`, das zwischen "Feed existiert lokal bereits" (partielles UPDATE) und
    /// "Feed ist neu für dieses Gerät" (voller INSERT) unterscheiden muss.
    struct FeedConfig {
        let url: String
        let title: String
        let originalTitle: String?
        let websiteURL: String?
        let faviconURL: String?
        let folderName: String?
        let sortIndex: Int
        let refreshIntervalMinutes: Int
        let isNotificationEnabled: Bool
        let articleRetentionOverridesGlobalSetting: Bool
        let articleRetentionIsEnabled: Bool
        let articleRetentionDays: Int
        let articleRetentionMinimumArticles: Int
        let articleRetentionIncludesProtectedArticles: Bool
    }

    static func makeCKRecord(from feed: FeedRecord, existing: CKRecord? = nil) -> CKRecord {
        let record = existing ?? CKRecord(recordType: recordType, recordID: recordID(forLocalID: feed.id))
        record["url"] = feed.url as CKRecordValue
        record["title"] = feed.title as CKRecordValue
        record["originalTitle"] = feed.originalTitle as CKRecordValue?
        record["websiteURL"] = feed.websiteURL as CKRecordValue?
        record["faviconURL"] = feed.faviconURL as CKRecordValue?
        record["folderName"] = feed.folderName as CKRecordValue?
        record["sortIndex"] = feed.sortIndex as CKRecordValue
        record["refreshIntervalMinutes"] = feed.refreshIntervalMinutes as CKRecordValue
        record["isNotificationEnabled"] = feed.isNotificationEnabled as CKRecordValue
        record["articleRetentionOverridesGlobalSetting"] = feed.articleRetentionOverridesGlobalSetting as CKRecordValue
        record["articleRetentionIsEnabled"] = feed.articleRetentionIsEnabled as CKRecordValue
        record["articleRetentionDays"] = feed.articleRetentionDays as CKRecordValue
        record["articleRetentionMinimumArticles"] = feed.articleRetentionMinimumArticles as CKRecordValue
        record["articleRetentionIncludesProtectedArticles"] = feed.articleRetentionIncludesProtectedArticles as CKRecordValue
        return record
    }

    static func feedConfig(from ckRecord: CKRecord) -> FeedConfig? {
        guard
            let url = ckRecord["url"] as? String,
            let title = ckRecord["title"] as? String,
            let sortIndex = ckRecord["sortIndex"] as? Int,
            let refreshIntervalMinutes = ckRecord["refreshIntervalMinutes"] as? Int,
            let isNotificationEnabled = ckRecord["isNotificationEnabled"] as? Bool,
            let overridesGlobal = ckRecord["articleRetentionOverridesGlobalSetting"] as? Bool,
            let retentionIsEnabled = ckRecord["articleRetentionIsEnabled"] as? Bool,
            let retentionDays = ckRecord["articleRetentionDays"] as? Int,
            let retentionMinimumArticles = ckRecord["articleRetentionMinimumArticles"] as? Int,
            let retentionIncludesProtected = ckRecord["articleRetentionIncludesProtectedArticles"] as? Bool
        else {
            return nil
        }

        return FeedConfig(
            url: url,
            title: title,
            originalTitle: ckRecord["originalTitle"] as? String,
            websiteURL: ckRecord["websiteURL"] as? String,
            faviconURL: ckRecord["faviconURL"] as? String,
            folderName: ckRecord["folderName"] as? String,
            sortIndex: sortIndex,
            refreshIntervalMinutes: refreshIntervalMinutes,
            isNotificationEnabled: isNotificationEnabled,
            articleRetentionOverridesGlobalSetting: overridesGlobal,
            articleRetentionIsEnabled: retentionIsEnabled,
            articleRetentionDays: retentionDays,
            articleRetentionMinimumArticles: retentionMinimumArticles,
            articleRetentionIncludesProtectedArticles: retentionIncludesProtected
        )
    }

    static func makeCKRecord(fromLocalID id: String, database: FeedivoDatabase) throws -> CKRecord? {
        guard let feed = try FeedStore(database: database).feed(id: id) else { return nil }
        return makeCKRecord(from: feed)
    }

    static func applyIncoming(_ record: CKRecord, database: FeedivoDatabase) throws {
        guard let config = feedConfig(from: record) else { return }
        let localID = record.recordID.recordName
        let modificationDate = record.modificationDate ?? Date()

        try database.write { db in
            let exists = try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM feeds WHERE id = ?)", arguments: [localID]) ?? false

            if exists {
                try db.execute(
                    sql: """
                        UPDATE feeds
                        SET url = ?, title = ?, originalTitle = ?, websiteURL = ?, faviconURL = ?,
                            folderName = ?, sortIndex = ?, refreshIntervalMinutes = ?,
                            isNotificationEnabled = ?, articleRetentionOverridesGlobalSetting = ?,
                            articleRetentionIsEnabled = ?, articleRetentionDays = ?,
                            articleRetentionMinimumArticles = ?, articleRetentionIncludesProtectedArticles = ?,
                            configUpdatedAt = ?
                        WHERE id = ?
                        """,
                    arguments: [
                        config.url, config.title, config.originalTitle, config.websiteURL, config.faviconURL,
                        config.folderName, config.sortIndex, config.refreshIntervalMinutes,
                        config.isNotificationEnabled, config.articleRetentionOverridesGlobalSetting,
                        config.articleRetentionIsEnabled, config.articleRetentionDays,
                        config.articleRetentionMinimumArticles, config.articleRetentionIncludesProtectedArticles,
                        modificationDate, localID
                    ]
                )
            } else {
                var newFeed = FeedRecord(
                    id: localID,
                    url: config.url,
                    title: config.title,
                    originalTitle: config.originalTitle,
                    websiteURL: config.websiteURL,
                    faviconURL: config.faviconURL,
                    folderName: config.folderName,
                    sortIndex: config.sortIndex,
                    refreshIntervalMinutes: config.refreshIntervalMinutes,
                    isNotificationEnabled: config.isNotificationEnabled,
                    articleRetentionOverridesGlobalSetting: config.articleRetentionOverridesGlobalSetting,
                    articleRetentionIsEnabled: config.articleRetentionIsEnabled,
                    articleRetentionDays: config.articleRetentionDays,
                    articleRetentionMinimumArticles: config.articleRetentionMinimumArticles,
                    articleRetentionIncludesProtectedArticles: config.articleRetentionIncludesProtectedArticles,
                    configUpdatedAt: modificationDate
                )
                try newFeed.insert(db)
            }
        }
    }

    static func applyIncomingDeletion(recordID: CKRecord.ID, database: FeedivoDatabase) throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM feeds WHERE id = ?", arguments: [recordID.recordName])
        }
    }

    static func localUpdatedAt(forLocalID id: String, database: FeedivoDatabase) throws -> Date? {
        try FeedStore(database: database).feed(id: id)?.configUpdatedAt
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CloudSyncFeedMappingTests 2>&1 | tail -40`
Expected: PASS

- [ ] **Step 5: Wire `FeedStore`'s config-mutating methods**

In `Feedivo/Stores/FeedStore.swift`, füge einen privaten Helfer analog zu `TagStore.enqueuePendingSync` hinzu (nach `init`):

```swift
    private func enqueuePendingSync(_ db: Database, feedID: String, changeType: CloudSyncChangeType) throws {
        guard CloudSyncSettings.isEnabled() else { return }
        try CloudSyncPendingChangeStore.enqueue(db, recordType: CloudSyncFeedMapping.recordType, recordName: feedID, changeType: changeType)
    }
```

Ändere `save(_:)`, `renameFeed`, `updateRefreshInterval`, `updateFolderName`, `updateNotificationEnabled`, `updateRetentionSettings`, `moveFeed` und `delete(id:)` so, dass sie zusätzlich `configUpdatedAt` setzen (statt/zusätzlich zu `updatedAt`) und die Änderung enqueuen. Beispiel für `renameFeed`:

```swift
    func renameFeed(id: String, displayTitle: String) throws {
        let title = displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw FeedStoreError.emptyTitle
        }

        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE feeds
                    SET title = ?,
                        originalTitle = COALESCE(NULLIF(originalTitle, ''), title),
                        updatedAt = ?,
                        configUpdatedAt = ?
                    WHERE id = ?
                    """,
                arguments: [title, Date(), Date(), id]
            )

            if db.changesCount == 0 {
                throw FeedStoreError.missingFeed
            }

            try enqueuePendingSync(db, feedID: id, changeType: .save)
        }
        CloudSyncEngine.notifyPendingChangesAvailable(database: database)
    }
```

Dasselbe Muster (zusätzliches `configUpdatedAt = ?` in der SQL-`SET`-Klausel, zusätzliches `Date()`-Argument, `try enqueuePendingSync(db, feedID: id, changeType: .save)` vor Ende des `db.write`-Blocks, `CloudSyncEngine.notifyPendingChangesAvailable(database: database)` nach dem `db.write`-Block) auf die übrigen fünf Methoden angewendet:

```swift
    func restoreOriginalTitle(id: String) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE feeds
                    SET title = COALESCE(NULLIF(originalTitle, ''), title),
                        updatedAt = ?,
                        configUpdatedAt = ?
                    WHERE id = ?
                    """,
                arguments: [Date(), Date(), id]
            )

            if db.changesCount == 0 {
                throw FeedStoreError.missingFeed
            }

            try enqueuePendingSync(db, feedID: id, changeType: .save)
        }
        CloudSyncEngine.notifyPendingChangesAvailable(database: database)
    }

    func updateRefreshInterval(id: String, minutes: Int) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE feeds
                    SET refreshIntervalMinutes = ?, updatedAt = ?, configUpdatedAt = ?
                    WHERE id = ?
                    """,
                arguments: [BackgroundRefreshSettings.clampedIntervalMinutes(minutes), Date(), Date(), id]
            )

            if db.changesCount == 0 {
                throw FeedStoreError.missingFeed
            }

            try enqueuePendingSync(db, feedID: id, changeType: .save)
        }
        CloudSyncEngine.notifyPendingChangesAvailable(database: database)
    }

    func updateFolderName(id: String, folderName: String?) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE feeds
                    SET folderName = ?, updatedAt = ?, configUpdatedAt = ?
                    WHERE id = ?
                    """,
                arguments: [FeedFolderOrganizer.normalizedFolderName(folderName), Date(), Date(), id]
            )

            if db.changesCount == 0 {
                throw FeedStoreError.missingFeed
            }

            try enqueuePendingSync(db, feedID: id, changeType: .save)
        }
        CloudSyncEngine.notifyPendingChangesAvailable(database: database)
    }

    func updateNotificationEnabled(id: String, isEnabled: Bool) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE feeds
                    SET isNotificationEnabled = ?, updatedAt = ?, configUpdatedAt = ?
                    WHERE id = ?
                    """,
                arguments: [isEnabled, Date(), Date(), id]
            )

            if db.changesCount == 0 {
                throw FeedStoreError.missingFeed
            }

            try enqueuePendingSync(db, feedID: id, changeType: .save)
        }
        CloudSyncEngine.notifyPendingChangesAvailable(database: database)
    }

    func updateRetentionSettings(
        id: String,
        overridesGlobal: Bool,
        isEnabled: Bool,
        days: Int,
        minimumArticles: Int,
        includesProtectedArticles: Bool
    ) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE feeds
                    SET articleRetentionOverridesGlobalSetting = ?,
                        articleRetentionIsEnabled = ?,
                        articleRetentionDays = ?,
                        articleRetentionMinimumArticles = ?,
                        articleRetentionIncludesProtectedArticles = ?,
                        updatedAt = ?,
                        configUpdatedAt = ?
                    WHERE id = ?
                    """,
                arguments: [
                    overridesGlobal,
                    isEnabled,
                    ArticleRetentionSettings.clampedRetentionDays(days),
                    ArticleRetentionSettings.clampedMinimumArticlesPerFeed(minimumArticles),
                    includesProtectedArticles,
                    Date(),
                    Date(),
                    id
                ]
            )

            if db.changesCount == 0 {
                throw FeedStoreError.missingFeed
            }

            try enqueuePendingSync(db, feedID: id, changeType: .save)
        }
        CloudSyncEngine.notifyPendingChangesAvailable(database: database)
    }
```

Für `moveFeed` (reorder über mehrere Feeds hinweg) enqueue JEDEN umsortierten Feed (analog `TagStore.move()`), da `sortIndex` Teil des Sync-Scopes ist:

```swift
    func moveFeed(id: String, toFolderName: String?, targetIndex: Int) throws {
        let trimmedFolderName = toFolderName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveFolderName = (trimmedFolderName?.isEmpty ?? true) ? nil : trimmedFolderName

        try database.write { db in
            // ... bestehende otherFeedIDs-Ermittlung unverändert ...

            var orderedIDs = otherFeedIDs
            let clampedIndex = min(max(targetIndex, 0), orderedIDs.count)
            orderedIDs.insert(id, at: clampedIndex)

            let now = Date()
            for (index, feedID) in orderedIDs.enumerated() {
                if feedID == id {
                    try db.execute(
                        sql: """
                            UPDATE feeds
                            SET sortIndex = ?, folderName = ?, updatedAt = ?, configUpdatedAt = ?
                            WHERE id = ?
                            """,
                        arguments: [index, effectiveFolderName, now, now, feedID]
                    )
                } else {
                    try db.execute(
                        sql: "UPDATE feeds SET sortIndex = ?, configUpdatedAt = ? WHERE id = ?",
                        arguments: [index, now, feedID]
                    )
                }
                try enqueuePendingSync(db, feedID: feedID, changeType: .save)
            }
        }
        CloudSyncEngine.notifyPendingChangesAvailable(database: database)
    }
```

`save(_:)` (Feed-Neuanlage) und `delete(id:)`:

```swift
    func save(_ feed: FeedRecord) throws {
        try database.write { db in
            var feed = feed
            try feed.save(db)
            try enqueuePendingSync(db, feedID: feed.id, changeType: .save)
        }
        CloudSyncEngine.notifyPendingChangesAvailable(database: database)
    }

    func delete(id: String) throws {
        try database.write { db in
            try enqueuePendingSync(db, feedID: id, changeType: .delete)
            try db.execute(
                sql: """
                    DELETE FROM feeds
                    WHERE id = ?
                    """,
                arguments: [id]
            )
        }
        CloudSyncEngine.notifyPendingChangesAvailable(database: database)
    }
```

`updateAfterRefresh` und `setUnreadCount` bleiben **UNVERÄNDERT** — reine lokale Refresh-Metadaten, kein Sync.

- [ ] **Step 6: Register `"Feed"` in `CloudSyncEngine`**

In `Feedivo/Services/CloudSync/CloudSyncEngine.swift`, Registry erweitern:

```swift
    private static let registry: [String: any CloudSyncRecordMapping.Type] = [
        CloudSyncTagMapping.recordType: CloudSyncTagMapping.self,
        CloudSyncFeedMapping.recordType: CloudSyncFeedMapping.self
    ]
```

- [ ] **Step 7: Write and run the requeue regression test**

Ergänze in `FeedivoTests/SQLiteFeedStoreTests.swift` (Datei-/Hilfsfunktionsnamen zuvor per Read gegen die tatsächliche Datei verifizieren, nicht raten):

```swift
    @Test func moveFeedMarkiertAlleUmsortiertenFeedsAlsPendingSync() throws {
        let database = try makeTestDatabase()
        CloudSyncSettings.setEnabled(true)
        defer { CloudSyncSettings.setEnabled(false) }

        let store = FeedStore(database: database)
        let feedA = FeedRecord(id: "feed-a", url: "https://a.example.com", title: "A", sortIndex: 0)
        let feedB = FeedRecord(id: "feed-b", url: "https://b.example.com", title: "B", sortIndex: 1)
        try store.save(feedA)
        try store.save(feedB)

        try store.moveFeed(id: "feed-b", toFolderName: nil, targetIndex: 0)

        let pendingChangeStore = CloudSyncPendingChangeStore(database: database)
        let pendingIDs = Set(try pendingChangeStore.pendingChanges().map(\.id))
        #expect(pendingIDs.contains("feed-a"))
        #expect(pendingIDs.contains("feed-b"))
    }
```

> Prüfe per Read, ob `CloudSyncSettings` bereits `setEnabled(_:)` als Test-Hilfsmethode anbietet (wird bereits von `CloudSyncSettingsTests.swift` genutzt) — falls der Name abweicht, an die tatsächliche API anpassen. Prüfe ebenso den exakten Namen der bestehenden Test-DB-Hilfsfunktion (per `grep -rn "func makeTestDatabase\|DatabaseQueue()" FeedivoTests/SQLiteTagStoreTests.swift` das tatsächlich verwendete Muster übernehmen).

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedStoreTests -only-testing:FeedivoTests/CloudSyncFeedMappingTests -parallel-testing-enabled NO 2>&1 | tail -60`
Expected: PASS

- [ ] **Step 8: Full build**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -60`
Expected: BUILD SUCCEEDED

- [ ] **Step 9: Commit**

```bash
git add Feedivo/Services/CloudSync/CloudSyncFeedMapping.swift Feedivo/Services/CloudSync/CloudSyncEngine.swift Feedivo/Stores/FeedStore.swift FeedivoTests/CloudSyncFeedMappingTests.swift FeedivoTests/SQLiteFeedStoreTests.swift
git commit -m "Feature: Feed-Sync (CloudSyncFeedMapping + FeedStore-Wiring, iCloud Sync Phase 2a Task 4)"
```

---

### Task 5: `CloudSyncFeedFolderMapping` + `FeedFolderStore`-Wiring (inkl. Requeue betroffener Feeds bei Umbenennung)

**Files:**
- Create: `Feedivo/Services/CloudSync/CloudSyncFeedFolderMapping.swift`
- Modify: `Feedivo/Stores/FeedFolderStore.swift` (`save`/`renameFolder`/`moveFolder`/`delete`/`sortAlphabetically`)
- Modify: `Feedivo/Services/CloudSync/CloudSyncEngine.swift` (Registry-Eintrag `"FeedFolder"`)
- Test: `FeedivoTests/CloudSyncFeedFolderMappingTests.swift` (neu)
- Test: existierende Test-Datei für `FeedFolderStore` (Name zuvor per `find FeedivoTests -iname "*FeedFolder*"` verifizieren), Ergänzung um Rename-requeued-Feeds-Test

**Interfaces:**
- Consumes: `CloudSyncRecordMapping` (Task 3), `CloudSyncFeedMapping.recordType` (Task 4, für den Feed-Requeue in `renameFolder`).
- Produces: `CloudSyncFeedFolderMapping.recordType == "FeedFolder"`.

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import CloudKit
import Testing
@testable import Feedivo

struct CloudSyncFeedFolderMappingTests {
    @Test func makeCKRecordMapptAlleFelder() {
        let folder = FeedFolderRecord(id: "folder-1", name: "Tech", sortIndex: 2)

        let record = CloudSyncFeedFolderMapping.makeCKRecord(from: folder)

        #expect(record.recordType == "FeedFolder")
        #expect(record["name"] as? String == "Tech")
        #expect(record["sortIndex"] as? Int == 2)
    }

    @Test func feedFolderRecordFromCKRecordMapptZurueck() {
        let folder = FeedFolderRecord(id: "folder-1", name: "Tech", sortIndex: 2)
        let record = CloudSyncFeedFolderMapping.makeCKRecord(from: folder)

        let mapped = CloudSyncFeedFolderMapping.feedFolderRecord(from: record)

        #expect(mapped?.id == "folder-1")
        #expect(mapped?.name == "Tech")
        #expect(mapped?.sortIndex == 2)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CloudSyncFeedFolderMappingTests 2>&1 | tail -40`
Expected: FAIL

- [ ] **Step 3: Create `CloudSyncFeedFolderMapping.swift`**

```swift
import Foundation
import CloudKit

/// Mapping für `feed_folders` — vollständiger Sync (keine lokal-only Felder, anders als Feeds).
enum CloudSyncFeedFolderMapping: CloudSyncRecordMapping {
    static let recordType = "FeedFolder"

    static func makeCKRecord(from folder: FeedFolderRecord, existing: CKRecord? = nil) -> CKRecord {
        let record = existing ?? CKRecord(recordType: recordType, recordID: recordID(forLocalID: folder.id))
        record["name"] = folder.name as CKRecordValue
        record["sortIndex"] = folder.sortIndex as CKRecordValue
        return record
    }

    static func feedFolderRecord(from ckRecord: CKRecord) -> FeedFolderRecord? {
        guard
            let name = ckRecord["name"] as? String,
            let sortIndex = ckRecord["sortIndex"] as? Int
        else {
            return nil
        }

        return FeedFolderRecord(
            id: ckRecord.recordID.recordName,
            name: name,
            sortIndex: sortIndex,
            createdAt: ckRecord.creationDate ?? Date(),
            updatedAt: ckRecord.modificationDate ?? Date()
        )
    }

    static func makeCKRecord(fromLocalID id: String, database: FeedivoDatabase) throws -> CKRecord? {
        let folders = try FeedFolderStore(database: database).folders()
        guard let folder = folders.first(where: { $0.id == id }) else { return nil }
        return makeCKRecord(from: folder)
    }

    static func applyIncoming(_ record: CKRecord, database: FeedivoDatabase) throws {
        guard var incoming = feedFolderRecord(from: record) else { return }
        try database.write { db in
            try incoming.save(db)
        }
    }

    static func applyIncomingDeletion(recordID: CKRecord.ID, database: FeedivoDatabase) throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM feed_folders WHERE id = ?", arguments: [recordID.recordName])
        }
    }

    static func localUpdatedAt(forLocalID id: String, database: FeedivoDatabase) throws -> Date? {
        try FeedFolderStore(database: database).folders().first(where: { $0.id == id })?.updatedAt
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CloudSyncFeedFolderMappingTests 2>&1 | tail -40`
Expected: PASS

- [ ] **Step 5: Wire `FeedFolderStore`**

In `Feedivo/Stores/FeedFolderStore.swift`, Helfer + Wiring:

```swift
    private func enqueuePendingSync(_ db: Database, folderID: String, changeType: CloudSyncChangeType) throws {
        guard CloudSyncSettings.isEnabled() else { return }
        try CloudSyncPendingChangeStore.enqueue(db, recordType: CloudSyncFeedFolderMapping.recordType, recordName: folderID, changeType: changeType)
    }

    private func enqueueFeedPendingSync(_ db: Database, feedID: String) throws {
        guard CloudSyncSettings.isEnabled() else { return }
        try CloudSyncPendingChangeStore.enqueue(db, recordType: CloudSyncFeedMapping.recordType, recordName: feedID, changeType: .save)
    }

    func save(_ folder: FeedFolderRecord) throws {
        try database.write { db in
            var folder = folder
            try folder.save(db)
            try enqueuePendingSync(db, folderID: folder.id, changeType: .save)
        }
        CloudSyncEngine.notifyPendingChangesAvailable(database: database)
    }

    func delete(id: String) throws {
        try database.write { db in
            try enqueuePendingSync(db, folderID: id, changeType: .delete)
            try db.execute(
                sql: """
                    DELETE FROM feed_folders
                    WHERE id = ?
                    """,
                arguments: [id]
            )
        }
        CloudSyncEngine.notifyPendingChangesAvailable(database: database)
    }
```

`renameFolder` — zusätzlich ALLE betroffenen Feeds requeuen (der Grund, siehe Design-Spec: `folderName` lebt nur auf dem Feed-Record):

```swift
    func renameFolder(from oldName: String, to newName: String) throws {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            throw FeedFolderRenameError.emptyName
        }

        try database.write { db in
            // ... bestehende Kollisionsprüfung unverändert ...

            let affectedFeedIDs = try String.fetchAll(
                db,
                sql: "SELECT id FROM feeds WHERE folderName = ? COLLATE NOCASE",
                arguments: [oldName]
            )

            try db.execute(
                sql: """
                    UPDATE feeds
                    SET folderName = ?, configUpdatedAt = ?
                    WHERE folderName = ? COLLATE NOCASE
                    """,
                arguments: [trimmedName, Date(), oldName]
            )

            for feedID in affectedFeedIDs {
                try enqueueFeedPendingSync(db, feedID: feedID)
            }

            try db.execute(
                sql: """
                    UPDATE feed_folders
                    SET name = ?, updatedAt = ?
                    WHERE name = ? COLLATE NOCASE
                    """,
                arguments: [trimmedName, Date(), oldName]
            )

            let folderID = try String.fetchOne(db, sql: "SELECT id FROM feed_folders WHERE name = ? COLLATE NOCASE", arguments: [trimmedName])
            if let folderID {
                try enqueuePendingSync(db, folderID: folderID, changeType: .save)
            }
        }
        CloudSyncEngine.notifyPendingChangesAvailable(database: database)
    }
```

`moveFolder` und `sortAlphabetically` — jeden umsortierten Ordner enqueuen (analog `TagStore.move()`):

```swift
    func moveFolder(name: String, targetIndex: Int) throws {
        try database.write { db in
            try materializeImplicitFolders(db)

            let otherFolderNames = try String.fetchAll(
                db,
                sql: """
                    SELECT name FROM feed_folders
                    WHERE name != ? COLLATE NOCASE
                    ORDER BY sortIndex
                    """,
                arguments: [name]
            )

            var orderedNames = otherFolderNames
            let clampedIndex = min(max(targetIndex, 0), orderedNames.count)
            orderedNames.insert(name, at: clampedIndex)

            let now = Date()
            for (index, folderName) in orderedNames.enumerated() {
                try db.execute(
                    sql: "UPDATE feed_folders SET sortIndex = ?, updatedAt = ? WHERE name = ? COLLATE NOCASE",
                    arguments: [index, now, folderName]
                )
                let folderID = try String.fetchOne(db, sql: "SELECT id FROM feed_folders WHERE name = ? COLLATE NOCASE", arguments: [folderName])
                if let folderID {
                    try enqueuePendingSync(db, folderID: folderID, changeType: .save)
                }
            }
        }
        CloudSyncEngine.notifyPendingChangesAvailable(database: database)
    }
```

Dasselbe "jede Zeile in der Schleife enqueuen"-Muster auf `sortAlphabetically()` angewendet:

```swift
    func sortAlphabetically() throws {
        try database.write { db in
            try materializeImplicitFolders(db)

            let orderedNames = try String.fetchAll(
                db,
                sql: "SELECT name FROM feed_folders ORDER BY name COLLATE NOCASE, id COLLATE NOCASE"
            )

            let now = Date()
            for (index, folderName) in orderedNames.enumerated() {
                try db.execute(
                    sql: "UPDATE feed_folders SET sortIndex = ?, updatedAt = ? WHERE name = ? COLLATE NOCASE",
                    arguments: [index, now, folderName]
                )
                let folderID = try String.fetchOne(db, sql: "SELECT id FROM feed_folders WHERE name = ? COLLATE NOCASE", arguments: [folderName])
                if let folderID {
                    try enqueuePendingSync(db, folderID: folderID, changeType: .save)
                }
            }
        }
        CloudSyncEngine.notifyPendingChangesAvailable(database: database)
    }
```

- [ ] **Step 6: Register `"FeedFolder"` in `CloudSyncEngine`**

```swift
    private static let registry: [String: any CloudSyncRecordMapping.Type] = [
        CloudSyncTagMapping.recordType: CloudSyncTagMapping.self,
        CloudSyncFeedMapping.recordType: CloudSyncFeedMapping.self,
        CloudSyncFeedFolderMapping.recordType: CloudSyncFeedFolderMapping.self
    ]
```

- [ ] **Step 7: Write and run the rename-requeues-feeds regression test**

Ergänze in der bestehenden `FeedFolderStore`-Testdatei:

```swift
    @Test func renameFolderMarkiertAlleBetroffenenFeedsAlsPendingSync() throws {
        let database = try makeTestDatabase()
        CloudSyncSettings.setEnabled(true)
        defer { CloudSyncSettings.setEnabled(false) }

        let feedStore = FeedStore(database: database)
        let folderStore = FeedFolderStore(database: database)
        try feedStore.save(FeedRecord(id: "feed-1", url: "https://a.example.com", title: "A", folderName: "Alt"))
        try folderStore.save(FeedFolderRecord(id: "folder-1", name: "Alt"))

        try folderStore.renameFolder(from: "Alt", to: "Neu")

        let pendingIDs = Set(try CloudSyncPendingChangeStore(database: database).pendingChanges().map(\.id))
        #expect(pendingIDs.contains("feed-1"))
        #expect(pendingIDs.contains("folder-1"))
    }
```

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CloudSyncFeedFolderMappingTests -parallel-testing-enabled NO 2>&1 | tail -60`

(Suite-Name für den bestehenden `FeedFolderStore`-Test per `find`-Ergebnis aus Step 1 ergänzen.)
Expected: PASS

- [ ] **Step 8: Full build**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -60`
Expected: BUILD SUCCEEDED

- [ ] **Step 9: Commit**

```bash
git add Feedivo/Services/CloudSync/CloudSyncFeedFolderMapping.swift Feedivo/Services/CloudSync/CloudSyncEngine.swift Feedivo/Stores/FeedFolderStore.swift FeedivoTests/CloudSyncFeedFolderMappingTests.swift
git commit -m "Feature: Feed-Ordner-Sync (CloudSyncFeedFolderMapping + FeedFolderStore-Wiring, iCloud Sync Phase 2a Task 5)"
```

---

### Task 6: `CloudSyncRuleMapping` + `CloudSyncRuleConditionMapping` + `SQLiteRuleStore`-Wiring

**Files:**
- Create: `Feedivo/Services/CloudSync/CloudSyncRuleMapping.swift`
- Create: `Feedivo/Services/CloudSync/CloudSyncRuleConditionMapping.swift`
- Modify: `Feedivo/Stores/SQLiteRuleStore.swift` (`save`/`updateEnabled`/`duplicate`/`move`/`delete`)
- Modify: `Feedivo/Services/CloudSync/CloudSyncEngine.swift` (Registry-Einträge `"Rule"`/`"RuleCondition"`)
- Test: `FeedivoTests/CloudSyncRuleMappingTests.swift` (neu)
- Test: `FeedivoTests/CloudSyncRuleConditionMappingTests.swift` (neu)
- Test: `FeedivoTests/SQLiteRuleStoreTests.swift` (Ergänzung: Kaskaden-Lösch-Test)

**Interfaces:**
- Consumes: `CloudSyncRecordMapping` (Task 3).
- Produces: `CloudSyncRuleMapping.recordType == "Rule"`, `CloudSyncRuleConditionMapping.recordType == "RuleCondition"`.

- [ ] **Step 1: Write the failing tests**

```swift
// FeedivoTests/CloudSyncRuleMappingTests.swift
import Foundation
import CloudKit
import Testing
@testable import Feedivo

struct CloudSyncRuleMappingTests {
    @Test func makeCKRecordMapptAlleFelder() {
        let rule = RuleRecord(id: "rule-1", name: "Wichtig", isEnabled: true, matchMode: "all", action: "assignTag", assignTagID: "tag-1", notificationTemplate: "{Titel}", notificationPriority: "normal", sortOrder: 1)

        let record = CloudSyncRuleMapping.makeCKRecord(from: rule)

        #expect(record.recordType == "Rule")
        #expect(record["name"] as? String == "Wichtig")
        #expect(record["assignTagID"] as? String == "tag-1")
    }

    @Test func ruleRecordFromCKRecordMapptZurueckOhneAssignTagID() {
        let rule = RuleRecord(id: "rule-1", name: "Wichtig", assignTagID: nil, sortOrder: 0)
        let record = CloudSyncRuleMapping.makeCKRecord(from: rule)

        let mapped = CloudSyncRuleMapping.ruleRecord(from: record)

        #expect(mapped?.assignTagID == nil)
        #expect(mapped?.name == "Wichtig")
    }
}
```

```swift
// FeedivoTests/CloudSyncRuleConditionMappingTests.swift
import Foundation
import CloudKit
import Testing
@testable import Feedivo

struct CloudSyncRuleConditionMappingTests {
    @Test func makeCKRecordMapptAlleFelder() {
        let condition = RuleConditionRecord(id: "cond-1", ruleID: "rule-1", field: "title", conditionOperator: "contains", value: "Test", sortOrder: 0, groupIndex: 1)

        let record = CloudSyncRuleConditionMapping.makeCKRecord(from: condition)

        #expect(record.recordType == "RuleCondition")
        #expect(record["ruleID"] as? String == "rule-1")
        #expect(record["groupIndex"] as? Int == 1)
    }

    @Test func ruleConditionRecordFromCKRecordMapptZurueck() {
        let condition = RuleConditionRecord(id: "cond-1", ruleID: "rule-1", field: "title", conditionOperator: "contains", value: "Test")
        let record = CloudSyncRuleConditionMapping.makeCKRecord(from: condition)

        let mapped = CloudSyncRuleConditionMapping.ruleConditionRecord(from: record)

        #expect(mapped?.ruleID == "rule-1")
        #expect(mapped?.field == "title")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CloudSyncRuleMappingTests -only-testing:FeedivoTests/CloudSyncRuleConditionMappingTests 2>&1 | tail -40`
Expected: FAIL

- [ ] **Step 3: Create `CloudSyncRuleMapping.swift`**

```swift
import Foundation
import CloudKit

/// Mapping für `rules` — vollständiger Sync. `assignTagID` ist eine reine String-Referenz auf
/// `tags.id`, löst sich von selbst auf, sobald der referenzierte Tag lokal existiert.
enum CloudSyncRuleMapping: CloudSyncRecordMapping {
    static let recordType = "Rule"

    static func makeCKRecord(from rule: RuleRecord, existing: CKRecord? = nil) -> CKRecord {
        let record = existing ?? CKRecord(recordType: recordType, recordID: recordID(forLocalID: rule.id))
        record["name"] = rule.name as CKRecordValue
        record["isEnabled"] = rule.isEnabled as CKRecordValue
        record["matchMode"] = rule.matchMode as CKRecordValue
        record["action"] = rule.action as CKRecordValue
        record["assignTagID"] = rule.assignTagID as CKRecordValue?
        record["notificationTemplate"] = rule.notificationTemplate as CKRecordValue
        record["notificationPriority"] = rule.notificationPriority as CKRecordValue
        record["sortOrder"] = rule.sortOrder as CKRecordValue
        return record
    }

    static func ruleRecord(from ckRecord: CKRecord) -> RuleRecord? {
        guard
            let name = ckRecord["name"] as? String,
            let isEnabled = ckRecord["isEnabled"] as? Bool,
            let matchMode = ckRecord["matchMode"] as? String,
            let action = ckRecord["action"] as? String,
            let notificationTemplate = ckRecord["notificationTemplate"] as? String,
            let notificationPriority = ckRecord["notificationPriority"] as? String,
            let sortOrder = ckRecord["sortOrder"] as? Int
        else {
            return nil
        }

        return RuleRecord(
            id: ckRecord.recordID.recordName,
            name: name,
            isEnabled: isEnabled,
            matchMode: matchMode,
            action: action,
            assignTagID: ckRecord["assignTagID"] as? String,
            notificationTemplate: notificationTemplate,
            notificationPriority: notificationPriority,
            sortOrder: sortOrder,
            createdAt: ckRecord.creationDate ?? Date(),
            updatedAt: ckRecord.modificationDate ?? Date()
        )
    }

    static func makeCKRecord(fromLocalID id: String, database: FeedivoDatabase) throws -> CKRecord? {
        guard let rule = try SQLiteRuleStore(database: database).rule(id: id) else { return nil }
        return makeCKRecord(from: rule)
    }

    static func applyIncoming(_ record: CKRecord, database: FeedivoDatabase) throws {
        guard var incoming = ruleRecord(from: record) else { return }
        try database.write { db in
            try incoming.save(db)
        }
    }

    static func applyIncomingDeletion(recordID: CKRecord.ID, database: FeedivoDatabase) throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM rules WHERE id = ?", arguments: [recordID.recordName])
        }
    }

    static func localUpdatedAt(forLocalID id: String, database: FeedivoDatabase) throws -> Date? {
        try SQLiteRuleStore(database: database).rule(id: id)?.updatedAt
    }
}
```

- [ ] **Step 4: Create `CloudSyncRuleConditionMapping.swift`**

```swift
import Foundation
import CloudKit
import GRDB

/// Mapping für `rule_conditions` — eigener CKRecord pro Bedingungszeile. `rule_conditions.ruleID`
/// hat `ON DELETE CASCADE` + `PRAGMA foreign_keys = ON` ist aktiv: trifft eine Bedingung lokal
/// ein, BEVOR ihre Regel existiert, schlägt der Insert mit einem Fremdschlüssel-Fehler fehl.
/// `CloudSyncEngine.sortedByDependencyOrder(_:)` mindert das (Eltern vor Kindern innerhalb
/// eines Batches) — dieser verbleibende Randfall wird geloggt und übersprungen statt die
/// gesamte Sync-Pipeline zu blockieren.
enum CloudSyncRuleConditionMapping: CloudSyncRecordMapping {
    static let recordType = "RuleCondition"

    static func makeCKRecord(from condition: RuleConditionRecord, existing: CKRecord? = nil) -> CKRecord {
        let record = existing ?? CKRecord(recordType: recordType, recordID: recordID(forLocalID: condition.id))
        record["ruleID"] = condition.ruleID as CKRecordValue
        record["field"] = condition.field as CKRecordValue
        record["conditionOperator"] = condition.conditionOperator as CKRecordValue
        record["value"] = condition.value as CKRecordValue
        record["sortOrder"] = condition.sortOrder as CKRecordValue
        record["groupIndex"] = condition.groupIndex as CKRecordValue
        return record
    }

    static func ruleConditionRecord(from ckRecord: CKRecord) -> RuleConditionRecord? {
        guard
            let ruleID = ckRecord["ruleID"] as? String,
            let field = ckRecord["field"] as? String,
            let conditionOperator = ckRecord["conditionOperator"] as? String,
            let value = ckRecord["value"] as? String,
            let sortOrder = ckRecord["sortOrder"] as? Int,
            let groupIndex = ckRecord["groupIndex"] as? Int
        else {
            return nil
        }

        return RuleConditionRecord(
            id: ckRecord.recordID.recordName,
            ruleID: ruleID,
            field: field,
            conditionOperator: conditionOperator,
            value: value,
            sortOrder: sortOrder,
            groupIndex: groupIndex,
            updatedAt: ckRecord.modificationDate ?? Date()
        )
    }

    static func makeCKRecord(fromLocalID id: String, database: FeedivoDatabase) throws -> CKRecord? {
        let condition = try database.read { db in
            try RuleConditionRecord.fetchOne(db, sql: "SELECT * FROM rule_conditions WHERE id = ?", arguments: [id])
        }
        guard let condition else { return nil }
        return makeCKRecord(from: condition)
    }

    static func applyIncoming(_ record: CKRecord, database: FeedivoDatabase) throws {
        guard var incoming = ruleConditionRecord(from: record) else { return }
        do {
            try database.write { db in
                try incoming.save(db)
            }
        } catch {
            // Fremdschlüssel-Verletzung: die Elternregel ist auf diesem Gerät noch nicht
            // eingetroffen (siehe Dokumentation oben). Geloggt statt propagiert, damit die
            // restliche Sync-Pipeline unbeeinträchtigt weiterläuft — bekannte Phase-2a-Grenze.
            AppLogger.dataAccess.error("iCloud Sync: RuleCondition konnte nicht gespeichert werden (Elternregel evtl. noch nicht synct): \(error.localizedDescription, privacy: .public)")
        }
    }

    static func applyIncomingDeletion(recordID: CKRecord.ID, database: FeedivoDatabase) throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM rule_conditions WHERE id = ?", arguments: [recordID.recordName])
        }
    }

    static func localUpdatedAt(forLocalID id: String, database: FeedivoDatabase) throws -> Date? {
        try database.read { db in
            try Date.fetchOne(db, sql: "SELECT updatedAt FROM rule_conditions WHERE id = ?", arguments: [id])
        }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CloudSyncRuleMappingTests -only-testing:FeedivoTests/CloudSyncRuleConditionMappingTests 2>&1 | tail -40`
Expected: PASS

- [ ] **Step 6: Wire `SQLiteRuleStore`**

In `Feedivo/Stores/SQLiteRuleStore.swift`:

```swift
    private func enqueuePendingSync(_ db: Database, recordType: String, recordName: String, changeType: CloudSyncChangeType) throws {
        guard CloudSyncSettings.isEnabled() else { return }
        try CloudSyncPendingChangeStore.enqueue(db, recordType: recordType, recordName: recordName, changeType: changeType)
    }

    func save(_ rule: RuleRecord, conditions: [RuleConditionRecord]) throws {
        try database.write { db in
            var rule = rule
            try rule.save(db)
            try enqueuePendingSync(db, recordType: CloudSyncRuleMapping.recordType, recordName: rule.id, changeType: .save)

            let existingConditionIDs = try String.fetchAll(db, sql: "SELECT id FROM rule_conditions WHERE ruleID = ?", arguments: [rule.id])
            for conditionID in existingConditionIDs {
                try enqueuePendingSync(db, recordType: CloudSyncRuleConditionMapping.recordType, recordName: conditionID, changeType: .delete)
            }

            try db.execute(
                sql: """
                    DELETE FROM rule_conditions
                    WHERE ruleID = ?
                    """,
                arguments: [rule.id]
            )

            for condition in conditions {
                var condition = condition
                condition.ruleID = rule.id
                try condition.insert(db)
                try enqueuePendingSync(db, recordType: CloudSyncRuleConditionMapping.recordType, recordName: condition.id, changeType: .save)
            }
        }
        CloudSyncEngine.notifyPendingChangesAvailable(database: database)
    }

    func updateEnabled(id: String, isEnabled: Bool) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE rules
                    SET isEnabled = ?, updatedAt = ?
                    WHERE id = ?
                    """,
                arguments: [isEnabled, Date(), id]
            )
            try enqueuePendingSync(db, recordType: CloudSyncRuleMapping.recordType, recordName: id, changeType: .save)
        }
        CloudSyncEngine.notifyPendingChangesAvailable(database: database)
    }

    func move(id sourceID: String, toPositionOf targetID: String) throws {
        try database.write { db in
            var rules = try Self.fetchRules(db)
            guard sourceID != targetID,
                  let sourceIndex = rules.firstIndex(where: { $0.id == sourceID }),
                  let targetIndex = rules.firstIndex(where: { $0.id == targetID })
            else {
                return
            }

            let movedRule = rules.remove(at: sourceIndex)
            rules.insert(movedRule, at: targetIndex)

            for (index, rule) in rules.enumerated() {
                try db.execute(
                    sql: """
                        UPDATE rules
                        SET sortOrder = ?, updatedAt = ?
                        WHERE id = ?
                        """,
                    arguments: [index, Date(), rule.id]
                )
                try enqueuePendingSync(db, recordType: CloudSyncRuleMapping.recordType, recordName: rule.id, changeType: .save)
            }
        }
        CloudSyncEngine.notifyPendingChangesAvailable(database: database)
    }

    func delete(id: String) throws {
        try database.write { db in
            let conditionIDs = try String.fetchAll(db, sql: "SELECT id FROM rule_conditions WHERE ruleID = ?", arguments: [id])
            for conditionID in conditionIDs {
                try enqueuePendingSync(db, recordType: CloudSyncRuleConditionMapping.recordType, recordName: conditionID, changeType: .delete)
            }
            try enqueuePendingSync(db, recordType: CloudSyncRuleMapping.recordType, recordName: id, changeType: .delete)

            try db.execute(
                sql: """
                    DELETE FROM rules
                    WHERE id = ?
                    """,
                arguments: [id]
            )
        }
        CloudSyncEngine.notifyPendingChangesAvailable(database: database)
    }
```

`duplicate(id:copyName:)` ebenfalls enqueuen — beachte, dass `database.write { ... }` hier den Rückgabewert des Closures (`RuleRecord`) durchreicht, `notifyPendingChangesAvailable` deshalb NACH dem `write`-Aufruf steht, nicht darin:

```swift
    func duplicate(id: String, copyName: String) throws -> RuleRecord {
        let duplicate = try database.write { db -> RuleRecord in
            guard let source = try RuleRecord.fetchOne(db, sql: """
                SELECT *
                FROM rules
                WHERE id = ?
                """, arguments: [id])
            else {
                throw SQLiteRuleStoreError.missingRule
            }

            let maxSortOrder = (try Int.fetchOne(db, sql: "SELECT MAX(sortOrder) FROM rules") ?? -1) + 1
            let duplicateID = UUID().uuidString
            var duplicate = RuleRecord(
                id: duplicateID,
                name: copyName,
                isEnabled: source.isEnabled,
                matchMode: source.matchMode,
                action: source.action,
                assignTagID: source.assignTagID,
                notificationTemplate: source.notificationTemplate,
                notificationPriority: source.notificationPriority,
                sortOrder: maxSortOrder
            )
            try duplicate.insert(db)
            try enqueuePendingSync(db, recordType: CloudSyncRuleMapping.recordType, recordName: duplicateID, changeType: .save)

            let conditions = try Self.fetchConditions(db, ruleID: source.id)
            for (index, condition) in conditions.enumerated() {
                var copiedCondition = RuleConditionRecord(
                    id: UUID().uuidString,
                    ruleID: duplicateID,
                    field: condition.field,
                    conditionOperator: condition.conditionOperator,
                    value: condition.value,
                    sortOrder: index,
                    groupIndex: condition.groupIndex
                )
                try copiedCondition.insert(db)
                try enqueuePendingSync(db, recordType: CloudSyncRuleConditionMapping.recordType, recordName: copiedCondition.id, changeType: .save)
            }

            return duplicate
        }
        CloudSyncEngine.notifyPendingChangesAvailable(database: database)
        return duplicate
    }
```

- [ ] **Step 7: Register `"Rule"`/`"RuleCondition"` in `CloudSyncEngine`**

```swift
    private static let registry: [String: any CloudSyncRecordMapping.Type] = [
        CloudSyncTagMapping.recordType: CloudSyncTagMapping.self,
        CloudSyncFeedMapping.recordType: CloudSyncFeedMapping.self,
        CloudSyncFeedFolderMapping.recordType: CloudSyncFeedFolderMapping.self,
        CloudSyncRuleMapping.recordType: CloudSyncRuleMapping.self,
        CloudSyncRuleConditionMapping.recordType: CloudSyncRuleConditionMapping.self
    ]
```

- [ ] **Step 8: Write and run the cascade-delete regression test**

Ergänze in `FeedivoTests/SQLiteRuleStoreTests.swift`:

```swift
    @Test func deleteRuleEnqueuedLoeschungenFuerRegelUndAlleBedingungen() throws {
        let database = try makeTestDatabase()
        CloudSyncSettings.setEnabled(true)
        defer { CloudSyncSettings.setEnabled(false) }

        let store = SQLiteRuleStore(database: database)
        let rule = RuleRecord(id: "rule-1", name: "Test", sortOrder: 0)
        let condition = RuleConditionRecord(id: "cond-1", ruleID: "rule-1", field: "title", conditionOperator: "contains", value: "x")
        try store.save(rule, conditions: [condition])

        try store.delete(id: "rule-1")

        let pendingDeletes = try CloudSyncPendingChangeStore(database: database).pendingChanges()
            .filter { $0.changeType == .delete }
            .map(\.id)
        #expect(Set(pendingDeletes) == Set(["rule-1", "cond-1"]))
    }
```

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteRuleStoreTests -only-testing:FeedivoTests/CloudSyncRuleMappingTests -only-testing:FeedivoTests/CloudSyncRuleConditionMappingTests -parallel-testing-enabled NO 2>&1 | tail -60`
Expected: PASS

- [ ] **Step 9: Full build**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -60`
Expected: BUILD SUCCEEDED

- [ ] **Step 10: Commit**

```bash
git add Feedivo/Services/CloudSync/CloudSyncRuleMapping.swift Feedivo/Services/CloudSync/CloudSyncRuleConditionMapping.swift Feedivo/Services/CloudSync/CloudSyncEngine.swift Feedivo/Stores/SQLiteRuleStore.swift FeedivoTests/CloudSyncRuleMappingTests.swift FeedivoTests/CloudSyncRuleConditionMappingTests.swift FeedivoTests/SQLiteRuleStoreTests.swift
git commit -m "Feature: Regel-Sync (CloudSyncRuleMapping/CloudSyncRuleConditionMapping + SQLiteRuleStore-Wiring, iCloud Sync Phase 2a Task 6)"
```

---

### Task 7: `CloudSyncSmartFolderMapping` + `CloudSyncSmartFolderConditionMapping` + `SQLiteSmartFolderStore`-Wiring (nur benutzerdefinierte Ordner)

**Files:**
- Create: `Feedivo/Services/CloudSync/CloudSyncSmartFolderMapping.swift`
- Create: `Feedivo/Services/CloudSync/CloudSyncSmartFolderConditionMapping.swift`
- Modify: `Feedivo/Stores/SQLiteSmartFolderStore.swift` (`save`/`updateSidebarVisibility`/`duplicate`/`move`/`delete`; `restoreDefaultFolders()` bleibt **UNVERÄNDERT**, kein Enqueue)
- Modify: `Feedivo/Services/CloudSync/CloudSyncEngine.swift` (Registry-Einträge `"SmartFolder"`/`"SmartFolderCondition"`)
- Test: `FeedivoTests/CloudSyncSmartFolderMappingTests.swift` (neu, inkl. Schutzklausel-Test)
- Test: `FeedivoTests/SQLiteSmartFolderStoreTests.swift` (Ergänzung: Default-Ordner-nie-enqueuen-Test, Kaskaden-Lösch-Test)

**Interfaces:**
- Consumes: `CloudSyncRecordMapping` (Task 3).
- Produces: `CloudSyncSmartFolderMapping.recordType == "SmartFolder"`, `CloudSyncSmartFolderConditionMapping.recordType == "SmartFolderCondition"`.

- [ ] **Step 1: Write the failing tests**

```swift
// FeedivoTests/CloudSyncSmartFolderMappingTests.swift
import Foundation
import CloudKit
import Testing
@testable import Feedivo

struct CloudSyncSmartFolderMappingTests {
    @Test func makeCKRecordMapptAlleFelder() {
        let folder = SmartFolderRecord(id: "folder-1", name: "Meine Auswahl", matchMode: "all", isShownInSidebar: true, isDefault: false, sortOrder: 3, iconName: "star", colorHex: "#FF0000")

        let record = CloudSyncSmartFolderMapping.makeCKRecord(from: folder)

        #expect(record.recordType == "SmartFolder")
        #expect(record["name"] as? String == "Meine Auswahl")
        #expect(record["iconName"] as? String == "star")
    }

    @Test func applyIncomingVerwirftRecordMitGesetztemDefaultKey() throws {
        let database = try makeTestDatabase()
        let record = CKRecord(recordType: "SmartFolder", recordID: CloudSyncSmartFolderMapping.recordID(forLocalID: "folder-1"))
        record["name"] = "Ungelesen" as CKRecordValue
        record["matchMode"] = "all" as CKRecordValue
        record["isShownInSidebar"] = true as CKRecordValue
        record["sortOrder"] = 0 as CKRecordValue
        record["defaultShowsReadArticles"] = false as CKRecordValue
        // Simuliert einen defensiv zu verwerfenden eingehenden Record — ein regulär von
        // CloudSyncSmartFolderMapping.makeCKRecord(from:) erzeugter Record trägt niemals einen
        // defaultKey, aber ein fremder Client könnte theoretisch einen solchen Wert senden.
        record["defaultKey"] = "unread" as CKRecordValue

        try CloudSyncSmartFolderMapping.applyIncoming(record, database: database)

        let count = try database.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM smart_folders WHERE id = 'folder-1'") ?? 0
        }
        #expect(count == 0)
    }

    @Test func smartFolderRecordFromCKRecordMapptZurueck() {
        let folder = SmartFolderRecord(id: "folder-1", name: "Meine Auswahl", sortOrder: 3)
        let record = CloudSyncSmartFolderMapping.makeCKRecord(from: folder)

        let mapped = CloudSyncSmartFolderMapping.smartFolderRecord(from: record)

        #expect(mapped?.name == "Meine Auswahl")
        #expect(mapped?.isDefault == false)
    }
}
```

> Prüfe per `grep -rn "func makeTestDatabase" FeedivoTests/` den exakten Namen/Signatur der bereits existierenden Test-DB-Hilfsfunktion und übernimm ihn 1:1 in allen neuen Testdateien dieses Plans (Task 4/5/6/7) statt zu raten.

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CloudSyncSmartFolderMappingTests 2>&1 | tail -40`
Expected: FAIL

- [ ] **Step 3: Create `CloudSyncSmartFolderMapping.swift`**

```swift
import Foundation
import CloudKit

/// Mapping für `smart_folders` — NUR benutzerdefinierte Ordner (`isDefault == false`).
/// Eingebaute Ordner (z. B. "Ungelesen") werden pro Gerät über einen stabilen `defaultKey`
/// lokal verwaltet (`SQLiteSmartFolderStore.restoreDefaultFolders()`) und syncen NIE — jedes
/// Gerät vergibt dafür eine eigene, zufällige `id`. `isDefault`/`defaultKey` werden deshalb
/// bewusst NICHT auf das CKRecord geschrieben (ein synctes SmartFolder ist per Definition immer
/// benutzerdefiniert); `applyIncoming` verwirft defensiv trotzdem jeden eingehenden Record mit
/// gesetztem `defaultKey`, falls ein zukünftiger Bug oder ein anderer Client das doch sendet.
enum CloudSyncSmartFolderMapping: CloudSyncRecordMapping {
    static let recordType = "SmartFolder"

    static func makeCKRecord(from folder: SmartFolderRecord, existing: CKRecord? = nil) -> CKRecord {
        let record = existing ?? CKRecord(recordType: recordType, recordID: recordID(forLocalID: folder.id))
        record["name"] = folder.name as CKRecordValue
        record["matchMode"] = folder.matchMode as CKRecordValue
        record["isShownInSidebar"] = folder.isShownInSidebar as CKRecordValue
        record["sortOrder"] = folder.sortOrder as CKRecordValue
        record["iconName"] = folder.iconName as CKRecordValue?
        record["colorHex"] = folder.colorHex as CKRecordValue?
        record["defaultShowsReadArticles"] = folder.defaultShowsReadArticles as CKRecordValue
        return record
    }

    static func smartFolderRecord(from ckRecord: CKRecord) -> SmartFolderRecord? {
        guard
            let name = ckRecord["name"] as? String,
            let matchMode = ckRecord["matchMode"] as? String,
            let isShownInSidebar = ckRecord["isShownInSidebar"] as? Bool,
            let sortOrder = ckRecord["sortOrder"] as? Int,
            let defaultShowsReadArticles = ckRecord["defaultShowsReadArticles"] as? Bool
        else {
            return nil
        }

        return SmartFolderRecord(
            id: ckRecord.recordID.recordName,
            name: name,
            matchMode: matchMode,
            isShownInSidebar: isShownInSidebar,
            isDefault: false,
            sortOrder: sortOrder,
            defaultKey: nil,
            iconName: ckRecord["iconName"] as? String,
            colorHex: ckRecord["colorHex"] as? String,
            defaultShowsReadArticles: defaultShowsReadArticles,
            createdAt: ckRecord.creationDate ?? Date(),
            updatedAt: ckRecord.modificationDate ?? Date()
        )
    }

    static func makeCKRecord(fromLocalID id: String, database: FeedivoDatabase) throws -> CKRecord? {
        guard let folder = try SQLiteSmartFolderStore(database: database).folder(id: id), !folder.isDefault else { return nil }
        return makeCKRecord(from: folder)
    }

    static func applyIncoming(_ record: CKRecord, database: FeedivoDatabase) throws {
        // Schutzklausel: ein Record mit gesetztem, nicht-leerem defaultKey darf nie ankommen
        // (siehe Dokumentation oben) — defensiv verwerfen statt einen zweiten, ID-fremden
        // Default-Ordner lokal anzulegen.
        if let defaultKey = record["defaultKey"] as? String, !defaultKey.isEmpty {
            return
        }
        guard var incoming = smartFolderRecord(from: record) else { return }
        try database.write { db in
            try incoming.save(db)
        }
    }

    static func applyIncomingDeletion(recordID: CKRecord.ID, database: FeedivoDatabase) throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM smart_folders WHERE id = ? AND isDefault = 0", arguments: [recordID.recordName])
        }
    }

    static func localUpdatedAt(forLocalID id: String, database: FeedivoDatabase) throws -> Date? {
        try SQLiteSmartFolderStore(database: database).folder(id: id)?.updatedAt
    }
}
```

- [ ] **Step 4: Create `CloudSyncSmartFolderConditionMapping.swift`**

```swift
import Foundation
import CloudKit
import GRDB

/// Mapping für `smart_folder_conditions` — analog zu `CloudSyncRuleConditionMapping`, inkl.
/// derselben Fremdschlüssel-Randfall-Behandlung (Eltern-Ordner evtl. noch nicht synct).
/// Bedingungen zu EINGEBAUTEN Ordnern werden nie gesynct — das wird bereits dadurch
/// sichergestellt, dass `SQLiteSmartFolderStore` (Task 7, Step 6) für `isDefault`-Ordner gar
/// nie enqueued, nicht durch eine zusätzliche Prüfung hier.
enum CloudSyncSmartFolderConditionMapping: CloudSyncRecordMapping {
    static let recordType = "SmartFolderCondition"

    static func makeCKRecord(from condition: SmartFolderConditionRecord, existing: CKRecord? = nil) -> CKRecord {
        let record = existing ?? CKRecord(recordType: recordType, recordID: recordID(forLocalID: condition.id))
        record["smartFolderID"] = condition.smartFolderID as CKRecordValue
        record["field"] = condition.field as CKRecordValue
        record["conditionOperator"] = condition.conditionOperator as CKRecordValue
        record["value"] = condition.value as CKRecordValue
        record["sortOrder"] = condition.sortOrder as CKRecordValue
        return record
    }

    static func smartFolderConditionRecord(from ckRecord: CKRecord) -> SmartFolderConditionRecord? {
        guard
            let smartFolderID = ckRecord["smartFolderID"] as? String,
            let field = ckRecord["field"] as? String,
            let conditionOperator = ckRecord["conditionOperator"] as? String,
            let value = ckRecord["value"] as? String,
            let sortOrder = ckRecord["sortOrder"] as? Int
        else {
            return nil
        }

        return SmartFolderConditionRecord(
            id: ckRecord.recordID.recordName,
            smartFolderID: smartFolderID,
            field: field,
            conditionOperator: conditionOperator,
            value: value,
            sortOrder: sortOrder,
            updatedAt: ckRecord.modificationDate ?? Date()
        )
    }

    static func makeCKRecord(fromLocalID id: String, database: FeedivoDatabase) throws -> CKRecord? {
        let condition = try database.read { db in
            try SmartFolderConditionRecord.fetchOne(db, sql: "SELECT * FROM smart_folder_conditions WHERE id = ?", arguments: [id])
        }
        guard let condition else { return nil }
        return makeCKRecord(from: condition)
    }

    static func applyIncoming(_ record: CKRecord, database: FeedivoDatabase) throws {
        guard var incoming = smartFolderConditionRecord(from: record) else { return }
        do {
            try database.write { db in
                try incoming.save(db)
            }
        } catch {
            AppLogger.dataAccess.error("iCloud Sync: SmartFolderCondition konnte nicht gespeichert werden (Elternordner evtl. noch nicht synct): \(error.localizedDescription, privacy: .public)")
        }
    }

    static func applyIncomingDeletion(recordID: CKRecord.ID, database: FeedivoDatabase) throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM smart_folder_conditions WHERE id = ?", arguments: [recordID.recordName])
        }
    }

    static func localUpdatedAt(forLocalID id: String, database: FeedivoDatabase) throws -> Date? {
        try database.read { db in
            try Date.fetchOne(db, sql: "SELECT updatedAt FROM smart_folder_conditions WHERE id = ?", arguments: [id])
        }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CloudSyncSmartFolderMappingTests 2>&1 | tail -40`
Expected: PASS

- [ ] **Step 6: Wire `SQLiteSmartFolderStore` (nur für `isDefault == false`)**

```swift
    private func enqueuePendingSync(_ db: Database, recordType: String, recordName: String, changeType: CloudSyncChangeType) throws {
        guard CloudSyncSettings.isEnabled() else { return }
        try CloudSyncPendingChangeStore.enqueue(db, recordType: recordType, recordName: recordName, changeType: changeType)
    }

    func save(_ folder: SmartFolderRecord, conditions: [SmartFolderConditionRecord]) throws {
        try database.write { db in
            var folder = folder
            try folder.save(db)

            guard !folder.isDefault else { return }

            try enqueuePendingSync(db, recordType: CloudSyncSmartFolderMapping.recordType, recordName: folder.id, changeType: .save)

            let existingConditionIDs = try String.fetchAll(db, sql: "SELECT id FROM smart_folder_conditions WHERE smartFolderID = ?", arguments: [folder.id])
            for conditionID in existingConditionIDs {
                try enqueuePendingSync(db, recordType: CloudSyncSmartFolderConditionMapping.recordType, recordName: conditionID, changeType: .delete)
            }

            try db.execute(
                sql: """
                    DELETE FROM smart_folder_conditions
                    WHERE smartFolderID = ?
                    """,
                arguments: [folder.id]
            )

            for condition in conditions {
                var condition = condition
                condition.smartFolderID = folder.id
                try condition.insert(db)
                try enqueuePendingSync(db, recordType: CloudSyncSmartFolderConditionMapping.recordType, recordName: condition.id, changeType: .save)
            }
        }
        CloudSyncEngine.notifyPendingChangesAvailable(database: database)
    }

    func updateSidebarVisibility(id: String, isShownInSidebar: Bool) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE smart_folders
                    SET isShownInSidebar = ?, updatedAt = ?
                    WHERE id = ?
                    """,
                arguments: [isShownInSidebar, Date(), id]
            )

            let isDefault = try Bool.fetchOne(db, sql: "SELECT isDefault FROM smart_folders WHERE id = ?", arguments: [id]) ?? true
            guard !isDefault else { return }
            try enqueuePendingSync(db, recordType: CloudSyncSmartFolderMapping.recordType, recordName: id, changeType: .save)
        }
        CloudSyncEngine.notifyPendingChangesAvailable(database: database)
    }

    func move(id sourceID: String, toPositionOf targetID: String) throws {
        try database.write { db in
            var folders = try Self.fetchFolders(db)
            guard sourceID != targetID,
                  let sourceIndex = folders.firstIndex(where: { $0.id == sourceID }),
                  let targetIndex = folders.firstIndex(where: { $0.id == targetID })
            else {
                return
            }

            let movedFolder = folders.remove(at: sourceIndex)
            folders.insert(movedFolder, at: targetIndex)

            for (index, folder) in folders.enumerated() {
                try db.execute(
                    sql: """
                        UPDATE smart_folders
                        SET sortOrder = ?, updatedAt = ?
                        WHERE id = ?
                        """,
                    arguments: [index, Date(), folder.id]
                )
                guard !folder.isDefault else { continue }
                try enqueuePendingSync(db, recordType: CloudSyncSmartFolderMapping.recordType, recordName: folder.id, changeType: .save)
            }
        }
        CloudSyncEngine.notifyPendingChangesAvailable(database: database)
    }

    func delete(id: String) throws {
        try database.write { db in
            let isDefault = try Bool.fetchOne(db, sql: "SELECT isDefault FROM smart_folders WHERE id = ?", arguments: [id]) ?? true

            if !isDefault {
                let conditionIDs = try String.fetchAll(db, sql: "SELECT id FROM smart_folder_conditions WHERE smartFolderID = ?", arguments: [id])
                for conditionID in conditionIDs {
                    try enqueuePendingSync(db, recordType: CloudSyncSmartFolderConditionMapping.recordType, recordName: conditionID, changeType: .delete)
                }
                try enqueuePendingSync(db, recordType: CloudSyncSmartFolderMapping.recordType, recordName: id, changeType: .delete)
            }

            try db.execute(
                sql: """
                    DELETE FROM smart_folders
                    WHERE id = ?
                    """,
                arguments: [id]
            )
        }
        CloudSyncEngine.notifyPendingChangesAvailable(database: database)
    }
```

`duplicate(id:copyName:)` — die neu erzeugte Kopie ist laut bestehendem Code immer `isDefault: false`, also IMMER enqueuen (gleiche Rückgabewert-Reihenfolge-Regel wie bei `SQLiteRuleStore.duplicate` in Task 6: `notifyPendingChangesAvailable` NACH dem `write`-Aufruf):

```swift
    func duplicate(id: String, copyName: String) throws -> SmartFolderRecord {
        let duplicate = try database.write { db -> SmartFolderRecord in
            guard let source = try SmartFolderRecord.fetchOne(db, sql: """
                SELECT *
                FROM smart_folders
                WHERE id = ?
                """, arguments: [id])
            else {
                throw SQLiteSmartFolderStoreError.missingFolder
            }

            let maxSortOrder = (try Int.fetchOne(db, sql: "SELECT MAX(sortOrder) FROM smart_folders") ?? -1) + 1
            let duplicateID = UUID().uuidString
            var duplicate = SmartFolderRecord(
                id: duplicateID,
                name: copyName,
                matchMode: source.matchMode,
                isShownInSidebar: source.isShownInSidebar,
                isDefault: false,
                sortOrder: maxSortOrder,
                defaultKey: nil,
                iconName: source.iconName,
                colorHex: source.colorHex,
                defaultShowsReadArticles: source.defaultShowsReadArticles
            )
            try duplicate.insert(db)
            try enqueuePendingSync(db, recordType: CloudSyncSmartFolderMapping.recordType, recordName: duplicateID, changeType: .save)

            let conditions = try Self.fetchConditions(db, folderID: source.id)
            for (index, condition) in conditions.enumerated() {
                var copiedCondition = SmartFolderConditionRecord(
                    id: UUID().uuidString,
                    smartFolderID: duplicateID,
                    field: condition.field,
                    conditionOperator: condition.conditionOperator,
                    value: condition.value,
                    sortOrder: index
                )
                try copiedCondition.insert(db)
                try enqueuePendingSync(db, recordType: CloudSyncSmartFolderConditionMapping.recordType, recordName: copiedCondition.id, changeType: .save)
            }

            return duplicate
        }
        CloudSyncEngine.notifyPendingChangesAvailable(database: database)
        return duplicate
    }
```

`restoreDefaultFolders()` **bewusst unverändert lassen** — legt ausschließlich `isDefault: true`-Ordner an, die nie syncen sollen.

- [ ] **Step 7: Register `"SmartFolder"`/`"SmartFolderCondition"` in `CloudSyncEngine`**

```swift
    private static let registry: [String: any CloudSyncRecordMapping.Type] = [
        CloudSyncTagMapping.recordType: CloudSyncTagMapping.self,
        CloudSyncFeedMapping.recordType: CloudSyncFeedMapping.self,
        CloudSyncFeedFolderMapping.recordType: CloudSyncFeedFolderMapping.self,
        CloudSyncRuleMapping.recordType: CloudSyncRuleMapping.self,
        CloudSyncRuleConditionMapping.recordType: CloudSyncRuleConditionMapping.self,
        CloudSyncSmartFolderMapping.recordType: CloudSyncSmartFolderMapping.self,
        CloudSyncSmartFolderConditionMapping.recordType: CloudSyncSmartFolderConditionMapping.self
    ]
```

- [ ] **Step 8: Write and run the default-folder-never-enqueues + cascade-delete regression tests**

Ergänze in `FeedivoTests/SQLiteSmartFolderStoreTests.swift`:

```swift
    @Test func restoreDefaultFoldersEnqueuedNiemalsPendingSync() throws {
        let database = try makeTestDatabase()
        CloudSyncSettings.setEnabled(true)
        defer { CloudSyncSettings.setEnabled(false) }

        let store = SQLiteSmartFolderStore(database: database)
        try store.restoreDefaultFolders()

        let pendingChanges = try CloudSyncPendingChangeStore(database: database).pendingChanges()
        #expect(pendingChanges.isEmpty)
    }

    @Test func deleteBenutzerdefiniertenOrdnerEnqueuedLoeschungenFuerOrdnerUndAlleBedingungen() throws {
        let database = try makeTestDatabase()
        CloudSyncSettings.setEnabled(true)
        defer { CloudSyncSettings.setEnabled(false) }

        let store = SQLiteSmartFolderStore(database: database)
        let folder = SmartFolderRecord(id: "folder-1", name: "Meine Auswahl", isDefault: false)
        let condition = SmartFolderConditionRecord(id: "cond-1", smartFolderID: "folder-1", field: "status", conditionOperator: "is", value: "unread")
        try store.save(folder, conditions: [condition])

        try store.delete(id: "folder-1")

        let pendingDeletes = try CloudSyncPendingChangeStore(database: database).pendingChanges()
            .filter { $0.changeType == .delete }
            .map(\.id)
        #expect(Set(pendingDeletes) == Set(["folder-1", "cond-1"]))
    }
```

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteSmartFolderStoreTests -only-testing:FeedivoTests/CloudSyncSmartFolderMappingTests -parallel-testing-enabled NO 2>&1 | tail -60`
Expected: PASS

- [ ] **Step 9: Full build**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -60`
Expected: BUILD SUCCEEDED

- [ ] **Step 10: Commit**

```bash
git add Feedivo/Services/CloudSync/CloudSyncSmartFolderMapping.swift Feedivo/Services/CloudSync/CloudSyncSmartFolderConditionMapping.swift Feedivo/Services/CloudSync/CloudSyncEngine.swift Feedivo/Stores/SQLiteSmartFolderStore.swift FeedivoTests/CloudSyncSmartFolderMappingTests.swift FeedivoTests/SQLiteSmartFolderStoreTests.swift
git commit -m "Feature: Intelligente-Ordner-Sync fuer benutzerdefinierte Ordner (iCloud Sync Phase 2a Task 7)"
```

---

### Task 8: Whole-Branch-Verifikation + CLAUDE.md-Abschluss

**Files:**
- Modify: `CLAUDE.md` (Tech-Stack-Zeile "iCloud Sync", "Aktuell in Arbeit"-Eintrag, "Offene Entscheidungen")
- Kein neuer Produktivcode.

**Interfaces:**
- Consumes: alle Tasks 1–7.

- [ ] **Step 1: Run the full CloudSync-related test suite**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CloudSyncEngineRegistryTests -only-testing:FeedivoTests/CloudSyncTagMappingTests -only-testing:FeedivoTests/CloudSyncFeedMappingTests -only-testing:FeedivoTests/CloudSyncFeedFolderMappingTests -only-testing:FeedivoTests/CloudSyncRuleMappingTests -only-testing:FeedivoTests/CloudSyncRuleConditionMappingTests -only-testing:FeedivoTests/CloudSyncSmartFolderMappingTests -only-testing:FeedivoTests/CloudSyncPendingChangeStoreTests -only-testing:FeedivoTests/CloudSyncSettingsTests -only-testing:FeedivoTests/SQLiteTagStoreTests -only-testing:FeedivoTests/SQLiteFeedStoreTests -only-testing:FeedivoTests/SQLiteRuleStoreTests -only-testing:FeedivoTests/SQLiteSmartFolderStoreTests -only-testing:FeedivoTests/FeedivoDatabaseMigratorTests -parallel-testing-enabled NO 2>&1 | tail -100`
Expected: alle PASS.

- [ ] **Step 2: Full release build**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -configuration Release -destination 'platform=macOS' 2>&1 | tail -60`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Update CLAUDE.md**

In der Tech-Stack-Tabelle, Zeile "iCloud Sync", ändere den Text von "Phase 1 implementiert (nur Tags)" auf "Phase 2a implementiert (Feeds/Ordner/Regeln/benutzerdefinierte Intelligente Ordner)" und ergänze einen neuen Eintrag unter "Aktuell in Arbeit" analog zu den bestehenden Phase-1-Einträgen (Datum, Umfang, Testergebnis, offene Live-Verifikation für Push-Richtung auf allen 4 neuen Tabellen, Pull-Richtung weiterhin ungetestet mangels Zweitgerät).

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "Docs: iCloud Sync Phase 2a abgeschlossen - CLAUDE.md aktualisiert"
```

---

## Live-Verifikation (nach diesem Plan, manuell durch den Nutzer)

Analog zu Phase 1 (CloudKit Dashboard, `https://icloud.developer.apple.com/dashboard/`):

1. Feed anlegen/umbenennen/in Ordner verschieben/löschen → passende `Feed`-Records erscheinen/ändern sich/verschwinden im Dashboard.
2. Ordner umbenennen → sowohl der `FeedFolder`-Record ALS AUCH alle betroffenen `Feed`-Records zeigen den neuen `folderName`.
3. Regel mit Bedingungen anlegen/bearbeiten/löschen → `Rule`- und `RuleCondition`-Records erscheinen/verschwinden konsistent.
4. Benutzerdefinierten Intelligenten Ordner mit Bedingungen anlegen/löschen → `SmartFolder`-/`SmartFolderCondition`-Records erscheinen/verschwinden.
5. Eingebauten Intelligenten Ordner (z. B. "Ungelesen") NICHT im Dashboard sehen — bestätigt die Ausschlussklausel.
6. Pull-Richtung bleibt wie in Phase 1 bis zu einem zweiten Testgerät unverifiziert.
