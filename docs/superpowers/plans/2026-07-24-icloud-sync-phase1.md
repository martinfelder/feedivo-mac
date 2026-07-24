# iCloud Sync — Phase 1 (Fundament) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eine funktionierende Ende-zu-Ende-Sync-Pipeline über CloudKit (`CKSyncEngine`) für die
`tags`-Tabelle, inklusive Settings-Toggle (sofort wirksam, kein Neustart) — als Fundament für
die restlichen Tabellen in Phase 2.

**Architecture:** Neue GRDB-Tabelle `cloud_sync_pending_changes` als App-eigene, durable
Warteschlange für noch nicht hochgeladene Änderungen. `CKSyncEngine` (Apples Sync-Engine,
private CloudKit-Datenbank, eigene Zone `"FeedivoZone"`) übernimmt Change-Tracking,
Batching, Retry. `TagStore`-Mutationen markieren betroffene IDs in der Warteschlange;
`CloudSyncEngine` liest sie beim Senden und dequeued nach Bestätigung. Eingehende
CloudKit-Änderungen werden per GRDB-Upsert/Delete in `tags` übernommen und lösen
`SQLiteDataInvalidation.bumpStatusVersion()` aus (bestehender UI-Reload-Mechanismus).

**Tech Stack:** Swift, GRDB, CloudKit (`CKSyncEngine`, macOS 14+), SwiftUI, Swift Testing.

## Global Constraints

- Nur `tags`-Tabelle wird in Phase 1 synchronisiert — Feeds/Ordner/Regeln/Intelligente
  Ordner/Artikelstatus folgen in Phase 2 (siehe Spec, Abschnitt "Ziel").
- Konfliktstrategie: Last-Write-Wins auf Record-Ebene — `TagRecord.updatedAt` (lokal) vs.
  `CKRecord.modificationDate` (Server), neuere Seite gewinnt.
- Toggle "iCloud Sync Beta" wirkt sofort, kein App-Neustart nötig.
- CloudKit-Container-Identifier: `iCloud.ch.martin.Feedivo` (bereits in
  `Feedivo/Feedivo.entitlements` deklariert). Private Datenbank, eigene Record-Zone
  `"FeedivoZone"` (keine Default-Zone).
- Kein Modal-Alert bei Sync-Fehlern — nur Status-Text im Settings-Bereich (Projektkonvention,
  siehe CLAUDE.md).
- Migrationen NIE nachträglich ändern, immer neu anhängen. Letzte bestehende Migration ist
  `v20_add_rule_condition_group_index` (`Feedivo/Database/FeedivoDatabaseMigrator.swift`) —
  diese Phase fügt `v21_create_cloud_sync_pending_changes` an.
- Kommentare im Code auf Deutsch (Projektkonvention).
- Volle Testsuite (`xcodebuild test` ohne `-only-testing`) hängt bekanntermaßen — immer gezielt
  mit `-only-testing:FeedivoTests/<SuiteName>` testen.
- `Localizable.xcstrings`-Ergänzungen NIEMALS per vollem `json.load`/`json.dump`-Roundtrip —
  immer als reine Text-Segment-Einfügung an einem stabilen, eindeutigen Anker, danach
  `git diff --stat` prüfen (nur Insertions, keine/kaum Deletions).
- **Wichtiger Hinweis zur `CKSyncEngine`-API:** Diese API ist relativ neu (macOS 14/WWDC23) und
  über die verfügbaren Recherche-Tools nicht mit Compiler-Sicherheit verifizierbar (Apples
  Doku ist JS-gerendert, nicht per Tool abrufbar). Der Code in Task 3 ist ein fundiert
  recherchierter, bestmöglicher Entwurf (abgeglichen mit Apples offiziellem Sample-Repo
  `apple/sample-cloudkit-sync-engine`), aber **vor der Implementierung MUSS die exakte
  Signatur jedes verwendeten `CKSyncEngine`/`CKSyncEngineDelegate`/`CKSyncEngine.Event`-Typs
  in Xcode direkt verifiziert werden** (⌘-Klick ins generierte Interface oder Quick Help) —
  nicht raten, sondern wie beim bestehenden `NSBackgroundActivityScheduler`-Gotcha (CLAUDE.md)
  gegen die echte SDK-Deklaration abgleichen. Der abschließende `xcodebuild build`-Lauf ist die
  eigentliche Wahrheitsquelle.

---

## File Structure

**Neu:**
- `Feedivo/Database/Records/CloudSyncPendingChangeRecord.swift`
- `Feedivo/Stores/CloudSyncPendingChangeStore.swift`
- `Feedivo/Services/CloudSync/CloudSyncTagMapping.swift`
- `Feedivo/Services/CloudSync/CloudSyncStatus.swift`
- `Feedivo/Services/CloudSync/CloudSyncEngine.swift`
- `FeedivoTests/CloudSyncPendingChangeStoreTests.swift`
- `FeedivoTests/CloudSyncTagMappingTests.swift`

**Geändert:**
- `Feedivo/Database/FeedivoDatabaseMigrator.swift` (Migration v21)
- `Feedivo/Stores/TagStore.swift` (Pending-Change-Hooks in den 5 Mutationsmethoden)
- `Feedivo/Services/CloudSyncSettings.swift` (Refactor: `isAvailable = true`,
  Restart-Konzept entfernt)
- `FeedivoTests/CloudSyncSettingsTests.swift` (an neue Signatur angepasst)
- `Feedivo/Views/Settings/SettingsView.swift` (`SyncSettingsView` neu verdrahtet)
- `Feedivo/Resources/L10n.swift` (2 neue Keys)
- `Feedivo/Resources/Localizable.xcstrings` (2 neue Einträge, 4 Sprachen)
- `Feedivo/App/FeedivoApp.swift` (Live-Start/Stop der `CloudSyncEngine`, Environment-Injection)
- `CLAUDE.md` (Abschlussdokumentation)

---

## Task 0: Manuelle Voraussetzung (kein Code, Nutzeraktion)

**Dieser Schritt kann nicht automatisiert werden — bitte vor Beginn von Task 6 (Live-Verifikation)
erledigen, blockiert Tasks 1–5 nicht.**

- [ ] In Xcode: Feedivo-Target auswählen → "Signing & Capabilities" → "+ Capability" →
  "iCloud" hinzufügen (falls noch nicht als aktive Capability vorhanden — die Entitlements-
  Datei deklariert den Container bereits, die Capability muss aber im Xcode-Projekt selbst
  aktiv geschaltet sein, damit Xcode das Provisioning Profile entsprechend erstellt).
- [ ] Unter der iCloud-Capability "CloudKit" aktivieren, Container `iCloud.ch.martin.Feedivo`
  auswählen (ggf. im Apple Developer Portal bestätigen, falls er dort noch nicht existiert).
- [ ] Sicherstellen, dass auf dem Test-Mac ein iCloud-Konto angemeldet ist (Systemeinstellungen
  → Apple-Account) — nötig für die Live-Verifikation in Task 6.

---

## Task 1: CloudSyncPendingChangeRecord + Store + Migration v21

**Files:**
- Create: `Feedivo/Database/Records/CloudSyncPendingChangeRecord.swift`
- Create: `Feedivo/Stores/CloudSyncPendingChangeStore.swift`
- Modify: `Feedivo/Database/FeedivoDatabaseMigrator.swift` (nach der `v20`-Migration, vor
  `return migrator`)
- Test: `FeedivoTests/CloudSyncPendingChangeStoreTests.swift`

**Interfaces:**
- Produces:
  - `enum CloudSyncChangeType: String, Codable, Sendable { case save, delete }`
  - `struct CloudSyncPendingChangeRecord: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable, Sendable` mit
    `id: String` (= CKRecord-`recordName`), `recordType: String`, `changeType: CloudSyncChangeType`, `queuedAt: Date`
  - `struct CloudSyncPendingChangeStore` mit:
    - `init(database: FeedivoDatabase)`
    - `func enqueue(recordType: String, recordName: String, changeType: CloudSyncChangeType) throws`
    - `static func enqueue(_ db: Database, recordType: String, recordName: String, changeType: CloudSyncChangeType) throws`
      (für Einbettung in bestehende `database.write`-Transaktionen, z. B. in `TagStore`)
    - `func dequeue(recordName: String) throws`
    - `func pendingChanges() throws -> [CloudSyncPendingChangeRecord]`

- [ ] **Step 1: Migration v21 schreiben**

In `Feedivo/Database/FeedivoDatabaseMigrator.swift`, direkt nach dem
`v20_add_rule_condition_group_index`-Block und vor `return migrator`:

```swift
        migrator.registerMigration("v21_create_cloud_sync_pending_changes") { database in
            try database.create(table: "cloud_sync_pending_changes") { table in
                table.column("id", .text).primaryKey()
                table.column("recordType", .text).notNull()
                table.column("changeType", .text).notNull()
                table.column("queuedAt", .datetime).notNull()
            }
        }
```

- [ ] **Step 2: `CloudSyncPendingChangeRecord` schreiben**

`Feedivo/Database/Records/CloudSyncPendingChangeRecord.swift`:

```swift
import Foundation
import GRDB

/// Art der ausstehenden Änderung an einem lokal-CloudKit-gemappten Datensatz.
enum CloudSyncChangeType: String, Codable, Sendable {
    case save
    case delete
}

/// Hält fest, welche lokalen Zeilen noch nicht zu CloudKit hochgeladen wurden. `id` entspricht
/// dem `CKRecord.ID.recordName` (für Tags: `TagRecord.id`). App-eigene, durable Warteschlange —
/// zusätzlich zu `CKSyncEngine`s eigener interner State-Serialisierung, damit ein App-Absturz
/// zwischen einer lokalen Mutation und dem nächsten `CKSyncEngine`-State-Update keine
/// ausstehende Änderung stillschweigend verliert (Muster aus Apples eigenem Sample-Code
/// `apple/sample-cloudkit-sync-engine`).
struct CloudSyncPendingChangeRecord: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable, Sendable {
    static let databaseTableName = "cloud_sync_pending_changes"

    var id: String
    var recordType: String
    var changeType: CloudSyncChangeType
    var queuedAt: Date
}
```

- [ ] **Step 3: Fehlschlagenden Test für `CloudSyncPendingChangeStore` schreiben**

`FeedivoTests/CloudSyncPendingChangeStoreTests.swift`:

```swift
import Foundation
import Testing
import GRDB
@testable import Feedivo

struct CloudSyncPendingChangeStoreTests {
    @Test func enqueueUndPendingChangesRoundtrip() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = CloudSyncPendingChangeStore(database: database)

        try store.enqueue(recordType: "tag", recordName: "tag-1", changeType: .save)

        let pending = try store.pendingChanges()
        #expect(pending.count == 1)
        #expect(pending[0].id == "tag-1")
        #expect(pending[0].recordType == "tag")
        #expect(pending[0].changeType == .save)
    }

    @Test func enqueueUeberschreibtBestehendenEintragFuerDieselbeID() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = CloudSyncPendingChangeStore(database: database)

        try store.enqueue(recordType: "tag", recordName: "tag-1", changeType: .save)
        try store.enqueue(recordType: "tag", recordName: "tag-1", changeType: .delete)

        let pending = try store.pendingChanges()
        #expect(pending.count == 1)
        #expect(pending[0].changeType == .delete)
    }

    @Test func dequeueEntferntEintrag() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = CloudSyncPendingChangeStore(database: database)

        try store.enqueue(recordType: "tag", recordName: "tag-1", changeType: .save)
        try store.dequeue(recordName: "tag-1")

        #expect(try store.pendingChanges().isEmpty)
    }

    @Test func pendingChangesSindNachQueuedAtSortiert() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = CloudSyncPendingChangeStore(database: database)

        try store.enqueue(recordType: "tag", recordName: "tag-2", changeType: .save)
        try store.enqueue(recordType: "tag", recordName: "tag-1", changeType: .save)

        let pending = try store.pendingChanges()
        #expect(pending.map(\.id) == ["tag-2", "tag-1"])
    }

    @Test func staticEnqueueFunktioniertInnerhalbBestehenderTransaktion() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        try database.write { db in
            try CloudSyncPendingChangeStore.enqueue(db, recordType: "tag", recordName: "tag-1", changeType: .save)
        }

        let store = CloudSyncPendingChangeStore(database: database)
        #expect(try store.pendingChanges().count == 1)
    }
}
```

- [ ] **Step 4: Tests laufen lassen, sollten mit "cannot find CloudSyncPendingChangeStore" fehlschlagen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CloudSyncPendingChangeStoreTests`
Expected: FAIL (Compile-Fehler, Typ existiert noch nicht)

- [ ] **Step 5: `CloudSyncPendingChangeStore` implementieren**

`Feedivo/Stores/CloudSyncPendingChangeStore.swift`:

```swift
import Foundation
import GRDB

/// App-eigene, durable Warteschlange für Datensätze, die noch zu CloudKit hochgeladen werden
/// müssen (siehe `CloudSyncPendingChangeRecord`-Dokumentation). Analog zu den übrigen
/// `*Store`-Typen (ein Store pro Tabelle) aufgebaut.
struct CloudSyncPendingChangeStore {
    private let database: FeedivoDatabase

    init(database: FeedivoDatabase) {
        self.database = database
    }

    func enqueue(recordType: String, recordName: String, changeType: CloudSyncChangeType) throws {
        try database.write { db in
            try Self.enqueue(db, recordType: recordType, recordName: recordName, changeType: changeType)
        }
    }

    /// Variante für Aufrufer, die bereits in einer eigenen `database.write`-Transaktion stecken
    /// (z. B. `TagStore`) — hält die fachliche Mutation und das Pending-Change-Markieren atomar.
    static func enqueue(_ db: Database, recordType: String, recordName: String, changeType: CloudSyncChangeType) throws {
        var change = CloudSyncPendingChangeRecord(
            id: recordName,
            recordType: recordType,
            changeType: changeType,
            queuedAt: Date()
        )
        try change.save(db)
    }

    func dequeue(recordName: String) throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM cloud_sync_pending_changes WHERE id = ?", arguments: [recordName])
        }
    }

    func pendingChanges() throws -> [CloudSyncPendingChangeRecord] {
        try database.read { db in
            try CloudSyncPendingChangeRecord.fetchAll(db, sql: """
                SELECT * FROM cloud_sync_pending_changes ORDER BY queuedAt
                """)
        }
    }
}
```

- [ ] **Step 6: Tests laufen lassen, sollten bestehen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CloudSyncPendingChangeStoreTests`
Expected: PASS (5 Tests)

- [ ] **Step 7: Commit**

```bash
git add Feedivo/Database/FeedivoDatabaseMigrator.swift Feedivo/Database/Records/CloudSyncPendingChangeRecord.swift Feedivo/Stores/CloudSyncPendingChangeStore.swift FeedivoTests/CloudSyncPendingChangeStoreTests.swift
git commit -m "Feature: CloudSyncPendingChangeRecord/Store + Migration v21 (iCloud Sync Phase 1)"
```

---

## Task 2: CloudSyncTagMapping (reine Mapping-Funktionen)

**Files:**
- Create: `Feedivo/Services/CloudSync/CloudSyncTagMapping.swift`
- Test: `FeedivoTests/CloudSyncTagMappingTests.swift`

**Interfaces:**
- Consumes: `TagRecord` (`Feedivo/Database/Records/TagRecord.swift`) — Felder `id: String`,
  `name: String`, `colorHex: String`, `sortIndex: Int`, `createdAt: Date`, `updatedAt: Date`
- Produces:
  - `enum CloudSyncTagMapping`
  - `static let recordType: String = "Tag"`
  - `static let zoneName: String = "FeedivoZone"`
  - `static func zoneID() -> CKRecordZone.ID`
  - `static func recordID(forTagID tagID: String) -> CKRecord.ID`
  - `static func makeCKRecord(from tag: TagRecord, existing: CKRecord? = nil) -> CKRecord`
  - `static func tagRecord(from ckRecord: CKRecord) -> TagRecord?`

- [ ] **Step 1: Fehlschlagenden Test schreiben**

`FeedivoTests/CloudSyncTagMappingTests.swift`:

```swift
import Foundation
import CloudKit
import Testing
@testable import Feedivo

struct CloudSyncTagMappingTests {
    @Test func recordIDNutztTagIDAlsRecordNameInnerhalbDerFeedivoZone() {
        let recordID = CloudSyncTagMapping.recordID(forTagID: "tag-1")

        #expect(recordID.recordName == "tag-1")
        #expect(recordID.zoneID.zoneName == "FeedivoZone")
    }

    @Test func makeCKRecordMapptAlleFelder() {
        let tag = TagRecord(id: "tag-1", name: "Wichtig", colorHex: "#FF0000", sortIndex: 3)

        let record = CloudSyncTagMapping.makeCKRecord(from: tag)

        #expect(record.recordType == "Tag")
        #expect(record.recordID.recordName == "tag-1")
        #expect(record["name"] as? String == "Wichtig")
        #expect(record["colorHex"] as? String == "#FF0000")
        #expect(record["sortIndex"] as? Int == 3)
    }

    @Test func makeCKRecordAktualisiertBestehendesRecordStattEinNeuesZuErzeugen() {
        let tag = TagRecord(id: "tag-1", name: "Wichtig", colorHex: "#FF0000", sortIndex: 3)
        let existing = CKRecord(recordType: "Tag", recordID: CloudSyncTagMapping.recordID(forTagID: "tag-1"))

        let record = CloudSyncTagMapping.makeCKRecord(from: tag, existing: existing)

        #expect(record === existing)
        #expect(record["name"] as? String == "Wichtig")
    }

    @Test func tagRecordFromCKRecordMapptZurueck() {
        let source = TagRecord(id: "tag-1", name: "Wichtig", colorHex: "#FF0000", sortIndex: 3)
        let ckRecord = CloudSyncTagMapping.makeCKRecord(from: source)

        let mapped = CloudSyncTagMapping.tagRecord(from: ckRecord)

        #expect(mapped?.id == "tag-1")
        #expect(mapped?.name == "Wichtig")
        #expect(mapped?.colorHex == "#FF0000")
        #expect(mapped?.sortIndex == 3)
    }

    @Test func tagRecordFromCKRecordLiefertNilBeiFehlendenPflichtfeldern() {
        let ckRecord = CKRecord(recordType: "Tag", recordID: CloudSyncTagMapping.recordID(forTagID: "tag-1"))
        // Absichtlich keine Felder gesetzt.

        #expect(CloudSyncTagMapping.tagRecord(from: ckRecord) == nil)
    }
}
```

- [ ] **Step 2: Test laufen lassen, sollte fehlschlagen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CloudSyncTagMappingTests`
Expected: FAIL (Compile-Fehler, `CloudSyncTagMapping` existiert noch nicht)

- [ ] **Step 3: `CloudSyncTagMapping` implementieren**

`Feedivo/Services/CloudSync/CloudSyncTagMapping.swift`:

```swift
import Foundation
import CloudKit

/// Reine, CloudKit-Netzwerk-freie Mapping-Funktionen zwischen `TagRecord` (GRDB) und `CKRecord`
/// (CloudKit). `CKRecord`-Konstruktion selbst löst keinen Netzwerkzugriff aus — direkt
/// unit-testbar ohne echtes CloudKit-Konto.
enum CloudSyncTagMapping {
    static let recordType = "Tag"
    static let zoneName = "FeedivoZone"

    static func zoneID() -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
    }

    static func recordID(forTagID tagID: String) -> CKRecord.ID {
        CKRecord.ID(recordName: tagID, zoneID: zoneID())
    }

    /// Baut ein `CKRecord` aus einem `TagRecord`. Wird `existing` übergeben (ein von
    /// `CKSyncEngine` geliefertes Record, z. B. beim erneuten Versuch nach einem
    /// Server-Konflikt), wird DIESES Objekt mutiert statt ein neues zu erzeugen — nötig, damit
    /// CloudKits interne Change-Tag-/Server-Record-Verwaltung für die `.ifServerRecordUnchanged`-
    /// Speicherpolicy erhalten bleibt.
    static func makeCKRecord(from tag: TagRecord, existing: CKRecord? = nil) -> CKRecord {
        let record = existing ?? CKRecord(recordType: recordType, recordID: recordID(forTagID: tag.id))
        record["name"] = tag.name as CKRecordValue
        record["colorHex"] = tag.colorHex as CKRecordValue
        record["sortIndex"] = tag.sortIndex as CKRecordValue
        return record
    }

    static func tagRecord(from ckRecord: CKRecord) -> TagRecord? {
        guard
            let name = ckRecord["name"] as? String,
            let colorHex = ckRecord["colorHex"] as? String,
            let sortIndex = ckRecord["sortIndex"] as? Int
        else {
            return nil
        }

        return TagRecord(
            id: ckRecord.recordID.recordName,
            name: name,
            colorHex: colorHex,
            sortIndex: sortIndex,
            createdAt: ckRecord.creationDate ?? Date(),
            updatedAt: ckRecord.modificationDate ?? Date()
        )
    }
}
```

- [ ] **Step 4: Test laufen lassen, sollte bestehen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CloudSyncTagMappingTests`
Expected: PASS (5 Tests)

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Services/CloudSync/CloudSyncTagMapping.swift FeedivoTests/CloudSyncTagMappingTests.swift
git commit -m "Feature: CloudSyncTagMapping (TagRecord <-> CKRecord, iCloud Sync Phase 1)"
```

---

## Task 3: CloudSyncStatus + CloudSyncEngine (CKSyncEngine-Wrapper)

**WICHTIG — vor Step 1:** Da diese Task die neueste, am schwersten per Tooling verifizierbare
Apple-API dieses Plans verwendet, zuerst in Xcode kurz `import CloudKit` in eine Scratch-Datei
schreiben und per ⌘-Klick auf `CKSyncEngine`, `CKSyncEngineDelegate`, `CKSyncEngine.Event`,
`CKSyncEngine.State`, `CKSyncEngine.RecordZoneChangeBatch` ins generierte Interface springen —
Namen/Signaturen unten sind ein fundiert recherchierter, aber nicht 100 % garantierter Entwurf.
Bei Abweichungen die echten SDK-Namen verwenden, nicht den untenstehenden Code blind übernehmen.

**Files:**
- Create: `Feedivo/Services/CloudSync/CloudSyncStatus.swift`
- Create: `Feedivo/Services/CloudSync/CloudSyncEngine.swift`

**Interfaces:**
- Consumes: `CloudSyncPendingChangeStore` (Task 1), `CloudSyncTagMapping` (Task 2),
  `TagStore.tags() throws -> [TagRecord]` (bestehend), `FeedivoDatabase.write`/`.read`
  (bestehend), `SQLiteDataInvalidation.bumpStatusVersion()` (bestehend),
  `AppLogger.dataAccess` (bestehend), `CloudSyncSettings.cloudKitContainerIdentifier`
  (bestehend, unverändert `"iCloud.ch.martin.Feedivo"`)
- Produces:
  - `@Observable final class CloudSyncStatus` mit `enum State: Equatable { case idle, syncing, accountUnavailable, error(String) }` und `var state: State`
  - `@MainActor final class CloudSyncEngine: NSObject, CKSyncEngineDelegate` mit
    `init(database: FeedivoDatabase)`, `let status: CloudSyncStatus`, `func start()`, `func stop()`

Kein isolierter Unit-Test für diese Task — `CKSyncEngine` selbst lässt sich nicht ohne echtes
CloudKit-Konto sinnvoll mocken (siehe Design-Spec, Abschnitt "Tests"). Verifikation läuft über
Build-Erfolg hier und über die Live-Verifikation in Task 6 (CloudKit Dashboard).

- [ ] **Step 1: `CloudSyncStatus` schreiben**

`Feedivo/Services/CloudSync/CloudSyncStatus.swift`:

```swift
import Foundation
import Observation

/// Hält den aktuellen iCloud-Sync-Status für die Settings-UI. Eigene, CloudKit-freie Datei,
/// damit `CloudSyncSettings.swift` (liest u. a. `state` für den Status-Text) nicht `CloudKit`
/// importieren muss.
@Observable
final class CloudSyncStatus {
    enum State: Equatable {
        case idle
        case syncing
        case accountUnavailable
        case error(String)
    }

    var state: State = .idle
}
```

- [ ] **Step 2: `CloudSyncEngine` schreiben**

`Feedivo/Services/CloudSync/CloudSyncEngine.swift`:

```swift
import Foundation
import CloudKit
import GRDB
import OSLog

/// Wrapper um Apples `CKSyncEngine` für die private CloudKit-Datenbank. Läuft komplett auf dem
/// MainActor (Projektkonvention, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`). `start()`/`stop()`
/// sind bewusst so gebaut, dass sie ohne App-Neustart aufgerufen werden können (Toggle in den
/// Einstellungen wirkt sofort).
@MainActor
final class CloudSyncEngine: NSObject {
    private static let stateSerializationKey = "cloudSync.stateSerialization"
    private static let hasCreatedZoneKey = "cloudSync.hasCreatedZone"

    private let database: FeedivoDatabase
    private let pendingChangeStore: CloudSyncPendingChangeStore
    let status = CloudSyncStatus()

    private var syncEngine: CKSyncEngine?

    init(database: FeedivoDatabase) {
        self.database = database
        self.pendingChangeStore = CloudSyncPendingChangeStore(database: database)
        super.init()
    }

    func start() {
        guard syncEngine == nil else { return }

        Task {
            let container = CKContainer(identifier: CloudSyncSettings.cloudKitContainerIdentifier)

            let accountStatus = (try? await container.accountStatus()) ?? .couldNotDetermine
            guard accountStatus == .available else {
                status.state = .accountUnavailable
                return
            }

            let storedSerialization = Self.loadStateSerialization()
            var configuration = CKSyncEngine.Configuration(
                database: container.privateCloudDatabase,
                stateSerialization: storedSerialization,
                delegate: self
            )
            configuration.automaticallySync = true

            let engine = CKSyncEngine(configuration)
            self.syncEngine = engine

            if !UserDefaults.standard.bool(forKey: Self.hasCreatedZoneKey) {
                engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: CloudSyncTagMapping.zoneID()))])
                UserDefaults.standard.set(true, forKey: Self.hasCreatedZoneKey)
            }

            if let pending = try? pendingChangeStore.pendingChanges(), !pending.isEmpty {
                let recordIDs = pending.map { CloudSyncTagMapping.recordID(forTagID: $0.id) }
                engine.state.add(pendingRecordZoneChanges: recordIDs)
            }

            status.state = .idle
        }
    }

    func stop() {
        syncEngine = nil
        status.state = .idle
    }

    private static func loadStateSerialization() -> CKSyncEngine.State.Serialization? {
        guard let data = UserDefaults.standard.data(forKey: stateSerializationKey) else {
            return nil
        }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    private static func persist(_ serialization: CKSyncEngine.State.Serialization) {
        guard let data = try? JSONEncoder().encode(serialization) else { return }
        UserDefaults.standard.set(data, forKey: stateSerializationKey)
    }
}

extension CloudSyncEngine: CKSyncEngineDelegate {
    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let stateUpdate):
            Self.persist(stateUpdate.stateSerialization)

        case .accountChange(let change):
            switch change.changeType {
            case .signIn, .switchAccounts:
                status.state = .idle
            case .signOut:
                status.state = .accountUnavailable
            @unknown default:
                break
            }

        case .fetchedRecordZoneChanges(let changes):
            for modification in changes.modifications {
                await applyIncomingRecord(modification.record)
            }
            for deletion in changes.deletions {
                await applyIncomingDeletion(deletion.recordID)
            }

        case .sentRecordZoneChanges(let changes):
            for saved in changes.savedRecords {
                try? pendingChangeStore.dequeue(recordName: saved.recordID.recordName)
            }
            for deletedID in changes.deletedRecordIDs {
                try? pendingChangeStore.dequeue(recordName: deletedID.recordName)
            }
            for failedSave in changes.failedRecordSaves {
                await handleFailedSave(failedSave)
            }

        default:
            break
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        guard !changes.isEmpty else { return nil }

        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { recordID in
            await self.record(forPendingChange: recordID)
        }
    }

    private func record(forPendingChange recordID: CKRecord.ID) async -> CKRecord? {
        guard let tag = (try? TagStore(database: database).tags())?.first(where: { $0.id == recordID.recordName }) else {
            return nil
        }
        return CloudSyncTagMapping.makeCKRecord(from: tag)
    }

    private func applyIncomingRecord(_ record: CKRecord) async {
        guard let incoming = CloudSyncTagMapping.tagRecord(from: record) else { return }
        try? database.write { db in
            try incoming.save(db)
        }
        SQLiteDataInvalidation.bumpStatusVersion()
    }

    private func applyIncomingDeletion(_ recordID: CKRecord.ID) async {
        try? database.write { db in
            try db.execute(sql: "DELETE FROM tags WHERE id = ?", arguments: [recordID.recordName])
        }
        SQLiteDataInvalidation.bumpStatusVersion()
    }

    /// Last-Write-Wins: bei einem Server-Konflikt (`.serverRecordChanged`) gewinnt die Seite mit
    /// dem neueren Zeitstempel (`CKRecord.modificationDate` vs. `TagRecord.updatedAt`).
    private func handleFailedSave(_ failedSave: CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave) async {
        guard failedSave.error.code == .serverRecordChanged else {
            status.state = .error(failedSave.error.localizedDescription)
            AppLogger.dataAccess.error("iCloud Sync: Record-Save fehlgeschlagen: \(failedSave.error.localizedDescription, privacy: .public)")
            return
        }

        guard let serverRecord = failedSave.error.serverRecord else { return }

        let localTag = (try? TagStore(database: database).tags())?.first { $0.id == failedSave.record.recordID.recordName }
        let serverIsNewer = (serverRecord.modificationDate ?? .distantPast) > (localTag?.updatedAt ?? .distantPast)

        if serverIsNewer {
            await applyIncomingRecord(serverRecord)
        } else {
            try? pendingChangeStore.enqueue(recordType: "tag", recordName: failedSave.record.recordID.recordName, changeType: .save)
        }
    }
}
```

- [ ] **Step 3: Build ausführen und Compiler-Fehler gegen die echte SDK-Signatur korrigieren**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`
Expected: Zunächst möglicherweise Fehler bei einzelnen `CKSyncEngine`-Typnamen/Signaturen —
per Xcode-Quick-Help/generiertem Interface korrigieren (siehe Hinweis am Task-Anfang), bis
BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add Feedivo/Services/CloudSync/CloudSyncStatus.swift Feedivo/Services/CloudSync/CloudSyncEngine.swift
git commit -m "Feature: CloudSyncEngine (CKSyncEngine-Wrapper fuer Tags, iCloud Sync Phase 1)"
```

---

## Task 4: CloudSyncSettings-Refactor + TagStore-Wiring

**Files:**
- Modify: `Feedivo/Services/CloudSyncSettings.swift`
- Modify: `FeedivoTests/CloudSyncSettingsTests.swift`
- Modify: `Feedivo/Stores/TagStore.swift`
- Test: neue Fälle in einer bestehenden Testdatei — prüfen, ob `FeedivoTests/SQLiteRuleStoreTests.swift`
  oder eine eigene `TagStoreTests.swift` existiert (siehe Step 5 unten)

**Interfaces:**
- Consumes: `CloudSyncStatus.State` (Task 3)
- Produces (geändert): `CloudSyncSettings.isAvailable == true`,
  `CloudSyncSettings.statusLocalizationKey(isEnabled: Bool, syncState: CloudSyncStatus.State, hasDatabaseError: Bool) -> String`
  (ersetzt die alte Signatur mit `isEnabledAtLaunch`/`currentIsEnabled`)

- [ ] **Step 1: `CloudSyncSettings.swift` refactoren**

Vollständiger neuer Inhalt für `Feedivo/Services/CloudSyncSettings.swift`:

```swift
import Foundation

/// Persistente Einstellung für iCloud Sync (Phase 1: nur Tags, siehe
/// docs/superpowers/specs/2026-07-24-icloud-sync-phase1-design.md). Der Toggle wirkt sofort,
/// kein Neustart nötig — anders als der ursprüngliche, überholte SwiftData-Plan
/// (docs/superpowers/specs/2026-07-01-icloud-sync-beta-design.md).
enum CloudSyncSettings {
    static let isAvailable = true
    static let isEnabledKey = "cloudSync.isEnabled"
    static let defaultIsEnabled = false
    static let cloudKitContainerIdentifier = "iCloud.ch.martin.Feedivo"

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: isEnabledKey) != nil else {
            return defaultIsEnabled
        }
        return defaults.bool(forKey: isEnabledKey)
    }

    static func statusLocalizationKey(
        isEnabled: Bool,
        syncState: CloudSyncStatus.State,
        hasDatabaseError: Bool
    ) -> String {
        if hasDatabaseError {
            return "settings.sync.status.databaseError"
        }

        guard isEnabled else {
            return "settings.sync.status.local"
        }

        switch syncState {
        case .idle, .syncing:
            return "settings.sync.status.active"
        case .accountUnavailable:
            return "settings.sync.status.accountUnavailable"
        case .error:
            return "settings.sync.status.error"
        }
    }
}
```

- [ ] **Step 2: `CloudSyncSettingsTests.swift` an neue Signatur anpassen**

Vollständiger neuer Inhalt für `FeedivoTests/CloudSyncSettingsTests.swift`:

```swift
import Foundation
import Testing
@testable import Feedivo

struct CloudSyncSettingsTests {
    @Test func defaultsUndVerfuegbarkeit() {
        #expect(CloudSyncSettings.isEnabledKey == "cloudSync.isEnabled")
        #expect(CloudSyncSettings.defaultIsEnabled == false)
        #expect(CloudSyncSettings.isAvailable == true)
        #expect(CloudSyncSettings.cloudKitContainerIdentifier == "iCloud.ch.martin.Feedivo")
    }

    @Test func isEnabledLiestGespeichertenWert() throws {
        let defaults = try temporaryUserDefaults()

        #expect(CloudSyncSettings.isEnabled(in: defaults) == false)

        defaults.set(true, forKey: CloudSyncSettings.isEnabledKey)

        #expect(CloudSyncSettings.isEnabled(in: defaults) == true)
    }

    @Test func statusLocalizationKeyLiefertDatabaseErrorUnabhaengigVonAllemAnderen() {
        #expect(
            CloudSyncSettings.statusLocalizationKey(isEnabled: true, syncState: .idle, hasDatabaseError: true)
                == "settings.sync.status.databaseError"
        )
    }

    @Test func statusLocalizationKeyLiefertLocalWennDeaktiviert() {
        #expect(
            CloudSyncSettings.statusLocalizationKey(isEnabled: false, syncState: .idle, hasDatabaseError: false)
                == "settings.sync.status.local"
        )
    }

    @Test func statusLocalizationKeyLiefertActiveBeiIdleUndSyncing() {
        #expect(
            CloudSyncSettings.statusLocalizationKey(isEnabled: true, syncState: .idle, hasDatabaseError: false)
                == "settings.sync.status.active"
        )
        #expect(
            CloudSyncSettings.statusLocalizationKey(isEnabled: true, syncState: .syncing, hasDatabaseError: false)
                == "settings.sync.status.active"
        )
    }

    @Test func statusLocalizationKeyLiefertAccountUnavailable() {
        #expect(
            CloudSyncSettings.statusLocalizationKey(isEnabled: true, syncState: .accountUnavailable, hasDatabaseError: false)
                == "settings.sync.status.accountUnavailable"
        )
    }

    @Test func statusLocalizationKeyLiefertError() {
        #expect(
            CloudSyncSettings.statusLocalizationKey(isEnabled: true, syncState: .error("Netzwerkfehler"), hasDatabaseError: false)
                == "settings.sync.status.error"
        )
    }
}

private func temporaryUserDefaults() throws -> UserDefaults {
    let suiteName = "FeedivoTests.CloudSyncSettings.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
```

- [ ] **Step 3: Tests laufen lassen (sollten jetzt bestehen)**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CloudSyncSettingsTests`
Expected: PASS (7 Tests)

- [ ] **Step 4: `TagStore.swift` um Pending-Change-Hooks erweitern**

In `Feedivo/Stores/TagStore.swift` nach der bestehenden `init`-Methode (vor `func save`) einen
privaten Helfer ergänzen:

```swift
    /// Markiert `tagID` als ausstehende Sync-Änderung, falls iCloud Sync aktiv ist. Läuft
    /// bewusst INNERHALB derselben `database.write`-Transaktion wie die fachliche Mutation
    /// (atomar — kein Zwischenzustand, in dem der Tag geändert, aber nicht als sync-pending
    /// markiert ist).
    private func enqueuePendingSync(_ db: Database, tagID: String, changeType: CloudSyncChangeType) throws {
        guard CloudSyncSettings.isEnabled() else { return }
        try CloudSyncPendingChangeStore.enqueue(db, recordType: "tag", recordName: tagID, changeType: changeType)
    }
```

Dann folgende fünf Mutationsmethoden anpassen (jeweils den bestehenden `database.write { db in ... }`-Body
um einen Aufruf von `enqueuePendingSync` ergänzen, unmittelbar nach der jeweiligen SQL-Änderung):

`save(_:)` — nach dem `if let existingID { ... } else { ... }`-Block, vor dem schließenden `}` der Closure:
```swift
            try enqueuePendingSync(db, tagID: tag.id, changeType: .save)
```

`renameTag(id:name:)` — nach der `UPDATE`- und `changesCount`-Prüfung, vor dem schließenden `}`:
```swift
            try enqueuePendingSync(db, tagID: id, changeType: .save)
```

`move(id:targetIndex:)` — INNERHALB der bestehenden `for (index, tagID) in orderedIDs.enumerated()`-Schleife,
direkt nach dem vorhandenen `db.execute(sql: "UPDATE tags SET sortIndex = ...")`-Aufruf (alle verschobenen
Tags müssen markiert werden, nicht nur der explizit bewegte):
```swift
                try enqueuePendingSync(db, tagID: tagID, changeType: .save)
```

`updateColor(id:colorHex:)` — nach der `UPDATE`- und `changesCount`-Prüfung, vor dem schließenden `}`:
```swift
            try enqueuePendingSync(db, tagID: id, changeType: .save)
```

`deleteTag(id:)` — nach dem `DELETE`-Aufruf, vor dem schließenden `}`:
```swift
            try enqueuePendingSync(db, tagID: id, changeType: .delete)
```

- [ ] **Step 5: Bestehende Store-Tests-Datei für TagStore suchen und Regressionstest ergänzen**

Run: `find FeedivoTests -iname "*TagStore*"`

Falls eine Datei existiert (z. B. `FeedivoTests/TagStoreTests.swift`), dort folgenden Test
ergänzen (Datei- und Test-Namenskonvention der bestehenden Datei beibehalten). Falls keine
Datei existiert, `FeedivoTests/TagStoreTests.swift` neu anlegen mit mindestens folgendem Test
(Setup analog zu bestehenden Store-Tests — `FeedivoDatabase.inMemoryForTests()` verwenden):

```swift
    @Test func saveMarkiertTagAlsPendingSyncWennAktiviert() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        UserDefaults.standard.set(true, forKey: CloudSyncSettings.isEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey) }
        let store = TagStore(database: database)

        try store.save(TagRecord(id: "tag-1", name: "Wichtig"))

        let pending = try CloudSyncPendingChangeStore(database: database).pendingChanges()
        #expect(pending.map(\.id) == ["tag-1"])
    }

    @Test func saveMarkiertNichtsWennSyncDeaktiviert() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey)
        let store = TagStore(database: database)

        try store.save(TagRecord(id: "tag-1", name: "Wichtig"))

        #expect(try CloudSyncPendingChangeStore(database: database).pendingChanges().isEmpty)
    }
```

**Achtung:** `CloudSyncSettings.isEnabled()` liest ohne Parameter aus `UserDefaults.standard` —
für einen isolierten Test kann daher NICHT die `temporaryUserDefaults()`-Hilfsfunktion aus
`CloudSyncSettingsTests.swift` verwendet werden (Swift-`private` auf Dateiebene ist
file-private, in einer neuen `TagStoreTests.swift`-Datei nicht sichtbar). Stattdessen wird
direkt `UserDefaults.standard` verwendet und der Key per `defer` wieder entfernt (siehe oben) —
das ist der einzige Weg, da `TagStore.enqueuePendingSync` aus Task 4 bewusst ohne
`defaults`-Parameter gebaut wurde (kein bestehender Präzedenzfall für `UserDefaults`-Injection
direkt in `TagStore`). Falls beim Schreiben dieses Tests Store-Setup-Konventionen (z. B. ein
Test-Helper für `TagStore`) in der gefundenen/neuen Testdatei abweichen, an die dortige
Konvention anpassen statt den obigen Code wörtlich zu übernehmen.

- [ ] **Step 6: Tests laufen lassen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/TagStoreTests -only-testing:FeedivoTests/CloudSyncSettingsTests`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add Feedivo/Services/CloudSyncSettings.swift FeedivoTests/CloudSyncSettingsTests.swift Feedivo/Stores/TagStore.swift FeedivoTests/TagStoreTests.swift
git commit -m "Feature: CloudSyncSettings-Refactor (kein Neustart-Konzept mehr) + TagStore-Sync-Wiring"
```

---

## Task 5: Settings-UI + FeedivoApp-Wiring

**Files:**
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`
- Modify: `Feedivo/Views/Settings/SettingsView.swift`
- Modify: `Feedivo/App/FeedivoApp.swift`

**Interfaces:**
- Consumes: `CloudSyncEngine` (Task 3), `CloudSyncSettings` (Task 4)
- Produces: `\.cloudSyncEngine`-artige Environment-Bereitstellung (als einfaches
  `@Environment`-Objekt über `.environment(cloudSyncEngine)`, analog zu `databaseLoadState`)

- [ ] **Step 1: Neue L10n-Keys ergänzen**

In `Feedivo/Resources/L10n.swift`, direkt nach der bestehenden Zeile
`static let settingsSyncDatabaseErrorHint = LocalizedStringKey("settings.sync.databaseError.hint")`:

```swift
    static let settingsSyncBetaScopeHint = LocalizedStringKey("settings.sync.beta.scopeHint")
```

- [ ] **Step 2: Neue Katalogeinträge in `Localizable.xcstrings` einfügen (Text-Anker, kein JSON-Roundtrip)**

In `Feedivo/Resources/Localizable.xcstrings` den Text unmittelbar VOR der Zeile
`"settings.sync.status.databaseError" : {` einfügen (exakt dieses Einrückungsmuster
übernehmen, Komma am Ende nicht vergessen):

```
    "settings.sync.beta.scopeHint" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "In dieser frühen Beta wird zunächst nur Tags synchronisiert."
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "This early beta currently syncs tags only."
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Cette bêta précoce ne synchronise pour l’instant que les tags."
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Questa beta iniziale sincronizza per ora solo i tag."
          }
        }
      }
    },
    "settings.sync.status.accountUnavailable" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Kein iCloud-Konto angemeldet"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "No iCloud account signed in"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Aucun compte iCloud connecté"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Nessun account iCloud connesso"
          }
        }
      }
    },
    "settings.sync.status.error" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Synchronisierung fehlgeschlagen"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Sync failed"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Échec de la synchronisation"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Sincronizzazione non riuscita"
          }
        }
      }
    },
```

Danach sofort prüfen:

Run: `git diff --stat Feedivo/Resources/Localizable.xcstrings`
Expected: Nur Insertions (deutlich unter 200 Zeilen), keine oder kaum Deletions. Bei
abweichendem Ergebnis (z. B. tausende geänderte Zeilen) sofort stoppen, Datei per
`git checkout -- Feedivo/Resources/Localizable.xcstrings` zurücksetzen und die Einfügung erneut
per gezieltem Text-Editor-Aufruf (nicht per Skript mit JSON-Serialisierung) versuchen.

- [ ] **Step 3: `SyncSettingsView` in `SettingsView.swift` neu verdrahten**

Der bisherige `SyncSettingsView`-Body (`Feedivo/Views/Settings/SettingsView.swift`, ab Zeile
1056) wird komplett ersetzt durch:

```swift
private struct SyncSettingsView: View {
    @Environment(DatabaseLoadState.self) private var databaseLoadState
    @Environment(CloudSyncStatus.self) private var cloudSyncStatus
    @Environment(\.cloudSyncEngine) private var cloudSyncEngine

    @AppStorage(CloudSyncSettings.isEnabledKey)
    private var cloudSyncIsEnabled = CloudSyncSettings.defaultIsEnabled

    private var hasDatabaseError: Bool {
        databaseLoadState.initializationError != nil
    }

    private var statusLocalizationKey: String {
        CloudSyncSettings.statusLocalizationKey(
            isEnabled: cloudSyncIsEnabled,
            syncState: cloudSyncStatus.state,
            hasDatabaseError: hasDatabaseError
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsBlock(eyebrow: L10n.settingsSyncSection) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "icloud")
                            .font(.system(size: 26, weight: .regular))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 32)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.settingsSyncBetaTitle)
                                .font(.system(size: 14, weight: .semibold))
                            Text(L10n.settingsSyncBetaDescription)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    SettingRow(
                        title: L10n.settingsSyncBetaTitle,
                        description: L10n.settingsSyncBetaScopeHint
                    ) {
                        Toggle("", isOn: $cloudSyncIsEnabled)
                            .toggleStyle(.switch)
                    }

                    InfoRow(
                        iconName: hasDatabaseError ? "exclamationmark.triangle" : "icloud",
                        title: L10n.settingsSyncStatusTitle,
                        description: LocalizedStringKey(statusLocalizationKey)
                    )

                    if hasDatabaseError {
                        InfoRow(
                            iconName: "internaldrive",
                            title: L10n.settingsSyncDatabaseTitle,
                            description: L10n.settingsSyncDatabaseErrorHint
                        )
                    }
                }
            }
        }
        .onChange(of: cloudSyncIsEnabled) {
            if cloudSyncIsEnabled {
                cloudSyncEngine?.start()
            } else {
                cloudSyncEngine?.stop()
            }
        }
    }
}
```

- [ ] **Step 4: `\.cloudSyncEngine`-Environment-Key ergänzen**

Neuer Abschnitt am Ende von `Feedivo/Views/Settings/SettingsView.swift` (oder in einer
bestehenden Environment-Key-Datei, falls eine existiert — vorher per
`grep -rn "EnvironmentKey" Feedivo/` prüfen und dort ergänzen; sonst direkt unten in
`SettingsView.swift` anfügen):

```swift
private struct CloudSyncEngineKey: EnvironmentKey {
    static let defaultValue: CloudSyncEngine? = nil
}

extension EnvironmentValues {
    var cloudSyncEngine: CloudSyncEngine? {
        get { self[CloudSyncEngineKey.self] }
        set { self[CloudSyncEngineKey.self] = newValue }
    }
}
```

- [ ] **Step 5: `FeedivoApp.swift` verdrahten**

In `Feedivo/App/FeedivoApp.swift`:

1. Neue gespeicherte Property nach `private let localExtensionBridgeServer: LocalExtensionBridgeServer`:

```swift
    private let cloudSyncEngine: CloudSyncEngine
```

2. Im `init()`, nach `self.localExtensionBridgeServer = LocalExtensionBridgeServer(database: database)`:

```swift
        self.cloudSyncEngine = CloudSyncEngine(database: database)
```

3. Am Ende des `init()`, nach dem bestehenden `if databaseOpenResult.errorDescription == nil { ... }`-Block:

```swift
        if databaseOpenResult.errorDescription == nil, CloudSyncSettings.isEnabled() {
            self.cloudSyncEngine.start()
        }
```

4. Die Zeile `self.databaseLoadState.isCloudSyncEnabledAtLaunch = false` (Zeile 61) komplett
   entfernen — das Restart-Konzept existiert nicht mehr, `DatabaseLoadState.isCloudSyncEnabledAtLaunch`
   wird nirgends mehr gelesen (per `grep -rn "isCloudSyncEnabledAtLaunch" Feedivo/` vor dem
   Löschen verifizieren, dass nach Task 5 keine Referenz mehr übrig bleibt — die einzige
   verbleibende Lesestelle war die alte `SyncSettingsView`, die in Step 3 bereits ersetzt wurde).
   Die `var isCloudSyncEnabledAtLaunch = false`-Property in `DatabaseLoadState` (Zeile 336) same
   file ebenfalls entfernen.

5. In `.environment(\.feedivoDatabase, feedivoDatabase)`-Ketten aller Scenes, die
   `SettingsView()` einbetten (nur die `Settings { ... }`-Scene, ca. Zeile 213–221), zusätzlich
   ergänzen:

```swift
                .environment(cloudSyncEngine.status)
                .environment(\.cloudSyncEngine, cloudSyncEngine)
```

- [ ] **Step 6: Build ausführen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Commit**

```bash
git add Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings Feedivo/Views/Settings/SettingsView.swift Feedivo/App/FeedivoApp.swift
git commit -m "Feature: iCloud-Sync-Settings-UI + Live-Start/Stop ohne Neustart (iCloud Sync Phase 1)"
```

---

## Task 6: Verifikation + Dokumentation

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Gezielte Tests laufen lassen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CloudSyncPendingChangeStoreTests -only-testing:FeedivoTests/CloudSyncTagMappingTests -only-testing:FeedivoTests/CloudSyncSettingsTests -only-testing:FeedivoTests/TagStoreTests`
Expected: PASS, keine neuen Fehlschläge zusätzlich zu den bekannten vorbestehenden (17 in
`FeedivoAppSceneConfigurationTests.swift`, 2 flaky in `FeedViewModelTests.swift` — siehe
CLAUDE.md-Gotchas)

- [ ] **Step 2: Vollen Build ausführen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Manuelle Live-Verifikation (Nutzeraktion, nicht automatisierbar)**

Voraussetzung: Task 0 (Xcode-Capability) erledigt, iCloud-Konto angemeldet.

1. Feedivo starten, Einstellungen → Sync-Tab öffnen, "iCloud Sync Beta" aktivieren.
2. Statuszeile sollte "iCloud Sync aktiv" zeigen (nicht "Kein iCloud-Konto angemeldet" — falls
   doch, iCloud-Anmeldung in den Systemeinstellungen prüfen).
3. Einen neuen Tag anlegen, z. B. "Sync-Test".
4. Im Browser https://icloud.developer.apple.com/dashboard/ öffnen → mit Apple-ID anmelden →
   Feedivo-Container auswählen → Environment "Development" → Private Database → Zone
   "FeedivoZone" → Record-Type "Tag" → Records durchsuchen. Der neue Tag sollte als `CKRecord`
   mit passendem `name`/`colorHex`/`sortIndex` erscheinen.
5. Tag umbenennen, im Dashboard erneut prüfen (aktualisiertes `name`-Feld, neue
   `modificationDate`).
6. Tag löschen, im Dashboard erneut prüfen (Record verschwindet).
7. **Bekannte Einschränkung, hier nicht testbar:** Pull-Richtung (Cloud → lokal) bleibt bis zur
   Verfügbarkeit eines zweiten Geräts unverifiziert — nicht versuchen, das zu erzwingen.

- [ ] **Step 4: CLAUDE.md aktualisieren**

Unter „Aktuell in Arbeit" in `CLAUDE.md` einen neuen Eintrag ergänzen (Format an bestehende
Einträge anlehnen), der festhält: Phase 1 (CKSyncEngine-Fundament, nur Tags) implementiert,
Spec/Plan-Pfade verlinkt, Pull-Richtung noch nicht live verifiziert (falls Step 3 das nicht
abdecken konnte), Phase 2–4 stehen noch aus. Nicht additiv zu den bestehenden Einträgen
schreiben, sondern als neuen eigenen Absatz mit Datum 2026-07-24.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md
git commit -m "Docs: iCloud Sync Phase 1 Abschlussdokumentation"
```

---

## Nach Abschluss

Phase 1 liefert ein funktionierendes, aber bewusst eingeschränktes Sync-Fundament (nur Tags).
Phase 2 (restliche Tabellen), Phase 3 (Feld-Ebene-Konflikte + Merge-Dialog bei Erst-Aktivierung)
und Phase 4 (Härtung) sind jeweils eigene, separate Brainstorming/Plan-Zyklen — nicht Teil
dieses Plans.
