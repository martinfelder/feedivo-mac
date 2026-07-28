# iCloud Sync Phase 2a Backfill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bestehende, vor der Sync-Aktivierung existierende (oder während Sync-aus bearbeitete) Feeds/Ordner/Regeln/Bedingungen/benutzerdefinierte Intelligente Ordner werden bei jedem `CloudSyncEngine.start()` einmalig erneut in die Pending-Sync-Queue eingereiht, statt dauerhaft nie gesynct zu werden.

**Architecture:** Neue Protokollanforderung `allLocalIDs(database:) throws -> [String]` auf `CloudSyncRecordMapping`, implementiert von allen 7 bestehenden Mapping-Typen. `CloudSyncEngine.start()` iteriert bei jedem Start über die Registry und enqueued alle lokalen IDs als `.save`.

**Tech Stack:** Swift, GRDB (SQLite), CloudKit (`CKSyncEngine`), Swift Testing.

## Global Constraints

- Backfill läuft bei JEDEM `start()`-Aufruf, kein `hasBackfilled`-Flag.
- Scope: nur erneutes Einreihen bestehender Zeilen als `.save`. Löschungen während Sync-aus werden NICHT nachträglich gemeldet — explizit außerhalb des Scopes, nicht anfassen.
- `isDefault`-Intelligente-Ordner + ihre Bedingungen werden NIE eingereiht — auch im Backfill nicht.
- Sprache für Code-Kommentare: Deutsch.
- Tests: Swift Testing (`@Test`/`#expect`), kein XCTest. Gezielt mit `-only-testing:FeedivoTests/<SuiteName>` laufen lassen, `-parallel-testing-enabled NO` bei mehreren Suiten gleichzeitig.
- Design-Referenz: `docs/superpowers/specs/2026-07-24-icloud-sync-phase2a-backfill-design.md`.

---

### Task 1: `allLocalIDs` auf allen 7 `CloudSyncRecordMapping`-Typen

**Files:**
- Modify: `Feedivo/Services/CloudSync/CloudSyncRecordMapping.swift` (neue Protokollanforderung)
- Modify: `Feedivo/Services/CloudSync/CloudSyncTagMapping.swift`
- Modify: `Feedivo/Services/CloudSync/CloudSyncFeedMapping.swift`
- Modify: `Feedivo/Services/CloudSync/CloudSyncFeedFolderMapping.swift`
- Modify: `Feedivo/Services/CloudSync/CloudSyncRuleMapping.swift`
- Modify: `Feedivo/Services/CloudSync/CloudSyncRuleConditionMapping.swift`
- Modify: `Feedivo/Services/CloudSync/CloudSyncSmartFolderMapping.swift`
- Modify: `Feedivo/Services/CloudSync/CloudSyncSmartFolderConditionMapping.swift`
- Test: `FeedivoTests/CloudSyncTagMappingTests.swift`, `CloudSyncFeedMappingTests.swift`, `CloudSyncFeedFolderMappingTests.swift`, `CloudSyncRuleMappingTests.swift`, `CloudSyncRuleConditionMappingTests.swift`, `CloudSyncSmartFolderMappingTests.swift` (je eine Ergänzung), `CloudSyncSmartFolderConditionMappingTests.swift` (falls nicht vorhanden, neu anlegen)

**Interfaces:**
- Produces: `static func allLocalIDs(database: FeedivoDatabase) throws -> [String]` auf allen 7 Typen — von Task 2 aufgerufen.

- [ ] **Step 1: Write the failing tests**

Ergänze in jeder der 6 bestehenden Mapping-Testdateien einen Test nach diesem Muster (Beispiel für `CloudSyncFeedMappingTests.swift`):

```swift
@Test func allLocalIDsListetAlleFeedsAuf() throws {
    let database = try makeTestDatabase()
    try FeedStore(database: database).save(FeedRecord(id: "feed-1", url: "https://a.example.com", title: "A"))
    try FeedStore(database: database).save(FeedRecord(id: "feed-2", url: "https://b.example.com", title: "B"))

    let ids = try CloudSyncFeedMapping.allLocalIDs(database: database)

    #expect(Set(ids) == Set(["feed-1", "feed-2"]))
}
```

Analog für Tag/FeedFolder/Rule/RuleCondition mit den jeweils passenden Store-Methoden und IDs.

Für `CloudSyncSmartFolderMappingTests.swift` zusätzlich der Ausschluss-Test:

```swift
@Test func allLocalIDsSchliesstDefaultOrdnerAus() throws {
    let database = try makeTestDatabase()
    let store = SQLiteSmartFolderStore(database: database)
    try store.restoreDefaultFolders()
    try store.save(SmartFolderRecord(id: "custom-1", name: "Meine Auswahl", isDefault: false), conditions: [])

    let ids = try CloudSyncSmartFolderMapping.allLocalIDs(database: database)

    #expect(ids == ["custom-1"])
}
```

Erstelle `FeedivoTests/CloudSyncSmartFolderConditionMappingTests.swift` (prüfe zuerst per `find FeedivoTests -iname "*SmartFolderCondition*"`, ob sie schon existiert) mit:

```swift
import Foundation
import CloudKit
import Testing
@testable import Feedivo

struct CloudSyncSmartFolderConditionMappingTests {
    @Test func allLocalIDsListetNurBedingungenNichtDefaultOrdnerAuf() throws {
        let database = try makeTestDatabase()
        let store = SQLiteSmartFolderStore(database: database)
        try store.restoreDefaultFolders()
        let customCondition = SmartFolderConditionRecord(id: "cond-custom", smartFolderID: "custom-1", field: "status", conditionOperator: "is", value: "unread")
        try store.save(SmartFolderRecord(id: "custom-1", name: "Meine Auswahl", isDefault: false), conditions: [customCondition])

        let ids = try CloudSyncSmartFolderConditionMapping.allLocalIDs(database: database)

        #expect(ids == ["cond-custom"])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CloudSyncFeedMappingTests -only-testing:FeedivoTests/CloudSyncSmartFolderMappingTests -only-testing:FeedivoTests/CloudSyncSmartFolderConditionMappingTests -parallel-testing-enabled NO 2>&1 | tail -40`
Expected: FAIL — `allLocalIDs` existiert noch nicht (Compile-Fehler).

- [ ] **Step 3: Add the protocol requirement**

In `Feedivo/Services/CloudSync/CloudSyncRecordMapping.swift`, ergänze im Protokoll (nach `localUpdatedAt`):

```swift
    /// Alle aktuell existierenden lokalen IDs dieser Tabelle — Grundlage für den Backfill
    /// bestehender Zeilen bei jedem `CloudSyncEngine.start()` (siehe Design-Spec
    /// `docs/superpowers/specs/2026-07-24-icloud-sync-phase2a-backfill-design.md`).
    static func allLocalIDs(database: FeedivoDatabase) throws -> [String]
```

- [ ] **Step 4: Implement `allLocalIDs` on all 7 mapping types**

In `Feedivo/Services/CloudSync/CloudSyncTagMapping.swift`:

```swift
    static func allLocalIDs(database: FeedivoDatabase) throws -> [String] {
        try database.read { db in
            try String.fetchAll(db, sql: "SELECT id FROM tags")
        }
    }
```

In `Feedivo/Services/CloudSync/CloudSyncFeedMapping.swift`:

```swift
    static func allLocalIDs(database: FeedivoDatabase) throws -> [String] {
        try database.read { db in
            try String.fetchAll(db, sql: "SELECT id FROM feeds")
        }
    }
```

In `Feedivo/Services/CloudSync/CloudSyncFeedFolderMapping.swift`:

```swift
    static func allLocalIDs(database: FeedivoDatabase) throws -> [String] {
        try database.read { db in
            try String.fetchAll(db, sql: "SELECT id FROM feed_folders")
        }
    }
```

In `Feedivo/Services/CloudSync/CloudSyncRuleMapping.swift`:

```swift
    static func allLocalIDs(database: FeedivoDatabase) throws -> [String] {
        try database.read { db in
            try String.fetchAll(db, sql: "SELECT id FROM rules")
        }
    }
```

In `Feedivo/Services/CloudSync/CloudSyncRuleConditionMapping.swift`:

```swift
    static func allLocalIDs(database: FeedivoDatabase) throws -> [String] {
        try database.read { db in
            try String.fetchAll(db, sql: "SELECT id FROM rule_conditions")
        }
    }
```

In `Feedivo/Services/CloudSync/CloudSyncSmartFolderMapping.swift`:

```swift
    static func allLocalIDs(database: FeedivoDatabase) throws -> [String] {
        try database.read { db in
            try String.fetchAll(db, sql: "SELECT id FROM smart_folders WHERE isDefault = 0")
        }
    }
```

In `Feedivo/Services/CloudSync/CloudSyncSmartFolderConditionMapping.swift`:

```swift
    static func allLocalIDs(database: FeedivoDatabase) throws -> [String] {
        try database.read { db in
            try String.fetchAll(db, sql: """
                SELECT sfc.id
                FROM smart_folder_conditions sfc
                JOIN smart_folders sf ON sf.id = sfc.smartFolderID
                WHERE sf.isDefault = 0
                """)
        }
    }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CloudSyncTagMappingTests -only-testing:FeedivoTests/CloudSyncFeedMappingTests -only-testing:FeedivoTests/CloudSyncFeedFolderMappingTests -only-testing:FeedivoTests/CloudSyncRuleMappingTests -only-testing:FeedivoTests/CloudSyncRuleConditionMappingTests -only-testing:FeedivoTests/CloudSyncSmartFolderMappingTests -only-testing:FeedivoTests/CloudSyncSmartFolderConditionMappingTests -parallel-testing-enabled NO 2>&1 | tail -60`
Expected: PASS

- [ ] **Step 6: Full build**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -60`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Commit**

```bash
git add Feedivo/Services/CloudSync/ FeedivoTests/CloudSyncTagMappingTests.swift FeedivoTests/CloudSyncFeedMappingTests.swift FeedivoTests/CloudSyncFeedFolderMappingTests.swift FeedivoTests/CloudSyncRuleMappingTests.swift FeedivoTests/CloudSyncRuleConditionMappingTests.swift FeedivoTests/CloudSyncSmartFolderMappingTests.swift FeedivoTests/CloudSyncSmartFolderConditionMappingTests.swift
git commit -m "Feature: allLocalIDs auf allen CloudSyncRecordMapping-Typen (iCloud Sync Backfill Task 1)"
```

---

### Task 2: Backfill-Schritt in `CloudSyncEngine.start()`

**Files:**
- Modify: `Feedivo/Services/CloudSync/CloudSyncEngine.swift`
- Test: `FeedivoTests/CloudSyncEngineRegistryTests.swift` (Ergänzung)

**Interfaces:**
- Consumes: `CloudSyncRecordMapping.allLocalIDs(database:)` (Task 1) für alle 7 registrierten Typen.

- [ ] **Step 1: Write the failing test**

Ergänze in `FeedivoTests/CloudSyncEngineRegistryTests.swift` (lies zuerst die aktuelle Datei, um den exakt passenden Aufbau/Imports zu übernehmen):

```swift
@Test func backfillAllExistingRecordsEnqueuedAlleBestehendenZeilenAlsSave() throws {
    let database = try makeTestDatabase()
    try TagStore(database: database).save(TagRecord(id: "tag-1", name: "Alt", colorHex: "#000000"))
    try FeedStore(database: database).save(FeedRecord(id: "feed-1", url: "https://a.example.com", title: "A"))

    try CloudSyncEngine.backfillAllExistingRecords(database: database)

    let pending = try CloudSyncPendingChangeStore(database: database).pendingChanges()
    let pendingIDs = Set(pending.map(\.id))
    #expect(pendingIDs.contains("tag-1"))
    #expect(pendingIDs.contains("feed-1"))
    #expect(pending.allSatisfy { $0.changeType == .save })
}

@Test func backfillAllExistingRecordsSchliesstDefaultIntelligenteOrdnerAus() throws {
    let database = try makeTestDatabase()
    try SQLiteSmartFolderStore(database: database).restoreDefaultFolders()

    try CloudSyncEngine.backfillAllExistingRecords(database: database)

    let pending = try CloudSyncPendingChangeStore(database: database).pendingChanges()
    #expect(pending.isEmpty)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CloudSyncEngineRegistryTests 2>&1 | tail -40`
Expected: FAIL — `CloudSyncEngine.backfillAllExistingRecords(database:)` existiert noch nicht.

- [ ] **Step 3: Implement the backfill step**

Lies zuerst die aktuelle `Feedivo/Services/CloudSync/CloudSyncEngine.swift` in voller Länge (insbesondere `start()`s `Task { ... }`-Block und die bestehende `notifyPendingChangesAvailable`-Methode), dann ergänze eine neue statische Methode (Sichtbarkeit `internal`, nicht `private`, damit der Test sie direkt aufrufen kann):

```swift
    /// Reiht alle aktuell existierenden lokalen Zeilen aller registrierten Tabellen erneut als
    /// `.save` in die Pending-Sync-Queue ein — läuft bei JEDEM `start()`, kein einmaliges Flag
    /// (siehe Design-Spec `docs/superpowers/specs/2026-07-24-icloud-sync-phase2a-backfill-design.md`).
    /// Deckt sowohl echte Altbestände (vor Sync-Aktivierung angelegt) als auch Bearbeitungen ab,
    /// die passierten, während Sync ausgeschaltet war. Ein erneutes `.save` für eine bereits
    /// unveränderte, längst synchronisierte Zeile ist harmlos (CloudKit behandelt es als
    /// inhaltlich identisches Update). Löschungen, die während Sync-aus passierten, werden
    /// bewusst NICHT nachträglich gemeldet — das kennt nur den aktuellen lokalen Stand.
    static func backfillAllExistingRecords(database: FeedivoDatabase) throws {
        try database.write { db in
            for mapping in Self.registry.values {
                do {
                    let ids = try mapping.allLocalIDs(database: database)
                    for id in ids {
                        try CloudSyncPendingChangeStore.enqueue(db, recordType: mapping.recordType, recordName: id, changeType: .save)
                    }
                } catch {
                    AppLogger.dataAccess.error("iCloud Sync: Backfill fuer \(mapping.recordType, privacy: .public) fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }
```

> **Wichtig für den Implementierer:** `mapping.allLocalIDs(database:)` nutzt intern `database.read { ... }` — verschachtelte Lese-innerhalb-Schreib-Transaktionen sind bei GRDB grundsätzlich möglich (Lesevorgänge innerhalb einer laufenden Schreibtransaktion sehen den bisherigen Transaktionsstand), aber verifiziere das anhand der tatsächlichen `FeedivoDatabase.write`/`.read`-Implementierung (`Feedivo/Database/FeedivoDatabase.swift`), bevor du diesen Code committest — falls das nicht sauber funktioniert (z. B. weil `database.read` intern eine neue, konkurrierende `DatabaseQueue`-Verbindung statt derselben Transaktion nutzt), rufe `mapping.allLocalIDs(database:)` STATTDESSEN außerhalb des `database.write`-Blocks auf (IDs pro Mapping vorab sammeln, danach in einem einzigen `database.write`-Block alle enqueuen) und passe die Funktion entsprechend an.

In `start()`s `Task { ... }`-Block, nach dem Anlegen der Zone (`if !UserDefaults.standard.bool(forKey: Self.hasCreatedZoneKey) { ... }`) und VOR `Self.notifyPendingChangesAvailable(database: database)`, ergänze:

```swift
            do {
                try Self.backfillAllExistingRecords(database: database)
            } catch {
                AppLogger.dataAccess.error("iCloud Sync: Backfill bestehender Eintraege fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            }

            Self.notifyPendingChangesAvailable(database: database)
```

(ersetzt die bisherige alleinstehende `Self.notifyPendingChangesAvailable(database: database)`-Zeile an dieser Stelle — lies den exakten umgebenden Code zuerst, um die Einfügestelle korrekt zu treffen.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CloudSyncEngineRegistryTests -parallel-testing-enabled NO 2>&1 | tail -60`
Expected: PASS

- [ ] **Step 5: Run the full CloudSync regression suite**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CloudSyncEngineRegistryTests -only-testing:FeedivoTests/CloudSyncTagMappingTests -only-testing:FeedivoTests/CloudSyncFeedMappingTests -only-testing:FeedivoTests/CloudSyncFeedFolderMappingTests -only-testing:FeedivoTests/CloudSyncRuleMappingTests -only-testing:FeedivoTests/CloudSyncRuleConditionMappingTests -only-testing:FeedivoTests/CloudSyncSmartFolderMappingTests -only-testing:FeedivoTests/CloudSyncSmartFolderConditionMappingTests -only-testing:FeedivoTests/CloudSyncPendingChangeStoreTests -only-testing:FeedivoTests/CloudSyncSettingsTests -only-testing:FeedivoTests/SQLiteTagStoreTests -only-testing:FeedivoTests/SQLiteFeedStoreTests -only-testing:FeedivoTests/FeedFolderStoreTests -only-testing:FeedivoTests/SQLiteRuleStoreTests -only-testing:FeedivoTests/SQLiteSmartFolderStoreTests -parallel-testing-enabled NO 2>&1 | tail -100`
Expected: alle PASS — keine Regression zu Phase 1/2a.

- [ ] **Step 6: Full build**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -60`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Commit**

```bash
git add Feedivo/Services/CloudSync/CloudSyncEngine.swift FeedivoTests/CloudSyncEngineRegistryTests.swift
git commit -m "Feature: Backfill bestehender Eintraege bei jedem CloudSyncEngine.start() (iCloud Sync Backfill Task 2)"
```

---

## Live-Verifikation (nach diesem Plan, manuell durch den Nutzer)

Einen bestehenden, nie zuvor gesyncten Feed/eine Regel/einen Ordner (angelegt VOR dieser
Ergänzung oder während Sync ausgeschaltet war) im CloudKit-Dashboard NACH einem Sync-Start
prüfen — sollte jetzt erscheinen, ohne dass der Eintrag manuell bearbeitet wurde.
