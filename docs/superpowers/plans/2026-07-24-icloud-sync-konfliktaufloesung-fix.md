# iCloud Sync Konfliktauflösung Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sync-Konflikte mit bereits serverseitig existierenden Datensätzen (`.serverRecordChanged`, "record to insert already exists") führen nicht mehr zu einer Endlosschleife — Resends nach "lokal gewinnt" übernehmen die Server-Systemfelder, "Server gewinnt"-Fälle verschwinden korrekt aus der lokalen Pending-Warteschlange, und ein Konflikt-Batch löst nur noch einen einzigen Resend-Versuch statt einem pro betroffenem Element aus.

**Architecture:** `CloudSyncRecordMapping.makeCKRecord(fromLocalID:database:)` bekommt einen neuen `existing: CKRecord?`-Parameter, den alle 7 Typen an ihren bereits vorhandenen `makeCKRecord(from:existing:)`-Baustein durchreichen. `CloudSyncEngine` hält einen kurzlebigen In-Memory-Cache (`knownServerRecordsByID`), befüllt von `handleFailedSave` beim "lokal gewinnt"-Pfad, konsultiert von `record(forPendingChange:)`. `applyIncomingRecord` und `handleFailedSave` liefern jetzt `Bool` zurück, damit `handleEvent` pro Batch nur einmal (statt einmal pro Konflikt) einen Resend anstößt.

**Tech Stack:** Swift, CloudKit (`CKSyncEngine`), GRDB (SQLite), Swift Testing.

## Global Constraints

- Last-Write-Wins-Entscheidung (neuerer Zeitstempel gewinnt) bleibt unverändert — nur die technische Durchführung wird korrigiert.
- Fix gilt einheitlich für alle 7 `CloudSyncRecordMapping`-Typen: `CloudSyncTagMapping`, `CloudSyncFeedMapping`, `CloudSyncFeedFolderMapping`, `CloudSyncRuleMapping`, `CloudSyncRuleConditionMapping`, `CloudSyncSmartFolderMapping`, `CloudSyncSmartFolderConditionMapping`.
- Kein Persistieren der Server-Systemfelder (kein neues DB-Feld, keine Migration) — reiner In-Memory-Cache genügt.
- Sprache für Code-Kommentare: Deutsch.
- Tests: Swift Testing (`@Test`/`#expect`), kein XCTest. Gezielt mit `-only-testing:FeedivoTests/<SuiteName>` laufen lassen, `-parallel-testing-enabled NO` bei mehreren Suiten gleichzeitig.
- `CloudSyncEngine`-Verhalten (`handleFailedSave`/`.sentRecordZoneChanges`) ist wegen der `CKSyncEngine.Event`-Framework-Typen nicht automatisiert testbar (kein Mock/keine Konstruktion synthetischer Werte möglich, bereits bekannte, dokumentierte Grenze aus einem früheren Plan in diesem Projekt) — Verifikation über volle Kompilierung + bestehende Regressionssuite + manuelle Live-Verifikation.
- Design-Referenz: `docs/superpowers/specs/2026-07-24-icloud-sync-konfliktaufloesung-fix-design.md`.

---

### Task 1: `existing:`-Parameter durch alle 7 `CloudSyncRecordMapping`-Typen durchreichen

**Files:**
- Modify: `Feedivo/Services/CloudSync/CloudSyncRecordMapping.swift`
- Modify: `Feedivo/Services/CloudSync/CloudSyncTagMapping.swift`
- Modify: `Feedivo/Services/CloudSync/CloudSyncFeedMapping.swift`
- Modify: `Feedivo/Services/CloudSync/CloudSyncFeedFolderMapping.swift`
- Modify: `Feedivo/Services/CloudSync/CloudSyncRuleMapping.swift`
- Modify: `Feedivo/Services/CloudSync/CloudSyncRuleConditionMapping.swift`
- Modify: `Feedivo/Services/CloudSync/CloudSyncSmartFolderMapping.swift`
- Modify: `Feedivo/Services/CloudSync/CloudSyncSmartFolderConditionMapping.swift`
- Test: `FeedivoTests/CloudSyncTagMappingTests.swift`, `CloudSyncFeedMappingTests.swift`, `CloudSyncFeedFolderMappingTests.swift`, `CloudSyncRuleMappingTests.swift`, `CloudSyncRuleConditionMappingTests.swift`, `CloudSyncSmartFolderMappingTests.swift`, `CloudSyncSmartFolderConditionMappingTests.swift` (je eine Ergänzung + 2 angepasste Zeilen)

**Interfaces:**
- Produces: `static func makeCKRecord(fromLocalID id: String, existing: CKRecord?, database: FeedivoDatabase) throws -> CKRecord?` auf allen 7 Typen — von Task 2 (`CloudSyncEngine.record(forPendingChange:)`) mit einem optionalen Cache-Treffer aufgerufen.

- [ ] **Step 1: Write the failing tests**

Ergänze in JEDER der 7 Testdateien einen neuen Test nach diesem Muster (Beispiel
`CloudSyncTagMappingTests.swift`, direkt nach `allLocalIDsListetAlleTagsAuf`):

```swift
    @Test func makeCKRecordFromLocalIDMitExistingBehaeltSystemfelder() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try TagStore(database: database).save(TagRecord(id: "tag-1", name: "Wichtig", colorHex: "#FF0000", sortIndex: 3))
        let existing = CKRecord(recordType: "Tag", recordID: CloudSyncTagMapping.recordID(forTagID: "tag-1"))

        let record = try CloudSyncTagMapping.makeCKRecord(fromLocalID: "tag-1", existing: existing, database: database)

        #expect(record === existing)
        #expect(record?["name"] as? String == "Wichtig")
    }
```

Passe außerdem die BESTEHENDEN Aufrufe von `makeCKRecord(fromLocalID:database:)` in derselben
Datei an, indem du `existing: nil` einfügst — lies jede der 7 Dateien zuerst per Grep
`grep -n "makeCKRecord(fromLocalID" FeedivoTests/CloudSync*MappingTests.swift`, um die exakten
2-3 Fundstellen pro Datei zu bestätigen (z. B. Tag hat 1 Fundstelle, SmartFolder hat 3
inklusive eines Default-Ordner-Tests), und füge bei JEDER `existing: nil` ein. Beispiel Tag:

```swift
    @Test func makeCKRecordFromLocalIDLiefertNilFuerUnbekannteID() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        let record = try CloudSyncTagMapping.makeCKRecord(fromLocalID: "unbekannt", existing: nil, database: database)

        #expect(record == nil)
    }
```

Ergänze außerdem für die übrigen 6 Typen jeweils den analogen neuen Test:

`CloudSyncFeedMappingTests.swift`, nach `allLocalIDsListetAlleFeedsAuf`:
```swift
    @Test func makeCKRecordFromLocalIDMitExistingBehaeltSystemfelder() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try FeedStore(database: database).save(FeedRecord(id: "feed-1", url: "https://example.com/feed", title: "Beispiel", refreshIntervalMinutes: 45))
        let existing = CKRecord(recordType: "Feed", recordID: CloudSyncFeedMapping.recordID(forLocalID: "feed-1"))

        let record = try CloudSyncFeedMapping.makeCKRecord(fromLocalID: "feed-1", existing: existing, database: database)

        #expect(record === existing)
        #expect(record?["url"] as? String == "https://example.com/feed")
    }
```

`CloudSyncFeedFolderMappingTests.swift`, nach dem letzten bestehenden Test (lies die Datei
zuerst für den exakten Anschluss):
```swift
    @Test func makeCKRecordFromLocalIDMitExistingBehaeltSystemfelder() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try FeedFolderStore(database: database).save(FeedFolderRecord(id: "folder-1", name: "Tech", sortIndex: 0))
        let existing = CKRecord(recordType: "FeedFolder", recordID: CloudSyncFeedFolderMapping.recordID(forLocalID: "folder-1"))

        let record = try CloudSyncFeedFolderMapping.makeCKRecord(fromLocalID: "folder-1", existing: existing, database: database)

        #expect(record === existing)
        #expect(record?["name"] as? String == "Tech")
    }
```

`CloudSyncRuleMappingTests.swift`, nach dem letzten bestehenden Test:
```swift
    @Test func makeCKRecordFromLocalIDMitExistingBehaeltSystemfelder() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try SQLiteRuleStore(database: database).save(RuleRecord(id: "rule-1", name: "Wichtig", sortOrder: 0), conditions: [])
        let existing = CKRecord(recordType: "Rule", recordID: CloudSyncRuleMapping.recordID(forLocalID: "rule-1"))

        let record = try CloudSyncRuleMapping.makeCKRecord(fromLocalID: "rule-1", existing: existing, database: database)

        #expect(record === existing)
        #expect(record?["name"] as? String == "Wichtig")
    }
```

`CloudSyncRuleConditionMappingTests.swift`, nach `allLocalIDsListetAlleBedingungenAuf`:
```swift
    @Test func makeCKRecordFromLocalIDMitExistingBehaeltSystemfelder() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try SQLiteRuleStore(database: database).save(
            RuleRecord(id: "rule-1", name: "Wichtig", sortOrder: 0),
            conditions: [RuleConditionRecord(id: "cond-1", ruleID: "rule-1", field: "title", conditionOperator: "contains", value: "Test")]
        )
        let existing = CKRecord(recordType: "RuleCondition", recordID: CloudSyncRuleConditionMapping.recordID(forLocalID: "cond-1"))

        let record = try CloudSyncRuleConditionMapping.makeCKRecord(fromLocalID: "cond-1", existing: existing, database: database)

        #expect(record === existing)
        #expect(record?["value"] as? String == "Test")
    }
```

`CloudSyncSmartFolderMappingTests.swift`, nach dem letzten bestehenden Test:
```swift
    @Test func makeCKRecordFromLocalIDMitExistingBehaeltSystemfelder() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try SQLiteSmartFolderStore(database: database).save(SmartFolderRecord(id: "folder-1", name: "Meine Auswahl", sortOrder: 0), conditions: [])
        let existing = CKRecord(recordType: "SmartFolder", recordID: CloudSyncSmartFolderMapping.recordID(forLocalID: "folder-1"))

        let record = try CloudSyncSmartFolderMapping.makeCKRecord(fromLocalID: "folder-1", existing: existing, database: database)

        #expect(record === existing)
        #expect(record?["name"] as? String == "Meine Auswahl")
    }
```

`CloudSyncSmartFolderConditionMappingTests.swift`, nach `allLocalIDsListetNurBedingungenNichtDefaultOrdnerAuf`:
```swift
    @Test func makeCKRecordFromLocalIDMitExistingBehaeltSystemfelder() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try SQLiteSmartFolderStore(database: database).save(
            SmartFolderRecord(id: "folder-1", name: "Meine Auswahl", sortOrder: 0),
            conditions: [SmartFolderConditionRecord(id: "cond-1", smartFolderID: "folder-1", field: "status", conditionOperator: "is", value: "unread")]
        )
        let existing = CKRecord(recordType: "SmartFolderCondition", recordID: CloudSyncSmartFolderConditionMapping.recordID(forLocalID: "cond-1"))

        let record = try CloudSyncSmartFolderConditionMapping.makeCKRecord(fromLocalID: "cond-1", existing: existing, database: database)

        #expect(record === existing)
        #expect(record?["value"] as? String == "unread")
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CloudSyncTagMappingTests -only-testing:FeedivoTests/CloudSyncFeedMappingTests -only-testing:FeedivoTests/CloudSyncFeedFolderMappingTests -only-testing:FeedivoTests/CloudSyncRuleMappingTests -only-testing:FeedivoTests/CloudSyncRuleConditionMappingTests -only-testing:FeedivoTests/CloudSyncSmartFolderMappingTests -only-testing:FeedivoTests/CloudSyncSmartFolderConditionMappingTests -parallel-testing-enabled NO 2>&1 | tail -60`
Expected: FAIL (Compile-Fehler) — `makeCKRecord(fromLocalID:existing:database:)` existiert noch nicht.

- [ ] **Step 3: Add the protocol requirement**

In `Feedivo/Services/CloudSync/CloudSyncRecordMapping.swift`, ersetze:

```swift
    static func makeCKRecord(fromLocalID id: String, database: FeedivoDatabase) throws -> CKRecord?
```

durch:

```swift
    static func makeCKRecord(fromLocalID id: String, existing: CKRecord?, database: FeedivoDatabase) throws -> CKRecord?
```

- [ ] **Step 4: Update all 7 mapping types**

In `Feedivo/Services/CloudSync/CloudSyncTagMapping.swift`, ersetze:

```swift
    static func makeCKRecord(fromLocalID id: String, database: FeedivoDatabase) throws -> CKRecord? {
        let tags = try TagStore(database: database).tags()
        guard let tag = tags.first(where: { $0.id == id }) else { return nil }
        return makeCKRecord(from: tag)
    }
```

durch:

```swift
    static func makeCKRecord(fromLocalID id: String, existing: CKRecord?, database: FeedivoDatabase) throws -> CKRecord? {
        let tags = try TagStore(database: database).tags()
        guard let tag = tags.first(where: { $0.id == id }) else { return nil }
        return makeCKRecord(from: tag, existing: existing)
    }
```

In `Feedivo/Services/CloudSync/CloudSyncFeedMapping.swift`, ersetze:

```swift
    static func makeCKRecord(fromLocalID id: String, database: FeedivoDatabase) throws -> CKRecord? {
        guard let feed = try FeedStore(database: database).feed(id: id) else { return nil }
        return makeCKRecord(from: feed)
    }
```

durch:

```swift
    static func makeCKRecord(fromLocalID id: String, existing: CKRecord?, database: FeedivoDatabase) throws -> CKRecord? {
        guard let feed = try FeedStore(database: database).feed(id: id) else { return nil }
        return makeCKRecord(from: feed, existing: existing)
    }
```

In `Feedivo/Services/CloudSync/CloudSyncFeedFolderMapping.swift`, ersetze:

```swift
    static func makeCKRecord(fromLocalID id: String, database: FeedivoDatabase) throws -> CKRecord? {
        let folders = try FeedFolderStore(database: database).folders()
        guard let folder = folders.first(where: { $0.id == id }) else { return nil }
        return makeCKRecord(from: folder)
    }
```

durch:

```swift
    static func makeCKRecord(fromLocalID id: String, existing: CKRecord?, database: FeedivoDatabase) throws -> CKRecord? {
        let folders = try FeedFolderStore(database: database).folders()
        guard let folder = folders.first(where: { $0.id == id }) else { return nil }
        return makeCKRecord(from: folder, existing: existing)
    }
```

In `Feedivo/Services/CloudSync/CloudSyncRuleMapping.swift`, ersetze:

```swift
    static func makeCKRecord(fromLocalID id: String, database: FeedivoDatabase) throws -> CKRecord? {
        guard let rule = try SQLiteRuleStore(database: database).rule(id: id) else { return nil }
        return makeCKRecord(from: rule)
    }
```

durch:

```swift
    static func makeCKRecord(fromLocalID id: String, existing: CKRecord?, database: FeedivoDatabase) throws -> CKRecord? {
        guard let rule = try SQLiteRuleStore(database: database).rule(id: id) else { return nil }
        return makeCKRecord(from: rule, existing: existing)
    }
```

In `Feedivo/Services/CloudSync/CloudSyncRuleConditionMapping.swift`, ersetze:

```swift
    static func makeCKRecord(fromLocalID id: String, database: FeedivoDatabase) throws -> CKRecord? {
        let condition = try database.read { db in
            try RuleConditionRecord.fetchOne(db, sql: "SELECT * FROM rule_conditions WHERE id = ?", arguments: [id])
        }
        guard let condition else { return nil }
        return makeCKRecord(from: condition)
    }
```

durch:

```swift
    static func makeCKRecord(fromLocalID id: String, existing: CKRecord?, database: FeedivoDatabase) throws -> CKRecord? {
        let condition = try database.read { db in
            try RuleConditionRecord.fetchOne(db, sql: "SELECT * FROM rule_conditions WHERE id = ?", arguments: [id])
        }
        guard let condition else { return nil }
        return makeCKRecord(from: condition, existing: existing)
    }
```

In `Feedivo/Services/CloudSync/CloudSyncSmartFolderMapping.swift`, ersetze:

```swift
    static func makeCKRecord(fromLocalID id: String, database: FeedivoDatabase) throws -> CKRecord? {
        guard let folder = try SQLiteSmartFolderStore(database: database).folder(id: id), !folder.isDefault else { return nil }
        return makeCKRecord(from: folder)
    }
```

durch:

```swift
    static func makeCKRecord(fromLocalID id: String, existing: CKRecord?, database: FeedivoDatabase) throws -> CKRecord? {
        guard let folder = try SQLiteSmartFolderStore(database: database).folder(id: id), !folder.isDefault else { return nil }
        return makeCKRecord(from: folder, existing: existing)
    }
```

In `Feedivo/Services/CloudSync/CloudSyncSmartFolderConditionMapping.swift`, ersetze:

```swift
    static func makeCKRecord(fromLocalID id: String, database: FeedivoDatabase) throws -> CKRecord? {
        let condition = try database.read { db in
            try SmartFolderConditionRecord.fetchOne(db, sql: "SELECT * FROM smart_folder_conditions WHERE id = ?", arguments: [id])
        }
        guard let condition else { return nil }
        return makeCKRecord(from: condition)
    }
```

durch:

```swift
    static func makeCKRecord(fromLocalID id: String, existing: CKRecord?, database: FeedivoDatabase) throws -> CKRecord? {
        let condition = try database.read { db in
            try SmartFolderConditionRecord.fetchOne(db, sql: "SELECT * FROM smart_folder_conditions WHERE id = ?", arguments: [id])
        }
        guard let condition else { return nil }
        return makeCKRecord(from: condition, existing: existing)
    }
```

- [ ] **Step 5: Update the one production call site so this task still builds standalone**

`Feedivo/Services/CloudSync/CloudSyncEngine.swift` hat GENAU eine Aufrufstelle dieser
Protokollmethode (`record(forPendingChange:)`). Damit dieser Task für sich allein baut (Task 2
verdrahtet dort erst den eigentlichen Cache), ersetze dort NUR das fehlende Argument:

```swift
            return try mapping.makeCKRecord(fromLocalID: recordID.recordName, database: database)
```

durch:

```swift
            return try mapping.makeCKRecord(fromLocalID: recordID.recordName, existing: nil, database: database)
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CloudSyncTagMappingTests -only-testing:FeedivoTests/CloudSyncFeedMappingTests -only-testing:FeedivoTests/CloudSyncFeedFolderMappingTests -only-testing:FeedivoTests/CloudSyncRuleMappingTests -only-testing:FeedivoTests/CloudSyncRuleConditionMappingTests -only-testing:FeedivoTests/CloudSyncSmartFolderMappingTests -only-testing:FeedivoTests/CloudSyncSmartFolderConditionMappingTests -parallel-testing-enabled NO 2>&1 | tail -100`
Expected: PASS (alle Suiten)

- [ ] **Step 7: Full build**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -60`
Expected: BUILD SUCCEEDED

- [ ] **Step 8: Commit**

```bash
git add Feedivo/Services/CloudSync/CloudSyncRecordMapping.swift Feedivo/Services/CloudSync/CloudSyncTagMapping.swift Feedivo/Services/CloudSync/CloudSyncFeedMapping.swift Feedivo/Services/CloudSync/CloudSyncFeedFolderMapping.swift Feedivo/Services/CloudSync/CloudSyncRuleMapping.swift Feedivo/Services/CloudSync/CloudSyncRuleConditionMapping.swift Feedivo/Services/CloudSync/CloudSyncSmartFolderMapping.swift Feedivo/Services/CloudSync/CloudSyncSmartFolderConditionMapping.swift Feedivo/Services/CloudSync/CloudSyncEngine.swift FeedivoTests/CloudSyncTagMappingTests.swift FeedivoTests/CloudSyncFeedMappingTests.swift FeedivoTests/CloudSyncFeedFolderMappingTests.swift FeedivoTests/CloudSyncRuleMappingTests.swift FeedivoTests/CloudSyncRuleConditionMappingTests.swift FeedivoTests/CloudSyncSmartFolderMappingTests.swift FeedivoTests/CloudSyncSmartFolderConditionMappingTests.swift
git commit -m "Feature: existing:-Parameter durch alle 7 CloudSyncRecordMapping-Typen (iCloud Sync Konfliktauflösung Fix Task 1)"
```

---

### Task 2: `CloudSyncEngine` — Cache, `applyIncomingRecord`/`handleFailedSave` als `Bool`, gebündelter Resend-Trigger

**Files:**
- Modify: `Feedivo/Services/CloudSync/CloudSyncEngine.swift`

**Interfaces:**
- Consumes: `CloudSyncRecordMapping.makeCKRecord(fromLocalID:existing:database:)` (Task 1) auf allen 7 Typen.

**Hinweis zur Testbarkeit:** Wie in den Global Constraints beschrieben — `CKSyncEngine.Event`
ist nicht synthetisch konstruierbar, kein Test-first-Zyklus für diesen Task. Verifikation über
volle Kompilierung + bestehende Regressionssuite + manuelle Live-Verifikation (letzter
Abschnitt dieses Plans).

- [ ] **Step 1: Read the current file**

Lies `Feedivo/Services/CloudSync/CloudSyncEngine.swift` vollständig, insbesondere
`record(forPendingChange:)`, `applyIncomingRecord`, `handleEvent`s `.fetchedRecordZoneChanges`-
und `.sentRecordZoneChanges`-Fälle sowie `handleFailedSave`, um die exakte aktuelle Fassung zu
bestätigen (Task 1 hat diese Datei nicht verändert, aber vorherige Tasks dieser Session haben —
verlass dich nicht auf einen älteren Stand).

- [ ] **Step 2: Add the cache property**

Ergänze direkt nach `private let pendingChangeStore: CloudSyncPendingChangeStore`:

```swift

    /// Kurzlebiger Zwischenspeicher für Server-Records aus aufgelösten Konflikten — wird von
    /// `handleFailedSave` beim "lokal gewinnt"-Pfad befüllt und von `record(forPendingChange:)`
    /// konsultiert, damit der nächste Sendeversuch die korrekten Server-Systemfelder
    /// (Change-Tag) wiederverwendet, statt erneut ein jungfräuliches CKRecord zu bauen (das
    /// sonst garantiert wieder mit `.serverRecordChanged` scheitern würde). Rein In-Memory,
    /// bewusst nicht persistiert — überlebt einen Konflikt-Retry innerhalb derselben Sync-
    /// Session; nach einem App-Neustart liefert der nächste Sendeversuch ohnehin erneut den
    /// aktuellen Server-Stand über einen neuen `.serverRecordChanged`-Fehler. Siehe Design-Spec
    /// `docs/superpowers/specs/2026-07-24-icloud-sync-konfliktaufloesung-fix-design.md`.
    private var knownServerRecordsByID: [CKRecord.ID: CKRecord] = [:]
```

- [ ] **Step 3: Wire the cache into `record(forPendingChange:)`**

Ersetze (Stand nach Task 1 — der Aufruf hat bereits `existing: nil` fest verdrahtet):

```swift
    private func record(forPendingChange recordID: CKRecord.ID) async -> CKRecord? {
        guard
            let pendingChange = try? pendingChangeStore.pendingChange(recordName: recordID.recordName),
            let mapping = Self.mapping(forRecordType: pendingChange.recordType)
        else {
            return nil
        }
        do {
            return try mapping.makeCKRecord(fromLocalID: recordID.recordName, existing: nil, database: database)
        } catch {
            AppLogger.dataAccess.error("iCloud Sync: CKRecord fuer ausstehende Aenderung konnte nicht gebaut werden: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
```

durch:

```swift
    private func record(forPendingChange recordID: CKRecord.ID) async -> CKRecord? {
        guard
            let pendingChange = try? pendingChangeStore.pendingChange(recordName: recordID.recordName),
            let mapping = Self.mapping(forRecordType: pendingChange.recordType)
        else {
            return nil
        }
        do {
            let existing = knownServerRecordsByID[recordID]
            let record = try mapping.makeCKRecord(fromLocalID: recordID.recordName, existing: existing, database: database)
            knownServerRecordsByID.removeValue(forKey: recordID)
            return record
        } catch {
            AppLogger.dataAccess.error("iCloud Sync: CKRecord fuer ausstehende Aenderung konnte nicht gebaut werden: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
```

- [ ] **Step 4: `applyIncomingRecord` returns `Bool`**

Ersetze:

```swift
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
```

durch:

```swift
    private func applyIncomingRecord(_ record: CKRecord) async -> Bool {
        guard let mapping = Self.mapping(forRecordType: record.recordType) else { return false }
        do {
            try mapping.applyIncoming(record, database: database)
        } catch {
            AppLogger.dataAccess.error("iCloud Sync: Eingehender \(record.recordType, privacy: .public)-Record konnte nicht gespeichert werden: \(error.localizedDescription, privacy: .public)")
            return false
        }
        SQLiteDataInvalidation.bumpStatusVersion()
        return true
    }
```

Der bestehende Aufrufer in `.fetchedRecordZoneChanges` (`await applyIncomingRecord(modification)`,
ohne Zuweisung) bleibt unverändert — Swift erlaubt, einen `Bool`-Rückgabewert zu ignorieren.

- [ ] **Step 5: `handleFailedSave` returns `Bool` (needs resend?) + dequeue on server-wins**

Ersetze:

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

durch:

```swift
    /// Liefert `true`, wenn dieses Element einen erneuten Sendeversuch braucht (der Aufrufer in
    /// `handleEvent` bündelt daraus höchstens EINEN `notifyPendingChangesAvailable`-Aufruf pro
    /// Batch, statt einem pro Konflikt — siehe Design-Spec
    /// `docs/superpowers/specs/2026-07-24-icloud-sync-konfliktaufloesung-fix-design.md`).
    private func handleFailedSave(_ failedSave: CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave) async -> Bool {
        guard failedSave.error.code == .serverRecordChanged else {
            status.state = .error(failedSave.error.localizedDescription)
            AppLogger.dataAccess.error("iCloud Sync: Record-Save fehlgeschlagen: \(failedSave.error.localizedDescription, privacy: .public)")
            return false
        }

        guard let serverRecord = failedSave.error.serverRecord,
              let mapping = Self.mapping(forRecordType: failedSave.record.recordType)
        else { return false }

        let localUpdatedAt: Date?
        do {
            localUpdatedAt = try mapping.localUpdatedAt(forLocalID: failedSave.record.recordID.recordName, database: database)
        } catch {
            AppLogger.dataAccess.error("iCloud Sync: Lokaler Stand fuer Konfliktaufloesung konnte nicht geladen werden: \(error.localizedDescription, privacy: .public)")
            return false
        }

        let serverIsNewer = (serverRecord.modificationDate ?? .distantPast) > (localUpdatedAt ?? .distantPast)

        if serverIsNewer {
            let applied = await applyIncomingRecord(serverRecord)
            if applied {
                dequeuePendingChange(recordName: failedSave.record.recordID.recordName)
            }
            return false
        } else {
            knownServerRecordsByID[failedSave.record.recordID] = serverRecord
            do {
                try pendingChangeStore.enqueue(recordType: mapping.recordType, recordName: failedSave.record.recordID.recordName, changeType: .save)
                return true
            } catch {
                AppLogger.dataAccess.error("iCloud Sync: Erneuter Sync-Versuch nach Konflikt konnte nicht eingeplant werden: \(error.localizedDescription, privacy: .public)")
                return false
            }
        }
    }
```

- [ ] **Step 6: Bundle the resend trigger in `handleEvent`**

Ersetze:

```swift
        case .sentRecordZoneChanges(let changes):
            for saved in changes.savedRecords {
                dequeuePendingChange(recordName: saved.recordID.recordName)
            }
            for deletedID in changes.deletedRecordIDs {
                dequeuePendingChange(recordName: deletedID.recordName)
            }
            for failedSave in changes.failedRecordSaves {
                await handleFailedSave(failedSave)
            }
            recordSyncActivityOutcome(failedRecordSaves: changes.failedRecordSaves)
```

durch:

```swift
        case .sentRecordZoneChanges(let changes):
            for saved in changes.savedRecords {
                dequeuePendingChange(recordName: saved.recordID.recordName)
            }
            for deletedID in changes.deletedRecordIDs {
                dequeuePendingChange(recordName: deletedID.recordName)
            }
            var needsResend = false
            for failedSave in changes.failedRecordSaves {
                if await handleFailedSave(failedSave) {
                    needsResend = true
                }
            }
            if needsResend {
                Self.notifyPendingChangesAvailable(database: database)
            }
            recordSyncActivityOutcome(failedRecordSaves: changes.failedRecordSaves)
```

- [ ] **Step 7: Full build**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -80`
Expected: BUILD SUCCEEDED

- [ ] **Step 8: Run the full CloudSync regression suite**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CloudSyncEngineRegistryTests -only-testing:FeedivoTests/CloudSyncTagMappingTests -only-testing:FeedivoTests/CloudSyncFeedMappingTests -only-testing:FeedivoTests/CloudSyncFeedFolderMappingTests -only-testing:FeedivoTests/CloudSyncRuleMappingTests -only-testing:FeedivoTests/CloudSyncRuleConditionMappingTests -only-testing:FeedivoTests/CloudSyncSmartFolderMappingTests -only-testing:FeedivoTests/CloudSyncSmartFolderConditionMappingTests -only-testing:FeedivoTests/CloudSyncPendingChangeStoreTests -only-testing:FeedivoTests/CloudSyncSettingsTests -only-testing:FeedivoTests/CloudSyncActivityStatusTests -only-testing:FeedivoTests/CloudSyncActivityCategoryTests -parallel-testing-enabled NO 2>&1 | tail -120`
Expected: alle PASS — keine Regression durch die Signaturänderungen.

- [ ] **Step 9: Commit**

```bash
git add Feedivo/Services/CloudSync/CloudSyncEngine.swift
git commit -m "Fix: Konfliktauflösung nutzt Server-Systemfelder + dequeued korrekt + gebündelter Resend (iCloud Sync Konfliktauflösung Fix Task 2)"
```

---

## Live-Verifikation (nach diesem Plan, manuell durch den Nutzer)

1. Mit den aktuell in der lokalen Datenbank hängenden 94 Elementen (Stand dieser Session, per
   direkter SQLite-Abfrage verifiziert) einen erneuten Sync-Versuch auslösen (App neu starten
   oder Sync kurz aus-/wieder einschalten).
2. Die zuvor dauerhaft mit `.serverRecordChanged` scheiternden Sendeversuche sollten jetzt
   entweder erfolgreich das lokale Feld-Update durchsetzen (falls lokal neuer) oder den
   Server-Stand übernehmen und sofort aus der lokalen Warteschlange verschwinden (falls Server
   neuer).
3. Der "Ausstehend"-Zähler der Sync-Status-Übersicht sollte sichtbar auf 0 sinken, nicht mehr
   dauerhaft hängen bleiben.
4. Xcode-Konsole gegenprüfen: keine wiederholten `.serverRecordChanged`-Fehlermeldungen mehr für
   dieselben Elemente; falls doch — prüfen, ob es sich um ein genuines Multi-Geräte-Update
   handelt (unwahrscheinlich bei Single-Device) oder ein neuer Bug.
5. Keine erneute CloudKit-429-Drosselung durch den gebündelten Resend-Trigger (statt vieler
   gleichzeitiger `sendChanges()`-Aufrufe).
