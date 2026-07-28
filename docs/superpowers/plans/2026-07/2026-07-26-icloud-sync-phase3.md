# iCloud Sync Phase 3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ersetzt das aktuelle Ganz-Record-Last-Write-Wins in `CloudSyncEngine` durch eine
Feld-Ebene-Konfliktauflösung (Touched-Fields-Tracking) für Tag/Feed/FeedFolder/Rule/
RuleCondition/SmartFolder/SmartFolderCondition (ArticleStatus bekommt eine eigene, einfachere
Pro-Feld-Zeitstempel-Regel), ergänzt eine UI zum Auflösen nicht-automatisch lösbarer laufender
Konflikte, und baut einen einmaligen Merge-Dialog mit Namens-Duplikat-Erkennung (Tag,
FeedFolder) für die Erst-Aktivierung von iCloud Sync auf einem Gerät mit bereits vorhandenen
lokalen Daten. Behebt zusätzlich eine während der Planung entdeckte ID-Instabilität bei
`RuleCondition`/`SmartFolderCondition` (jede Bearbeitung vergibt bisher eine neue Zufalls-ID),
ohne die Feld-Ebene-Konfliktauflösung für diese beiden Tabellen nie greifen könnte.

**Architecture:** Jede Store-Mutationsmethode, die einen Pending-Change enqueued, übergibt ab
jetzt zusätzlich die Namen der von ihr geänderten Spalten (`changedFields: [String]?`,
JSON-codiert in einer neuen Spalte auf `cloud_sync_pending_changes`). Bei einem
`.serverRecordChanged`-Konflikt vergleicht `CloudSyncEngine.handleFailedSave` nur diese
Felder gegen den Server-Stand: übereinstimmend → kein Konflikt; abweichend und laut
statischer Pro-Tabelle-Policy (`askFields`/`autoFields` auf jedem `CloudSyncRecordMapping`)
automatisch lösbar → lokalen Wert überlagern und sofort speichern; abweichend und
„fragen"-Feld → in einer neuen lokalen Tabelle `pending_sync_conflicts` vermerken, sichtbar
über ein neues Sheet in den Sync-Einstellungen. Ein neuer `CloudSyncFirstActivationAnalyzer`
läuft einmalig vor dem ersten Backfill, wenn Sync neu aktiviert wird, fragt bestehende
`Tag`/`FeedFolder`-Cloud-Records per `CKQuery` ab und lässt Namens-Duplikate über ein neues
Sheet auflösen (zusammenführen oder disambiguierend umbenennen), bevor der reguläre
Erstabgleich startet.

**Tech Stack:** Swift 5.9+, SwiftUI, GRDB (SQLite), CloudKit (`CKSyncEngine`), Swift Testing
(kein XCTest).

## Global Constraints

- Alle Tests mit Swift Testing (`import Testing`, `@Test func`, `#expect`), niemals XCTest.
- Kommentare im Code auf Deutsch.
- Neue Migrationen immer als neuer `migrator.registerMigration("vN_…")`-Block anhängen (hier:
  `v27`, `v28`), niemals bestehende Migrationen nachträglich ändern. Zuletzt existierende
  Migration zum Zeitpunkt dieses Plans: `v26_add_article_status_sync_stable_id`.
- `CloudSyncEngine` läuft komplett auf `@MainActor`.
- `database.read` darf niemals von INNERHALB eines bereits laufenden `database.write`-Blocks
  auf derselben `DatabaseQueue` aufgerufen werden (GRDB ist nicht reentrant, harter Absturz
  per Precondition) — alle lesenden Zugriffe für eine Entscheidung müssen VOR dem
  `database.write`-Block abgeschlossen sein.
- Jede Store-Mutationsmethode ruft `CloudSyncEngine.notifyPendingChangesAvailable(database:)`
  NACH (nicht innerhalb) ihrem `database.write`-Block auf.
- `enqueuePendingSync`-Helfer prüfen immer zuerst `CloudSyncSettings.isEnabled()`, bevor sie
  einen Pending-Change enqueuen.
- Bestehende `AppLogger.dataAccess.error(...)`-Logging-Konvention für alle neu eingeführten
  Fehlerpfade verwenden, niemals Fehler still verschlucken (`try?` ohne Logging).

---

## Task 1: Bedingungs-ID-Stabilität für RuleCondition/SmartFolderCondition

**Files:**
- Modify: `Feedivo/Views/Rules/RuleSettingsView.swift:606-623` (`RuleSettingsFormatter.conditionDrafts(for:)`)
- Modify: `Feedivo/Views/Rules/RuleWizardView.swift:696-708` (normalizedDrafts-Closure), `:738-748` (finale `RuleConditionRecord`-Konstruktion)
- Modify: `Feedivo/Views/SmartFolders/SmartFolderFormatter.swift:40-54` (`SmartFolderFormatter.drafts(for:)`)
- Modify: `Feedivo/Views/SmartFolders/SmartFolderEditorView.swift:520-534`, `:536-555`, `:566-580` (drei Normalisierungs-Helfer), `:450-459` (finale `SmartFolderConditionRecord`-Konstruktion)
- Test: `FeedivoTests/RuleSettingsFormatterConditionIdentityTests.swift` (neu)
- Test: `FeedivoTests/SmartFolderFormatterConditionIdentityTests.swift` (neu)
- Test: `FeedivoTests/RuleConditionIdentityRoundtripTests.swift` (neu)
- Test: `FeedivoTests/SmartFolderConditionIdentityRoundtripTests.swift` (neu)

**Interfaces:**
- Produces: `RuleSettingsFormatter.conditionDrafts(for:)` und `SmartFolderFormatter.drafts(for:)`
  liefern Drafts, deren `id` exakt der `id` der übergebenen persistierten Bedingung entspricht
  (statt einer neuen Zufalls-ID) — genutzt von Task 9/10 (Diffing beim Speichern setzt
  stabile IDs voraus, um „dieselbe Bedingung" über einen Save-Zyklus hinweg zu erkennen).

- [ ] **Step 1: Fehlschlagenden Test für `RuleSettingsFormatter.conditionDrafts(for:)` schreiben**

```swift
import Foundation
import Testing
@testable import Feedivo

struct RuleSettingsFormatterConditionIdentityTests {
    @Test func conditionDraftsUebernimmtDieBestehendeIDStattEinerNeuen() {
        let existingID = UUID()
        let condition = RuleConditionRecord(
            id: existingID.uuidString,
            ruleID: "rule-1",
            field: RuleConditionField.title.rawValue,
            conditionOperator: RuleConditionOperator.contains.rawValue,
            value: "Test",
            sortOrder: 0,
            groupIndex: 0,
            updatedAt: Date()
        )

        let drafts = RuleSettingsFormatter.conditionDrafts(for: [condition])

        #expect(drafts.first?.id == existingID)
    }
}
```

- [ ] **Step 2: Test ausführen, Fehlschlag bestätigen**

Run: `xcodebuild test -scheme Feedivo -only-testing:FeedivoTests/RuleSettingsFormatterConditionIdentityTests`
Expected: FAIL — `drafts.first?.id` ist eine neue Zufalls-UUID, nicht `existingID`.

- [ ] **Step 3: `RuleSettingsFormatter.conditionDrafts(for:)` fixen**

In `RuleSettingsView.swift`, in der bestehenden `static func conditionDrafts(for conditions:)`
(Zeile 606-623):

```swift
    static func conditionDrafts(for conditions: [RuleConditionRecord]) -> [RuleConditionDraft] {
        conditions
            .sorted { $0.sortOrder < $1.sortOrder }
            .compactMap { condition -> RuleConditionDraft? in
                guard let field = RuleConditionField(rawValue: condition.field),
                      let conditionOperator = RuleConditionOperator(rawValue: condition.conditionOperator)
                else {
                    return nil
                }

                return RuleConditionDraft(
                    id: UUID(uuidString: condition.id) ?? UUID(),
                    field: field,
                    conditionOperator: conditionOperator,
                    value: condition.value,
                    groupIndex: condition.groupIndex
                )
        }
    }
```

- [ ] **Step 4: Test ausführen, Erfolg bestätigen**

Run: `xcodebuild test -scheme Feedivo -only-testing:FeedivoTests/RuleSettingsFormatterConditionIdentityTests`
Expected: PASS

- [ ] **Step 5: Gleichen Test + Fix für `SmartFolderFormatter.drafts(for:)` schreiben**

```swift
import Foundation
import Testing
@testable import Feedivo

struct SmartFolderFormatterConditionIdentityTests {
    @Test func draftsUebernimmtDieBestehendeIDStattEinerNeuen() {
        let existingID = UUID()
        let condition = SmartFolderConditionRecord(
            id: existingID.uuidString,
            smartFolderID: "folder-1",
            field: SmartFolderConditionField.title.rawValue,
            conditionOperator: SmartFolderConditionOperator.contains.rawValue,
            value: "Test",
            sortOrder: 0,
            updatedAt: Date()
        )

        let drafts = SmartFolderFormatter.drafts(for: [condition])

        #expect(drafts.first?.id == existingID)
    }
}
```

Fix in `SmartFolderFormatter.swift:40-54`:

```swift
    static func drafts(for conditions: [SmartFolderConditionRecord]) -> [SmartFolderConditionDraft] {
        sortedConditions(conditions).compactMap { condition in
            guard let field = SmartFolderConditionField(rawValue: condition.field),
                  let conditionOperator = SmartFolderConditionOperator(rawValue: condition.conditionOperator)
            else {
                return nil
            }

            return SmartFolderConditionDraft(
                id: UUID(uuidString: condition.id) ?? UUID(),
                field: field,
                conditionOperator: conditionOperator,
                value: condition.value
            )
        }
    }
```

Run: `xcodebuild test -scheme Feedivo -only-testing:FeedivoTests/SmartFolderFormatterConditionIdentityTests`
Expected: PASS

- [ ] **Step 6: `RuleWizardView.swift` — ID durch die Normalisierung durchreichen**

Zeile ~696-708, `normalizedDrafts`:

```swift
        let normalizedDrafts = drafts.compactMap { draft -> RuleConditionDraft? in
            let value = draft.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else {
                return nil
            }

            return RuleConditionDraft(
                id: draft.id,
                field: draft.field,
                conditionOperator: draft.conditionOperator,
                value: value,
                groupIndex: draft.groupIndex
            )
        }
```

Zeile ~738-748, finale `RuleConditionRecord`-Konstruktion — `id: UUID().uuidString` durch
`id: draft.id.uuidString` ersetzen:

```swift
        let conditions = normalizedDrafts.enumerated().map { index, draft in
            RuleConditionRecord(
                id: draft.id.uuidString,
                ruleID: ruleID,
                field: draft.field.rawValue,
                conditionOperator: draft.conditionOperator.rawValue,
                value: draft.value,
                sortOrder: index,
                groupIndex: draft.groupIndex
            )
        }
```

- [ ] **Step 7: `SmartFolderEditorView.swift` — ID durch alle drei Normalisierungs-Helfer und die finale Konstruktion durchreichen**

Zeile ~520-534 (`normalizeConditionFolderValue`):

```swift
    private func normalizeConditionFolderValue(_ draft: SmartFolderConditionDraft) -> SmartFolderConditionDraft? {
        guard draft.field == .feedFolder else {
            return draft
        }

        guard let normalizedValue = normalizedFeedFolderValue(for: draft.value) else {
            return draft
        }

        return SmartFolderConditionDraft(
            id: draft.id,
            field: draft.field,
            conditionOperator: draft.conditionOperator,
            value: normalizedValue
        )
    }
```

Zeile ~536-555 (`normalizedConditionFolderValue`):

```swift
    private func normalizedConditionFolderValue(_ draft: SmartFolderConditionDraft) -> SmartFolderConditionDraft {
        guard draft.field == .feedFolder else {
            return draft
        }

        let value = draft.value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedValue = normalizedFeedFolderValue(for: value) {
            return SmartFolderConditionDraft(
                id: draft.id,
                field: draft.field,
                conditionOperator: draft.conditionOperator,
                value: normalizedValue
            )
        }

        return SmartFolderConditionDraft(
            id: draft.id,
            field: draft.field,
            conditionOperator: draft.conditionOperator,
            value: value
        )
    }
```

Zeile ~566-580 (`normalizedConditionDrafts`) — beide verschachtelten Konstruktionen bekommen
`id: draft.id`:

```swift
    private var normalizedConditionDrafts: [SmartFolderConditionDraft] {
        conditionDrafts.compactMap { draft in
            let value = draft.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else {
                return nil
            }

            return SmartFolderConditionDraft(
                id: draft.id,
                field: draft.field,
                conditionOperator: draft.conditionOperator,
                value: normalizedConditionFolderValue(
                    SmartFolderConditionDraft(
                        id: draft.id,
                        field: draft.field,
                        conditionOperator: draft.conditionOperator,
                        value: value
                    )
                ).value
            )
        }
    }
```

Zeile ~450-459, finale `SmartFolderConditionRecord`-Konstruktion:

```swift
        let conditions = normalizedConditionDrafts.enumerated().map { index, draft in
            SmartFolderConditionRecord(
                id: draft.id.uuidString,
                smartFolderID: folderID,
                field: draft.field.rawValue,
                conditionOperator: draft.conditionOperator.rawValue,
                value: draft.value,
                sortOrder: index
            )
        }
```

- [ ] **Step 8: End-to-End-Roundtrip-Test — Bedingungs-ID übersteht einen vollständigen Speicher-/Lade-/Speicher-Zyklus**

```swift
import Foundation
import Testing
@testable import Feedivo

struct RuleConditionIdentityRoundtripTests {
    @Test func bedingungsIDBleibtUeberEinenSpeicherLadeSpeicherZyklusStabil() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = SQLiteRuleStore(database: database)

        let originalConditionID = UUID().uuidString
        let rule = RuleRecord(
            id: UUID().uuidString,
            name: "Test-Regel",
            isEnabled: true,
            matchMode: RuleMatchMode.all.rawValue,
            action: "assignTag",
            assignTagID: nil,
            notificationTemplate: "{Titel}",
            notificationPriority: RuleNotificationPriority.normal.rawValue,
            sortOrder: 0,
            createdAt: Date()
        )
        let condition = RuleConditionRecord(
            id: originalConditionID,
            ruleID: rule.id,
            field: RuleConditionField.title.rawValue,
            conditionOperator: RuleConditionOperator.contains.rawValue,
            value: "Alt",
            sortOrder: 0,
            groupIndex: 0,
            updatedAt: Date()
        )
        try store.save(rule, conditions: [condition])

        // Simuliert den Editor-Lade-/Bearbeitungs-/Speicher-Zyklus mit dem Fix aus Steps 3-7:
        // Drafts über conditionDrafts(for:) laden (übernimmt die ID), Wert bearbeiten, per
        // draft.id.uuidString zurückspeichern.
        let reloadedConditions = try store.conditions(ruleID: rule.id)
        let drafts = RuleSettingsFormatter.conditionDrafts(for: reloadedConditions)
        let editedDraft = RuleConditionDraft(
            id: drafts[0].id,
            field: drafts[0].field,
            conditionOperator: drafts[0].conditionOperator,
            value: "Neu",
            groupIndex: drafts[0].groupIndex
        )
        let updatedCondition = RuleConditionRecord(
            id: editedDraft.id.uuidString,
            ruleID: rule.id,
            field: editedDraft.field.rawValue,
            conditionOperator: editedDraft.conditionOperator.rawValue,
            value: editedDraft.value,
            sortOrder: 0,
            groupIndex: editedDraft.groupIndex,
            updatedAt: Date()
        )
        try store.save(rule, conditions: [updatedCondition])

        let finalConditions = try store.conditions(ruleID: rule.id)
        #expect(finalConditions.count == 1)
        #expect(finalConditions.first?.id == originalConditionID)
        #expect(finalConditions.first?.value == "Neu")
    }
}
```

Run: `xcodebuild test -scheme Feedivo -only-testing:FeedivoTests/RuleConditionIdentityRoundtripTests`
Expected: PASS — `RuleConditionRecord(id:)` erhält jetzt exakt `originalConditionID` statt einer
neuen Zufalls-ID.

- [ ] **Step 9: Analogen Roundtrip-Test für `SmartFolderConditionRecord` schreiben**

Gleiche Struktur wie Step 8, mit `SQLiteSmartFolderStore`, `SmartFolderRecord`,
`SmartFolderConditionRecord`, `SmartFolderFormatter.drafts(for:)`,
`SmartFolderConditionDraft` — Datei `FeedivoTests/SmartFolderConditionIdentityRoundtripTests.swift`.

Run: `xcodebuild test -scheme Feedivo -only-testing:FeedivoTests/SmartFolderConditionIdentityRoundtripTests`
Expected: PASS

- [ ] **Step 10: Vollen bestehenden Regel-/Smart-Folder-Testlauf gegenprüfen (keine Regression)**

Run: `xcodebuild test -scheme Feedivo -only-testing:FeedivoTests/SQLiteRuleStoreTests -only-testing:FeedivoTests/SQLiteSmartFolderStoreTests -only-testing:FeedivoTests/RuleSettingsFormatterTests`
Expected: PASS (alle bestehenden Tests unverändert grün)

- [ ] **Step 11: Commit**

```bash
git add Feedivo/Views/Rules/RuleSettingsView.swift Feedivo/Views/Rules/RuleWizardView.swift \
        Feedivo/Views/SmartFolders/SmartFolderFormatter.swift Feedivo/Views/SmartFolders/SmartFolderEditorView.swift \
        FeedivoTests/RuleSettingsFormatterConditionIdentityTests.swift \
        FeedivoTests/SmartFolderFormatterConditionIdentityTests.swift \
        FeedivoTests/RuleConditionIdentityRoundtripTests.swift \
        FeedivoTests/SmartFolderConditionIdentityRoundtripTests.swift
git commit -m "Fix: Bedingungs-IDs bleiben über Bearbeitungszyklen stabil (Voraussetzung für Phase-3-Feld-Konfliktauflösung)"
```

---

## Task 2: Migration v27 + `changedFields` auf `CloudSyncPendingChangeRecord`/`-Store`

**Files:**
- Modify: `Feedivo/Database/FeedivoDatabaseMigrator.swift` (neue Migration nach `v26_add_article_status_sync_stable_id`)
- Modify: `Feedivo/Database/Records/CloudSyncPendingChangeRecord.swift`
- Modify: `Feedivo/Stores/CloudSyncPendingChangeStore.swift`
- Test: `FeedivoTests/CloudSyncPendingChangeStoreTests.swift` (bestehende Datei erweitern)

**Interfaces:**
- Produces: `CloudSyncPendingChangeRecord.changedFields: [String]?` (im Swift-Modell dekodiert,
  in der DB als JSON-`String?` gespeichert). `CloudSyncPendingChangeStore.enqueue(recordType:recordName:changeType:changedFields:)`
  und die statische `Database`-Transaktions-Variante bekommen einen neuen, defaultenden
  Parameter `changedFields: [String]? = nil` — bestehende Aufrufer (alle bisherigen
  `enqueuePendingSync`-Helfer) bleiben ohne Änderung kompilierfähig.

- [ ] **Step 1: Fehlschlagenden Test schreiben**

In `FeedivoTests/CloudSyncPendingChangeStoreTests.swift` ergänzen:

```swift
    @Test func enqueueSpeichertChangedFieldsAlsJSON() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = CloudSyncPendingChangeStore(database: database)

        try store.enqueue(recordType: "Tag", recordName: "tag-1", changeType: .save, changedFields: ["name"])

        let change = try store.pendingChange(recordName: "tag-1")
        #expect(change?.changedFields == ["name"])
    }

    @Test func enqueueOhneChangedFieldsBleibtNil() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = CloudSyncPendingChangeStore(database: database)

        try store.enqueue(recordType: "Tag", recordName: "tag-1", changeType: .delete)

        let change = try store.pendingChange(recordName: "tag-1")
        #expect(change?.changedFields == nil)
    }
```

- [ ] **Step 2: Test ausführen, Fehlschlag bestätigen**

Run: `xcodebuild test -scheme Feedivo -only-testing:FeedivoTests/CloudSyncPendingChangeStoreTests`
Expected: FAIL — Compile-Fehler, `enqueue` kennt keinen `changedFields`-Parameter.

- [ ] **Step 3: Migration `v27_add_changed_fields_to_pending_changes` anlegen**

In `FeedivoDatabaseMigrator.swift`, direkt nach dem bestehenden
`v26_add_article_status_sync_stable_id`-Block:

```swift
        migrator.registerMigration("v27_add_changed_fields_to_pending_changes") { database in
            try database.alter(table: "cloud_sync_pending_changes") { table in
                table.add(column: "changedFields", .text)
            }
        }
```

- [ ] **Step 4: `CloudSyncPendingChangeRecord` um `changedFields` erweitern**

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
///
/// `changedFields` (seit Migration v27): JSON-codierte Liste der Feldnamen, die diese konkrete
/// Mutation geändert hat — Grundlage für die Feld-Ebene-Konfliktauflösung in
/// `CloudSyncEngine.handleFailedSave` (Phase 3). `nil` für Pending-Changes ohne bekannte
/// Feldgranularität (z. B. Löschungen, oder Altbestand von vor Phase 3) — diese fallen weiterhin
/// auf das bisherige Ganz-Record-Last-Write-Wins zurück.
struct CloudSyncPendingChangeRecord: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable, Sendable {
    static let databaseTableName = "cloud_sync_pending_changes"

    var id: String
    var recordType: String
    var changeType: CloudSyncChangeType
    var queuedAt: Date
    private var changedFieldsJSON: String?

    var changedFields: [String]? {
        get {
            guard let changedFieldsJSON, let data = changedFieldsJSON.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode([String].self, from: data)
        }
        set {
            guard let newValue else {
                changedFieldsJSON = nil
                return
            }
            changedFieldsJSON = (try? JSONEncoder().encode(newValue)).flatMap { String(data: $0, encoding: .utf8) }
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, recordType, changeType, queuedAt
        case changedFieldsJSON = "changedFields"
    }

    init(id: String, recordType: String, changeType: CloudSyncChangeType, queuedAt: Date, changedFields: [String]? = nil) {
        self.id = id
        self.recordType = recordType
        self.changeType = changeType
        self.queuedAt = queuedAt
        self.changedFieldsJSON = nil
        self.changedFields = changedFields
    }
}
```

- [ ] **Step 5: `CloudSyncPendingChangeStore.enqueue` um `changedFields` erweitern**

```swift
    func enqueue(recordType: String, recordName: String, changeType: CloudSyncChangeType, changedFields: [String]? = nil) throws {
        try database.write { db in
            try Self.enqueue(db, recordType: recordType, recordName: recordName, changeType: changeType, changedFields: changedFields)
        }
    }

    /// Variante für Aufrufer, die bereits in einer eigenen `database.write`-Transaktion stecken
    /// (z. B. `TagStore`) — hält die fachliche Mutation und das Pending-Change-Markieren atomar.
    static func enqueue(_ db: Database, recordType: String, recordName: String, changeType: CloudSyncChangeType, changedFields: [String]? = nil) throws {
        var change = CloudSyncPendingChangeRecord(
            id: recordName,
            recordType: recordType,
            changeType: changeType,
            queuedAt: Date(),
            changedFields: changedFields
        )
        try change.save(db)
    }
```

Alle übrigen Methoden in dieser Datei (`dequeue`, `deleteAll`, `pendingChanges`,
`pendingChange(recordName:)`, `pendingCounts`) bleiben unverändert.

- [ ] **Step 6: Test ausführen, Erfolg bestätigen**

Run: `xcodebuild test -scheme Feedivo -only-testing:FeedivoTests/CloudSyncPendingChangeStoreTests`
Expected: PASS

- [ ] **Step 7: Vollen Migrations-Testlauf gegenprüfen**

Run: `xcodebuild test -scheme Feedivo -only-testing:FeedivoTests/FeedivoDatabaseMigratorTests`
Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add Feedivo/Database/FeedivoDatabaseMigrator.swift Feedivo/Database/Records/CloudSyncPendingChangeRecord.swift \
        Feedivo/Stores/CloudSyncPendingChangeStore.swift FeedivoTests/CloudSyncPendingChangeStoreTests.swift
git commit -m "Feature: Migration v27 + changedFields auf CloudSyncPendingChangeRecord/-Store (iCloud Sync Phase 3 Task 2)"
```

---

## Task 3: `CloudSyncRecordMapping` um `askFields`/`autoFields` erweitern

**Files:**
- Modify: `Feedivo/Services/CloudSync/CloudSyncRecordMapping.swift`
- Modify: `Feedivo/Services/CloudSync/CloudSyncTagMapping.swift`
- Modify: `Feedivo/Services/CloudSync/CloudSyncFeedMapping.swift`
- Modify: `Feedivo/Services/CloudSync/CloudSyncFeedFolderMapping.swift`
- Modify: `Feedivo/Services/CloudSync/CloudSyncRuleMapping.swift`
- Modify: `Feedivo/Services/CloudSync/CloudSyncRuleConditionMapping.swift`
- Modify: `Feedivo/Services/CloudSync/CloudSyncSmartFolderMapping.swift`
- Modify: `Feedivo/Services/CloudSync/CloudSyncSmartFolderConditionMapping.swift`
- Modify: `Feedivo/Services/CloudSync/CloudSyncArticleStatusMapping.swift`
- Test: `FeedivoTests/CloudSyncRecordMappingPolicyTests.swift` (neu)

**Interfaces:**
- Produces: `static var askFields: Set<String>` und `static var autoFields: Set<String>` auf
  `CloudSyncRecordMapping` — genutzt von Task 5 (`handleFailedSave`), um pro Feld zu
  entscheiden, ob ein Konflikt automatisch gelöst oder in `pending_sync_conflicts` vermerkt
  wird. `CloudSyncArticleStatusMapping` implementiert beide Properties als leere Sets (siehe
  Step 5) — sie nutzt die generische Touched-Fields-Logik gar nicht (eigene Regel in Task 5).

- [ ] **Step 1: Protokoll erweitern**

In `CloudSyncRecordMapping.swift`, nach der bestehenden `allLocalIDs`-Deklaration:

```swift
    /// Feldnamen (exakt die CKRecord-Schlüssel aus `makeCKRecord`), bei denen ein Feld-Konflikt
    /// (beide Seiten haben dieses Feld unterschiedlich geändert) dem Nutzer zur Entscheidung
    /// vorgelegt wird (`pending_sync_conflicts`), statt automatisch aufgelöst zu werden. Siehe
    /// Design-Spec `docs/superpowers/specs/2026-07-26-icloud-sync-phase3-design.md`, Abschnitt 3.
    static var askFields: Set<String> { get }

    /// Feldnamen, bei denen ein Konflikt automatisch über die bestehende Ganz-Record-
    /// Last-Write-Wins-Logik aufgelöst wird — kein Dialog.
    static var autoFields: Set<String> { get }
```

- [ ] **Step 2: Policy je Mapping ergänzen**

`CloudSyncTagMapping.swift`, direkt unter `static let recordType = "Tag"`:

```swift
    static let askFields: Set<String> = ["name"]
    static let autoFields: Set<String> = ["colorHex", "sortIndex"]
```

`CloudSyncFeedFolderMapping.swift`, unter `static let recordType = "FeedFolder"`:

```swift
    static let askFields: Set<String> = ["name"]
    static let autoFields: Set<String> = ["sortIndex"]
```

`CloudSyncFeedMapping.swift`, unter `static let recordType = "Feed"`:

```swift
    static let askFields: Set<String> = ["title"]
    static let autoFields: Set<String> = [
        "folderName", "sortIndex", "refreshIntervalMinutes", "isNotificationEnabled",
        "articleRetentionOverridesGlobalSetting", "articleRetentionIsEnabled",
        "articleRetentionDays", "articleRetentionMinimumArticles",
        "articleRetentionIncludesProtectedArticles"
    ]
```

`CloudSyncRuleMapping.swift`, unter `static let recordType = "Rule"`:

```swift
    static let askFields: Set<String> = ["name"]
    static let autoFields: Set<String> = ["isEnabled", "matchMode", "action", "assignTagID", "notificationTemplate", "notificationPriority", "sortOrder"]
```

`CloudSyncRuleConditionMapping.swift`, unter `static let recordType = "RuleCondition"`:

```swift
    static let askFields: Set<String> = ["value"]
    static let autoFields: Set<String> = ["field", "conditionOperator", "groupIndex", "sortOrder"]
```

`CloudSyncSmartFolderMapping.swift`, unter `static let recordType = "SmartFolder"`:

```swift
    static let askFields: Set<String> = ["name"]
    static let autoFields: Set<String> = ["matchMode", "isShownInSidebar", "sortOrder", "iconName", "colorHex", "defaultShowsReadArticles"]
```

`CloudSyncSmartFolderConditionMapping.swift`, unter `static let recordType = "SmartFolderCondition"`:

```swift
    static let askFields: Set<String> = ["value"]
    static let autoFields: Set<String> = ["field", "conditionOperator", "sortOrder"]
```

- [ ] **Step 3: Test schreiben, der alle 7 Mappings gegen ihre Spec-Policy prüft**

```swift
import Testing
@testable import Feedivo

struct CloudSyncRecordMappingPolicyTests {
    @Test func tagPolicyEntsprichtDesignSpec() {
        #expect(CloudSyncTagMapping.askFields == ["name"])
        #expect(CloudSyncTagMapping.autoFields == ["colorHex", "sortIndex"])
    }

    @Test func feedFolderPolicyEntsprichtDesignSpec() {
        #expect(CloudSyncFeedFolderMapping.askFields == ["name"])
        #expect(CloudSyncFeedFolderMapping.autoFields == ["sortIndex"])
    }

    @Test func feedPolicyEntsprichtDesignSpec() {
        #expect(CloudSyncFeedMapping.askFields == ["title"])
        #expect(CloudSyncFeedMapping.autoFields.count == 9)
        #expect(CloudSyncFeedMapping.autoFields.contains("folderName"))
        #expect(CloudSyncFeedMapping.autoFields.contains("articleRetentionDays"))
    }

    @Test func rulePolicyEntsprichtDesignSpec() {
        #expect(CloudSyncRuleMapping.askFields == ["name"])
        #expect(CloudSyncRuleMapping.autoFields.count == 7)
    }

    @Test func ruleConditionPolicyEntsprichtDesignSpec() {
        #expect(CloudSyncRuleConditionMapping.askFields == ["value"])
        #expect(CloudSyncRuleConditionMapping.autoFields == ["field", "conditionOperator", "groupIndex", "sortOrder"])
    }

    @Test func smartFolderPolicyEntsprichtDesignSpec() {
        #expect(CloudSyncSmartFolderMapping.askFields == ["name"])
        #expect(CloudSyncSmartFolderMapping.autoFields.count == 6)
    }

    @Test func smartFolderConditionPolicyEntsprichtDesignSpec() {
        #expect(CloudSyncSmartFolderConditionMapping.askFields == ["value"])
        #expect(CloudSyncSmartFolderConditionMapping.autoFields == ["field", "conditionOperator", "sortOrder"])
    }

    @Test func articleStatusHatKeineTouchedFieldsPolicy() {
        #expect(CloudSyncArticleStatusMapping.askFields.isEmpty)
        #expect(CloudSyncArticleStatusMapping.autoFields.isEmpty)
    }
}
```

- [ ] **Step 4: `CloudSyncArticleStatusMapping` um leere Policy-Sets ergänzen (Protokoll-Konformität)**

Unter `static let recordType = "ArticleStatus"` in `CloudSyncArticleStatusMapping.swift`:

```swift
    static let askFields: Set<String> = []
    static let autoFields: Set<String> = []
```

- [ ] **Step 5: Test ausführen, Erfolg bestätigen**

Run: `xcodebuild test -scheme Feedivo -only-testing:FeedivoTests/CloudSyncRecordMappingPolicyTests`
Expected: PASS

- [ ] **Step 6: Vollen Build gegenprüfen (Protokoll-Erweiterung ist ein Breaking Change für alle Konformer)**

Run: `xcodebuild build -scheme Feedivo`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Commit**

```bash
git add Feedivo/Services/CloudSync/
git commit -m "Feature: askFields/autoFields Pro-Tabelle-Policy auf CloudSyncRecordMapping (iCloud Sync Phase 3 Task 3)"
```

---

## Task 4: Migration v28 + `pending_sync_conflicts` Record/Store

**Files:**
- Modify: `Feedivo/Database/FeedivoDatabaseMigrator.swift`
- Create: `Feedivo/Database/Records/PendingSyncConflictRecord.swift`
- Create: `Feedivo/Stores/PendingSyncConflictStore.swift`
- Test: `FeedivoTests/PendingSyncConflictStoreTests.swift` (neu)

**Interfaces:**
- Produces: `PendingSyncConflictStore.record(recordType:recordName:fieldName:localValue:serverValue:)`,
  `.conflicts() -> [PendingSyncConflictRecord]`, `.resolve(id:)` — genutzt von Task 5
  (`handleFailedSave` schreibt hierher) und Task 11 (`SyncConflictResolutionView` liest/löscht
  hierüber).

- [ ] **Step 1: Fehlschlagenden Test schreiben**

```swift
import Foundation
import Testing
@testable import Feedivo

struct PendingSyncConflictStoreTests {
    @Test func recordSpeichertEinenKonfliktUndConflictsListetIhnAuf() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = PendingSyncConflictStore(database: database)

        try store.record(recordType: "Rule", recordName: "rule-1", fieldName: "name", localValue: "Neu-A", serverValue: "Neu-B")

        let conflicts = try store.conflicts()
        #expect(conflicts.count == 1)
        #expect(conflicts.first?.recordType == "Rule")
        #expect(conflicts.first?.fieldName == "name")
        #expect(conflicts.first?.localValue == "Neu-A")
        #expect(conflicts.first?.serverValue == "Neu-B")
    }

    @Test func resolveEntferntDenKonflikt() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = PendingSyncConflictStore(database: database)
        try store.record(recordType: "Rule", recordName: "rule-1", fieldName: "name", localValue: "Neu-A", serverValue: "Neu-B")
        let conflictID = try store.conflicts()[0].id

        try store.resolve(id: conflictID!)

        #expect(try store.conflicts().isEmpty)
    }
}
```

- [ ] **Step 2: Test ausführen, Fehlschlag bestätigen**

Run: `xcodebuild test -scheme Feedivo -only-testing:FeedivoTests/PendingSyncConflictStoreTests`
Expected: FAIL — Compile-Fehler, `PendingSyncConflictStore` existiert noch nicht.

- [ ] **Step 3: Migration `v28_create_pending_sync_conflicts` anlegen**

In `FeedivoDatabaseMigrator.swift`, direkt nach `v27_add_changed_fields_to_pending_changes`:

```swift
        migrator.registerMigration("v28_create_pending_sync_conflicts") { database in
            try database.create(table: "pending_sync_conflicts") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("recordType", .text).notNull()
                table.column("recordName", .text).notNull()
                table.column("fieldName", .text).notNull()
                table.column("localValue", .text).notNull()
                table.column("serverValue", .text).notNull()
                table.column("detectedAt", .datetime).notNull()
            }
        }
```

- [ ] **Step 4: `PendingSyncConflictRecord` anlegen**

```swift
import Foundation
import GRDB

/// Ein einzelner, noch nicht vom Nutzer aufgelöster Feld-Ebene-Konflikt aus
/// `CloudSyncEngine.handleFailedSave` — entsteht, wenn zwei Geräte dasselbe „Fragen"-Feld
/// (siehe `CloudSyncRecordMapping.askFields`) unterschiedlich geändert haben. Rein lokal,
/// wird selbst nicht synchronisiert. Siehe Design-Spec
/// `docs/superpowers/specs/2026-07-26-icloud-sync-phase3-design.md`, Abschnitt 5.
struct PendingSyncConflictRecord: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable, Sendable {
    static let databaseTableName = "pending_sync_conflicts"

    var id: Int64?
    var recordType: String
    var recordName: String
    var fieldName: String
    var localValue: String
    var serverValue: String
    var detectedAt: Date

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
```

- [ ] **Step 5: `PendingSyncConflictStore` anlegen**

```swift
import Foundation
import GRDB

struct PendingSyncConflictStore {
    private let database: FeedivoDatabase

    init(database: FeedivoDatabase) {
        self.database = database
    }

    func record(recordType: String, recordName: String, fieldName: String, localValue: String, serverValue: String) throws {
        try database.write { db in
            var conflict = PendingSyncConflictRecord(
                id: nil,
                recordType: recordType,
                recordName: recordName,
                fieldName: fieldName,
                localValue: localValue,
                serverValue: serverValue,
                detectedAt: Date()
            )
            try conflict.insert(db)
        }
    }

    func conflicts() throws -> [PendingSyncConflictRecord] {
        try database.read { db in
            try PendingSyncConflictRecord.fetchAll(db, sql: "SELECT * FROM pending_sync_conflicts ORDER BY detectedAt")
        }
    }

    func conflicts(recordType: String, recordName: String) throws -> [PendingSyncConflictRecord] {
        try database.read { db in
            try PendingSyncConflictRecord.fetchAll(
                db,
                sql: "SELECT * FROM pending_sync_conflicts WHERE recordType = ? AND recordName = ?",
                arguments: [recordType, recordName]
            )
        }
    }

    func resolve(id: Int64) throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM pending_sync_conflicts WHERE id = ?", arguments: [id])
        }
    }

    func count() throws -> Int {
        try database.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM pending_sync_conflicts") ?? 0
        }
    }
}
```

- [ ] **Step 6: Test ausführen, Erfolg bestätigen**

Run: `xcodebuild test -scheme Feedivo -only-testing:FeedivoTests/PendingSyncConflictStoreTests`
Expected: PASS

- [ ] **Step 7: Migrations-Testlauf gegenprüfen**

Run: `xcodebuild test -scheme Feedivo -only-testing:FeedivoTests/FeedivoDatabaseMigratorTests`
Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add Feedivo/Database/FeedivoDatabaseMigrator.swift Feedivo/Database/Records/PendingSyncConflictRecord.swift \
        Feedivo/Stores/PendingSyncConflictStore.swift FeedivoTests/PendingSyncConflictStoreTests.swift
git commit -m "Feature: Migration v28 + PendingSyncConflictRecord/-Store (iCloud Sync Phase 3 Task 4)"
```

---

## Task 5: `CloudSyncEngine.handleFailedSave` — Feld-Ebene-Konfliktauflösung

**Files:**
- Modify: `Feedivo/Services/CloudSync/CloudSyncEngine.swift:473-510` (`handleFailedSave`)
- Test: `FeedivoTests/CloudSyncEngineFieldConflictTests.swift` (neu)

**Interfaces:**
- Consumes: `CloudSyncPendingChangeRecord.changedFields` (Task 2),
  `CloudSyncRecordMapping.askFields`/`.autoFields` (Task 3),
  `PendingSyncConflictStore.record(...)` (Task 4).
- Produces: `handleFailedSave` löst weiterhin `Bool` auf (unverändert nach außen — `true` =
  erneuter Sendeversuch nötig). Verhalten ändert sich: bei einem „Auto"-Feld-Konflikt wird der
  GEMERGTE Record gespeichert (nicht mehr die komplette Gegenseite); bei einem „Fragen"-Feld-
  Konflikt landet der Konflikt in `pending_sync_conflicts`, der Datensatz bleibt lokal
  unverändert stehen, KEIN erneuter Sendeversuch (verhindert einen Loop, bis der Nutzer
  entscheidet).

- [ ] **Step 1: Reinen Unit-Test für die neue, direkt testbare `mergeDecision`-Funktion schreiben**

```swift
import Foundation
import CloudKit
import Testing
@testable import Feedivo

@MainActor
struct CloudSyncEngineFieldConflictTests {
    @Test func mergeDecisionOhneUnterschiedIstNoConflict() {
        let decision = CloudSyncEngine.mergeDecision(
            fieldName: "name", localValue: "Gleich" as CKRecordValue, serverValue: "Gleich" as CKRecordValue,
            askFields: ["name"], autoFields: []
        )
        #expect(decision == .noConflict)
    }

    @Test func mergeDecisionBeiAskFieldMitUnterschiedIstNeedsUserDecision() {
        let decision = CloudSyncEngine.mergeDecision(
            fieldName: "name", localValue: "Neu-A" as CKRecordValue, serverValue: "Neu-B" as CKRecordValue,
            askFields: ["name"], autoFields: []
        )
        #expect(decision == .needsUserDecision)
    }

    @Test func mergeDecisionBeiAutoFieldMitUnterschiedIstAutoResolved() {
        let decision = CloudSyncEngine.mergeDecision(
            fieldName: "sortIndex", localValue: 1 as CKRecordValue, serverValue: 2 as CKRecordValue,
            askFields: ["name"], autoFields: ["sortIndex"]
        )
        #expect(decision == .autoResolved)
    }
}
```

- [ ] **Step 2: Test ausführen, Fehlschlag bestätigen**

Run: `xcodebuild test -scheme Feedivo -only-testing:FeedivoTests/CloudSyncEngineFieldConflictTests`
Expected: FAIL — Compile-Fehler, `CloudSyncEngine.mergeDecision` existiert noch nicht.

- [ ] **Step 3: `handleFailedSave` in eine testbare reine Merge-Funktion + den bestehenden CKSyncEngine-Aufrufer aufteilen**

In `CloudSyncEngine.swift`, den bestehenden `handleFailedSave`-Block (Zeile 473-510) ersetzen:

```swift
    /// Ergebnis einer Feld-Ebene-Konfliktentscheidung für EIN Feld — Rückgabewert der reinen,
    /// direkt testbaren `mergeDecision`-Funktion unten.
    enum FieldMergeDecision: Equatable {
        case noConflict
        case autoResolved
        case needsUserDecision
    }

    /// Reine, `nonisolated` und direkt testbare Kernlogik der Feld-Ebene-Konfliktauflösung
    /// (Phase 3) — nimmt für EIN einzelnes Feld lokalen und Server-Wert entgegen und
    /// entscheidet nach der `CloudSyncRecordMapping`-Policy. Getrennt von `handleFailedSave`
    /// selbst, damit sie ohne echtes `CKSyncEngine`/`CKRecord.ID`-Setup unit-testbar ist.
    nonisolated static func mergeDecision(
        fieldName: String,
        localValue: CKRecordValue?,
        serverValue: CKRecordValue?,
        askFields: Set<String>,
        autoFields: Set<String>
    ) -> FieldMergeDecision {
        guard let localValue, let serverValue, !valuesEqual(localValue, serverValue) else {
            return .noConflict
        }
        if askFields.contains(fieldName) {
            return .needsUserDecision
        }
        return .autoResolved
    }

    private nonisolated static func valuesEqual(_ lhs: CKRecordValue, _ rhs: CKRecordValue) -> Bool {
        if let lhsString = lhs as? String, let rhsString = rhs as? String { return lhsString == rhsString }
        if let lhsInt = lhs as? Int, let rhsInt = rhs as? Int { return lhsInt == rhsInt }
        if let lhsBool = lhs as? Bool, let rhsBool = rhs as? Bool { return lhsBool == rhsBool }
        if let lhsDouble = lhs as? Double, let rhsDouble = rhs as? Double { return lhsDouble == rhsDouble }
        return false
    }

    /// Last-Write-Wins auf Ganz-Record-Ebene, ODER Feld-Ebene-Merge, falls die zugehörige
    /// Pending-Change-Zeile ein `changedFields` trägt (Phase 3). `ArticleStatus` nimmt einen
    /// eigenen, dritten Pfad (Pro-Feld-Zeitstempel über `readAt`/`starredAt`, kein Dialog).
    /// Liefert `true`, wenn dieses Element einen erneuten Sendeversuch braucht.
    private func handleFailedSave(_ failedSave: CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave) async -> Bool {
        guard failedSave.error.code == .serverRecordChanged else {
            status.state = .error(failedSave.error.localizedDescription)
            AppLogger.dataAccess.error("iCloud Sync: Record-Save fehlgeschlagen: \(failedSave.error.localizedDescription, privacy: .public)")
            return false
        }

        guard let serverRecord = failedSave.error.serverRecord,
              let mapping = Self.mapping(forRecordType: failedSave.record.recordType)
        else { return false }

        if mapping.recordType == CloudSyncArticleStatusMapping.recordType {
            return await handleArticleStatusConflict(localRecord: failedSave.record, serverRecord: serverRecord)
        }

        let pendingChange = try? pendingChangeStore.pendingChange(recordName: failedSave.record.recordID.recordName)

        guard let changedFields = pendingChange?.changedFields, !changedFields.isEmpty else {
            // Kein Feld-Tracking für diese Pending-Change (Altbestand oder Löschung) — bisheriges
            // Ganz-Record-Last-Write-Wins.
            return await resolveWholeRecordLastWriteWins(failedSave: failedSave, serverRecord: serverRecord, mapping: mapping)
        }

        var mergedRecord = serverRecord
        var hasUnresolvedConflict = false
        for fieldName in changedFields {
            let localValue = failedSave.record[fieldName]
            let serverValue = serverRecord[fieldName]
            let decision = Self.mergeDecision(
                fieldName: fieldName,
                localValue: localValue,
                serverValue: serverValue,
                askFields: mapping.askFields,
                autoFields: mapping.autoFields
            )
            switch decision {
            case .noConflict:
                continue
            case .autoResolved:
                mergedRecord[fieldName] = localValue
            case .needsUserDecision:
                hasUnresolvedConflict = true
                do {
                    try PendingSyncConflictStore(database: database).record(
                        recordType: mapping.recordType,
                        recordName: failedSave.record.recordID.recordName,
                        fieldName: fieldName,
                        localValue: describeForDisplay(localValue),
                        serverValue: describeForDisplay(serverValue)
                    )
                } catch {
                    AppLogger.dataAccess.error("iCloud Sync: Konflikt konnte nicht vermerkt werden: \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        if hasUnresolvedConflict {
            // Datensatz bleibt lokal auf dem aktuellen Vor-Konflikt-Stand stehen: weder wird der
            // Server-Stand übernommen noch ein erneuter Sendeversuch eingeplant, bis der Nutzer
            // im Konflikt-Sheet entscheidet (siehe Task 11).
            SQLiteDataInvalidation.bumpStatusVersion()
            return false
        }

        let applied = await applyIncomingRecord(mergedRecord)
        if applied {
            dequeuePendingChange(recordName: failedSave.record.recordID.recordName)
        }
        return false
    }

    private nonisolated static func describeForDisplay(_ value: CKRecordValue?) -> String {
        if let stringValue = value as? String { return stringValue }
        if let value { return String(describing: value) }
        return ""
    }

    /// Bisheriges Verhalten (Phase 1/2a/2b), unverändert — für Pending-Changes ohne bekannte
    /// Feldgranularität.
    private func resolveWholeRecordLastWriteWins(
        failedSave: CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave,
        serverRecord: CKRecord,
        mapping: any CloudSyncRecordMapping.Type
    ) async -> Bool {
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

    /// Sonderregel für `ArticleStatus` (siehe Design-Spec Abschnitt 4): `isRead`/`isStarred`
    /// werden UNABHÄNGIG voneinander per eigenem Zeitstempel (`readAt`/`starredAt`) aufgelöst,
    /// kein Dialog — niedrige Tragweite, ein falscher Status ist mit einem Klick korrigiert.
    private func handleArticleStatusConflict(localRecord: CKRecord, serverRecord: CKRecord) async -> Bool {
        let mergedRecord = serverRecord

        let localReadAt = localRecord["readAt"] as? Date
        let serverReadAt = serverRecord["readAt"] as? Date
        if (localReadAt ?? .distantPast) > (serverReadAt ?? .distantPast) {
            mergedRecord["isRead"] = localRecord["isRead"]
            mergedRecord["readAt"] = localRecord["readAt"]
        }

        let localStarredAt = localRecord["starredAt"] as? Date
        let serverStarredAt = serverRecord["starredAt"] as? Date
        if (localStarredAt ?? .distantPast) > (serverStarredAt ?? .distantPast) {
            mergedRecord["isStarred"] = localRecord["isStarred"]
            mergedRecord["starredAt"] = localRecord["starredAt"]
        }

        let applied = await applyIncomingRecord(mergedRecord)
        if applied {
            dequeuePendingChange(recordName: localRecord.recordID.recordName)
        }
        return false
    }
```

- [ ] **Step 4: Test ausführen, Erfolg bestätigen**

Run: `xcodebuild test -scheme Feedivo -only-testing:FeedivoTests/CloudSyncEngineFieldConflictTests`
Expected: PASS

- [ ] **Step 5: Integrationstest — Ganz-Record-Fallback bleibt für Pending-Changes ohne `changedFields` unverändert**

```swift
    @Test func pendingChangeOhneChangedFieldsNutztWeiterhinGanzRecordLWW() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let tag = TagRecord(id: "tag-1", name: "Alt", colorHex: "#FF0000", sortIndex: 0)
        try TagStore(database: database).save(tag)

        // Ohne CloudSyncSettings.isEnabled() wird kein changedFields gesetzt — simuliert
        // Altbestand von vor Phase 3.
        try CloudSyncPendingChangeStore(database: database).enqueue(recordType: "Tag", recordName: "tag-1", changeType: .save)

        let change = try CloudSyncPendingChangeStore(database: database).pendingChange(recordName: "tag-1")
        #expect(change?.changedFields == nil)
    }
```

Run: `xcodebuild test -scheme Feedivo -only-testing:FeedivoTests/CloudSyncEngineFieldConflictTests`
Expected: PASS

- [ ] **Step 6: Vollen bestehenden CloudSync-Testlauf gegenprüfen (keine Regression am bisherigen Ganz-Record-LWW)**

Run: `xcodebuild test -scheme Feedivo -only-testing:FeedivoTests/CloudSyncEngineRegistryTests -only-testing:FeedivoTests/CloudSyncTagMappingTests -only-testing:FeedivoTests/CloudSyncFeedMappingTests`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add Feedivo/Services/CloudSync/CloudSyncEngine.swift FeedivoTests/CloudSyncEngineFieldConflictTests.swift
git commit -m "Feature: Feld-Ebene-Konfliktauflösung in CloudSyncEngine.handleFailedSave (iCloud Sync Phase 3 Task 5)"
```

---

## Task 6: `changedFields` in `TagStore` verdrahten

**Files:**
- Modify: `Feedivo/Stores/TagStore.swift`
- Test: `FeedivoTests/TagStoreChangedFieldsTests.swift` (neu)

**Interfaces:**
- Consumes: `CloudSyncPendingChangeStore.enqueue(...changedFields:)` (Task 2).

- [ ] **Step 1: Fehlschlagenden Test schreiben**

Zuerst das im Projekt bereits etablierte Muster zum testweisen Aktivieren von Sync
(`CloudSyncSettings`) in einer bestehenden CloudSync-Testdatei (z. B.
`SQLiteTagStoreTests.swift` oder `CloudSyncTagMappingTests.swift`) nachschlagen und identisch
übernehmen.

```swift
import Foundation
import Testing
@testable import Feedivo

struct TagStoreChangedFieldsTests {
    @Test func renameTagMarkiertNurNameAlsGeaendert() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = TagStore(database: database)
        try store.save(TagRecord(id: "tag-1", name: "Alt", colorHex: "#FF0000", sortIndex: 0))
        UserDefaults.standard.set(true, forKey: CloudSyncSettings.isEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey) }

        try store.renameTag(id: "tag-1", name: "Neu")

        let change = try CloudSyncPendingChangeStore(database: database).pendingChange(recordName: "tag-1")
        #expect(change?.changedFields == ["name"])
    }

    @Test func updateColorMarkiertNurColorHexAlsGeaendert() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = TagStore(database: database)
        try store.save(TagRecord(id: "tag-1", name: "Alt", colorHex: "#FF0000", sortIndex: 0))
        UserDefaults.standard.set(true, forKey: CloudSyncSettings.isEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey) }

        try store.updateColor(id: "tag-1", colorHex: "#00FF00")

        let change = try CloudSyncPendingChangeStore(database: database).pendingChange(recordName: "tag-1")
        #expect(change?.changedFields == ["colorHex"])
    }
}
```

Hinweis: `CloudSyncSettings.isEnabledKey` exakt gegen die tatsächliche, in
`CloudSyncSettings.swift` deklarierte Konstante prüfen (Name kann abweichen) und das dort
etablierte Test-Setup-Muster 1:1 verwenden statt zu raten.

- [ ] **Step 2: Test ausführen, Fehlschlag bestätigen**

Run: `xcodebuild test -scheme Feedivo -only-testing:FeedivoTests/TagStoreChangedFieldsTests`
Expected: FAIL — `changedFields` ist `nil`.

- [ ] **Step 3: `TagStore.enqueuePendingSync` um `changedFields`-Parameter erweitern und an den drei relevanten Aufrufstellen setzen**

```swift
    private func enqueuePendingSync(_ db: Database, tagID: String, changeType: CloudSyncChangeType, changedFields: [String]? = nil) throws {
        guard CloudSyncSettings.isEnabled() else { return }
        try CloudSyncPendingChangeStore.enqueue(db, recordType: CloudSyncTagMapping.recordType, recordName: tagID, changeType: changeType, changedFields: changedFields)
    }
```

`renameTag` (Zeile 215): `try enqueuePendingSync(db, tagID: id, changeType: .save, changedFields: ["name"])`

`move` (Zeile 242): `try enqueuePendingSync(db, tagID: tagID, changeType: .save, changedFields: ["sortIndex"])`

`updateColor` (Zeile 263): `try enqueuePendingSync(db, tagID: id, changeType: .save, changedFields: ["colorHex"])`

`save`/`deleteTag` bleiben ohne `changedFields` (Ganz-Neuanlage bzw. Löschung — kein
Feld-Merge sinnvoll).

- [ ] **Step 4: Test ausführen, Erfolg bestätigen**

Run: `xcodebuild test -scheme Feedivo -only-testing:FeedivoTests/TagStoreChangedFieldsTests`
Expected: PASS

- [ ] **Step 5: Bestehenden TagStore-Testlauf gegenprüfen**

Run: `xcodebuild test -scheme Feedivo -only-testing:FeedivoTests/SQLiteTagStoreTests`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Stores/TagStore.swift FeedivoTests/TagStoreChangedFieldsTests.swift
git commit -m "Feature: changedFields-Tracking in TagStore verdrahtet (iCloud Sync Phase 3 Task 6)"
```

---

## Task 7: `changedFields` in `FeedFolderStore` verdrahten

**Files:**
- Modify: `Feedivo/Stores/FeedFolderStore.swift`
- Test: `FeedivoTests/FeedFolderStoreChangedFieldsTests.swift` (neu)

- [ ] **Step 1: Fehlschlagenden Test schreiben**

```swift
import Foundation
import Testing
@testable import Feedivo

struct FeedFolderStoreChangedFieldsTests {
    @Test func renameFolderMarkiertNurNameAlsGeaendert() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = FeedFolderStore(database: database)
        try store.save(FeedFolderRecord(id: "folder-1", name: "Alt", sortIndex: 0, createdAt: Date(), updatedAt: Date()))
        UserDefaults.standard.set(true, forKey: CloudSyncSettings.isEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey) }

        try store.renameFolder(from: "Alt", to: "Neu")

        let change = try CloudSyncPendingChangeStore(database: database).pendingChange(recordName: "folder-1")
        #expect(change?.changedFields == ["name"])
    }
}
```

- [ ] **Step 2: Test ausführen, Fehlschlag bestätigen**

Run: `xcodebuild test -scheme Feedivo -only-testing:FeedivoTests/FeedFolderStoreChangedFieldsTests`
Expected: FAIL

- [ ] **Step 3: `enqueuePendingSync` erweitern und an den relevanten Stellen setzen**

```swift
    private func enqueuePendingSync(_ db: Database, folderID: String, changeType: CloudSyncChangeType, changedFields: [String]? = nil) throws {
        guard CloudSyncSettings.isEnabled() else { return }
        try CloudSyncPendingChangeStore.enqueue(db, recordType: CloudSyncFeedFolderMapping.recordType, recordName: folderID, changeType: changeType, changedFields: changedFields)
    }
```

`renameFolder` (Zeile 153): `try enqueuePendingSync(db, folderID: folderID, changeType: .save, changedFields: ["name"])`

`moveFolder` (Zeile 253) und `sortAlphabetically` (Zeile 286): jeweils
`try enqueuePendingSync(db, folderID: folderID, changeType: .save, changedFields: ["sortIndex"])`

`save`/`delete` bleiben unverändert ohne `changedFields`.

- [ ] **Step 4: Test ausführen, Erfolg bestätigen**

Run: `xcodebuild test -scheme Feedivo -only-testing:FeedivoTests/FeedFolderStoreChangedFieldsTests`
Expected: PASS

- [ ] **Step 5: Bestehenden Testlauf gegenprüfen**

Run: `xcodebuild test -scheme Feedivo -only-testing:FeedivoTests/FeedFolderStoreTests`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Stores/FeedFolderStore.swift FeedivoTests/FeedFolderStoreChangedFieldsTests.swift
git commit -m "Feature: changedFields-Tracking in FeedFolderStore verdrahtet (iCloud Sync Phase 3 Task 7)"
```

---

## Task 8: `changedFields` in `FeedStore` verdrahten

**Files:**
- Modify: `Feedivo/Stores/FeedStore.swift`
- Test: `FeedivoTests/FeedStoreChangedFieldsTests.swift` (neu)

- [ ] **Step 1: Fehlschlagenden Test schreiben**

```swift
import Foundation
import Testing
@testable import Feedivo

struct FeedStoreChangedFieldsTests {
    @Test func renameFeedMarkiertNurTitleAlsGeaendert() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = FeedStore(database: database)
        try store.save(FeedRecord(id: "feed-1", url: "https://example.com/feed", title: "Alt", sortIndex: 0))
        UserDefaults.standard.set(true, forKey: CloudSyncSettings.isEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey) }

        try store.renameFeed(id: "feed-1", displayTitle: "Neu")

        let change = try CloudSyncPendingChangeStore(database: database).pendingChange(recordName: "feed-1")
        #expect(change?.changedFields == ["title"])
    }

    @Test func updateRetentionSettingsMarkiertAlle5RetentionFelderAlsGeaendert() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = FeedStore(database: database)
        try store.save(FeedRecord(id: "feed-1", url: "https://example.com/feed", title: "Titel", sortIndex: 0))
        UserDefaults.standard.set(true, forKey: CloudSyncSettings.isEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey) }

        try store.updateRetentionSettings(id: "feed-1", overridesGlobal: true, isEnabled: true, days: 30, minimumArticles: 5, includesProtectedArticles: false)

        let change = try CloudSyncPendingChangeStore(database: database).pendingChange(recordName: "feed-1")
        #expect(change?.changedFields?.count == 5)
        #expect(change?.changedFields?.contains("articleRetentionDays") == true)
    }
}
```

Hinweis: Die exakte Parameterliste von `updateRetentionSettings` gegen die tatsächliche
Signatur in `FeedStore.swift:155` prüfen und ggf. anpassen — dieser Plan geht von den 5
Feldern aus `CloudSyncFeedMapping.FeedConfig` aus (`articleRetentionOverridesGlobalSetting`,
`articleRetentionIsEnabled`, `articleRetentionDays`, `articleRetentionMinimumArticles`,
`articleRetentionIncludesProtectedArticles`).

- [ ] **Step 2: Test ausführen, Fehlschlag bestätigen**

Run: `xcodebuild test -scheme Feedivo -only-testing:FeedivoTests/FeedStoreChangedFieldsTests`
Expected: FAIL

- [ ] **Step 3: `enqueuePendingSync` erweitern und an allen relevanten Stellen setzen**

```swift
    private func enqueuePendingSync(_ db: Database, feedID: String, changeType: CloudSyncChangeType, changedFields: [String]? = nil) throws {
        guard CloudSyncSettings.isEnabled() else { return }
        try CloudSyncPendingChangeStore.enqueue(db, recordType: CloudSyncFeedMapping.recordType, recordName: feedID, changeType: changeType, changedFields: changedFields)
    }
```

- `renameFeed` (Zeile 68): `changedFields: ["title"]`
- `restoreOriginalTitle` (Zeile 90): `changedFields: ["title"]`
- `updateRefreshInterval` (Zeile 110): `changedFields: ["refreshIntervalMinutes"]`
- `updateFolderName` (Zeile 130): `changedFields: ["folderName"]`
- `updateNotificationEnabled` (Zeile 150): `changedFields: ["isNotificationEnabled"]`
- `updateRetentionSettings` (Zeile 192): `changedFields: ["articleRetentionOverridesGlobalSetting", "articleRetentionIsEnabled", "articleRetentionDays", "articleRetentionMinimumArticles", "articleRetentionIncludesProtectedArticles"]`
- `moveFeed` (Zeile 388): `changedFields: ["sortIndex"]`
- `save`/`delete`/`updateAfterRefresh`/`setUnreadCount` bleiben unverändert ohne `changedFields`
  (Letztere zwei sind ohnehin lokal-only Felder, die gar nicht gesynct werden — siehe
  `CloudSyncFeedMapping`-Dokumentation).

- [ ] **Step 4: Test ausführen, Erfolg bestätigen**

Run: `xcodebuild test -scheme Feedivo -only-testing:FeedivoTests/FeedStoreChangedFieldsTests`
Expected: PASS

- [ ] **Step 5: Bestehenden Testlauf gegenprüfen**

Run: `xcodebuild test -scheme Feedivo -only-testing:FeedivoTests/SQLiteFeedStoreTests`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Stores/FeedStore.swift FeedivoTests/FeedStoreChangedFieldsTests.swift
git commit -m "Feature: changedFields-Tracking in FeedStore verdrahtet (iCloud Sync Phase 3 Task 8)"
```

---

## Task 9: `changedFields` in `SQLiteRuleStore` verdrahten (mit Diffing)

**Files:**
- Modify: `Feedivo/Stores/SQLiteRuleStore.swift`
- Test: `FeedivoTests/SQLiteRuleStoreChangedFieldsTests.swift` (neu)

**Interfaces:**
- Consumes: `RuleRecord` (bestehend), `CloudSyncPendingChangeStore.enqueue(...changedFields:)`.

Anders als bei Tag/Feed/FeedFolder ist `save(_:conditions:)` ein genereller Upsert (der
Regel-Editor ruft ihn für JEDE Speicherung auf, egal welches Feld sich geändert hat) — hier
muss VOR dem Schreiben der bestehende Rule-Stand geladen und gegen den neuen verglichen
werden, um `changedFields` korrekt zu berechnen.

- [ ] **Step 1: Fehlschlagenden Test schreiben**

```swift
import Foundation
import Testing
@testable import Feedivo

struct SQLiteRuleStoreChangedFieldsTests {
    @Test func saveMarkiertNurTatsaechlichGeaenderteFelder() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = SQLiteRuleStore(database: database)
        let original = RuleRecord(
            id: "rule-1", name: "Alt", isEnabled: true, matchMode: RuleMatchMode.all.rawValue,
            action: "assignTag", assignTagID: nil, notificationTemplate: "{Titel}",
            notificationPriority: RuleNotificationPriority.normal.rawValue, sortOrder: 0, createdAt: Date()
        )
        try store.save(original, conditions: [])
        UserDefaults.standard.set(true, forKey: CloudSyncSettings.isEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey) }

        var updated = original
        updated.name = "Neu"
        try store.save(updated, conditions: [])

        let change = try CloudSyncPendingChangeStore(database: database).pendingChange(recordName: "rule-1")
        #expect(change?.changedFields == ["name"])
    }

    @Test func updateEnabledMarkiertNurIsEnabled() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = SQLiteRuleStore(database: database)
        let rule = RuleRecord(
            id: "rule-1", name: "Regel", isEnabled: true, matchMode: RuleMatchMode.all.rawValue,
            action: "assignTag", assignTagID: nil, notificationTemplate: "{Titel}",
            notificationPriority: RuleNotificationPriority.normal.rawValue, sortOrder: 0, createdAt: Date()
        )
        try store.save(rule, conditions: [])
        UserDefaults.standard.set(true, forKey: CloudSyncSettings.isEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey) }

        try store.updateEnabled(id: "rule-1", isEnabled: false)

        let change = try CloudSyncPendingChangeStore(database: database).pendingChange(recordName: "rule-1")
        #expect(change?.changedFields == ["isEnabled"])
    }
}
```

- [ ] **Step 2: Test ausführen, Fehlschlag bestätigen**

Run: `xcodebuild test -scheme Feedivo -only-testing:FeedivoTests/SQLiteRuleStoreChangedFieldsTests`
Expected: FAIL

- [ ] **Step 3: `enqueuePendingSync` erweitern**

```swift
    private func enqueuePendingSync(_ db: Database, recordType: String, recordName: String, changeType: CloudSyncChangeType, changedFields: [String]? = nil) throws {
        guard CloudSyncSettings.isEnabled() else { return }
        try CloudSyncPendingChangeStore.enqueue(db, recordType: recordType, recordName: recordName, changeType: changeType, changedFields: changedFields)
    }
```

- [ ] **Step 4: `save(_:conditions:)` um ein Vorher/Nachher-Diff der Rule-Felder erweitern**

```swift
    func save(_ rule: RuleRecord, conditions: [RuleConditionRecord]) throws {
        try database.write { db in
            let existingRule = try Self.fetchRules(db).first { $0.id == rule.id }
            var rule = rule
            try rule.save(db)
            try enqueuePendingSync(db, recordType: CloudSyncRuleMapping.recordType, recordName: rule.id, changeType: .save, changedFields: Self.changedRuleFields(old: existingRule, new: rule))

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

    /// Vergleicht den alten gegen den neuen Rule-Stand und liefert exakt die Feldnamen, die sich
    /// tatsächlich geändert haben — `nil` (kein Tracking) falls `existingRule` `nil` ist (echte
    /// Neuanlage, kein Feld-Merge sinnvoll). Feldnamen entsprechen exakt den CKRecord-Schlüsseln
    /// aus `CloudSyncRuleMapping.makeCKRecord`.
    private static func changedRuleFields(old existingRule: RuleRecord?, new rule: RuleRecord) -> [String]? {
        guard let existingRule else { return nil }
        var changed: [String] = []
        if existingRule.name != rule.name { changed.append("name") }
        if existingRule.isEnabled != rule.isEnabled { changed.append("isEnabled") }
        if existingRule.matchMode != rule.matchMode { changed.append("matchMode") }
        if existingRule.action != rule.action { changed.append("action") }
        if existingRule.assignTagID != rule.assignTagID { changed.append("assignTagID") }
        if existingRule.notificationTemplate != rule.notificationTemplate { changed.append("notificationTemplate") }
        if existingRule.notificationPriority != rule.notificationPriority { changed.append("notificationPriority") }
        if existingRule.sortOrder != rule.sortOrder { changed.append("sortOrder") }
        return changed.isEmpty ? nil : changed
    }
```

`updateEnabled` (Zeile 84): `try enqueuePendingSync(db, recordType: CloudSyncRuleMapping.recordType, recordName: id, changeType: .save, changedFields: ["isEnabled"])`

`move` (Zeile 162): `changedFields: ["sortOrder"]`

`duplicate`/`delete` bleiben ohne `changedFields` (Neuanlage bzw. Löschung).

- [ ] **Step 5: Test ausführen, Erfolg bestätigen**

Run: `xcodebuild test -scheme Feedivo -only-testing:FeedivoTests/SQLiteRuleStoreChangedFieldsTests`
Expected: PASS

- [ ] **Step 6: Bestehenden Testlauf gegenprüfen**

Run: `xcodebuild test -scheme Feedivo -only-testing:FeedivoTests/SQLiteRuleStoreTests`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add Feedivo/Stores/SQLiteRuleStore.swift FeedivoTests/SQLiteRuleStoreChangedFieldsTests.swift
git commit -m "Feature: changedFields-Tracking mit Diffing in SQLiteRuleStore verdrahtet (iCloud Sync Phase 3 Task 9)"
```

---

## Task 10: `changedFields` in `SQLiteSmartFolderStore` verdrahten (Spiegelung von Task 9)

**Files:**
- Modify: `Feedivo/Stores/SQLiteSmartFolderStore.swift`
- Test: `FeedivoTests/SQLiteSmartFolderStoreChangedFieldsTests.swift` (neu)

- [ ] **Step 1: Fehlschlagenden Test schreiben**

```swift
import Foundation
import Testing
@testable import Feedivo

struct SQLiteSmartFolderStoreChangedFieldsTests {
    @Test func saveMarkiertNurTatsaechlichGeaenderteFelder() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = SQLiteSmartFolderStore(database: database)
        let original = SmartFolderRecord(
            id: "folder-1", name: "Alt", matchMode: RuleMatchMode.all.rawValue,
            isShownInSidebar: true, isDefault: false, sortOrder: 0, defaultKey: nil,
            iconName: nil, colorHex: nil, defaultShowsReadArticles: false,
            createdAt: Date(), updatedAt: Date()
        )
        try store.save(original, conditions: [])
        UserDefaults.standard.set(true, forKey: CloudSyncSettings.isEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey) }

        var updated = original
        updated.name = "Neu"
        try store.save(updated, conditions: [])

        let change = try CloudSyncPendingChangeStore(database: database).pendingChange(recordName: "folder-1")
        #expect(change?.changedFields == ["name"])
    }
}
```

- [ ] **Step 2: Test ausführen, Fehlschlag bestätigen**

Run: `xcodebuild test -scheme Feedivo -only-testing:FeedivoTests/SQLiteSmartFolderStoreChangedFieldsTests`
Expected: FAIL

- [ ] **Step 3: `enqueuePendingSync` erweitern, `save` um Diffing ergänzen — identisches Muster zu Task 9**

```swift
    private func enqueuePendingSync(_ db: Database, recordType: String, recordName: String, changeType: CloudSyncChangeType, changedFields: [String]? = nil) throws {
        guard CloudSyncSettings.isEnabled() else { return }
        try CloudSyncPendingChangeStore.enqueue(db, recordType: recordType, recordName: recordName, changeType: changeType, changedFields: changedFields)
    }

    func save(_ folder: SmartFolderRecord, conditions: [SmartFolderConditionRecord]) throws {
        try database.write { db in
            let existingFolder = try Self.fetchFolders(db).first { $0.id == folder.id }
            var folder = folder
            try folder.save(db)

            if !folder.isDefault {
                try enqueuePendingSync(db, recordType: CloudSyncSmartFolderMapping.recordType, recordName: folder.id, changeType: .save, changedFields: Self.changedSmartFolderFields(old: existingFolder, new: folder))
            }

            let existingConditionIDs = try String.fetchAll(db, sql: "SELECT id FROM smart_folder_conditions WHERE smartFolderID = ?", arguments: [folder.id])
            if !folder.isDefault {
                for conditionID in existingConditionIDs {
                    try enqueuePendingSync(db, recordType: CloudSyncSmartFolderConditionMapping.recordType, recordName: conditionID, changeType: .delete)
                }
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
                if !folder.isDefault {
                    try enqueuePendingSync(db, recordType: CloudSyncSmartFolderConditionMapping.recordType, recordName: condition.id, changeType: .save)
                }
            }
        }
        CloudSyncEngine.notifyPendingChangesAvailable(database: database)
    }

    private static func changedSmartFolderFields(old existingFolder: SmartFolderRecord?, new folder: SmartFolderRecord) -> [String]? {
        guard let existingFolder else { return nil }
        var changed: [String] = []
        if existingFolder.name != folder.name { changed.append("name") }
        if existingFolder.matchMode != folder.matchMode { changed.append("matchMode") }
        if existingFolder.isShownInSidebar != folder.isShownInSidebar { changed.append("isShownInSidebar") }
        if existingFolder.sortOrder != folder.sortOrder { changed.append("sortOrder") }
        if existingFolder.iconName != folder.iconName { changed.append("iconName") }
        if existingFolder.colorHex != folder.colorHex { changed.append("colorHex") }
        if existingFolder.defaultShowsReadArticles != folder.defaultShowsReadArticles { changed.append("defaultShowsReadArticles") }
        return changed.isEmpty ? nil : changed
    }
```

`updateSidebarVisibility` (Zeile 102): `changedFields: ["isShownInSidebar"]`

`move` (Zeile 182): `changedFields: ["sortOrder"]`

`duplicate`/`delete` bleiben ohne `changedFields`.

- [ ] **Step 4: Test ausführen, Erfolg bestätigen**

Run: `xcodebuild test -scheme Feedivo -only-testing:FeedivoTests/SQLiteSmartFolderStoreChangedFieldsTests`
Expected: PASS

- [ ] **Step 5: Bestehenden Testlauf gegenprüfen**

Run: `xcodebuild test -scheme Feedivo -only-testing:FeedivoTests/SQLiteSmartFolderStoreTests`
Expected: PASS — insbesondere `smartFolderStoreSpeichertOrdnerMitConditionsUndSnapshots()`
(prüft explizit den `isDefault: true`-Fall, siehe Kommentar in der bestehenden Datei) bleibt
grün.

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Stores/SQLiteSmartFolderStore.swift FeedivoTests/SQLiteSmartFolderStoreChangedFieldsTests.swift
git commit -m "Feature: changedFields-Tracking mit Diffing in SQLiteSmartFolderStore verdrahtet (iCloud Sync Phase 3 Task 10)"
```

---

## Task 11: `SyncConflictResolutionView` + „Konflikte: N"-Anzeige im Sync-Tab

**Files:**
- Create: `Feedivo/Views/Settings/SyncConflictResolutionView.swift`
- Modify: `Feedivo/Views/Settings/SettingsView.swift` (Sync-Tab-Abschnitt, dort wo die
  bestehende Sync-Status-Zeile lebt — direkt neben „Synchron"/„Ausstehend (N)"/„Fehler: …")
- Modify: `Feedivo/Resources/L10n.swift` + `Feedivo/Resources/Localizable.xcstrings` (neue Keys)

**Interfaces:**
- Consumes: `PendingSyncConflictStore.conflicts()`/`.resolve(id:)`/`.count()` (Task 4).

- [ ] **Step 1: `SyncConflictResolutionView` anlegen**

```swift
import SwiftUI

/// Sheet zum Auflösen laufender Feld-Ebene-Konflikte (Phase 3) — pro Konflikt zwei Buttons
/// „Dieses Gerät"/„Anderes Gerät". Nach Auswahl wird der gemergte Wert direkt in die
/// betroffene Tabelle geschrieben und der Konflikt aus `pending_sync_conflicts` entfernt.
/// Siehe Design-Spec Abschnitt 5.
struct SyncConflictResolutionView: View {
    @Environment(\.feedivoDatabase) private var feedivoDatabase
    @Environment(\.dismiss) private var dismiss
    @State private var conflicts: [PendingSyncConflictRecord] = []
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                ForEach(Dictionary(grouping: conflicts, by: { "\($0.recordType)|\($0.recordName)" }).sorted(by: { $0.key < $1.key }), id: \.key) { _, group in
                    Section(group.first?.recordType ?? "") {
                        ForEach(group) { conflict in
                            conflictRow(conflict)
                        }
                    }
                }
            }
            .navigationTitle(L10n.syncConflictsTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.commonDone) { dismiss() }
                }
            }
            .task { loadConflicts() }
            .alert(L10n.commonError, isPresented: .constant(errorMessage != nil), actions: {
                Button(L10n.commonOK) { errorMessage = nil }
            }, message: {
                Text(errorMessage ?? "")
            })
        }
    }

    @ViewBuilder
    private func conflictRow(_ conflict: PendingSyncConflictRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(conflict.fieldName)
                .font(.headline)
            HStack {
                Button(action: { resolve(conflict, keepLocal: true) }) {
                    VStack(alignment: .leading) {
                        Text(L10n.syncConflictsThisDevice)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(conflict.localValue)
                    }
                }
                .buttonStyle(.bordered)
                Button(action: { resolve(conflict, keepLocal: false) }) {
                    VStack(alignment: .leading) {
                        Text(L10n.syncConflictsOtherDevice)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(conflict.serverValue)
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }

    private func loadConflicts() {
        guard let feedivoDatabase else { return }
        do {
            conflicts = try PendingSyncConflictStore(database: feedivoDatabase).conflicts()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resolve(_ conflict: PendingSyncConflictRecord, keepLocal: Bool) {
        guard let feedivoDatabase, let mapping = CloudSyncEngine.mapping(forRecordType: conflict.recordType) else { return }
        do {
            if !keepLocal {
                try applyServerFieldValue(conflict, mapping: mapping, database: feedivoDatabase)
            }
            // `keepLocal == true`: der lokale Wert steht bereits in der Tabelle (er wurde nie
            // überschrieben, siehe Task 5) — nur den Konflikt-Eintrag entfernen und den
            // nächsten regulären Sendeversuch anstoßen.
            guard let conflictID = conflict.id else { return }
            try PendingSyncConflictStore(database: feedivoDatabase).resolve(id: conflictID)
            try CloudSyncPendingChangeStore(database: feedivoDatabase).enqueue(recordType: conflict.recordType, recordName: conflict.recordName, changeType: .save)
            CloudSyncEngine.notifyPendingChangesAvailable(database: feedivoDatabase)
            loadConflicts()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Schreibt den Server-Wert für GENAU dieses eine Feld in die lokale Tabelle — über einen
    /// direkten SQL-`UPDATE`, da die einzelnen `CloudSyncRecordMapping`-Typen keine generische
    /// Ein-Feld-Update-Methode anbieten (bewusst: Feld-Ebene-Schreibzugriff ist ein
    /// Phase-3-spezifischer Bedarf, kein allgemeiner Store-Anwendungsfall).
    private func applyServerFieldValue(_ conflict: PendingSyncConflictRecord, mapping: any CloudSyncRecordMapping.Type, database: FeedivoDatabase) throws {
        let tableName = Self.tableName(forRecordType: conflict.recordType)
        try database.write { db in
            try db.execute(
                sql: "UPDATE \(tableName) SET \(conflict.fieldName) = ? WHERE id = ?",
                arguments: [conflict.serverValue, conflict.recordName]
            )
        }
    }

    private static func tableName(forRecordType recordType: String) -> String {
        switch recordType {
        case "Tag": return "tags"
        case "Feed": return "feeds"
        case "FeedFolder": return "feed_folders"
        case "Rule": return "rules"
        case "RuleCondition": return "rule_conditions"
        case "SmartFolder": return "smart_folders"
        case "SmartFolderCondition": return "smart_folder_conditions"
        default: return ""
        }
    }
}
```

Neue `L10n`-Keys (`syncConflictsTitle`, `syncConflictsThisDevice`, `syncConflictsOtherDevice`,
`syncConflictsBadge`) in `L10n.swift` nach dem etablierten Muster ergänzen (siehe bestehende
`L10n.sync*`-Keys als Vorbild) und in `Localizable.xcstrings` per
`grep -c "sync.conflicts" Feedivo/Resources/Localizable.xcstrings` verifizieren (muss > 0
sein — siehe Gotcha zu indirekten `L10n`-Keys in CLAUDE.md: der Auto-Stub-Mechanismus greift
NICHT bei indirekt referenzierten Keys).

- [ ] **Step 2: Badge im Sync-Tab ergänzen**

In `SettingsView.swift`, im bestehenden Sync-Status-Block (direkt neben der Zeile, die
„Synchron"/„Ausstehend (N)"/„Fehler: …" rendert — Block unter „Sync-Status", Zeile mit
`Status`-Label, siehe bestehende `SyncSettingsView`-Struktur):

```swift
    @State private var pendingConflictCount = 0
    @State private var showingConflictSheet = false

    // Im bestehenden Sync-Status-Bereich, als zusätzliche Zeile nach der Status-Zeile:
    if pendingConflictCount > 0 {
        Button(action: { showingConflictSheet = true }) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(L10n.syncConflictsBadge(pendingConflictCount))
            }
        }
        .buttonStyle(.plain)
    }
```

Sowie ein `.sheet(isPresented: $showingConflictSheet) { SyncConflictResolutionView() }` und
ein `.task`/`.onChange(of: SQLiteDataInvalidation.statusVersion)`, das
`pendingConflictCount = (try? PendingSyncConflictStore(database: feedivoDatabase).count()) ?? 0`
neu lädt — exakt analog zum bereits bestehenden Muster, mit dem die Sync-Status-Zeile selbst
ihre Pending-Anzahl aktuell hält (bestehenden Code in `SettingsView.swift` direkt oberhalb
dieser neuen Zeile als Vorlage für den genauen `.onChange`-Anschluss verwenden).

`L10n.syncConflictsBadge(_:)` ist ein neuer, parametrisierter Lokalisierungs-Key
(„Konflikte: %d") — nach dem Muster bestehender parametrisierter Keys in `L10n.swift` anlegen.

- [ ] **Step 3: Build verifizieren**

Run: `xcodebuild build -scheme Feedivo`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add Feedivo/Views/Settings/SyncConflictResolutionView.swift Feedivo/Views/Settings/SettingsView.swift \
        Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings
git commit -m "Feature: SyncConflictResolutionView + Konflikte-Badge im Sync-Tab (iCloud Sync Phase 3 Task 11)"
```

---

## Task 12: `CloudSyncFirstActivationAnalyzer` — Duplikat-Erkennung

**Files:**
- Create: `Feedivo/Services/CloudSync/CloudSyncFirstActivationAnalyzer.swift`
- Test: `FeedivoTests/CloudSyncFirstActivationAnalyzerTests.swift` (neu)

**Interfaces:**
- Produces: `struct FirstActivationCollision { let recordType: String; let name: String; let localID: String; let cloudRecordID: CKRecord.ID }`,
  `CloudSyncFirstActivationAnalyzer.findCollisions(database:tagRecords:folderRecords:) -> [FirstActivationCollision]`
  — reine, `CKRecord`-Array-basierte Vergleichsfunktion (kein echtes `CKQuery` in dieser
  Funktion selbst, damit sie ohne Netzwerk testbar ist). Ein separater, dünner Wrapper
  `fetchExistingCloudRecords(container:) async -> (tags: [CKRecord], folders: [CKRecord])`
  kapselt den echten `CKQuery`-Aufruf und wird von Task 14 (UI) aufgerufen.

- [ ] **Step 1: Fehlschlagenden Test schreiben**

```swift
import Foundation
import CloudKit
import Testing
@testable import Feedivo

struct CloudSyncFirstActivationAnalyzerTests {
    @Test func findCollisionsFindetGleichenTagNamenCaseInsensitiv() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try TagStore(database: database).save(TagRecord(id: "local-tag-1", name: "Intune", colorHex: "#FF0000", sortIndex: 0))

        let cloudTag = TagRecord(id: "cloud-tag-1", name: "intune", colorHex: "#00FF00", sortIndex: 0)
        let cloudRecord = CloudSyncTagMapping.makeCKRecord(from: cloudTag)

        let collisions = try CloudSyncFirstActivationAnalyzer.findCollisions(database: database, tagRecords: [cloudRecord], folderRecords: [])

        #expect(collisions.count == 1)
        #expect(collisions.first?.recordType == "Tag")
        #expect(collisions.first?.name == "Intune")
        #expect(collisions.first?.localID == "local-tag-1")
    }

    @Test func findCollisionsFindetKeineKollisionBeiUnterschiedlichenNamen() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try TagStore(database: database).save(TagRecord(id: "local-tag-1", name: "Intune", colorHex: "#FF0000", sortIndex: 0))

        let cloudTag = TagRecord(id: "cloud-tag-1", name: "Anders", colorHex: "#00FF00", sortIndex: 0)
        let cloudRecord = CloudSyncTagMapping.makeCKRecord(from: cloudTag)

        let collisions = try CloudSyncFirstActivationAnalyzer.findCollisions(database: database, tagRecords: [cloudRecord], folderRecords: [])

        #expect(collisions.isEmpty)
    }

    @Test func findCollisionsFindetGleichenFeedFolderNamen() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try FeedFolderStore(database: database).save(FeedFolderRecord(id: "local-folder-1", name: "Technik", sortIndex: 0, createdAt: Date(), updatedAt: Date()))

        let cloudFolder = FeedFolderRecord(id: "cloud-folder-1", name: "Technik", sortIndex: 0, createdAt: Date(), updatedAt: Date())
        let cloudRecord = CloudSyncFeedFolderMapping.makeCKRecord(from: cloudFolder)

        let collisions = try CloudSyncFirstActivationAnalyzer.findCollisions(database: database, tagRecords: [], folderRecords: [cloudRecord])

        #expect(collisions.count == 1)
        #expect(collisions.first?.recordType == "FeedFolder")
    }
}
```

- [ ] **Step 2: Test ausführen, Fehlschlag bestätigen**

Run: `xcodebuild test -scheme Feedivo -only-testing:FeedivoTests/CloudSyncFirstActivationAnalyzerTests`
Expected: FAIL — Typ existiert noch nicht.

- [ ] **Step 3: `CloudSyncFirstActivationAnalyzer` implementieren**

```swift
import Foundation
import CloudKit

/// Läuft einmalig VOR dem ersten Backfill, wenn iCloud Sync neu aktiviert wird (siehe Task 14).
/// Erkennt Namensduplikate zwischen bereits in der Cloud vorhandenen `Tag`/`FeedFolder`-Records
/// und den lokal vorhandenen Zeilen — löst das dokumentierte `materializeImplicitFolders()`-
/// Duplikat-Risiko aus dem Phase-2a-Whole-Branch-Review mit. Siehe Design-Spec
/// `docs/superpowers/specs/2026-07-26-icloud-sync-phase3-design.md`, Abschnitt 6.
enum CloudSyncFirstActivationAnalyzer {
    struct FirstActivationCollision {
        let recordType: String
        let name: String
        let localID: String
        let cloudRecordID: CKRecord.ID
    }

    /// Reine Vergleichsfunktion, kein Netzwerkzugriff — nimmt bereits abgefragte Cloud-`CKRecord`s
    /// entgegen (siehe `fetchExistingCloudRecords` für den echten `CKQuery`-Aufruf). Case-
    /// insensitiver Namensvergleich, exakt wie der bestehende Duplikat-Check in
    /// `FeedFolderStore.renameFolder`.
    static func findCollisions(database: FeedivoDatabase, tagRecords: [CKRecord], folderRecords: [CKRecord]) throws -> [FirstActivationCollision] {
        var collisions: [FirstActivationCollision] = []

        let localTags = try TagStore(database: database).tags()
        for cloudRecord in tagRecords {
            guard let cloudName = cloudRecord["name"] as? String else { continue }
            if let match = localTags.first(where: { $0.name.caseInsensitiveCompare(cloudName) == .orderedSame }) {
                collisions.append(FirstActivationCollision(recordType: CloudSyncTagMapping.recordType, name: match.name, localID: match.id, cloudRecordID: cloudRecord.recordID))
            }
        }

        let localFolders = try FeedFolderStore(database: database).folders()
        for cloudRecord in folderRecords {
            guard let cloudName = cloudRecord["name"] as? String else { continue }
            if let match = localFolders.first(where: { $0.name.caseInsensitiveCompare(cloudName) == .orderedSame }) {
                collisions.append(FirstActivationCollision(recordType: CloudSyncFeedFolderMapping.recordType, name: match.name, localID: match.id, cloudRecordID: cloudRecord.recordID))
            }
        }

        return collisions
    }

    /// Echter `CKQuery`-Aufruf gegen `FeedivoZone` — fragt ALLE bestehenden `Tag`- und
    /// `FeedFolder`-Records ab. Schlägt der Aufruf fehl (z. B. kein Netz), liefert diese Methode
    /// leere Arrays statt den Fehler zu propagieren — Duplikat-Erkennung ist ein
    /// Komfort-Feature, kein Sync-Gate (siehe Design-Spec Abschnitt 8).
    static func fetchExistingCloudRecords(container: CKContainer) async -> (tags: [CKRecord], folders: [CKRecord]) {
        let database = container.privateCloudDatabase
        let zoneID = CloudSyncTagMapping.zoneID()

        async let tags = fetchAllRecords(recordType: CloudSyncTagMapping.recordType, database: database, zoneID: zoneID)
        async let folders = fetchAllRecords(recordType: CloudSyncFeedFolderMapping.recordType, database: database, zoneID: zoneID)
        return (await tags, await folders)
    }

    private static func fetchAllRecords(recordType: String, database: CKDatabase, zoneID: CKRecordZone.ID) async -> [CKRecord] {
        do {
            let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
            let (matchResults, _) = try await database.records(matching: query, inZoneWith: zoneID)
            return matchResults.compactMap { _, result in try? result.get() }
        } catch {
            AppLogger.dataAccess.error("iCloud Sync: Erst-Aktivierungs-Abfrage fuer \(recordType, privacy: .public) fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}
```

- [ ] **Step 4: Test ausführen, Erfolg bestätigen**

Run: `xcodebuild test -scheme Feedivo -only-testing:FeedivoTests/CloudSyncFirstActivationAnalyzerTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Services/CloudSync/CloudSyncFirstActivationAnalyzer.swift FeedivoTests/CloudSyncFirstActivationAnalyzerTests.swift
git commit -m "Feature: CloudSyncFirstActivationAnalyzer — Namens-Duplikat-Erkennung für Tag/FeedFolder (iCloud Sync Phase 3 Task 12)"
```

---

## Task 13: Merge-Logik „Zusammenführen"/„Beide behalten"

**Files:**
- Create: `Feedivo/Services/CloudSync/CloudSyncFirstActivationMerger.swift`
- Test: `FeedivoTests/CloudSyncFirstActivationMergerTests.swift` (neu)

**Interfaces:**
- Consumes: `CloudSyncFirstActivationAnalyzer.FirstActivationCollision` (Task 12).
- Produces: `CloudSyncFirstActivationMerger.merge(_ collision:database:) throws` (Tag: FK-Remap
  in `article_tags`/`feed_tags` + Löschen der alten lokalen Zeile; FeedFolder: reines Löschen
  der alten lokalen Zeile, da `feeds.folderName` namensbasiert ist),
  `.keepBoth(_ collision:database:) throws` (disambiguierender Namenszusatz, z. B. „Technik (2)").

- [ ] **Step 1: Fehlschlagenden Test für Tag-Merge (mit FK-Remap) schreiben**

Zuerst die exakte Signatur von `ArticleStore.upsert`/`ArticleUpsertInput` in
`Feedivo/Stores/ArticleStore.swift` nachschlagen, um den Test-Setup-Aufruf korrekt zu füllen.

```swift
import Foundation
import CloudKit
import Testing
@testable import Feedivo

struct CloudSyncFirstActivationMergerTests {
    @Test func mergeTagSchreibtArticleTagsAufDieCloudIDUm() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try TagStore(database: database).save(TagRecord(id: "local-tag-1", name: "Intune", colorHex: "#FF0000", sortIndex: 0))
        try FeedStore(database: database).save(FeedRecord(id: "feed-1", url: "https://example.com/feed", title: "Feed", sortIndex: 0))
        // Artikel direkt über SQL anlegen, um nicht von der exakten ArticleUpsertInput-Signatur
        // abzuhängen (nur article_tags-FK-Umschreiben ist Testgegenstand):
        try database.write { db in
            try db.execute(
                sql: "INSERT INTO articles (id, feedID, title, arrivedAt) VALUES (?, ?, ?, ?)",
                arguments: ["article-1", "feed-1", "Artikel", Date()]
            )
        }
        try TagStore(database: database).assignTag(tagID: "local-tag-1", toArticleID: "article-1", at: Date())

        let cloudRecordID = CKRecord.ID(recordName: "cloud-tag-1", zoneID: CloudSyncTagMapping.zoneID())
        let collision = CloudSyncFirstActivationAnalyzer.FirstActivationCollision(
            recordType: CloudSyncTagMapping.recordType, name: "Intune", localID: "local-tag-1", cloudRecordID: cloudRecordID
        )

        try CloudSyncFirstActivationMerger.merge(collision, database: database)

        let remappedCount = try database.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM article_tags WHERE tagID = ?", arguments: ["cloud-tag-1"]) ?? 0
        }
        #expect(remappedCount == 1)
        let oldTagStillReferenced = try database.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM article_tags WHERE tagID = ?", arguments: ["local-tag-1"]) ?? 0
        }
        #expect(oldTagStillReferenced == 0)
    }
}
```

Hinweis: Die minimal benötigten NOT-NULL-Spalten von `articles` gegen das tatsächliche Schema
in `FeedivoDatabaseMigrator.swift` (`v1_create_core_tables`) prüfen und das direkte `INSERT`
entsprechend ergänzen, falls weitere Pflichtfelder existieren.

- [ ] **Step 2: Test ausführen, Fehlschlag bestätigen**

Run: `xcodebuild test -scheme Feedivo -only-testing:FeedivoTests/CloudSyncFirstActivationMergerTests`
Expected: FAIL — Typ existiert noch nicht.

- [ ] **Step 3: `CloudSyncFirstActivationMerger` implementieren**

```swift
import Foundation
import CloudKit
import GRDB

/// Setzt die vom Nutzer im Erst-Aktivierungs-Dialog getroffene Entscheidung für einen erkannten
/// Namens-Duplikat um (siehe `CloudSyncFirstActivationAnalyzer`). Siehe Design-Spec Abschnitt 6.
enum CloudSyncFirstActivationMerger {
    /// „Zusammenführen": die alte lokale Zeile wird entfernt, referenzierende Fremdschlüssel
    /// werden auf die Cloud-ID umgeschrieben. Für `Tag` ist das ein echtes FK-Umschreiben
    /// (`article_tags`/`feed_tags.tagID` referenzieren über die ID, nicht über den Namen) — für
    /// `FeedFolder` genügt reines Löschen, da `feeds.folderName` ein Namens-String ist und über
    /// den identischen Namen ohnehin weiterläuft.
    static func merge(_ collision: CloudSyncFirstActivationAnalyzer.FirstActivationCollision, database: FeedivoDatabase) throws {
        try database.write { db in
            switch collision.recordType {
            case CloudSyncTagMapping.recordType:
                let cloudTagID = collision.cloudRecordID.recordName
                try remapTagReferences(db, oldTagID: collision.localID, newTagID: cloudTagID)
                try db.execute(sql: "DELETE FROM tags WHERE id = ?", arguments: [collision.localID])
            case CloudSyncFeedFolderMapping.recordType:
                try db.execute(sql: "DELETE FROM feed_folders WHERE id = ?", arguments: [collision.localID])
            default:
                break
            }
        }
    }

    /// „Beide behalten": lokale Zeile bekommt einen disambiguierenden Namenszusatz
    /// („Technik (2)"), bleibt als eigenständige Zeile bestehen und wird beim folgenden
    /// Backfill regulär als neuer Cloud-Record hochgeladen.
    static func keepBoth(_ collision: CloudSyncFirstActivationAnalyzer.FirstActivationCollision, database: FeedivoDatabase) throws {
        let newName = "\(collision.name) (2)"
        try database.write { db in
            switch collision.recordType {
            case CloudSyncTagMapping.recordType:
                try db.execute(sql: "UPDATE tags SET name = ?, updatedAt = ? WHERE id = ?", arguments: [newName, Date(), collision.localID])
            case CloudSyncFeedFolderMapping.recordType:
                try db.execute(sql: "UPDATE feed_folders SET name = ?, updatedAt = ? WHERE id = ?", arguments: [newName, Date(), collision.localID])
            default:
                break
            }
        }
    }

    /// Schreibt `article_tags`/`feed_tags`-Zeilen mit `oldTagID` auf `newTagID` um — mit
    /// Dedupe-Schutz: existiert für dieselbe `articleID`/`feedID` bereits eine Zuordnung zur
    /// `newTagID`, wird die alte Zeile nur gelöscht statt einen doppelten Zuordnungs-Datensatz
    /// zu erzeugen (siehe Design-Spec Abschnitt 6).
    private static func remapTagReferences(_ db: Database, oldTagID: String, newTagID: String) throws {
        let affectedArticleIDs = try String.fetchAll(db, sql: "SELECT articleID FROM article_tags WHERE tagID = ?", arguments: [oldTagID])
        for articleID in affectedArticleIDs {
            let alreadyHasNewTag = try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM article_tags WHERE articleID = ? AND tagID = ?)", arguments: [articleID, newTagID]) ?? false
            if alreadyHasNewTag {
                try db.execute(sql: "DELETE FROM article_tags WHERE articleID = ? AND tagID = ?", arguments: [articleID, oldTagID])
            } else {
                try db.execute(sql: "UPDATE article_tags SET tagID = ? WHERE articleID = ? AND tagID = ?", arguments: [newTagID, articleID, oldTagID])
            }
        }

        let affectedFeedIDs = try String.fetchAll(db, sql: "SELECT feedID FROM feed_tags WHERE tagID = ?", arguments: [oldTagID])
        for feedID in affectedFeedIDs {
            let alreadyHasNewTag = try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM feed_tags WHERE feedID = ? AND tagID = ?)", arguments: [feedID, newTagID]) ?? false
            if alreadyHasNewTag {
                try db.execute(sql: "DELETE FROM feed_tags WHERE feedID = ? AND tagID = ?", arguments: [feedID, oldTagID])
            } else {
                try db.execute(sql: "UPDATE feed_tags SET tagID = ? WHERE feedID = ? AND tagID = ?", arguments: [newTagID, feedID, oldTagID])
            }
        }
    }
}
```

- [ ] **Step 4: Test ausführen, Erfolg bestätigen**

Run: `xcodebuild test -scheme Feedivo -only-testing:FeedivoTests/CloudSyncFirstActivationMergerTests`
Expected: PASS

- [ ] **Step 5: Test für „Beide behalten" + FeedFolder-Merge ergänzen**

```swift
    @Test func keepBothVergibtDisambiguierendenNamenszusatz() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try TagStore(database: database).save(TagRecord(id: "local-tag-1", name: "Intune", colorHex: "#FF0000", sortIndex: 0))
        let collision = CloudSyncFirstActivationAnalyzer.FirstActivationCollision(
            recordType: CloudSyncTagMapping.recordType, name: "Intune", localID: "local-tag-1",
            cloudRecordID: CKRecord.ID(recordName: "cloud-tag-1", zoneID: CloudSyncTagMapping.zoneID())
        )

        try CloudSyncFirstActivationMerger.keepBoth(collision, database: database)

        let tag = try TagStore(database: database).tags().first { $0.id == "local-tag-1" }
        #expect(tag?.name == "Intune (2)")
    }

    @Test func mergeFeedFolderLoeschtNurDieAlteZeileOhneFKUmschreiben() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try FeedFolderStore(database: database).save(FeedFolderRecord(id: "local-folder-1", name: "Technik", sortIndex: 0, createdAt: Date(), updatedAt: Date()))
        let collision = CloudSyncFirstActivationAnalyzer.FirstActivationCollision(
            recordType: CloudSyncFeedFolderMapping.recordType, name: "Technik", localID: "local-folder-1",
            cloudRecordID: CKRecord.ID(recordName: "cloud-folder-1", zoneID: CloudSyncTagMapping.zoneID())
        )

        try CloudSyncFirstActivationMerger.merge(collision, database: database)

        let folders = try FeedFolderStore(database: database).folders()
        #expect(folders.isEmpty)
    }
```

- [ ] **Step 6: Test ausführen, Erfolg bestätigen**

Run: `xcodebuild test -scheme Feedivo -only-testing:FeedivoTests/CloudSyncFirstActivationMergerTests`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add Feedivo/Services/CloudSync/CloudSyncFirstActivationMerger.swift FeedivoTests/CloudSyncFirstActivationMergerTests.swift
git commit -m "Feature: CloudSyncFirstActivationMerger — Zusammenführen/Beide-behalten (iCloud Sync Phase 3 Task 13)"
```

---

## Task 14: `CloudSyncFirstActivationView` + Verdrahtung in den Sync-Toggle

**Files:**
- Create: `Feedivo/Views/Settings/CloudSyncFirstActivationView.swift`
- Modify: `Feedivo/Views/Settings/SettingsView.swift` (Sync-Toggle-Handler)
- Modify: `Feedivo/Resources/L10n.swift` + `Feedivo/Resources/Localizable.xcstrings` (neue Keys)

**Interfaces:**
- Consumes: `CloudSyncFirstActivationAnalyzer.fetchExistingCloudRecords`/`.findCollisions`
  (Task 12), `CloudSyncFirstActivationMerger.merge`/`.keepBoth` (Task 13).

- [ ] **Step 1: `CloudSyncFirstActivationView` anlegen**

```swift
import SwiftUI
import CloudKit

/// Einmaliger Merge-Dialog beim Umlegen des iCloud-Sync-Schalters — erscheint VOR dem
/// eigentlichen Backfill. Zeigt erkannte Namens-Duplikate (Tag/FeedFolder) zur Entscheidung,
/// oder nur eine kurze Zusammenfassung, falls keine gefunden wurden. Siehe Design-Spec
/// Abschnitt 6.
struct CloudSyncFirstActivationView: View {
    @Environment(\.feedivoDatabase) private var feedivoDatabase
    @Environment(\.dismiss) private var dismiss
    let onContinue: () -> Void

    @State private var isLoading = true
    @State private var collisions: [CloudSyncFirstActivationAnalyzer.FirstActivationCollision] = []
    @State private var decisions: [String: Bool] = [:] // Schlüssel: cloudRecordID.recordName, true = zusammenführen

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.firstActivationTitle)
                .font(.title2.bold())

            if isLoading {
                ProgressView()
            } else if collisions.isEmpty {
                Text(L10n.firstActivationNoCollisions)
            } else {
                List(collisions, id: \.cloudRecordID.recordName) { collision in
                    collisionRow(collision)
                }
            }

            HStack {
                Spacer()
                Button(L10n.firstActivationContinue) {
                    applyDecisions()
                    onContinue()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading)
            }
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 300)
        .task { await loadCollisions() }
    }

    @ViewBuilder
    private func collisionRow(_ collision: CloudSyncFirstActivationAnalyzer.FirstActivationCollision) -> some View {
        let key = collision.cloudRecordID.recordName
        Picker(collision.name, selection: Binding(
            get: { decisions[key] ?? true },
            set: { decisions[key] = $0 }
        )) {
            Text(L10n.firstActivationMerge).tag(true)
            Text(L10n.firstActivationKeepBoth).tag(false)
        }
        .pickerStyle(.segmented)
    }

    private func loadCollisions() async {
        let container = CKContainer(identifier: CloudSyncSettings.cloudKitContainerIdentifier)
        let (tags, folders) = await CloudSyncFirstActivationAnalyzer.fetchExistingCloudRecords(container: container)

        guard let feedivoDatabase else {
            isLoading = false
            return
        }
        do {
            collisions = try CloudSyncFirstActivationAnalyzer.findCollisions(database: feedivoDatabase, tagRecords: tags, folderRecords: folders)
        } catch {
            AppLogger.dataAccess.error("iCloud Sync: Erst-Aktivierungs-Duplikat-Erkennung fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            collisions = []
        }
        isLoading = false
    }

    private func applyDecisions() {
        guard let feedivoDatabase else { return }
        for collision in collisions {
            let shouldMerge = decisions[collision.cloudRecordID.recordName] ?? true
            do {
                if shouldMerge {
                    try CloudSyncFirstActivationMerger.merge(collision, database: feedivoDatabase)
                } else {
                    try CloudSyncFirstActivationMerger.keepBoth(collision, database: feedivoDatabase)
                }
            } catch {
                AppLogger.dataAccess.error("iCloud Sync: Erst-Aktivierungs-Entscheidung konnte nicht angewendet werden: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
```

Neue `L10n`-Keys (`firstActivationTitle`, `firstActivationNoCollisions`,
`firstActivationContinue`, `firstActivationMerge`, `firstActivationKeepBoth`) nach
etabliertem Muster in `L10n.swift` + `Localizable.xcstrings` ergänzen, per `grep -c`
verifizieren.

- [ ] **Step 2: In den bestehenden Sync-Toggle-Handler verdrahten**

`SyncSettingsView` (in `SettingsView.swift`, private struct) hat den Schalter bereits über
`@AppStorage(CloudSyncSettings.isEnabledKey) private var cloudSyncIsEnabled = CloudSyncSettings.defaultIsEnabled`
direkt an ein `Toggle("", isOn: $cloudSyncIsEnabled)` gebunden (Zeile ~1052-1114); der
eigentliche Start/Stop läuft über einen bestehenden `.onChange(of: cloudSyncIsEnabled)`
(Zeile ~1193-1199):

```swift
        .onChange(of: cloudSyncIsEnabled) {
            if cloudSyncIsEnabled {
                cloudSyncEngine?.start()
            } else {
                cloudSyncEngine?.stop()
            }
        }
```

(`cloudSyncEngine` ist `@Environment(\.cloudSyncEngine)`, optional — bereits bestehend, siehe
Zeile 1049.) Diesen Block so ändern, dass beim Einschalten ZUERST das neue Sheet gezeigt wird
und `start()` erst in dessen `onContinue`-Callback läuft — beim Ausschalten bleibt das
Verhalten unverändert:

```swift
        .onChange(of: cloudSyncIsEnabled) {
            if cloudSyncIsEnabled {
                showingFirstActivationSheet = true
            } else {
                cloudSyncEngine?.stop()
            }
        }
        .sheet(isPresented: $showingFirstActivationSheet) {
            CloudSyncFirstActivationView(onContinue: { cloudSyncEngine?.start() })
        }
```

Dazu eine neue `@State private var showingFirstActivationSheet = false`-Property direkt bei
den übrigen `@State`-Deklarationen dieser View (Zeile ~1070-1075) ergänzen.

- [ ] **Step 3: Build verifizieren**

Run: `xcodebuild build -scheme Feedivo`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Manuelle Live-Verifikationscheckliste dokumentieren (nicht automatisierbar ohne Zweitgerät)**

In diesem Schritt keinen Code ändern — nur sicherstellen, dass Task 15 (Regressionslauf) die
folgende Checkliste als offenen Punkt in CLAUDE.md vermerkt: Sync-Schalter aus- und wieder
einschalten löst den Dialog zuverlässig aus; bei leerer Cloud-Zone erscheint nur die
Zusammenfassung ohne Duplikat-Zeilen; ein künstlich per zweitem CloudKit-Dashboard-Eintrag
angelegter gleichnamiger Tag wird als Kollision erkannt und nach „Zusammenführen" korrekt
verschmolzen (kein doppelter Tag in der Sidebar).

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Views/Settings/CloudSyncFirstActivationView.swift Feedivo/Views/Settings/SettingsView.swift \
        Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings
git commit -m "Feature: CloudSyncFirstActivationView im Sync-Toggle verdrahtet (iCloud Sync Phase 3 Task 14)"
```

---

## Task 15: Vollständiger Regressionslauf + Release-Build

**Files:** Keine Code-Änderungen — reine Verifikation.

- [ ] **Step 1: Gezielten Testlauf über alle in diesem Plan berührten/neuen Suiten ausführen**

Run:
```bash
xcodebuild test -scheme Feedivo -parallel-testing-enabled NO \
  -only-testing:FeedivoTests/RuleSettingsFormatterConditionIdentityTests \
  -only-testing:FeedivoTests/SmartFolderFormatterConditionIdentityTests \
  -only-testing:FeedivoTests/RuleConditionIdentityRoundtripTests \
  -only-testing:FeedivoTests/SmartFolderConditionIdentityRoundtripTests \
  -only-testing:FeedivoTests/CloudSyncPendingChangeStoreTests \
  -only-testing:FeedivoTests/CloudSyncRecordMappingPolicyTests \
  -only-testing:FeedivoTests/PendingSyncConflictStoreTests \
  -only-testing:FeedivoTests/CloudSyncEngineFieldConflictTests \
  -only-testing:FeedivoTests/TagStoreChangedFieldsTests \
  -only-testing:FeedivoTests/FeedFolderStoreChangedFieldsTests \
  -only-testing:FeedivoTests/FeedStoreChangedFieldsTests \
  -only-testing:FeedivoTests/SQLiteRuleStoreChangedFieldsTests \
  -only-testing:FeedivoTests/SQLiteSmartFolderStoreChangedFieldsTests \
  -only-testing:FeedivoTests/CloudSyncFirstActivationAnalyzerTests \
  -only-testing:FeedivoTests/CloudSyncFirstActivationMergerTests \
  -only-testing:FeedivoTests/SQLiteRuleStoreTests \
  -only-testing:FeedivoTests/SQLiteSmartFolderStoreTests \
  -only-testing:FeedivoTests/SQLiteTagStoreTests \
  -only-testing:FeedivoTests/FeedFolderStoreTests \
  -only-testing:FeedivoTests/SQLiteFeedStoreTests \
  -only-testing:FeedivoTests/CloudSyncEngineRegistryTests \
  -only-testing:FeedivoTests/CloudSyncTagMappingTests \
  -only-testing:FeedivoTests/CloudSyncFeedMappingTests \
  -only-testing:FeedivoTests/FeedivoDatabaseMigratorTests
```

Expected: alle PASS (mit `-parallel-testing-enabled NO` wegen des bekannten Parallel-Testing-
SIGSEGV-Gotchas), bis auf die bereits bekannten, vorbestehenden Fehlschläge in
`FeedivoAppSceneConfigurationTests.swift` (aktuell 17, siehe CLAUDE.md) und die 2-3 bekannten
flaky-unter-Last-Tests — beide NICHT Teil dieses Testlaufs, da hier gezielt nur die
berührten/neuen Suiten laufen.

- [ ] **Step 2: Vollen Release-Build ausführen**

Run: `xcodebuild build -scheme Feedivo -configuration Release`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: `git diff --stat` gegen den Stand vor Task 1 gegenprüfen**

Run: `git diff --stat <Basis-Commit-vor-Task-1> -- Feedivo/ FeedivoTests/`
Expected: Nur die in diesem Plan beschriebenen Dateien geändert/neu — keine unerwarteten
Nebenänderungen (insbesondere `Localizable.xcstrings` nur mit den neuen Keys aus Task 11/14,
kein vollständiges Reformat — siehe Gotcha zu `json.dump`-Vollreformatierung in CLAUDE.md,
gilt analog für jedes Skript-basierte Bearbeiten dieser Datei).

- [ ] **Step 4: CLAUDE.md aktualisieren**

„Aktuell in Arbeit" um einen neuen Eintrag ergänzen: iCloud Sync Phase 3 (Feld-Ebene-
Konfliktauflösung + Erst-Aktivierungs-Merge-Dialog + Bedingungs-ID-Stabilitäts-Fix)
implementiert, automatisierte Tests grün, Release-Build grün. Ausstehend: manuelle
Live-Verifikation (siehe Task 14 Step 4 — braucht ein zweites CloudKit-Dashboard-seitig
manipuliertes Duplikat bzw. ein echtes Zweitgerät für einen echten laufenden Konflikt).
M3-Checkbox „iCloud Sync via CloudKit" bleibt weiterhin offen (Phase 4 — Härtung — steht noch
aus), aber die Beschreibung entsprechend aktualisieren.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md
git commit -m "Docs: iCloud Sync Phase 3 (Feld-Ebene-Konfliktauflösung + Erst-Aktivierungs-Merge-Dialog) in CLAUDE.md dokumentiert"
```
