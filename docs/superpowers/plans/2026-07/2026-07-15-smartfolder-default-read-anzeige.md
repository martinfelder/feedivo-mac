# Konfigurierbare Standard-Artikelanzeige für Intelligente Ordner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Im Smart-Folder-Editor eine pro Ordner gespeicherte Einstellung
hinzufügen, ob die Artikelliste beim Betreten dieses Ordners standardmäßig
alle Artikel (gelesen + ungelesen) oder nur ungelesene zeigt — für alle
Smart Folder, auch die vier eingebauten Standard-Ordner.

**Architektur:** Neue `NOT NULL DEFAULT false`-Spalte `defaultShowsReadArticles`
auf `smart_folders` (Migration v17, mit Backfill für bestehende Standard-
Ordner). Sie ersetzt die bisher fest im Code verdrahtete Regel
(`SmartFolderDefaultDisplayPolicy.alwaysShowsReadArticles(defaultKey:)`)
als alleinige Quelle der Wahrheit — durchgereicht über `SmartFolderRecord` →
`SQLiteSmartFolderSnapshot` → `SQLiteFeedArticleListView`. Ein neuer
Segmented-Control im Editor-Dialog liest/schreibt den Wert.

**Tech Stack:** Swift 5.9+, SwiftUI, GRDB (SQLite), Swift Testing (`@Test`/`#expect`).

## Global Constraints

- Migrationen werden nie nachträglich verändert, nur als neuer
  `registerMigration`-Block angehängt (siehe CLAUDE.md).
- Vor Anlegen der neuen Migration den tatsächlich letzten Eintrag in
  `FeedivoDatabaseMigrator.swift` per `grep -n registerMigration` erneut
  prüfen (Stand bei Planerstellung: `v16_add_tag_sort_index` ist die letzte
  — falls seither etwas dazugekommen ist, `v17` entsprechend anpassen).
- Kommentare im Code auf Deutsch (Projektkonvention).
- Tests: Swift Testing (`@Test func ... throws`, `#expect(...)`), keine XCTest-Syntax.
- Test-Läufe immer gezielt mit `-only-testing:FeedivoTests/<SuiteName>` und
  `-parallel-testing-enabled NO` (volle Suite hängt bekanntermaßen, siehe
  CLAUDE.md-Gotcha).
- Bei jedem `xcodebuild build`/`test`-Lauf können veraltete SourceKit-
  Diagnosen in der IDE auftauchen — nur der tatsächliche Build-/Testlauf
  zählt als Wahrheit.
- Keine Änderung an `SmartFolderDefaultDisplayPolicy.mixedCountKeys` (Sidebar-
  Badge-Logik) — nur `alwaysShowsReadArticles`/`alwaysShowsReadArticleKeys`
  entfallen.

---

### Task 1: Datenbank-Migration v17 + Backfill

**Files:**
- Modify: `Feedivo/Database/FeedivoDatabaseMigrator.swift`
- Test: `FeedivoTests/SQLiteDatabaseMigrationTests.swift`

**Interfaces:**
- Produces: Neue Spalte `smart_folders.defaultShowsReadArticles` (`BOOLEAN NOT NULL DEFAULT 0`), verfügbar für alle nachfolgenden Tasks über `SmartFolderRecord` (Task 2).

- [ ] **Step 1: Failing Tests schreiben**

In `FeedivoTests/SQLiteDatabaseMigrationTests.swift` unmittelbar vor der
schließenden `}` des `SQLiteDatabaseMigrationTests`-Structs (direkt nach
`migrationV15IstIdempotentBeiBereitsVorhandenerSpalte()`) zwei neue Tests
einfügen:

```swift
    @Test func migrationV17BackfilltDefaultShowsReadArticlesFuerBestehendeStandardOrdner() throws {
        let queue = try DatabaseQueue()
        try FeedivoDatabaseMigrator.migrator.migrate(queue, upTo: "v16_add_tag_sort_index")

        try queue.write { db in
            let now = Date()
            try db.execute(
                sql: """
                    INSERT INTO smart_folders (id, name, defaultKey, createdAt, updatedAt)
                    VALUES
                        ('folder-starred', 'Mit Stern', 'starred', ?, ?),
                        ('folder-thisweek', 'Diese Woche', 'thisWeek', ?, ?),
                        ('folder-hidden', 'Ausgeblendet', 'hidden', ?, ?),
                        ('folder-saved', 'Gespeichert', 'saved', ?, ?),
                        ('folder-all', 'Alle Artikel', 'all', ?, ?),
                        ('folder-custom', 'Mein Ordner', NULL, ?, ?)
                    """,
                arguments: [now, now, now, now, now, now, now, now, now, now, now, now]
            )
        }

        try FeedivoDatabaseMigrator.migrator.migrate(queue)

        let valuesByID = try queue.read { db in
            try Row.fetchAll(db, sql: "SELECT id, defaultShowsReadArticles FROM smart_folders")
        }.reduce(into: [String: Bool]()) { result, row in
            result[row["id"]] = row["defaultShowsReadArticles"]
        }

        #expect(valuesByID["folder-starred"] == true)
        #expect(valuesByID["folder-thisweek"] == true)
        #expect(valuesByID["folder-hidden"] == true)
        #expect(valuesByID["folder-saved"] == true)
        #expect(valuesByID["folder-all"] == false)
        #expect(valuesByID["folder-custom"] == false)
    }

    @Test func migrationV17IstIdempotentBeiBereitsVorhandenerSpalte() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        let columns = try database.read { db in
            try Row.fetchAll(db, sql: "PRAGMA table_info(smart_folders)")
        }
        let column = columns.first { ($0["name"] as String?) == "defaultShowsReadArticles" }

        #expect(column != nil)
        #expect((column?["notnull"] as Int?) == 1)
        #expect((column?["dflt_value"] as String?) == "0")
    }
```

- [ ] **Step 2: Tests laufen lassen, Fehlschlag verifizieren**

Run:
```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' \
  -only-testing:FeedivoTests/SQLiteDatabaseMigrationTests/migrationV17BackfilltDefaultShowsReadArticlesFuerBestehendeStandardOrdner \
  -only-testing:FeedivoTests/SQLiteDatabaseMigrationTests/migrationV17IstIdempotentBeiBereitsVorhandenerSpalte \
  -parallel-testing-enabled NO
```
Erwartet: FAIL — SQL-Fehler `no such column: defaultShowsReadArticles`.

- [ ] **Step 3: Migration implementieren**

In `Feedivo/Database/FeedivoDatabaseMigrator.swift` nach dem Block
`migrator.registerMigration("v16_add_tag_sort_index") { ... }` (vor
`return migrator`) einfügen:

```swift
        migrator.registerMigration("v17_add_smart_folder_default_shows_read_articles") { database in
            try database.alter(table: "smart_folders") { table in
                table.add(column: "defaultShowsReadArticles", .boolean)
                    .notNull()
                    .defaults(to: false)
            }

            try backfillSmartFolderDefaultShowsReadArticles(database)
        }
```

Und nach der bestehenden `private static func backfillTagSortIndex(...) { ... }`
(direkt vor der schließenden `}` des `FeedivoDatabaseMigrator`-Enums)
einfügen:

```swift
    /// Setzt defaultShowsReadArticles=1 für die vier Standard-Ordner, die
    /// schon vor dieser Migration per fest verdrahteter Regel
    /// (SmartFolderDefaultDisplayPolicy.alwaysShowsReadArticleKeys) immer
    /// gelesene UND ungelesene Artikel zeigten — ihr Verhalten bleibt beim
    /// Umstieg auf die jetzt persistierte, im Editor änderbare Einstellung
    /// unverändert. Alle anderen Zeilen (inkl. eigener Ordner) behalten den
    /// Spalten-Default false.
    private static func backfillSmartFolderDefaultShowsReadArticles(_ database: Database) throws {
        try database.execute(
            sql: """
                UPDATE smart_folders
                SET defaultShowsReadArticles = 1
                WHERE defaultKey IN (?, ?, ?, ?)
                """,
            arguments: ["starred", "thisWeek", "hidden", "saved"]
        )
    }
```

- [ ] **Step 4: Tests laufen lassen, Erfolg verifizieren**

Run dasselbe Kommando wie in Step 2.
Erwartet: PASS (2 Tests).

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Database/FeedivoDatabaseMigrator.swift FeedivoTests/SQLiteDatabaseMigrationTests.swift
git commit -m "Feature: Migration v17 – defaultShowsReadArticles auf smart_folders"
```

---

### Task 2: Datenmodell (Record, Snapshot, Store)

**Files:**
- Modify: `Feedivo/Database/Records/SmartFolderRecord.swift`
- Modify: `Feedivo/Snapshots/SQLiteSmartFolderSnapshot.swift`
- Modify: `Feedivo/Stores/SQLiteSmartFolderStore.swift`
- Test: `FeedivoTests/SQLiteAdminStoreTests.swift`

**Interfaces:**
- Consumes: `smart_folders.defaultShowsReadArticles`-Spalte aus Task 1.
- Produces: `SmartFolderRecord.defaultShowsReadArticles: Bool` (Default `false`),
  `SQLiteSmartFolderSnapshot.defaultShowsReadArticles: Bool` (Default `false`)
  — beide für Task 3 (Editor-UI) und Task 4 (Konsument) verfügbar.

- [ ] **Step 1: Failing Test schreiben**

In `FeedivoTests/SQLiteAdminStoreTests.swift` direkt nach
`smartFolderStoreMutiertOrdnerSQLiteFirst()` (vor
`renameFeedRejectsEmptyTitle()`) einfügen:

```swift
    @Test func smartFolderStorePersistiertUndDupliziertDefaultShowsReadArticles() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = SQLiteSmartFolderStore(database: database)

        try store.save(
            SmartFolderRecord(
                id: "folder-1",
                name: "Projekt X",
                matchMode: RuleMatchMode.all.rawValue,
                isShownInSidebar: true,
                sortOrder: 0,
                iconName: "tray.full",
                colorHex: "#3B82F6",
                defaultShowsReadArticles: true
            ),
            conditions: []
        )

        #expect(try store.folder(id: "folder-1")?.defaultShowsReadArticles == true)
        #expect(try store.sidebarSnapshots().first?.defaultShowsReadArticles == true)

        let duplicate = try store.duplicate(id: "folder-1", copyName: "Projekt X Kopie")
        #expect(duplicate.defaultShowsReadArticles == true)

        try store.restoreDefaultFolders()
        let starredFolder = try store.folders().first { $0.defaultKey == "starred" }
        #expect(starredFolder?.defaultShowsReadArticles == true)
        let todayFolder = try store.folders().first { $0.defaultKey == "today" }
        #expect(todayFolder?.defaultShowsReadArticles == false)
    }
```

- [ ] **Step 2: Test laufen lassen, Fehlschlag verifizieren**

Run:
```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' \
  -only-testing:FeedivoTests/SQLiteAdminStoreTests/smartFolderStorePersistiertUndDupliziertDefaultShowsReadArticles \
  -parallel-testing-enabled NO
```
Erwartet: FAIL — Build-Fehler ("extra argument 'defaultShowsReadArticles' in call" bzw. "value of type 'SmartFolderRecord'/'SQLiteSmartFolderSnapshot' has no member 'defaultShowsReadArticles'").

- [ ] **Step 3: Implementierung**

**3a) `Feedivo/Database/Records/SmartFolderRecord.swift`** komplett ersetzen durch:

```swift
import Foundation
import GRDB

struct SmartFolderRecord: Codable, FetchableRecord, Identifiable, MutablePersistableRecord, Equatable, Sendable {
    static let databaseTableName = "smart_folders"

    var id: String
    var name: String
    var matchMode: String
    var isShownInSidebar: Bool
    var isDefault: Bool
    var sortOrder: Int
    var defaultKey: String?
    var iconName: String?
    var colorHex: String?
    var defaultShowsReadArticles: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        matchMode: String = RuleMatchMode.all.rawValue,
        isShownInSidebar: Bool = true,
        isDefault: Bool = false,
        sortOrder: Int = 0,
        defaultKey: String? = nil,
        iconName: String? = nil,
        colorHex: String? = nil,
        defaultShowsReadArticles: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.matchMode = matchMode
        self.isShownInSidebar = isShownInSidebar
        self.isDefault = isDefault
        self.sortOrder = sortOrder
        self.defaultKey = defaultKey
        self.iconName = iconName
        self.colorHex = colorHex
        self.defaultShowsReadArticles = defaultShowsReadArticles
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
```

**3b) `Feedivo/Snapshots/SQLiteSmartFolderSnapshot.swift`**: die Struct
`SQLiteSmartFolderSnapshot` (Zeilen 3–60 im aktuellen Stand) komplett
ersetzen durch:

```swift
struct SQLiteSmartFolderSnapshot: Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var matchMode: RuleMatchMode
    var conditions: [SQLiteSmartFolderConditionSnapshot]
    var iconName: String?
    var colorHex: String?
    var defaultKey: String?
    var defaultShowsReadArticles: Bool

    init(
        id: String,
        name: String,
        matchMode: RuleMatchMode,
        conditions: [SQLiteSmartFolderConditionSnapshot],
        iconName: String? = nil,
        colorHex: String? = nil,
        defaultKey: String? = nil,
        defaultShowsReadArticles: Bool = false
    ) {
        self.id = id
        self.name = name
        self.matchMode = matchMode
        self.conditions = conditions
        self.iconName = iconName
        self.colorHex = colorHex
        self.defaultKey = defaultKey
        self.defaultShowsReadArticles = defaultShowsReadArticles
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        matchMode: RuleMatchMode,
        conditionDrafts: [SmartFolderConditionDraft],
        defaultShowsReadArticles: Bool = false
    ) {
        self.id = id
        self.name = name
        self.matchMode = matchMode
        self.iconName = nil
        self.colorHex = nil
        self.defaultKey = nil
        self.defaultShowsReadArticles = defaultShowsReadArticles
        self.conditions = conditionDrafts.map { draft in
            SQLiteSmartFolderConditionSnapshot(
                field: draft.field,
                conditionOperator: draft.conditionOperator,
                value: draft.value
            )
        }
    }

    init(folder: SmartFolderRecord, conditions: [SmartFolderConditionRecord]) {
        self.id = folder.id
        self.name = SmartFolderFormatter.displayName(for: folder)
        self.matchMode = RuleMatchMode.normalized(folder.matchMode)
        self.iconName = folder.iconName
        self.colorHex = folder.colorHex
        self.defaultKey = folder.defaultKey
        self.defaultShowsReadArticles = folder.defaultShowsReadArticles
        self.conditions = conditions.compactMap(SQLiteSmartFolderConditionSnapshot.init(condition:))
    }
}
```

(Der nachfolgende `SQLiteSmartFolderConditionSnapshot`-Struct und die
`extension SQLiteSmartFolderSnapshot { var includesHiddenArticles ... }`
am Dateiende bleiben unverändert.)

**3c) `Feedivo/Stores/SQLiteSmartFolderStore.swift`** — vier gezielte Änderungen:

In `duplicate(id:copyName:)`, den bestehenden Block

```swift
            var duplicate = SmartFolderRecord(
                id: duplicateID,
                name: copyName,
                matchMode: source.matchMode,
                isShownInSidebar: source.isShownInSidebar,
                isDefault: false,
                sortOrder: maxSortOrder,
                defaultKey: nil,
                iconName: source.iconName,
                colorHex: source.colorHex
            )
```

ersetzen durch:

```swift
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
```

In `restoreDefaultFolders()`, den bestehenden Block

```swift
                var folder = SmartFolderRecord(
                    id: folderID,
                    name: definition.name,
                    matchMode: definition.matchMode.rawValue,
                    isShownInSidebar: true,
                    isDefault: true,
                    sortOrder: nextSortOrder,
                    defaultKey: definition.defaultKey,
                    iconName: definition.iconName,
                    colorHex: definition.colorHex
                )
```

ersetzen durch:

```swift
                var folder = SmartFolderRecord(
                    id: folderID,
                    name: definition.name,
                    matchMode: definition.matchMode.rawValue,
                    isShownInSidebar: true,
                    isDefault: true,
                    sortOrder: nextSortOrder,
                    defaultKey: definition.defaultKey,
                    iconName: definition.iconName,
                    colorHex: definition.colorHex,
                    defaultShowsReadArticles: definition.defaultShowsReadArticles
                )
```

In `sidebarSnapshots()`, den bestehenden Block

```swift
                return SQLiteSmartFolderSnapshot(
                    id: folder.id,
                    name: folder.name,
                    matchMode: RuleMatchMode.normalized(folder.matchMode),
                    conditions: conditions.compactMap { condition in
                        guard let field = SmartFolderConditionField(rawValue: condition.field),
                              let conditionOperator = SmartFolderConditionOperator(rawValue: condition.conditionOperator)
                        else {
                            return nil
                        }

                        return SQLiteSmartFolderConditionSnapshot(
                            field: field,
                            conditionOperator: conditionOperator,
                            value: condition.value
                        )
                    },
                    iconName: folder.iconName,
                    colorHex: folder.colorHex,
                    defaultKey: folder.defaultKey
                )
```

ersetzen durch (nur die letzten drei Zeilen vor der schließenden Klammer ändern sich):

```swift
                return SQLiteSmartFolderSnapshot(
                    id: folder.id,
                    name: folder.name,
                    matchMode: RuleMatchMode.normalized(folder.matchMode),
                    conditions: conditions.compactMap { condition in
                        guard let field = SmartFolderConditionField(rawValue: condition.field),
                              let conditionOperator = SmartFolderConditionOperator(rawValue: condition.conditionOperator)
                        else {
                            return nil
                        }

                        return SQLiteSmartFolderConditionSnapshot(
                            field: field,
                            conditionOperator: conditionOperator,
                            value: condition.value
                        )
                    },
                    iconName: folder.iconName,
                    colorHex: folder.colorHex,
                    defaultKey: folder.defaultKey,
                    defaultShowsReadArticles: folder.defaultShowsReadArticles
                )
```

`DefaultSmartFolderDefinition` (am Dateiende) und die
`defaultFolderDefinitions`-Liste ersetzen durch:

```swift
private struct DefaultSmartFolderDefinition {
    let name: String
    let matchMode: RuleMatchMode
    let defaultKey: String
    let iconName: String
    let colorHex: String
    let defaultShowsReadArticles: Bool
    let conditions: [DefaultSmartFolderCondition]
}
```

und die statische Liste `defaultFolderDefinitions` (innerhalb von
`SQLiteSmartFolderStore`) durch:

```swift
    private static let defaultFolderDefinitions: [DefaultSmartFolderDefinition] = [
        DefaultSmartFolderDefinition(
            name: "Alle Artikel",
            matchMode: .all,
            defaultKey: "all",
            iconName: "tray.full",
            colorHex: "#3B82F6",
            defaultShowsReadArticles: false,
            conditions: []
        ),
        DefaultSmartFolderDefinition(
            name: "Ungelesen",
            matchMode: .all,
            defaultKey: "unread",
            iconName: "circle.fill",
            colorHex: "#14B8A6",
            defaultShowsReadArticles: false,
            conditions: [
                DefaultSmartFolderCondition(
                    field: .status,
                    conditionOperator: .is,
                    value: SmartFolderStatusValue.unread.rawValue
                )
            ]
        ),
        DefaultSmartFolderDefinition(
            name: "Mit Stern",
            matchMode: .all,
            defaultKey: "starred",
            iconName: "star.fill",
            colorHex: "#F59E0B",
            defaultShowsReadArticles: true,
            conditions: [
                DefaultSmartFolderCondition(
                    field: .status,
                    conditionOperator: .is,
                    value: SmartFolderStatusValue.starred.rawValue
                )
            ]
        ),
        DefaultSmartFolderDefinition(
            name: "Heute",
            matchMode: .all,
            defaultKey: "today",
            iconName: "calendar",
            colorHex: "#22C55E",
            defaultShowsReadArticles: false,
            conditions: [
                DefaultSmartFolderCondition(
                    field: .date,
                    conditionOperator: .is,
                    value: SmartFolderDateValue.today.rawValue
                )
            ]
        ),
        DefaultSmartFolderDefinition(
            name: "Ausgeblendet",
            matchMode: .all,
            defaultKey: "hidden",
            iconName: "eye.slash",
            colorHex: "#6B7280",
            defaultShowsReadArticles: true,
            conditions: [
                DefaultSmartFolderCondition(
                    field: .status,
                    conditionOperator: .is,
                    value: SmartFolderStatusValue.hidden.rawValue
                )
            ]
        ),
        DefaultSmartFolderDefinition(
            name: "Archiviert",
            matchMode: .all,
            defaultKey: "archived",
            iconName: "archivebox",
            colorHex: "#8B5CF6",
            defaultShowsReadArticles: false,
            conditions: [
                DefaultSmartFolderCondition(
                    field: .status,
                    conditionOperator: .is,
                    value: SmartFolderStatusValue.archived.rawValue
                )
            ]
        ),
        DefaultSmartFolderDefinition(
            name: "Diese Woche",
            matchMode: .all,
            defaultKey: "thisWeek",
            iconName: "calendar",
            colorHex: "#22C55E",
            defaultShowsReadArticles: true,
            conditions: [
                DefaultSmartFolderCondition(
                    field: .date,
                    conditionOperator: .is,
                    value: SmartFolderDateValue.thisWeek.rawValue
                )
            ]
        ),
        DefaultSmartFolderDefinition(
            name: "Gespeichert",
            matchMode: .any,
            defaultKey: "saved",
            iconName: "bookmark",
            colorHex: "#F97316",
            defaultShowsReadArticles: true,
            conditions: [
                DefaultSmartFolderCondition(
                    field: .status,
                    conditionOperator: .is,
                    value: SmartFolderStatusValue.starred.rawValue
                ),
                DefaultSmartFolderCondition(
                    field: .status,
                    conditionOperator: .is,
                    value: SmartFolderStatusValue.archived.rawValue
                )
            ]
        )
    ]
```

- [ ] **Step 4: Test laufen lassen, Erfolg verifizieren**

Run dasselbe Kommando wie in Step 2.
Erwartet: PASS.

Zusätzlich zur Sicherheit die beiden bestehenden Smart-Folder-Tests erneut
mitlaufen lassen (Regressionsschutz für die geänderten Initializer):

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' \
  -only-testing:FeedivoTests/SQLiteAdminStoreTests \
  -parallel-testing-enabled NO
```
Erwartet: alle PASS.

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Database/Records/SmartFolderRecord.swift \
        Feedivo/Snapshots/SQLiteSmartFolderSnapshot.swift \
        Feedivo/Stores/SQLiteSmartFolderStore.swift \
        FeedivoTests/SQLiteAdminStoreTests.swift
git commit -m "Feature: defaultShowsReadArticles in SmartFolderRecord/Snapshot/Store"
```

---

### Task 3: Editor-UI (Segmented Control + L10n)

**Files:**
- Modify: `Feedivo/Views/SmartFolders/SmartFolderEditorView.swift`
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `SmartFolderRecord.defaultShowsReadArticles`, `RuleSegmentedControl<Option: RuleSelectOption>` (bestehender Baustein, `RuleDialogTheme.swift`), `L10n.articleListReadDisplayUnreadOnly`/`...All` (bestehende `String`-Konstanten, `L10n.swift:440-441`).
- Produces: Sichtbarer Editor-Control; keine neuen Symbole für andere Tasks.

Kein automatisierter Test möglich (reine SwiftUI-Dialog-Interaktion, wie bei
allen anderen Editor-Controls in dieser Datei — siehe bestehende
`sidebarCheckbox`/`operatorRow` ebenfalls ohne dedizierten UI-Test). Dieser
Task wird stattdessen über Build-Erfolg + eine manuelle Checkliste in Task 4
verifiziert.

- [ ] **Step 1: L10n-Key ergänzen**

In `Feedivo/Resources/L10n.swift` die Zeile

```swift
    static let smartFolderFieldNamePlaceholder = LocalizedStringKey("smartFolder.field.namePlaceholder")
```

ersetzen durch:

```swift
    static let smartFolderFieldNamePlaceholder = LocalizedStringKey("smartFolder.field.namePlaceholder")
    static let smartFolderDefaultArticleVisibility = LocalizedStringKey("smartFolder.defaultArticleVisibility")
```

In `Feedivo/Resources/Localizable.xcstrings` die Zeile

```
    "smartFolder.dragToSort" : {
```

ersetzen durch (neuer Eintrag davor, alphabetisch korrekt einsortiert):

```
    "smartFolder.defaultArticleVisibility" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Artikel-Anzeige"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Article Display"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Affichage des articles"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Visualizzazione articoli"
          }
        }
      }
    },
    "smartFolder.dragToSort" : {
```

- [ ] **Step 2: `Bool` für `RuleSegmentedControl` erweitern**

In `Feedivo/Views/SmartFolders/SmartFolderEditorView.swift` den Block

```swift
extension SmartFolderConditionField: RuleSelectOption {}
extension SmartFolderConditionOperator: RuleSelectOption {}
extension SmartFolderStatusValue: RuleSelectOption {}
extension SmartFolderDateValue: RuleSelectOption {}
extension String: RuleSelectOption {}
```

ersetzen durch:

```swift
extension SmartFolderConditionField: RuleSelectOption {}
extension SmartFolderConditionOperator: RuleSelectOption {}
extension SmartFolderStatusValue: RuleSelectOption {}
extension SmartFolderDateValue: RuleSelectOption {}
extension String: RuleSelectOption {}
extension Bool: RuleSelectOption {}
```

- [ ] **Step 3: State, Laden, Speichern, neue Zeile**

Den `@State`-Block

```swift
    @State private var name = ""
    @State private var matchMode = RuleMatchMode.all
    @State private var isShownInSidebar = true
    @State private var iconName = SmartFolderAppearance.defaultIconName
```

ersetzen durch:

```swift
    @State private var name = ""
    @State private var matchMode = RuleMatchMode.all
    @State private var isShownInSidebar = true
    @State private var defaultShowsReadArticles = false
    @State private var iconName = SmartFolderAppearance.defaultIconName
```

In `loadInitialState()` die Zeile

```swift
        isShownInSidebar = folder.isShownInSidebar
```

ersetzen durch:

```swift
        isShownInSidebar = folder.isShownInSidebar
        defaultShowsReadArticles = folder.defaultShowsReadArticles
```

In `save()` den Record-Konstruktor

```swift
        let record = SmartFolderRecord(
            id: folderID,
            name: folder?.defaultKey == nil ? trimmedName : (folder?.name ?? trimmedName),
            matchMode: matchMode.rawValue,
            isShownInSidebar: isShownInSidebar,
            isDefault: folder?.isDefault ?? false,
            sortOrder: sortOrder,
            defaultKey: folder?.defaultKey,
            iconName: iconName,
            colorHex: colorHex,
            createdAt: folder?.createdAt ?? Date()
        )
```

ersetzen durch:

```swift
        let record = SmartFolderRecord(
            id: folderID,
            name: folder?.defaultKey == nil ? trimmedName : (folder?.name ?? trimmedName),
            matchMode: matchMode.rawValue,
            isShownInSidebar: isShownInSidebar,
            isDefault: folder?.isDefault ?? false,
            sortOrder: sortOrder,
            defaultKey: folder?.defaultKey,
            iconName: iconName,
            colorHex: colorHex,
            defaultShowsReadArticles: defaultShowsReadArticles,
            createdAt: folder?.createdAt ?? Date()
        )
```

Im `body` den Block

```swift
            sidebarCheckbox(theme: theme)
                .padding(.top, 12)

            appearanceCard(theme: theme)
                .padding(.top, 18)
```

ersetzen durch:

```swift
            sidebarCheckbox(theme: theme)
                .padding(.top, 12)

            articleVisibilityRow(theme: theme)
                .padding(.top, 12)

            appearanceCard(theme: theme)
                .padding(.top, 18)
```

Und direkt nach der bestehenden `sidebarCheckbox(theme:)`-Funktion (vor dem
Kommentar `// MARK: - Darstellung`) eine neue Funktion einfügen:

```swift
    private func articleVisibilityRow(theme: RuleDialogTheme) -> some View {
        HStack(spacing: 12) {
            Text(L10n.smartFolderDefaultArticleVisibility)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.text2)

            RuleSegmentedControl(
                options: [
                    (false, LocalizedStringKey(L10n.articleListReadDisplayUnreadOnly)),
                    (true, LocalizedStringKey(L10n.articleListReadDisplayAll))
                ],
                selection: $defaultShowsReadArticles,
                theme: theme
            )
        }
    }
```

- [ ] **Step 4: Build verifizieren**

Run:
```bash
xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' build
```
Erwartet: `** BUILD SUCCEEDED **`. Kurz `git diff --stat -- Feedivo/Resources/Localizable.xcstrings` prüfen — kein automatischer Stub-Zusatzeintrag erwartet, da der Key bereits manuell mit vollständiger Übersetzung angelegt wurde (siehe CLAUDE.md-Gotcha zu automatischen Stubs bei fehlenden Katalogeinträgen).

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Views/SmartFolders/SmartFolderEditorView.swift \
        Feedivo/Resources/L10n.swift \
        Feedivo/Resources/Localizable.xcstrings
git commit -m "Feature: Segmented Control für Standard-Artikelanzeige im Smart-Folder-Editor"
```

---

### Task 4: Konsument umstellen + toten Code entfernen

**Files:**
- Modify: `Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift`
- Modify: `Feedivo/ViewModels/SQLiteSidebarState.swift`
- Modify: `FeedivoTests/SQLiteSidebarStateTests.swift`

**Interfaces:**
- Consumes: `SQLiteSmartFolderSnapshot.defaultShowsReadArticles` (Task 2).
- Produces: Nichts für weitere Tasks — letzter Task des Plans.

- [ ] **Step 1: `SQLiteFeedArticleListView.swift` auf den persistierten Wert umstellen**

Den `init(smartFolder:...)`-Block

```swift
        // "Mit Stern" soll ab dem allerersten Erscheinen gelesene UND ungelesene
        // Artikel zeigen (Nutzer-Report 2026-07-13) - ein markierter Artikel bleibt
        // unabhaengig vom Lese-Status wichtig. @State(initialValue:) greift nur beim
        // allerersten Erscheinen dieser View-Identitaet; fuer Scope-Wechsel innerhalb
        // derselben Sitzung sorgt zusaetzlich .onChange(of: scopeToken) fuer denselben
        // Default (siehe defaultShowsReadArticles).
        self._showsReadArticles = State(
            initialValue: SmartFolderDefaultDisplayPolicy.alwaysShowsReadArticles(
                defaultKey: smartFolder.defaultKey
            )
        )
    }
```

ersetzen durch:

```swift
        // Ein Smart Folder kann per Editor (SmartFolderEditorView) fest
        // einstellen, ob er standardmässig gelesene UND ungelesene Artikel
        // zeigt (z. B. "Mit Stern") oder nur ungelesene. @State(initialValue:)
        // greift nur beim allerersten Erscheinen dieser View-Identitaet; fuer
        // Scope-Wechsel innerhalb derselben Sitzung sorgt zusaetzlich
        // .onChange(of: scopeToken) fuer denselben Default (siehe
        // defaultShowsReadArticles).
        self._showsReadArticles = State(initialValue: smartFolder.defaultShowsReadArticles)
    }
```

Den Block

```swift
    private var defaultShowsReadArticles: Bool {
        if case let .smartFolder(smartFolder) = scope {
            return SmartFolderDefaultDisplayPolicy.alwaysShowsReadArticles(
                defaultKey: smartFolder.defaultKey
            )
        }

        return false
    }
```

ersetzen durch:

```swift
    private var defaultShowsReadArticles: Bool {
        if case let .smartFolder(smartFolder) = scope {
            return smartFolder.defaultShowsReadArticles
        }

        return false
    }
```

- [ ] **Step 2: Toten Code in `SQLiteSidebarState.swift` entfernen**

Den Block

```swift
enum SmartFolderDefaultDisplayPolicy {
    /// Standardordner mit getrennten Gelesen-/Ungelesen-Badges.
    static let mixedCountKeys: Set<String> = [
        "all", "today", "starred", "thisWeek", "hidden", "saved"
    ]

    /// Diese Ansichten zeigen unabhängig vom Lesestatus immer alle Treffer.
    static let alwaysShowsReadArticleKeys: Set<String> = [
        "starred", "thisWeek", "hidden", "saved"
    ]

    static func alwaysShowsReadArticles(defaultKey: String?) -> Bool {
        defaultKey.map(alwaysShowsReadArticleKeys.contains) ?? false
    }
}
```

ersetzen durch:

```swift
enum SmartFolderDefaultDisplayPolicy {
    /// Standardordner mit getrennten Gelesen-/Ungelesen-Badges (Sidebar-
    /// Zähler). Unabhängig von der pro Ordner änderbaren
    /// `defaultShowsReadArticles`-Einstellung (siehe SmartFolderEditorView) —
    /// diese Menge bleibt bewusst auf die vier eingebauten Standard-Ordner
    /// beschränkt.
    static let mixedCountKeys: Set<String> = [
        "all", "today", "starred", "thisWeek", "hidden", "saved"
    ]
}
```

- [ ] **Step 3: Jetzt ungültige Test-Zeile entfernen**

In `FeedivoTests/SQLiteSidebarStateTests.swift` den Block

```swift
        for defaultKey in ["starred", "thisWeek", "hidden", "saved"] {
            #expect(state.mixedCountsByDefaultKey[defaultKey] != nil)
            #expect(SmartFolderDefaultDisplayPolicy.alwaysShowsReadArticles(defaultKey: defaultKey))
        }
```

ersetzen durch:

```swift
        for defaultKey in ["starred", "thisWeek", "hidden", "saved"] {
            #expect(state.mixedCountsByDefaultKey[defaultKey] != nil)
        }
```

- [ ] **Step 4: Build + volle Regressionsrunde**

Run:
```bash
xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' build
```
Erwartet: `** BUILD SUCCEEDED **`.

Run:
```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' \
  -only-testing:FeedivoTests/SQLiteAdminStoreTests \
  -only-testing:FeedivoTests/SQLiteSidebarStateTests \
  -only-testing:FeedivoTests/SQLiteDatabaseMigrationTests \
  -only-testing:FeedivoTests/SQLiteFeedArticleListStateTests \
  -parallel-testing-enabled NO
```
Erwartet: alle PASS. (`FeedivoAppSceneConfigurationTests` bewusst NICHT mit
in dieser Liste — die hat einen dokumentierten, unabhängigen Vorab-
Fehlschlag-Bestand, siehe CLAUDE.md-Gotcha.)

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift \
        Feedivo/ViewModels/SQLiteSidebarState.swift \
        FeedivoTests/SQLiteSidebarStateTests.swift
git commit -m "Refactor: SQLiteFeedArticleListView nutzt defaultShowsReadArticles statt fest verdrahteter Policy"
```

- [ ] **Step 6: Manuelle Verifikation (nicht automatisierbar)**

Nach `xcodebuild build` die App tatsächlich starten und im Organizer/der
Sidebar per Rechtsklick auf einen Smart Folder → „Bearbeiten" prüfen:

1. „Mit Stern" öffnen → neue Zeile "Artikel-Anzeige" zeigt "Alle Artikel"
   vorausgewählt, Name-Feld bleibt weiterhin gesperrt, Control ist trotzdem
   bedienbar.
2. Einen neuen eigenen Smart Folder anlegen → "Artikel-Anzeige" startet bei
   "Nur ungelesen".
3. Bei einem eigenen Ordner auf "Alle Artikel" umstellen, speichern, in der
   Sidebar auf diesen Ordner klicken → Artikelliste zeigt sofort gelesene
   UND ungelesene Artikel, ohne dass das Filter-Menü manuell umgestellt
   werden muss.
4. Das bestehende Filter-Menü in der Artikelliste selbst weiterhin manuell
   auf "Nur ungelesen" umschalten können, unabhängig vom neuen Default.
