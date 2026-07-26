# Freie Gruppierung von Regel-Bedingungen (UND/ODER) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Im Power-User-Modus des Regel-Assistenten (`RuleWizardView.swift`) lassen sich
Bedingungen frei in Gruppen einteilen — jede Gruppe intern UND-verknüpft, die Gruppen
untereinander ODER-verknüpft (z. B. `(A UND B) ODER (C UND D) ODER E`), dargestellt als
explizite, umrandete Gruppen-Boxen. Der bisherige globale „Treffer bei: Alle Bedingungen /
Eine reicht"-Umschalter entfällt für Regeln vollständig.

**Architecture:** Jede `rule_conditions`-Zeile bekommt ein neues `groupIndex: Int`-Feld
(Migration v20 mit Backfill aus dem bisherigen `rules.matchMode`). Die Auswertung in
`RuleEngine.swift` gruppiert Bedingungen nach `groupIndex` (UND innerhalb einer Gruppe,
ODER zwischen den Gruppen-Werten) statt einen globalen `matchMode`-Parameter zu befragen.
Die Wizard-UI rendert Bedingungen gruppiert in Boxen; die Gruppierungs-/Entfernungslogik
ist als reine, view-freie Funktionen (`RuleConditionGroupLayout`) ausgelagert und isoliert
getestet — dasselbe etablierte Muster wie `SidebarFeedOrder.swift`/
`ReaderArrowKeyNavigation.swift` in diesem Projekt.

**Tech Stack:** Swift, SwiftUI, GRDB/SQLite, Swift Testing (`@Test`/`#expect`, kein XCTest).

## Global Constraints

- Eine Verschachtelungsebene reicht — keine Gruppen in Gruppen.
- Bedienkonzept: explizite, umrandete Gruppen-Boxen (Variante B aus dem Brainstorming),
  keine impliziten Verbinder-Toggles zwischen einzelnen Bedingungen.
- Bedingungen bleiben in ihrer Gruppe — kein Verschieben zwischen Gruppen nötig (weder
  Dropdown noch Drag & Drop).
- Neues Feld heißt exakt `groupIndex: Int`, Default `0`, auf `RuleConditionRecord` und
  `RuleConditionDraft`.
- Neue Migration heißt exakt `v20_add_rule_condition_group_index` — letzte tatsächlich
  bestehende Migration zum Planungszeitpunkt ist `v19_drop_article_offline_table`
  (per `grep -n registerMigration FeedivoDatabaseMigrator.swift` am 2026-07-24 verifiziert).
- Backfill-Regel: `matchMode == "all"` → alle Bedingungen der Regel bekommen `groupIndex = 0`
  (eine Gruppe). `matchMode == "any"` → jede Bedingung bekommt einen eigenen, fortlaufenden
  `groupIndex` (0, 1, 2, …) in ihrer bisherigen `sortOrder`-Reihenfolge.
- Die Spalte `rules.matchMode` bleibt in der Datenbank bestehen (wird nie rückwirkend
  gelöscht), wird aber von der Regel-Auswertungslogik ab dieser Änderung nicht mehr
  gelesen. Ein Entfernen der Spalte ist NICHT Teil dieses Plans.
- `RuleMatchMode` (der Typ) bleibt vollständig bestehen — wird weiterhin unabhängig von
  Smart Folders genutzt (`SmartFolderEditorView.swift`, `SmartFolderFormatter.swift`,
  `SQLiteSmartFolderStore.swift`, `SmartFolderRecord.swift`, verifiziert per Grep am
  2026-07-24). Nur die *Regeln*-Seite (`RuleEngine.swift`, `RuleWizardView.swift`,
  `RuleSettingsView.swift`) verliert ihre Abhängigkeit von `RuleMatchMode`.
- **Wichtiger Build-Stolperstein:** `extension RuleMatchMode: RuleSelectOption {}` steht
  aktuell in `RuleWizardView.swift:740`, wird aber auch von `SmartFolderEditorView.swift`s
  eigenem Match-Mode-Segmented-Control benötigt (`RuleSegmentedControl(options:
  RuleMatchMode.allCases...)` in `SmartFolderEditorView.swift:255-256` — Swift-Extensions
  sind modulweit sichtbar). Diese Zeile darf beim Entfernen des Wizard-Umschalters NICHT
  gelöscht, sondern muss nach `SmartFolderEditorView.swift` verschoben werden — sonst
  bricht dort der Build.
- **Zweiter Stolperstein (Source-Sniffing-Test):** `FeedivoTests/
  FeedivoAppSceneConfigurationTests.swift:680` prüft per Substring-Match auf
  whitespace-bereinigtem Quelltext exakt den alten Aufruf
  `SQLiteRuleEvaluationStore(database:database).matchingArticleCount(conditionDrafts:
  activeConditionDrafts,matchMode:activeMatchMode)`. Muss zusammen mit der
  Signaturänderung angepasst werden, sonst schlägt dieser Test neu fehl (wäre eine
  echte Regression, kein vorbestehender Fehlschlag).
- Bekannte, vorbestehende 17 Testfehlschläge in `FeedivoAppSceneConfigurationTests.swift`
  sind kein neuer Bug — nicht versuchen zu fixen, aber auch keine neuen hinzufügen.
- Volle Testsuite (`xcodebuild test` ohne `-only-testing:`) hängt bekanntermaßen — IMMER
  gezielt mit `-only-testing:FeedivoTests/<SuiteName>` testen.
- Kein Git-Worktree — direkt auf `main` arbeiten (etablierte Nutzerpräferenz). Niemals
  ohne explizite Nutzerbestätigung nach `origin/main` pushen.
- `Localizable.xcstrings`-Ergänzungen NIEMALS per vollem `json.load`/`json.dump`-Roundtrip
  — nur per chirurgischer Text-Segment-Einfügung an einem stabilen Anker (Edit-Tool),
  danach `git diff --stat` prüfen (nur Insertions, keine/kaum Deletions).
- Deutsche Kommentare im Code, wo eine Erklärung nötig ist (nicht WAS, sondern WARUM).

---

## Datei-Übersicht

| Datei | Änderung |
|---|---|
| `Feedivo/Database/Records/RuleConditionRecord.swift` | Neues Feld `groupIndex: Int = 0` |
| `Feedivo/Models/RuleConditionDraft.swift` | Neues Feld `groupIndex: Int = 0` |
| `Feedivo/Database/FeedivoDatabaseMigrator.swift` | Neue Migration `v20_add_rule_condition_group_index` + Backfill-Helfer |
| `Feedivo/Models/RuleConditionGroupLayout.swift` | NEU — reine Gruppierungs-/Entfernungslogik |
| `Feedivo/Services/RuleEngine.swift` | Gruppenbasierte Auswertung statt globalem `matchMode` |
| `Feedivo/Stores/SQLiteRuleEvaluationStore.swift` | `matchingArticleCount` verliert `matchMode`-Parameter |
| `Feedivo/Stores/SQLiteRuleStore.swift` | `duplicate()`/`ruleSnapshots()` propagieren `groupIndex` |
| `Feedivo/Views/Rules/RuleSettingsView.swift` | `RuleSettingsFormatter.conditionSummary`/`conditionDrafts(for:)` gruppenbewusst, Aufrufstelle `matchingArticleCount` angepasst |
| `Feedivo/Views/Rules/RuleWizardView.swift` | Globaler Match-Mode-Umschalter entfernt, neue Gruppen-Box-UI |
| `Feedivo/Views/SmartFolders/SmartFolderEditorView.swift` | Empfängt die verschobene `extension RuleMatchMode: RuleSelectOption {}` |
| `Feedivo/Resources/L10n.swift` | Neue Keys `ruleWizardAddGroup`/`ruleWizardRemoveGroup`, `ruleWizardMatchModeLabel` entfernt |
| `Feedivo/Resources/Localizable.xcstrings` | Neue Katalogeinträge für die beiden neuen Keys |
| `FeedivoTests/SQLiteDatabaseMigrationTests.swift` | Neue Migrationstests für v20 |
| `FeedivoTests/RuleConditionGroupLayoutTests.swift` | NEU — Tests für die reine Gruppierungslogik |
| `FeedivoTests/RuleEngineTests.swift` | Bestehender Test angepasst, neue Gruppierungstests |
| `FeedivoTests/SQLiteRuleEvaluationStoreTests.swift` | Bestehende Tests angepasst |
| `FeedivoTests/SQLiteAdminStoreTests.swift` | Eine veraltete Assertion entfernt |
| `FeedivoTests/RuleSettingsFormatterTests.swift` | NEU — Tests für `conditionSummary` |
| `FeedivoTests/FeedivoAppSceneConfigurationTests.swift` | Eine Source-Sniffing-Assertion angepasst |

---

### Task 1: Datenmodell & Migration (`groupIndex`)

**Files:**
- Modify: `Feedivo/Database/Records/RuleConditionRecord.swift`
- Modify: `Feedivo/Models/RuleConditionDraft.swift`
- Modify: `Feedivo/Database/FeedivoDatabaseMigrator.swift:418-424` (neue Migration nach v19 einfügen)
- Test: `FeedivoTests/SQLiteDatabaseMigrationTests.swift`

**Interfaces:**
- Produces: `RuleConditionRecord.groupIndex: Int` (Default `0`), `RuleConditionDraft.groupIndex: Int` (Default `0`), Migration `"v20_add_rule_condition_group_index"` fügt Spalte `rule_conditions.groupIndex INTEGER NOT NULL DEFAULT 0` hinzu und befüllt sie per Backfill.

- [ ] **Step 1: Fehlschlagenden Migrationstest schreiben**

In `FeedivoTests/SQLiteDatabaseMigrationTests.swift` am Ende der Datei (vor der letzten
schließenden Klammer der Test-Struct) einfügen:

```swift
    @Test func migrationV20FuegtGroupIndexSpalteHinzu() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        let columns = try database.read { db in
            try Row.fetchAll(db, sql: "PRAGMA table_info(rule_conditions)")
        }
        let column = columns.first { ($0["name"] as String?) == "groupIndex" }

        #expect(column != nil)
        #expect((column?["notnull"] as Int?) == 1)
        #expect((column?["dflt_value"] as String?) == "0")
    }

    @Test func migrationV20BackfilltGroupIndexFuerAllMatchModeAlsEineGruppe() throws {
        let queue = try DatabaseQueue()
        try FeedivoDatabaseMigrator.migrator.migrate(queue, upTo: "v19_drop_article_offline_table")

        try queue.write { db in
            let now = Date()
            try db.execute(
                sql: """
                    INSERT INTO rules (id, name, isEnabled, matchMode, action, notificationTemplate, notificationPriority, sortOrder, createdAt, updatedAt)
                    VALUES ('rule-all', 'Alle-Regel', 1, 'all', 'assignTag', '{Titel}', 'normal', 0, ?, ?)
                    """,
                arguments: [now, now]
            )
            try db.execute(
                sql: """
                    INSERT INTO rule_conditions (id, ruleID, field, conditionOperator, value, sortOrder)
                    VALUES
                        ('cond-1', 'rule-all', 'title', 'contains', 'Swift', 0),
                        ('cond-2', 'rule-all', 'summary', 'contains', 'macOS', 1),
                        ('cond-3', 'rule-all', 'author', 'contains', 'Apple', 2)
                    """
            )
        }

        try FeedivoDatabaseMigrator.migrator.migrate(queue)

        let groupIndexByID = try queue.read { db in
            try Row.fetchAll(db, sql: "SELECT id, groupIndex FROM rule_conditions ORDER BY sortOrder")
        }.reduce(into: [String: Int]()) { result, row in
            result[row["id"]] = row["groupIndex"]
        }

        #expect(groupIndexByID["cond-1"] == 0)
        #expect(groupIndexByID["cond-2"] == 0)
        #expect(groupIndexByID["cond-3"] == 0)
    }

    @Test func migrationV20BackfilltGroupIndexFuerAnyMatchModeAlsEinzelgruppenInSortOrderReihenfolge() throws {
        let queue = try DatabaseQueue()
        try FeedivoDatabaseMigrator.migrator.migrate(queue, upTo: "v19_drop_article_offline_table")

        try queue.write { db in
            let now = Date()
            try db.execute(
                sql: """
                    INSERT INTO rules (id, name, isEnabled, matchMode, action, notificationTemplate, notificationPriority, sortOrder, createdAt, updatedAt)
                    VALUES ('rule-any', 'Any-Regel', 1, 'any', 'assignTag', '{Titel}', 'normal', 0, ?, ?)
                    """,
                arguments: [now, now]
            )
            // Bewusst NICHT in sortOrder-Reihenfolge eingefügt, um zu verifizieren,
            // dass der Backfill wirklich nach sortOrder sortiert, nicht nach
            // Einfüge-/ID-Reihenfolge.
            try db.execute(
                sql: """
                    INSERT INTO rule_conditions (id, ruleID, field, conditionOperator, value, sortOrder)
                    VALUES
                        ('cond-c', 'rule-any', 'author', 'contains', 'Apple', 2),
                        ('cond-a', 'rule-any', 'title', 'contains', 'Swift', 0),
                        ('cond-b', 'rule-any', 'summary', 'contains', 'macOS', 1)
                    """
            )
        }

        try FeedivoDatabaseMigrator.migrator.migrate(queue)

        let groupIndexByID = try queue.read { db in
            try Row.fetchAll(db, sql: "SELECT id, groupIndex FROM rule_conditions")
        }.reduce(into: [String: Int]()) { result, row in
            result[row["id"]] = row["groupIndex"]
        }

        #expect(groupIndexByID["cond-a"] == 0)
        #expect(groupIndexByID["cond-b"] == 1)
        #expect(groupIndexByID["cond-c"] == 2)
    }

    @Test func migrationV20IstIdempotentBeiBereitsVorhandenerSpalte() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        let columns = try database.read { db in
            try Row.fetchAll(db, sql: "PRAGMA table_info(rule_conditions)")
        }
        let groupIndexColumns = columns.filter { ($0["name"] as String?) == "groupIndex" }

        #expect(groupIndexColumns.count == 1)
    }
```

- [ ] **Step 2: Test ausführen, Fehlschlag verifizieren**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteDatabaseMigrationTests`
Expected: FAIL — `rule_conditions` hat noch keine `groupIndex`-Spalte, Migration
`"v20_add_rule_condition_group_index"` existiert nicht.

- [ ] **Step 3: `RuleConditionRecord.groupIndex` ergänzen**

In `Feedivo/Database/Records/RuleConditionRecord.swift` das Feld und den Init-Parameter
hinzufügen:

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

    init(
        id: String = UUID().uuidString,
        ruleID: String,
        field: String,
        conditionOperator: String,
        value: String,
        sortOrder: Int = 0,
        groupIndex: Int = 0
    ) {
        self.id = id
        self.ruleID = ruleID
        self.field = field
        self.conditionOperator = conditionOperator
        self.value = value
        self.sortOrder = sortOrder
        self.groupIndex = groupIndex
    }
}
```

- [ ] **Step 4: `RuleConditionDraft.groupIndex` ergänzen**

`Feedivo/Models/RuleConditionDraft.swift` komplett ersetzen durch:

```swift
import Foundation

struct RuleConditionDraft: Identifiable, Equatable {
    var id = UUID()
    var field: RuleConditionField
    var conditionOperator: RuleConditionOperator
    var value: String
    var groupIndex: Int = 0
}
```

- [ ] **Step 5: Migration `v20_add_rule_condition_group_index` registrieren**

In `Feedivo/Database/FeedivoDatabaseMigrator.swift` nach dem Block
`migrator.registerMigration("v19_drop_article_offline_table") { ... }` (Zeilen 418-421)
einfügen:

```swift
        migrator.registerMigration("v20_add_rule_condition_group_index") { database in
            try database.alter(table: "rule_conditions") { table in
                table.add(column: "groupIndex", .integer).notNull().defaults(to: 0)
            }

            try backfillRuleConditionGroupIndex(database)
        }
```

Und am Ende der Datei (nach `backfillSmartFolderDefaultShowsReadArticles`, vor der
letzten schließenden Klammer) den Backfill-Helfer ergänzen:

```swift
    /// Befüllt groupIndex für Bestandsregeln anhand des bisherigen rules.matchMode:
    /// "all" -> eine gemeinsame Gruppe (groupIndex 0 für alle Bedingungen, entspricht
    /// dem Spaltendefault, kein UPDATE nötig). "any" -> jede Bedingung bekommt eine
    /// eigene Gruppe (fortlaufender groupIndex in sortOrder-Reihenfolge), damit jede
    /// für sich allein weiterhin ausreicht wie beim bisherigen ODER-Verhalten.
    private static func backfillRuleConditionGroupIndex(_ database: Database) throws {
        let anyModeRuleIDs = try String.fetchAll(
            database,
            sql: "SELECT id FROM rules WHERE matchMode = ?",
            arguments: [RuleMatchMode.any.rawValue]
        )

        for ruleID in anyModeRuleIDs {
            let conditionIDs = try String.fetchAll(
                database,
                sql: "SELECT id FROM rule_conditions WHERE ruleID = ? ORDER BY sortOrder, id COLLATE NOCASE",
                arguments: [ruleID]
            )

            for (index, conditionID) in conditionIDs.enumerated() {
                try database.execute(
                    sql: "UPDATE rule_conditions SET groupIndex = ? WHERE id = ?",
                    arguments: [index, conditionID]
                )
            }
        }
    }
```

- [ ] **Step 6: Tests ausführen, Erfolg verifizieren**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteDatabaseMigrationTests`
Expected: PASS — alle 4 neuen Tests grün, keine bestehenden Migrationstests brechen.

- [ ] **Step 7: Vollen Build verifizieren**

Run: `xcodebuild build -scheme Feedivo -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED (`RuleConditionRecord`/`RuleConditionDraft` haben beide einen
Default für `groupIndex`, daher brechen keine bestehenden Aufrufstellen).

- [ ] **Step 8: Commit**

```bash
git add Feedivo/Database/Records/RuleConditionRecord.swift Feedivo/Models/RuleConditionDraft.swift Feedivo/Database/FeedivoDatabaseMigrator.swift FeedivoTests/SQLiteDatabaseMigrationTests.swift
git commit -m "Feature: groupIndex-Feld fuer Regel-Bedingungen + Migration v20 mit Backfill"
```

---

### Task 2: Reine Gruppierungslogik (`RuleConditionGroupLayout`)

**Files:**
- Create: `Feedivo/Models/RuleConditionGroupLayout.swift`
- Test: `FeedivoTests/RuleConditionGroupLayoutTests.swift`

**Interfaces:**
- Consumes: `RuleConditionDraft` (aus Task 1, hat `id: UUID`, `groupIndex: Int`).
- Produces: `RuleConditionGroupLayout.groupedDraftIDs(_ drafts: [RuleConditionDraft]) -> [[UUID]]`,
  `RuleConditionGroupLayout.nextGroupIndex(in drafts: [RuleConditionDraft]) -> Int`,
  `RuleConditionGroupLayout.removingCondition(id: UUID, from drafts: [RuleConditionDraft]) -> [RuleConditionDraft]`,
  `RuleConditionGroupLayout.removingGroup(_ groupIndex: Int, from drafts: [RuleConditionDraft]) -> [RuleConditionDraft]`.
  Wird von Task 6 (RuleWizardView-UI) konsumiert.

- [ ] **Step 1: Fehlschlagende Tests schreiben**

Neue Datei `FeedivoTests/RuleConditionGroupLayoutTests.swift`:

```swift
import Foundation
import Testing
@testable import Feedivo

struct RuleConditionGroupLayoutTests {
    @Test func groupedDraftIDsGruppiertNachGroupIndexInReihenfolgeDesErstenAuftretens() {
        let draftA = RuleConditionDraft(field: .title, conditionOperator: .contains, value: "A", groupIndex: 1)
        let draftB = RuleConditionDraft(field: .title, conditionOperator: .contains, value: "B", groupIndex: 0)
        let draftC = RuleConditionDraft(field: .title, conditionOperator: .contains, value: "C", groupIndex: 1)

        let groups = RuleConditionGroupLayout.groupedDraftIDs([draftA, draftB, draftC])

        // Gruppe 1 (draftA) taucht zuerst im Array auf, daher zuerst in der
        // Ausgabe -- unabhaengig vom numerischen Wert des groupIndex.
        #expect(groups == [[draftA.id, draftC.id], [draftB.id]])
    }

    @Test func groupedDraftIDsLiefertLeeresArrayFuerLeereEingabe() {
        #expect(RuleConditionGroupLayout.groupedDraftIDs([]).isEmpty)
    }

    @Test func nextGroupIndexLiefertMaxPlusEins() {
        let drafts = [
            RuleConditionDraft(field: .title, conditionOperator: .contains, value: "A", groupIndex: 0),
            RuleConditionDraft(field: .title, conditionOperator: .contains, value: "B", groupIndex: 3)
        ]

        #expect(RuleConditionGroupLayout.nextGroupIndex(in: drafts) == 4)
    }

    @Test func nextGroupIndexLiefertNullBeiLeererListe() {
        #expect(RuleConditionGroupLayout.nextGroupIndex(in: []) == 0)
    }

    @Test func removingConditionEntferntNurDieBedingungMitDieserID() {
        let draftA = RuleConditionDraft(field: .title, conditionOperator: .contains, value: "A", groupIndex: 0)
        let draftB = RuleConditionDraft(field: .title, conditionOperator: .contains, value: "B", groupIndex: 0)

        let result = RuleConditionGroupLayout.removingCondition(id: draftA.id, from: [draftA, draftB])

        #expect(result.map(\.id) == [draftB.id])
    }

    @Test func removingConditionEntferntAutomatischDieGruppeWennLetzteBedingungEntfernt() {
        let draftA = RuleConditionDraft(field: .title, conditionOperator: .contains, value: "A", groupIndex: 0)
        let draftB = RuleConditionDraft(field: .title, conditionOperator: .contains, value: "B", groupIndex: 1)

        let result = RuleConditionGroupLayout.removingCondition(id: draftA.id, from: [draftA, draftB])
        let groups = RuleConditionGroupLayout.groupedDraftIDs(result)

        // Gruppe 0 hatte nur draftA -- nach dem Entfernen bleibt genau eine
        // Gruppe (Gruppe 1) uebrig, keine leere Box.
        #expect(groups == [[draftB.id]])
    }

    @Test func removingGroupEntferntAlleBedingungenDieserGruppe() {
        let draftA = RuleConditionDraft(field: .title, conditionOperator: .contains, value: "A", groupIndex: 0)
        let draftB = RuleConditionDraft(field: .title, conditionOperator: .contains, value: "B", groupIndex: 0)
        let draftC = RuleConditionDraft(field: .title, conditionOperator: .contains, value: "C", groupIndex: 1)

        let result = RuleConditionGroupLayout.removingGroup(0, from: [draftA, draftB, draftC])

        #expect(result.map(\.id) == [draftC.id])
    }
}
```

- [ ] **Step 2: Test ausführen, Fehlschlag verifizieren**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/RuleConditionGroupLayoutTests`
Expected: FAIL — `RuleConditionGroupLayout` existiert noch nicht (Compile-Fehler).

- [ ] **Step 3: `RuleConditionGroupLayout` implementieren**

Neue Datei `Feedivo/Models/RuleConditionGroupLayout.swift`:

```swift
import Foundation

/// Rein logische Gruppierungs-Operationen auf einer flachen Liste von
/// RuleConditionDraft fuer den Power-User-Modus des Regel-Assistenten
/// (RuleWizardView). Bewusst als reine, view-freie Funktionen ausgelagert
/// (Muster wie SidebarFeedOrder.swift/ReaderArrowKeyNavigation.swift in
/// diesem Projekt) -- testbar ohne SwiftUI-Rendering.
enum RuleConditionGroupLayout {
    /// Gruppiert Bedingungen nach groupIndex. Die aeussere Reihenfolge der
    /// Gruppen richtet sich nach dem ersten Auftreten eines groupIndex im
    /// Ursprungsarray (nicht nach dem numerischen Wert), damit eine neu per
    /// "+ ODER-Gruppe hinzufuegen" angehaengte Gruppe stets am Ende
    /// erscheint. Jede innere Liste behaelt die relative Reihenfolge ihrer
    /// Bedingungen im Ursprungsarray.
    static func groupedDraftIDs(_ drafts: [RuleConditionDraft]) -> [[UUID]] {
        var groupOrder: [Int] = []
        var idsByGroup: [Int: [UUID]] = [:]

        for draft in drafts {
            if idsByGroup[draft.groupIndex] == nil {
                idsByGroup[draft.groupIndex] = []
                groupOrder.append(draft.groupIndex)
            }
            idsByGroup[draft.groupIndex, default: []].append(draft.id)
        }

        return groupOrder.map { idsByGroup[$0] ?? [] }
    }

    /// Naechster, garantiert unbenutzter groupIndex fuer eine neue Gruppe.
    static func nextGroupIndex(in drafts: [RuleConditionDraft]) -> Int {
        (drafts.map(\.groupIndex).max() ?? -1) + 1
    }

    /// Entfernt eine einzelne Bedingung. War sie die letzte ihrer Gruppe,
    /// verschwindet die Gruppe dadurch automatisch aus groupedDraftIDs --
    /// kein Zustand mit einer leeren Box moeglich.
    static func removingCondition(id: UUID, from drafts: [RuleConditionDraft]) -> [RuleConditionDraft] {
        drafts.filter { $0.id != id }
    }

    /// Entfernt eine komplette Gruppe samt aller ihrer Bedingungen.
    static func removingGroup(_ groupIndex: Int, from drafts: [RuleConditionDraft]) -> [RuleConditionDraft] {
        drafts.filter { $0.groupIndex != groupIndex }
    }
}
```

- [ ] **Step 4: Tests ausführen, Erfolg verifizieren**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/RuleConditionGroupLayoutTests`
Expected: PASS — alle 7 Tests grün.

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Models/RuleConditionGroupLayout.swift FeedivoTests/RuleConditionGroupLayoutTests.swift
git commit -m "Feature: reine Gruppierungslogik RuleConditionGroupLayout fuer Regel-Bedingungsgruppen"
```

---

### Task 3: Gruppenbasierte Auswertung in `RuleEngine.swift`

**Files:**
- Modify: `Feedivo/Services/RuleEngine.swift`
- Modify: `Feedivo/Stores/SQLiteRuleEvaluationStore.swift`
- Modify: `Feedivo/Stores/SQLiteRuleStore.swift:67-108` (`duplicate`), `:148-193` (`ruleSnapshots`)
- Test: `FeedivoTests/RuleEngineTests.swift`
- Test: `FeedivoTests/SQLiteRuleEvaluationStoreTests.swift`
- Test: `FeedivoTests/SQLiteAdminStoreTests.swift`

**Interfaces:**
- Consumes: `RuleConditionRecord.groupIndex`, `RuleConditionDraft.groupIndex` (aus Task 1).
- Produces: `RuleEngine.matchingArticleCount(conditionDrafts: [RuleConditionDraft], articles: [ArticleRuleSnapshot]) -> Int`
  (kein `matchMode`-Parameter mehr), `SQLiteRuleEvaluationStore.matchingArticleCount(conditionDrafts: [RuleConditionDraft]) throws -> Int`
  (kein `matchMode`-Parameter mehr). Wird von Task 4 (`RuleSettingsView.swift`) und
  Task 6 (`RuleWizardView.swift`) konsumiert.

- [ ] **Step 1: Fehlschlagende Tests schreiben**

`FeedivoTests/RuleEngineTests.swift` komplett ersetzen durch:

```swift
import Foundation
import Testing
@testable import Feedivo

struct RuleEngineTests {
    @Test func matchingCountsLiefertTrefferProRegelInEinerMap() throws {
        let articles = [
            RuleEngine.ArticleRuleSnapshot(
                id: UUID().uuidString,
                title: "Swift auf dem Mac",
                summary: nil,
                feedTitle: "Mac News"
            ),
            RuleEngine.ArticleRuleSnapshot(
                id: UUID().uuidString,
                title: "Windows News",
                summary: nil,
                feedTitle: "Mac News"
            ),
            RuleEngine.ArticleRuleSnapshot(
                id: UUID().uuidString,
                title: "Swift 7 ist da",
                summary: nil,
                feedTitle: "Mac News"
            )
        ]

        let rules: [(String, RuleConditionDraft)] = [
            (
                "Swift",
                RuleConditionDraft(field: .title, conditionOperator: .contains, value: "Swift")
            ),
            (
                "Windows",
                RuleConditionDraft(field: .title, conditionOperator: .contains, value: "Windows")
            )
        ]

        var counts: [String: Int] = [:]
        for (name, draft) in rules {
            counts[name] = RuleEngine.matchingArticleCount(
                conditionDrafts: [draft],
                articles: articles
            )
        }

        let swiftRuleCount = counts["Swift"]
        let windowsRuleCount = counts["Windows"]
        #expect(swiftRuleCount == 2)
        #expect(windowsRuleCount == 1)
        #expect(counts.count == 2)
    }

    @Test func matchingArticleCountBeiEinerGruppeVerhaeltSichWieBisherigesUnd() {
        let article = RuleEngine.ArticleRuleSnapshot(
            id: "article-1",
            title: "Swift auf dem Mac",
            summary: nil,
            feedTitle: "Mac News"
        )
        // Beide Bedingungen in derselben Gruppe (groupIndex 0, Default) --
        // beide muessen zutreffen.
        let drafts = [
            RuleConditionDraft(field: .title, conditionOperator: .contains, value: "Swift"),
            RuleConditionDraft(field: .title, conditionOperator: .contains, value: "Windows")
        ]

        #expect(RuleEngine.matchingArticleCount(conditionDrafts: drafts, articles: [article]) == 0)
    }

    @Test func matchingArticleCountBeiMehrerenGruppenReichtEineTreffendeGruppe() {
        let article = RuleEngine.ArticleRuleSnapshot(
            id: "article-1",
            title: "Swift auf dem Mac",
            summary: "Ein Artikel ueber macOS-Entwicklung",
            feedTitle: "Mac News"
        )
        // Gruppe 0 (Titel enthaelt "Swift" UND Titel enthaelt "Windows")
        // trifft NICHT zu. Gruppe 1 (Summary enthaelt "macOS") trifft zu --
        // Gesamtergebnis muss dennoch ein Treffer sein (ODER zwischen Gruppen).
        let drafts = [
            RuleConditionDraft(field: .title, conditionOperator: .contains, value: "Swift", groupIndex: 0),
            RuleConditionDraft(field: .title, conditionOperator: .contains, value: "Windows", groupIndex: 0),
            RuleConditionDraft(field: .summary, conditionOperator: .contains, value: "macOS", groupIndex: 1)
        ]

        #expect(RuleEngine.matchingArticleCount(conditionDrafts: drafts, articles: [article]) == 1)
    }

    @Test func matchingArticleCountOhneBedingungenLiefertKeinenTreffer() {
        let article = RuleEngine.ArticleRuleSnapshot(
            id: "article-1",
            title: "Beliebiger Titel",
            summary: nil,
            feedTitle: "Beliebiger Feed"
        )

        #expect(RuleEngine.matchingArticleCount(conditionDrafts: [], articles: [article]) == 0)
    }
}
```

`FeedivoTests/SQLiteRuleEvaluationStoreTests.swift` anpassen — Aufruf ohne `matchMode`
(Zeile 17-23) und beide `conditionMatchMode`-Zeilen (47, 66) entfernen:

```swift
        let count = try ruleStore.matchingArticleCount(
            conditionDrafts: [
                RuleConditionDraft(field: .title, conditionOperator: .contains, value: "Swift"),
                RuleConditionDraft(field: .feedTitle, conditionOperator: .contains, value: "Mac")
            ]
        )
```

Und in beiden `RuleEngine.RuleSnapshot(...)`-Initialisierungen (`tagRule`, `hideRule`) die
Zeile `conditionMatchMode: RuleMatchMode.all.rawValue,` ersatzlos streichen.

In `FeedivoTests/SQLiteAdminStoreTests.swift` Zeile 120 ersatzlos streichen:

```swift
        #expect(snapshots.first?.conditionMatchMode == RuleMatchMode.any.rawValue)
```

- [ ] **Step 2: Tests ausführen, Fehlschlag verifizieren**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/RuleEngineTests`
Expected: FAIL — Compile-Fehler, da `matchingArticleCount` noch den `matchMode`-Parameter
verlangt.

- [ ] **Step 3: `RuleEngine.swift` auf gruppenbasierte Auswertung umstellen**

In `Feedivo/Services/RuleEngine.swift`:

`RuleConditionSnapshot` (Zeilen 4-9) um `groupIndex` mit Default erweitern:

```swift
    struct RuleConditionSnapshot: Equatable, Sendable {
        var field: String
        var conditionOperator: String
        var value: String
        var sortOrder: Int
        var groupIndex: Int = 0
    }
```

`RuleSnapshot` (Zeilen 11-22) verliert `conditionMatchMode`:

```swift
    struct RuleSnapshot: Equatable, Sendable {
        var id: UUID
        var name: String
        var isEnabled: Bool
        var actionRaw: String
        var notificationTemplate: String
        var notificationPriorityRaw: String
        var sortOrder: Int
        var conditions: [RuleConditionSnapshot]
        var assignTag: TagSnapshot?
    }
```

`NormalizedCondition` (Zeilen 51-56) bekommt `groupIndex`:

```swift
    private struct NormalizedCondition {
        var field: String
        var conditionOperator: String
        var lowercasedValue: String
        var regularExpression: NSRegularExpression?
        var groupIndex: Int
    }
```

`PreparedRuleSnapshot` (Zeilen 58-62) verliert `matchMode`:

```swift
    private struct PreparedRuleSnapshot {
        let rule: RuleSnapshot
        let conditions: [NormalizedCondition]
    }
```

`applySQLiteRules` — den `matches(...)`-Aufruf (Zeilen 77-83) anpassen:

```swift
        for article in articles {
            for preparedRule in preparedRules {
                guard matches(
                    conditions: preparedRule.conditions,
                    article: article
                ) else {
                    continue
                }
```

`matchingArticleCount` (Zeilen 123-138) verliert den `matchMode`-Parameter:

```swift
    static func matchingArticleCount(
        conditionDrafts: [RuleConditionDraft],
        articles: [ArticleRuleSnapshot]
    ) -> Int {
        let conditions = normalizedConditions(from: conditionDrafts)
        guard !conditions.isEmpty else {
            return 0
        }

        return articles.reduce(0) { count, article in
            matches(conditions: conditions, article: article)
                ? count + 1
                : count
        }
    }
```

`preparedSQLiteRules` (Zeilen 140-157):

```swift
    private static func preparedSQLiteRules(_ rules: [RuleSnapshot]) -> [PreparedRuleSnapshot] {
        sortedRules(rules).compactMap { rule in
            guard rule.isEnabled else {
                return nil
            }

            let conditions = normalizedConditions(for: rule)
            guard !conditions.isEmpty else {
                return nil
            }

            return PreparedRuleSnapshot(
                rule: rule,
                conditions: conditions
            )
        }
    }
```

`matches(conditions:matchMode:article:)` (Zeilen 159-174) wird zur gruppenbasierten
Auswertung — UND innerhalb einer Gruppe, ODER zwischen den Gruppen:

```swift
    private static func matches(
        conditions: [NormalizedCondition],
        article: ArticleRuleSnapshot
    ) -> Bool {
        let groups = Dictionary(grouping: conditions, by: \.groupIndex)
        guard !groups.isEmpty else {
            return false
        }

        return groups.values.contains { group in
            group.allSatisfy { condition in matches(condition: condition, article: article) }
        }
    }
```

`normalizedConditions(for rule:)` (Zeilen 186-196) reicht `groupIndex` durch:

```swift
    private static func normalizedConditions(for rule: RuleSnapshot) -> [NormalizedCondition] {
        rule.conditions
            .sorted { $0.sortOrder < $1.sortOrder }
            .compactMap { condition in
                normalizedCondition(
                    field: condition.field,
                    conditionOperator: condition.conditionOperator,
                    value: condition.value,
                    groupIndex: condition.groupIndex
                )
            }
    }
```

`normalizedConditions(from drafts:)` (Zeilen 198-206):

```swift
    private static func normalizedConditions(from drafts: [RuleConditionDraft]) -> [NormalizedCondition] {
        drafts.compactMap { draft in
            normalizedCondition(
                field: draft.field.rawValue,
                conditionOperator: draft.conditionOperator.rawValue,
                value: draft.value,
                groupIndex: draft.groupIndex
            )
        }
    }
```

`normalizedCondition(...)` (Zeilen 208-233) bekommt den zusätzlichen Parameter:

```swift
    private static func normalizedCondition(
        field: String,
        conditionOperator: String,
        value: String,
        groupIndex: Int
    ) -> NormalizedCondition? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return nil
        }

        let expression = regularExpression(
            for: conditionOperator,
            pattern: trimmedValue
        )
        if conditionOperator == RuleConditionOperator.regex.rawValue,
           expression == nil {
            return nil
        }

        return NormalizedCondition(
            field: field,
            conditionOperator: conditionOperator,
            lowercasedValue: trimmedValue.lowercased(),
            regularExpression: expression,
            groupIndex: groupIndex
        )
    }
```

- [ ] **Step 4: `SQLiteRuleEvaluationStore.matchingArticleCount` anpassen**

In `Feedivo/Stores/SQLiteRuleEvaluationStore.swift`:

```swift
    func matchingArticleCount(
        conditionDrafts: [RuleConditionDraft]
    ) throws -> Int {
        let snapshots = try articleRuleSnapshots()
        return RuleEngine.matchingArticleCount(
            conditionDrafts: conditionDrafts,
            articles: snapshots
        )
    }
```

- [ ] **Step 5: `SQLiteRuleStore.swift` anpassen (`duplicate`, `ruleSnapshots`)**

In `Feedivo/Stores/SQLiteRuleStore.swift`, Methode `duplicate(id:copyName:)` — die Schleife
über `conditions` (Zeilen 93-104) propagiert jetzt auch `groupIndex`:

```swift
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
            }
```

Methode `ruleSnapshots()` — die `RuleEngine.RuleSnapshot(...)`-Konstruktion (Zeilen
166-191) verliert `conditionMatchMode`, die verschachtelte
`RuleEngine.RuleConditionSnapshot`-Konstruktion bekommt `groupIndex`:

```swift
                return RuleEngine.RuleSnapshot(
                    id: id,
                    name: rule.name,
                    isEnabled: rule.isEnabled,
                    actionRaw: rule.action,
                    notificationTemplate: rule.notificationTemplate,
                    notificationPriorityRaw: rule.notificationPriority,
                    sortOrder: rule.sortOrder,
                    conditions: conditions.map { condition in
                        RuleEngine.RuleConditionSnapshot(
                            field: condition.field,
                            conditionOperator: condition.conditionOperator,
                            value: condition.value,
                            sortOrder: condition.sortOrder,
                            groupIndex: condition.groupIndex
                        )
                    },
                    assignTag: tag.map { tag in
                        RuleEngine.TagSnapshot(
                            id: tag.id,
                            name: tag.name,
                            colorHex: tag.colorHex
                        )
                    }
                )
```

- [ ] **Step 6: Build prüfen — RuleSettingsView.swift und RuleWizardView.swift kompilieren noch nicht**

Run: `xcodebuild build -scheme Feedivo -destination 'platform=macOS'`
Expected: FAIL — `RuleSettingsView.swift:249` und `RuleWizardView.swift:649` rufen
`matchingArticleCount(conditionDrafts:matchMode:)` noch mit dem alten Signatur-Aufruf auf.
Das ist an dieser Stelle im Plan erwartet (wird in Task 4 und Task 6 behoben) — nicht
versuchen, hier zu fixen.

- [ ] **Step 7: Betroffene Tests isoliert ausführen, Erfolg verifizieren**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/RuleEngineTests -only-testing:FeedivoTests/SQLiteRuleEvaluationStoreTests -only-testing:FeedivoTests/SQLiteAdminStoreTests`
Expected: Diese isolierten Test-Targets kompilieren nur gegen den `Feedivo`-Produktivcode,
der für sie relevant ist — falls `xcodebuild test` wegen der in Step 6 erwarteten
Build-Fehler in `RuleSettingsView.swift`/`RuleWizardView.swift` insgesamt nicht durchläuft
(das gesamte Feedivo-Target muss kompilieren, auch für Tests), diesen Schritt überspringen
und direkt mit Task 4 fortfahren, dort läuft der volle Build wieder grün. Falls der Build
durchläuft: PASS für alle Tests in diesen drei Suiten.

- [ ] **Step 8: Commit**

```bash
git add Feedivo/Services/RuleEngine.swift Feedivo/Stores/SQLiteRuleEvaluationStore.swift Feedivo/Stores/SQLiteRuleStore.swift FeedivoTests/RuleEngineTests.swift FeedivoTests/SQLiteRuleEvaluationStoreTests.swift FeedivoTests/SQLiteAdminStoreTests.swift
git commit -m "Feature: RuleEngine wertet Regel-Bedingungen gruppenbasiert aus (UND in Gruppe, ODER zwischen Gruppen)"
```

Hinweis: Dieser Commit lässt den Gesamt-Build bewusst kurzzeitig rot (siehe Step 6) —
Task 4 und Task 6 beheben die verbleibenden zwei Aufrufstellen. Falls der Nutzer einen
durchgängig grünen Build pro Commit bevorzugt, Task 4 direkt im Anschluss ohne Pause
starten.

---

### Task 4: `RuleSettingsFormatter` gruppenbewusst + Aufrufstelle in `RuleSettingsView.swift`

**Files:**
- Modify: `Feedivo/Views/Rules/RuleSettingsView.swift:240-254,414,569-643`
- Test: `FeedivoTests/RuleSettingsFormatterTests.swift` (neu)

**Interfaces:**
- Consumes: `RuleEngine.matchingArticleCount`/`SQLiteRuleEvaluationStore.matchingArticleCount`
  ohne `matchMode`-Parameter (aus Task 3), `RuleConditionRecord.groupIndex` (aus Task 1).
- Produces: `RuleSettingsFormatter.conditionSummary(conditions: [RuleConditionRecord]) -> String`
  (Parameter `rule` entfällt, da nicht mehr benötigt), `RuleSettingsFormatter.conditionDrafts(for:)`
  propagiert jetzt `groupIndex`. Wird von Task 6 (`RuleWizardView.load(_ rule:)`) konsumiert.

- [ ] **Step 1: Fehlschlagende Tests schreiben**

Neue Datei `FeedivoTests/RuleSettingsFormatterTests.swift`:

```swift
import Foundation
import Testing
@testable import Feedivo

struct RuleSettingsFormatterTests {
    @Test func conditionSummaryBeiEinerGruppeZeigtKeineKlammern() {
        let conditions = [
            RuleConditionRecord(id: "c1", ruleID: "r1", field: "title", conditionOperator: "contains", value: "Swift", sortOrder: 0, groupIndex: 0),
            RuleConditionRecord(id: "c2", ruleID: "r1", field: "author", conditionOperator: "contains", value: "Apple", sortOrder: 1, groupIndex: 0)
        ]

        let summary = RuleSettingsFormatter.conditionSummary(conditions: conditions)

        #expect(!summary.contains("("))
        #expect(!summary.contains(")"))
        #expect(summary.contains(" UND "))
    }

    @Test func conditionSummaryBeiMehrerenMehrbedingungsGruppenSetztKlammernUndOderVerbindung() {
        let conditions = [
            RuleConditionRecord(id: "c1", ruleID: "r1", field: "title", conditionOperator: "contains", value: "Swift", sortOrder: 0, groupIndex: 0),
            RuleConditionRecord(id: "c2", ruleID: "r1", field: "author", conditionOperator: "contains", value: "Apple", sortOrder: 1, groupIndex: 0),
            RuleConditionRecord(id: "c3", ruleID: "r1", field: "summary", conditionOperator: "contains", value: "macOS", sortOrder: 2, groupIndex: 1),
            RuleConditionRecord(id: "c4", ruleID: "r1", field: "feedTitle", conditionOperator: "contains", value: "News", sortOrder: 3, groupIndex: 1)
        ]

        let summary = RuleSettingsFormatter.conditionSummary(conditions: conditions)

        #expect(summary.contains(") ODER ("))
        #expect(summary.hasPrefix("("))
        #expect(summary.hasSuffix(")"))
    }

    @Test func conditionSummaryBeiEinzelBedingungsGruppenLaesstDieseUnklammert() {
        let conditions = [
            RuleConditionRecord(id: "c1", ruleID: "r1", field: "title", conditionOperator: "contains", value: "Swift", sortOrder: 0, groupIndex: 0),
            RuleConditionRecord(id: "c2", ruleID: "r1", field: "summary", conditionOperator: "contains", value: "macOS", sortOrder: 1, groupIndex: 1)
        ]

        let summary = RuleSettingsFormatter.conditionSummary(conditions: conditions)

        // Beide Gruppen haben nur je eine Bedingung -- trotz mehrerer Gruppen
        // insgesamt bleiben Einzel-Bedingungs-Gruppen unklammert.
        #expect(!summary.contains("("))
        #expect(!summary.contains(")"))
        #expect(summary.contains(" ODER "))
    }

    @Test func conditionSummaryOhneBedingungenLiefertPlatzhalter() {
        let summary = RuleSettingsFormatter.conditionSummary(conditions: [])

        #expect(summary == L10n.ruleSummaryNoCondition)
    }

    @Test func conditionSummaryOrdnetGruppenNachKleinstemSortOrder() {
        // Gruppe 1 (c-erste) hat die kleinere sortOrder als Gruppe 0
        // (c-zweite) -- die Ausgabereihenfolge muss der sortOrder folgen,
        // nicht dem numerischen groupIndex-Wert.
        let conditions = [
            RuleConditionRecord(id: "c-erste", ruleID: "r1", field: "title", conditionOperator: "contains", value: "Erste", sortOrder: 0, groupIndex: 1),
            RuleConditionRecord(id: "c-zweite", ruleID: "r1", field: "title", conditionOperator: "contains", value: "Zweite", sortOrder: 1, groupIndex: 0)
        ]

        let summary = RuleSettingsFormatter.conditionSummary(conditions: conditions)
        let erstePosition = try? #require(summary.range(of: "Erste"))
        let zweitePosition = try? #require(summary.range(of: "Zweite"))

        #expect(erstePosition != nil)
        #expect(zweitePosition != nil)
        if let erstePosition, let zweitePosition {
            #expect(erstePosition.lowerBound < zweitePosition.lowerBound)
        }
    }

    @Test func conditionDraftsForPropagiertGroupIndex() {
        let conditions = [
            RuleConditionRecord(id: "c1", ruleID: "r1", field: "title", conditionOperator: "contains", value: "Swift", sortOrder: 0, groupIndex: 2)
        ]

        let drafts = RuleSettingsFormatter.conditionDrafts(for: conditions)

        #expect(drafts.first?.groupIndex == 2)
    }
}
```

- [ ] **Step 2: Test ausführen, Fehlschlag verifizieren**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/RuleSettingsFormatterTests`
Expected: FAIL — Compile-Fehler, `conditionSummary(conditions:)` (ohne `rule`-Parameter)
existiert noch nicht.

- [ ] **Step 3: `RuleSettingsFormatter` in `RuleSettingsView.swift` umstellen**

In `Feedivo/Views/Rules/RuleSettingsView.swift` den `enum RuleSettingsFormatter`-Block
(aktuell Zeilen 569-643) wie folgt ersetzen (nur `conditionSummary` und
`conditionDrafts(for:)` ändern sich, `conditionDescription`/`fieldTitle`/`operatorTitle`
bleiben unverändert):

```swift
enum RuleSettingsFormatter {
    static func conditionSummary(conditions: [RuleConditionRecord]) -> String {
        guard !conditions.isEmpty else {
            return L10n.ruleSummaryNoCondition
        }

        let groupedConditions = Dictionary(grouping: conditions, by: \.groupIndex)
        let orderedGroupIndices = groupedConditions.keys.sorted { lhs, rhs in
            let lhsMinSortOrder = groupedConditions[lhs]?.map(\.sortOrder).min() ?? 0
            let rhsMinSortOrder = groupedConditions[rhs]?.map(\.sortOrder).min() ?? 0
            return lhsMinSortOrder < rhsMinSortOrder
        }
        let hasMultipleGroups = orderedGroupIndices.count > 1

        let groupDescriptions = orderedGroupIndices.compactMap { groupIndex -> String? in
            guard let groupConditions = groupedConditions[groupIndex] else {
                return nil
            }

            let drafts = conditionDrafts(for: groupConditions)
            guard !drafts.isEmpty else {
                return nil
            }

            let joined = drafts
                .map { draft in conditionDescription(draft) }
                .joined(separator: " \(L10n.ruleSummaryAll) ")

            return (hasMultipleGroups && drafts.count > 1) ? "(\(joined))" : joined
        }

        guard !groupDescriptions.isEmpty else {
            return L10n.ruleSummaryNoCondition
        }

        return groupDescriptions.joined(separator: " \(L10n.ruleSummaryAny) ")
    }

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
                    field: field,
                    conditionOperator: conditionOperator,
                    value: condition.value,
                    groupIndex: condition.groupIndex
                )
        }
    }

    private static func conditionDescription(_ draft: RuleConditionDraft) -> String {
        let field = fieldTitle(draft.field)
        let conditionOperator = operatorTitle(draft.conditionOperator)
        return "\(field) \(conditionOperator) \"\(draft.value)\""
    }

    private static func fieldTitle(_ field: RuleConditionField) -> String {
        switch field {
        case .title:
            return L10n.ruleFieldTitle
        case .summary:
            return L10n.ruleFieldSummary
        case .author:
            return L10n.ruleFieldAuthor
        case .link:
            return L10n.ruleFieldLink
        case .feedTitle:
            return L10n.ruleFieldFeedTitle
        }
    }

    private static func operatorTitle(_ conditionOperator: RuleConditionOperator) -> String {
        switch conditionOperator {
        case .contains:
            return L10n.ruleOperatorContains
        case .notContains:
            return L10n.ruleOperatorNotContains
        case .equals:
            return L10n.ruleOperatorEquals
        case .startsWith:
            return L10n.ruleOperatorStartsWith
        case .endsWith:
            return L10n.ruleOperatorEndsWith
        case .regex:
            return L10n.ruleOperatorRegex
        }
    }
}
```

- [ ] **Step 4: Aufrufstellen in `RuleSettingsView.swift` anpassen**

Zeile 414 (Aufruf in `RuleSettingsRow.body`):

```swift
                Text(RuleSettingsFormatter.conditionSummary(conditions: conditions))
```

Zeilen 240-254 (`matchingCounts`-Neuberechnung) — der `store.matchingArticleCount`-Aufruf
verliert `matchMode`:

```swift
        var counts: [String: Int] = [:]

        for rule in orderedRules {
            let drafts = RuleSettingsFormatter.conditionDrafts(
                for: conditionsByRuleID[rule.id] ?? []
            )

            counts[rule.id] = (try? store.matchingArticleCount(
                conditionDrafts: drafts
            )) ?? 0
        }

        matchingCounts = counts
```

- [ ] **Step 5: Tests ausführen, Erfolg verifizieren**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/RuleSettingsFormatterTests`
Expected: PASS — alle 6 Tests grün.

- [ ] **Step 6: Vollen Build verifizieren**

Run: `xcodebuild build -scheme Feedivo -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED — `RuleSettingsView.swift` kompiliert jetzt wieder;
`RuleWizardView.swift:649` (`SQLiteRuleEvaluationStore(...).matchingArticleCount(
conditionDrafts:activeConditionDrafts,matchMode:activeMatchMode)`) ist weiterhin der
einzige verbleibende Build-Fehler — das ist an dieser Stelle im Plan erwartet, wird in
Task 6 behoben.

- [ ] **Step 7: Commit**

```bash
git add Feedivo/Views/Rules/RuleSettingsView.swift FeedivoTests/RuleSettingsFormatterTests.swift
git commit -m "Feature: RuleSettingsFormatter fasst Regel-Bedingungsgruppen mit Klammern und ODER zusammen"
```

---

### Task 5: L10n-Keys + `RuleSelectOption`-Extension verschieben

**Files:**
- Modify: `Feedivo/Resources/L10n.swift:278-286`
- Modify: `Feedivo/Resources/Localizable.xcstrings`
- Modify: `Feedivo/Views/SmartFolders/SmartFolderEditorView.swift` (Ende der Datei)
- Modify: `Feedivo/Views/Rules/RuleWizardView.swift:740` (nur die eine Extension-Zeile)

**Interfaces:**
- Produces: `L10n.ruleWizardAddGroup: LocalizedStringKey`, `L10n.ruleWizardRemoveGroup: LocalizedStringKey`.
  `extension RuleMatchMode: RuleSelectOption {}` lebt danach in `SmartFolderEditorView.swift`
  statt `RuleWizardView.swift`. Wird von Task 6 konsumiert.

Dieser Task enthält keine automatisierten Tests (reine String-Katalog-/Extension-Änderung
ohne Logik) — Verifikation erfolgt über Build + `grep`-Kontrolle, wie im bestehenden
CLAUDE.md-Gotcha zu `xcodebuild build` und indirekten `L10n`-Keys beschrieben.

- [ ] **Step 1: Neue L10n-Keys ergänzen**

In `Feedivo/Resources/L10n.swift` nach Zeile 279 (`ruleWizardRemoveCondition`) einfügen:

```swift
    static let ruleWizardAddGroup = LocalizedStringKey("ruleWizard.addGroup")
    static let ruleWizardRemoveGroup = LocalizedStringKey("ruleWizard.removeGroup")
```

Zeile 284 (`static let ruleWizardMatchModeLabel = LocalizedStringKey("ruleWizard.matchMode.label")`)
ersatzlos entfernen — einziger Verwendungsort war die jetzt entfallende
Wizard-Matchmode-Zeile (wird in Step 5 dieses Tasks aus `RuleWizardView.swift` entfernt).

- [ ] **Step 2: Katalogeinträge in `Localizable.xcstrings` ergänzen**

**Wichtig:** Nur per chirurgischer Text-Einfügung an einem stabilen Anker — niemals die
Datei per `json.load`/`json.dump` roundtripen (siehe CLAUDE.md-Gotcha, hätte beim
Shortcuts-Feature bereits einen ~41000-Zeilen-Fehldiff verursacht).

Direkt nach dem Ende des `"ruleWizard.addCondition"`-Blocks (endet mit `},` vor
`"ruleWizard.conditions.title"`, aktuell um Zeile 18920) folgenden Block einfügen:

```json
    "ruleWizard.addGroup" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "ODER-Gruppe hinzufügen"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Add OR group"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Ajouter un groupe OU"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Aggiungi gruppo OR"
          }
        }
      }
    },
```

Direkt nach dem Ende des `"ruleWizard.removeCondition"`-Blocks (endet mit `},` vor
`"ruleWizard.save"`, aktuell um Zeile 20024) folgenden Block einfügen:

```json
    "ruleWizard.removeGroup" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Gruppe entfernen"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Remove group"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Supprimer le groupe"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Rimuovi gruppo"
          }
        }
      }
    },
```

Den orphaned `"ruleWizard.matchMode.label"`-Eintrag NICHT löschen — verwaiste
xcstrings-Einträge sind harmlos, Xcode markiert sie beim nächsten Build automatisch als
`extractionState: stale` (etabliertes Projektmuster, siehe Dead-Code-Cleanup 2026-07-10).

- [ ] **Step 3: Diff-Stat verifizieren — nur Insertions**

Run: `git diff --stat Feedivo/Resources/Localizable.xcstrings`
Expected: Nur wenige Dutzend Insertions (die zwei neuen Blöcke), keine oder kaum
Deletions. Falls die Zeilenzahl im vierstelligen Bereich liegt, ist versehentlich die
ganze Datei umformatiert worden — Datei per `git checkout -- Feedivo/Resources/
Localizable.xcstrings` zurücksetzen und Step 2 erneut versuchen.

- [ ] **Step 4: `grep`-Kontrolle — neue Keys tatsächlich im Katalog**

Run: `grep -c "ruleWizard.addGroup" Feedivo/Resources/Localizable.xcstrings && grep -c "ruleWizard.removeGroup" Feedivo/Resources/Localizable.xcstrings`
Expected: Beide Aufrufe geben `1` zurück.

- [ ] **Step 5: `extension RuleMatchMode: RuleSelectOption {}` verschieben**

In `Feedivo/Views/SmartFolders/SmartFolderEditorView.swift` am Ende der Datei, direkt nach
dem bestehenden Block

```swift
extension SmartFolderConditionField: RuleSelectOption {}
extension SmartFolderConditionOperator: RuleSelectOption {}
extension SmartFolderStatusValue: RuleSelectOption {}
extension SmartFolderDateValue: RuleSelectOption {}
extension String: RuleSelectOption {}
extension Bool: RuleSelectOption {}
```

folgende Zeile ergänzen:

```swift
extension RuleMatchMode: RuleSelectOption {}
```

Im selben Schritt in `Feedivo/Views/Rules/RuleWizardView.swift` Zeile 740
(`extension RuleMatchMode: RuleSelectOption {}`) entfernen — sonst kompiliert es nicht
(doppelte Konformitätserklärung für denselben Typ zum selben Protokoll im selben Modul).
Die restliche Matchmode-UI in `RuleWizardView.swift` bleibt an dieser Stelle im Plan
bewusst noch unverändert stehen (Zeilen 69, 218-231, 550-552, 583, 649, 698 werden erst
in Task 6 angefasst) und funktioniert unverändert weiter, da sie nur
`RuleMatchMode.allCases`/`RuleSegmentedControl` nutzt — das Protokoll-Conformance-Setup
ist rein modulweit sichtbar, unabhängig davon, in welcher Datei es steht.

- [ ] **Step 6: Vollen Build verifizieren**

Run: `xcodebuild build -scheme Feedivo -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED — `RuleMatchMode` konformiert weiterhin zu `RuleSelectOption`
(jetzt via `SmartFolderEditorView.swift`), `RuleWizardView.swift` kompiliert unverändert
weiter. Der in Task 3/4 erwartete Fehler an `RuleWizardView.swift:649`
(`matchingArticleCount(...matchMode:...)`) bleibt an dieser Stelle weiterhin bestehen —
erwartet, wird in Task 6 behoben.

- [ ] **Step 7: Commit**

```bash
git add Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings Feedivo/Views/SmartFolders/SmartFolderEditorView.swift Feedivo/Views/Rules/RuleWizardView.swift
git commit -m "Vorbereitung: L10n-Keys fuer ODER-Gruppen, RuleSelectOption-Extension zu SmartFolderEditorView verschoben"
```

---

### Task 6: `RuleWizardView.swift` — Gruppen-Box-UI

**Files:**
- Modify: `Feedivo/Views/Rules/RuleWizardView.swift`
- Modify: `FeedivoTests/FeedivoAppSceneConfigurationTests.swift:680`

**Interfaces:**
- Consumes: `RuleConditionGroupLayout.groupedDraftIDs`/`.nextGroupIndex`/`.removingCondition`/
  `.removingGroup` (aus Task 2), `RuleEngine`/`SQLiteRuleEvaluationStore.matchingArticleCount`
  ohne `matchMode` (aus Task 3), `RuleSettingsFormatter.conditionDrafts(for:)` mit `groupIndex`
  (aus Task 4), `L10n.ruleWizardAddGroup`/`.ruleWizardRemoveGroup` (aus Task 5).
- Produces: Fertige Wizard-UI. Kein weiterer Task hängt hiervon ab.

- [ ] **Step 1: Source-Sniffing-Test vorab anpassen**

In `FeedivoTests/FeedivoAppSceneConfigurationTests.swift` Zeile 680 ersetzen:

```swift
        #expect(compactWizardSource.contains("SQLiteRuleEvaluationStore(database:database).matchingArticleCount(conditionDrafts:activeConditionDrafts)"))
```

(Dieser Test prüft nur einen Substring am kompaktierten Quelltext — er dient hier als
Ziel-Spezifikation für die exakte Aufrufsyntax, die `reloadPreviewCount()` in Step 6
erzeugen muss. Vor der eigentlichen UI-Änderung angepasst, damit das „Rot"→„Grün" am Ende
dieses Tasks eindeutig auf die richtige Änderung zurückzuführen ist.)

- [ ] **Step 2: Test ausführen, aktuellen Stand verifizieren**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoAppSceneConfigurationTests/regelPreviewUndRueckwirkendesAnwendenNutzenSQLite`
Expected: FAIL (der angepasste String steht so noch nicht im echten Quelltext) — falls
dieser einzelne Test stattdessen aus einem völlig anderen Grund bereits vor dieser Änderung
fehlschlug (z. B. weil er zufällig zu den bekannten 17 vorbestehenden Fehlschlägen in dieser
Testdatei zählt), das explizit vermerken und in Step 8 gegen den Zustand VOR diesem Task
gegenprüfen (`git stash`), statt es als neue Regression fehlzudeuten.

- [ ] **Step 3: Zustand entfernen — `matchMode`, altes Matchmode-UI**

In `Feedivo/Views/Rules/RuleWizardView.swift`:

Zeile 69 (`@State private var matchMode = RuleMatchMode.all`) ersatzlos entfernen.

Den kompletten Matchmode-Block in `ifCard(theme:)` (Zeilen 218-231) entfernen:

```swift
            if mode == .power {
                HStack(spacing: 10) {
                    Text(L10n.ruleWizardMatchModeLabel)
                        .font(.system(size: 12.5))
                        .foregroundStyle(theme.text2)

                    RuleSegmentedControl(
                        options: RuleMatchMode.allCases.map { ($0, $0.titleKey) },
                        selection: $matchMode,
                        theme: theme
                    )
                }
                .padding(.top, 13)
            }
```

Computed Property `activeMatchMode` (Zeilen 550-552) ersatzlos entfernen.

In `load(_ rule:)` (Zeile 583) die Zeile `matchMode = RuleMatchMode.normalized(rule.matchMode)`
ersatzlos entfernen.

- [ ] **Step 4: Bedingungs-Rendering in `ifCard(theme:)` auf gruppenbewusste Darstellung umstellen**

Den bestehenden Block in `ifCard(theme:)` (aktuell Zeilen 233-266 — die
`VStack(spacing: 9) { ForEach(activeConditionDraftIDs...) }` gefolgt vom
`if mode == .power { Button { ... "+ Bedingung" } }`) komplett ersetzen durch:

```swift
            if mode == .power {
                powerModeConditionGroups(theme: theme)
                    .padding(.top, 13)
            } else {
                VStack(spacing: 9) {
                    ForEach(activeConditionDraftIDs, id: \.self) { draftID in
                        if let index = conditionDrafts.firstIndex(where: { $0.id == draftID }) {
                            RuleConditionRow(
                                draft: $conditionDrafts[index],
                                showRemove: false,
                                theme: theme,
                                onRemove: {}
                            )
                        }
                    }
                }
                .padding(.top, 13)
            }
```

- [ ] **Step 5: Neue Methoden/Komponenten ergänzen**

Direkt nach der bestehenden Methode `ifCard(theme:)` (vor `// MARK: - DANN-Karte`) folgende
neue Methode einfügen:

```swift
    // MARK: - Bedingungsgruppen (Power-User-Modus)

    @ViewBuilder
    private func powerModeConditionGroups(theme: RuleDialogTheme) -> some View {
        let groups = RuleConditionGroupLayout.groupedDraftIDs(conditionDrafts)

        VStack(spacing: 10) {
            ForEach(Array(groups.enumerated()), id: \.offset) { offset, draftIDs in
                if offset > 0 {
                    RuleConditionGroupOrDivider(theme: theme)
                }

                RuleConditionGroupBox(
                    conditionDrafts: $conditionDrafts,
                    draftIDs: draftIDs,
                    showRemoveGroup: groups.count > 1,
                    theme: theme,
                    onAddCondition: { addCondition(toGroupContaining: draftIDs.first) },
                    onRemoveCondition: { removeCondition(id: $0) },
                    onRemoveGroup: { removeGroup(containing: draftIDs.first) }
                )
            }

            Button {
                addGroup()
            } label: {
                (Text("+ ") + Text(L10n.ruleWizardAddGroup))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .foregroundStyle(theme.border)
                    )
            }
            .buttonStyle(.plain)
        }
    }
```

In den `// MARK: - Zustand & Logik`-Abschnitt (nach `removeCondition(id:)`, vor
`cancelTagCreation()`) folgende neue Methoden einfügen und die bestehende
`private func removeCondition(id: UUID) { conditionDrafts.removeAll { $0.id == id } }`
dabei ersetzen (nicht duplizieren):

```swift
    private func removeCondition(id: UUID) {
        conditionDrafts = RuleConditionGroupLayout.removingCondition(id: id, from: conditionDrafts)
    }

    private func addCondition(toGroupContaining draftID: UUID?) {
        guard let draftID,
              let groupIndex = conditionDrafts.first(where: { $0.id == draftID })?.groupIndex
        else {
            return
        }

        conditionDrafts.append(
            RuleConditionDraft(field: .title, conditionOperator: .contains, value: "", groupIndex: groupIndex)
        )
    }

    private func addGroup() {
        let newGroupIndex = RuleConditionGroupLayout.nextGroupIndex(in: conditionDrafts)
        conditionDrafts.append(
            RuleConditionDraft(field: .title, conditionOperator: .contains, value: "", groupIndex: newGroupIndex)
        )
    }

    private func removeGroup(containing draftID: UUID?) {
        guard let draftID,
              let groupIndex = conditionDrafts.first(where: { $0.id == draftID })?.groupIndex
        else {
            return
        }

        conditionDrafts = RuleConditionGroupLayout.removingGroup(groupIndex, from: conditionDrafts)
    }
```

Ganz am Dateiende, nach der bestehenden `private struct RuleConditionRow: View { ... }`
(vor `// MARK: - Tag-Chip`), zwei neue private Views einfügen:

```swift
// MARK: - Bedingungsgruppen-Box

private struct RuleConditionGroupBox: View {
    @Binding var conditionDrafts: [RuleConditionDraft]
    let draftIDs: [UUID]
    let showRemoveGroup: Bool
    let theme: RuleDialogTheme
    let onAddCondition: () -> Void
    let onRemoveCondition: (UUID) -> Void
    let onRemoveGroup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(draftIDs, id: \.self) { draftID in
                if let index = conditionDrafts.firstIndex(where: { $0.id == draftID }) {
                    RuleConditionRow(
                        draft: $conditionDrafts[index],
                        showRemove: conditionDrafts.count > 1,
                        theme: theme,
                        onRemove: { onRemoveCondition(draftID) }
                    )
                }
            }

            HStack(spacing: 8) {
                Button(action: onAddCondition) {
                    (Text("+ ") + Text(L10n.ruleWizardAddCondition))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.accent)
                }
                .buttonStyle(.plain)

                if showRemoveGroup {
                    Spacer()

                    Button(action: onRemoveGroup) {
                        Text(L10n.ruleWizardRemoveGroup)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(theme.destructiveText)
                    }
                    .buttonStyle(.plain)
                    .help(L10n.ruleWizardRemoveGroup)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(theme.card2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        )
    }
}

// MARK: - "ODER"-Trenner zwischen zwei Gruppen-Boxen

private struct RuleConditionGroupOrDivider: View {
    let theme: RuleDialogTheme

    var body: some View {
        Text(verbatim: L10n.ruleSummaryAny)
            .font(.system(size: 10.5, weight: .heavy))
            .tracking(0.6)
            .foregroundStyle(theme.text2)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(theme.card2)
            )
            .overlay(
                Capsule().stroke(theme.border, lineWidth: 1)
            )
            .frame(maxWidth: .infinity, alignment: .center)
    }
}
```

- [ ] **Step 6: `previewReloadToken`/`reloadPreviewCount()`/`save()` anpassen**

`previewReloadToken` (Zeilen 554-561) ersetzen:

```swift
    private var previewReloadToken: String {
        activeConditionDrafts
            .map { draft in
                "\(draft.groupIndex):\(draft.field.rawValue):\(draft.conditionOperator.rawValue):\(draft.value)"
            }
            .joined(separator: "|")
    }
```

`reloadPreviewCount()` (Zeilen 639-656) — `matchMode`-Argument entfernen:

```swift
    private func reloadPreviewCount() async {
        guard let database = feedivoDatabase else {
            previewMatchingCount = 0
            previewLoadFailed = true
            return
        }

        do {
            previewMatchingCount = try SQLiteRuleEvaluationStore(database: database).matchingArticleCount(
                conditionDrafts: activeConditionDrafts
            )
            previewLoadFailed = false
        } catch {
            previewMatchingCount = 0
            previewLoadFailed = true
        }
    }
```

`save()` (Zeilen 658-724) — `normalizedDrafts`-Erzeugung propagiert `groupIndex`, das
`RuleRecord` behält den jetzt vestigialen `matchMode` unverändert vom Original (oder
Default bei neuer Regel), die `RuleConditionRecord`-Erzeugung bekommt `groupIndex`:

```swift
    private func save() {
        guard let database = feedivoDatabase else {
            ruleError = L10n.feedPropertiesUnavailable
            return
        }

        let drafts = mode == .simple ? Array(conditionDrafts.prefix(1)) : conditionDrafts
        let normalizedDrafts = drafts.compactMap { draft -> RuleConditionDraft? in
            let value = draft.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else {
                return nil
            }

            return RuleConditionDraft(
                field: draft.field,
                conditionOperator: draft.conditionOperator,
                value: value,
                groupIndex: draft.groupIndex
            )
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              !normalizedDrafts.isEmpty,
              action != .assignTag || selectedTag != nil
        else {
            ruleError = L10n.ruleValidationError
            return
        }

        if let invalidPattern = RuleConditionOperator.firstInvalidRegexValue(in: normalizedDrafts) {
            ruleError = L10n.ruleRegexInvalidError(pattern: invalidPattern)
            return
        }

        let ruleID = rule?.id ?? UUID().uuidString
        let sortOrder = rule?.sortOrder ?? ((existingRules.map(\.sortOrder).max() ?? -1) + 1)
        let record = RuleRecord(
            id: ruleID,
            name: trimmedName,
            isEnabled: isEnabled,
            matchMode: rule?.matchMode ?? RuleMatchMode.all.rawValue,
            action: action.rawValue,
            assignTagID: action == .assignTag ? selectedTagID : nil,
            notificationTemplate: rule?.notificationTemplate ?? "{Titel}",
            notificationPriority: rule?.notificationPriority ?? RuleNotificationPriority.normal.rawValue,
            sortOrder: sortOrder,
            createdAt: rule?.createdAt ?? Date()
        )
        let conditions = normalizedDrafts.enumerated().map { index, draft in
            RuleConditionRecord(
                id: UUID().uuidString,
                ruleID: ruleID,
                field: draft.field.rawValue,
                conditionOperator: draft.conditionOperator.rawValue,
                value: draft.value,
                sortOrder: index,
                groupIndex: draft.groupIndex
            )
        }

        do {
            try SQLiteRuleStore(database: database).save(record, conditions: conditions)
            ruleError = nil
            dismiss()
        } catch {
            ruleError = error.localizedDescription
        }
    }
```

**Wichtig zum `matchMode`-Feld auf `RuleRecord`:** Die Spalte bleibt bestehen (siehe Global
Constraints), wird aber von keiner Auswertungslogik mehr gelesen — beim Speichern wird
deshalb bewusst der bisherige Wert der Regel unverändert durchgereicht (`rule?.matchMode`)
bzw. bei neuen Regeln `RuleMatchMode.all.rawValue` als reiner, folgenloser Platzhalter
gesetzt. Kein Datenverlust, keine funktionale Bedeutung mehr.

- [ ] **Step 7: Vollen Build verifizieren**

Run: `xcodebuild build -scheme Feedivo -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED — keine verbleibenden Referenzen auf `matchMode`/`activeMatchMode`
in `RuleWizardView.swift`. Zur Kontrolle zusätzlich:

Run: `grep -n "matchMode" Feedivo/Views/Rules/RuleWizardView.swift`
Expected: Kein Treffer mehr (leere Ausgabe).

- [ ] **Step 8: Source-Sniffing-Test + restliche betroffene Suiten ausführen**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoAppSceneConfigurationTests/regelPreviewUndRueckwirkendesAnwendenNutzenSQLite`
Expected: PASS. Falls dieser einzelne Test bereits vor Beginn dieses Plans zu den 17
bekannten vorbestehenden Fehlschlägen zählte (in Step 2 vermerkt), stattdessen verifizieren,
dass sich der Fehlschlaggrund jetzt tatsächlich auf die ursprüngliche, unabhängige Ursache
zurückführen lässt und NICHT auf den in diesem Task geänderten String — bei Unsicherheit
per `git stash` gegen den Stand vor Task 6 vergleichen.

- [ ] **Step 9: Commit**

```bash
git add Feedivo/Views/Rules/RuleWizardView.swift FeedivoTests/FeedivoAppSceneConfigurationTests.swift
git commit -m "Feature: Regel-Assistent zeigt Bedingungen als frei gruppierbare UND/ODER-Boxen (Power-User-Modus)"
```

---

### Task 7: Volle Verifikation über alle betroffenen Test-Suiten

**Files:** Keine Code-Änderungen — reiner Verifikationslauf.

- [ ] **Step 1: Alle in diesem Plan berührten Test-Suiten gezielt zusammen ausführen**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteDatabaseMigrationTests -only-testing:FeedivoTests/RuleConditionGroupLayoutTests -only-testing:FeedivoTests/RuleEngineTests -only-testing:FeedivoTests/SQLiteRuleEvaluationStoreTests -only-testing:FeedivoTests/SQLiteAdminStoreTests -only-testing:FeedivoTests/RuleSettingsFormatterTests`
Expected: Alle Tests PASS.

- [ ] **Step 2: `FeedivoAppSceneConfigurationTests` isoliert erneut prüfen**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoAppSceneConfigurationTests`
Expected: Exakt die bekannten 17 vorbestehenden Fehlschläge (unverändert gegenüber dem
Stand vor diesem Plan) — `regelPreviewUndRueckwirkendesAnwendenNutzenSQLite` selbst PASS
(aus Task 6, Step 8). Nicht die volle unscoped Testsuite laufen lassen (hängt bekanntlich).

- [ ] **Step 3: Vollen Release-Build zusätzlich verifizieren**

Run: `xcodebuild build -scheme Feedivo -destination 'platform=macOS' -configuration Release`
Expected: BUILD SUCCEEDED (deckt eventuelle nur-in-Release auftretende Optimierungswarnungen
ab, die im Debug-Build nicht sichtbar wären).

- [ ] **Step 4: Manuelle Live-Verifikationscheckliste dokumentieren (nicht automatisierbar)**

Kein `computer-use`-Zugriff auf native macOS-Apps in dieser Umgebung verfügbar — folgende
Punkte müssen vom Nutzer manuell im laufenden Betrieb geprüft werden, bevor gepusht wird:

1. Neue Regel im Power-User-Modus anlegen, „+ ODER-Gruppe hinzufügen" klicken — zweite
   Box erscheint mit einer leeren Startbedingung, „ODER"-Trenner zwischen beiden Boxen
   sichtbar.
2. Innerhalb einer Box „+ Bedingung" klicken — neue Zeile erscheint in genau dieser Box,
   nicht in einer anderen.
3. Eine Box mit mehreren Bedingungen anlegen, eine einzelne Bedingung per „×" entfernen —
   Box bleibt mit den restlichen Bedingungen bestehen.
4. Eine Box auf genau eine Bedingung reduzieren, diese letzte Bedingung per „×" entfernen —
   die komplette Box verschwindet automatisch (kein leerer Rahmen sichtbar).
5. Bei mehreren Boxen den „Gruppe entfernen"-Button einer Box klicken — komplette Box
   samt aller ihrer Bedingungen verschwindet.
6. Bei genau einer verbleibenden Box: „Gruppe entfernen"-Button ist nicht sichtbar.
7. Bei genau einer verbleibenden Bedingung insgesamt (letzte Box, letzte Bedingung): das
   „×"-Icon dieser Bedingung ist nicht sichtbar (kann nicht komplett leer werden).
8. Vorschau-Trefferzahl aktualisiert sich korrekt beim Bearbeiten von Bedingungen in
   beliebigen Gruppen (nicht nur der ersten).
9. Regel mit `(Titel enthält X UND Feed ist Y) ODER Autor ist Z` speichern, Regel-Liste
   öffnen — Zusammenfassungstext zeigt exakt diese Klammerung.
10. Bestehende Regel aus der Zeit vor diesem Feature öffnen (falls vorhanden, sonst eine
    Regel mit „Eine reicht" aus einem Datenbank-Backup vor der Migration testen) — jede
    Bedingung erscheint als eigene, einzelne Box (ODER-Verhalten korrekt migriert).
11. Bestehende Regel mit „Alle Bedingungen"-Modus öffnen — alle Bedingungen erscheinen in
    einer einzigen Box (UND-Verhalten korrekt migriert).
12. Simple-Modus (nur eine Bedingung) — unverändertes Verhalten, keine Box-Optik, kein
    „+ Bedingung"/„+ ODER-Gruppe"-Button sichtbar.
13. Intelligenter-Ordner-Dialog (`SmartFolderEditorView`) — bestehender
    „Treffer bei"-Umschalter dort funktioniert unverändert (Regressionscheck für die in
    Task 5 verschobene `RuleSelectOption`-Extension).

---

## Selbstprüfung gegen die Spec

- **Abschnitt 1 (Datenmodell & Migration):** Task 1.
- **Abschnitt 2 (Auswertungslogik `RuleEngine.swift`):** Task 3.
- **Abschnitt 3 (UI im Regel-Assistenten):** Task 2 (reine Logik) + Task 5 (L10n/Extension-
  Vorbereitung) + Task 6 (eigentliche UI).
- **Abschnitt 4 (Zusammenfassungstext `RuleSettingsFormatter.conditionSummary`):** Task 4.
- **Abschnitt 5 (Testing):** `RuleEngineTests`-Gruppierungstests in Task 3, Migrationstests
  in Task 1, `RuleSettingsFormatterTests`-Klammerungstests in Task 4, Wizard-UI-Zustandslogik
  (Gruppe hinzufügen/löschen, letzte Bedingung entfernt automatisch die Gruppe) in Task 2 als
  reine, testbare `RuleConditionGroupLayout`-Funktionen statt nur als manueller Prüfpunkt —
  zusätzlich die verbleibenden, wirklich nur live prüfbaren Punkte in Task 7, Step 4.
- **Offene technische Prüfpunkte der Spec:** Migrationsnummer (`v20`, da `v19` zuletzt)
  und `RuleMatchMode`-Unabhängigkeit von Smart Folders wurden am 2026-07-24 vor
  Planerstellung per Grep verifiziert (siehe Global Constraints) — beide Annahmen der Spec
  bestätigt. Exakte Komponenten-Benennung (`RuleConditionGroupBox`,
  `RuleConditionGroupOrDivider`, eingebettet in `RuleWizardView.swift` statt einer neuen
  eigenen Datei, da beide Views nur dort verwendet werden und `RuleWizardView.swift` bereits
  mehrere private Sub-Views desselben Musters enthält) in Task 6 festgelegt.
