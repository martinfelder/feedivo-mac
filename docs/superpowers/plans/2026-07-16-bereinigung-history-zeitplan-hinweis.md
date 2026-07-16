# Bereinigung — History, Zeitplan und Hinweis Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Feature 17.3a umsetzen — eine History der letzten 10 Bereinigungsläufe, drei
unabhängig konfigurierbare automatische Auslöser (App-Start, Wochentag+Uhrzeit,
App-Beenden) und ein In-App-Toast bei jedem Lauf mit tatsächlich gelöschten Artikeln.

**Architecture:** Neue GRDB-Tabelle `cleanup_runs` protokolliert jeden Lauf (manuell wie
automatisch). `ArticleRetentionCleanupService.runAutomaticCleanup` bekommt einen
Pflichtparameter `triggerSource`, schreibt History und feuert bei `deletedCount > 0` ein
Bump-Counter-Signal (`CleanupToastSignal`), das `ContentView` zu einem Toast verarbeitet.
Der bisherige unbedingte Trigger bei jedem Hintergrund-Refresh-Zyklus wird durch einen
zeitplan-gesteuerten Trigger ersetzt (`CleanupScheduleSettings.isWeekdayTimeScheduleDue`,
Nachhol-Semantik). Alle bestehenden Aufrufstellen (App-Start, Hintergrund-Refresh,
Retention-Settings-Änderung, manueller Button, neu: App-Beenden) werden auf das neue
Schema umgestellt.

**Tech Stack:** Swift, SwiftUI, GRDB (SQLite), Swift Testing.

## Global Constraints

- Kommentare im Code auf Deutsch (Projektkonvention laut CLAUDE.md).
- Neue Datenbank-Migrationen werden immer als neuer `registerMigration("vN_…")`-Block
  angehängt, bestehende Migrationen werden nie nachträglich geändert.
- Vor Implementierung von Task 1 per `grep -n registerMigration
  Feedivo/Database/FeedivoDatabaseMigrator.swift` erneut prüfen, dass `v17` tatsächlich
  noch die letzte Migration ist (Stand bei Planerstellung: ja) — falls nicht, `v18` in
  diesem Plan durch die tatsächlich nächste freie Nummer ersetzen.
- Jeder neue `L10n.swift`-Key, der nicht als direktes String-Literal in einer
  `Text(...)`-Stelle auftaucht, erzeugt beim Build KEINEN automatischen Stub-Eintrag in
  `Localizable.xcstrings` — jeder neue Key wird deshalb in diesem Plan explizit per
  gezieltem `Edit` (kein `json.dump`-Rewrite, das reformatiert die ganze Datei) in
  `Localizable.xcstrings` ergänzt, in allen 4 vorhandenen Sprachen (de/en/fr/it).
- Direktes Committen auf `main` nach jedem Task (keine Feature-Branches/Worktrees,
  etablierte Nutzerpräferenz).
- `xcodebuild build` nach jedem Task grün; volle Testsuite läuft NICHT zuverlässig
  (`xcodebuild test` ohne Scope hängt) — immer gezielt mit
  `-only-testing:FeedivoTests/<SuiteName>` testen.

---

### Task 1: History-Datenmodell (Migration, Record, Trigger-Enum, Store)

**Files:**
- Modify: `Feedivo/Database/FeedivoDatabaseMigrator.swift:392-403`
- Create: `Feedivo/Database/Records/CleanupRunRecord.swift`
- Create: `Feedivo/Models/CleanupRunTrigger.swift`
- Create: `Feedivo/Stores/CleanupRunHistoryStore.swift`
- Test: `FeedivoTests/CleanupRunHistoryStoreTests.swift`
- Modify: `FeedivoTests/SQLiteDatabaseMigrationTests.swift:690-691`

**Interfaces:**
- Produces: `CleanupRunTrigger` (enum, `String` rawValue, Cases `.manual`, `.appStart`,
  `.schedule`, `.onQuit`, `.settingsChange`), `CleanupRunRecord` (GRDB-Record, Felder `id:
  String`, `executedAt: Date`, `deletedCount: Int`, `triggerSource: String`, `succeeded:
  Bool`, `errorMessage: String?`), `CleanupRunHistoryStore(database:)` mit `func
  record(triggerSource: CleanupRunTrigger, deletedCount: Int, succeeded: Bool,
  errorMessage: String?, now: Date = Date()) throws` und `func recentRuns() throws ->
  [CleanupRunRecord]` (max. 10, neueste zuerst). Diese drei Typen werden von Task 3
  konsumiert.

- [ ] **Step 1: Migration ergänzen**

In `Feedivo/Database/FeedivoDatabaseMigrator.swift`, direkt nach dem
`v17_add_smart_folder_default_shows_read_articles`-Block (vor `return migrator`):

```swift
        migrator.registerMigration("v18_create_cleanup_run_history") { database in
            try database.create(table: "cleanup_runs") { table in
                table.column("id", .text).primaryKey()
                table.column("executedAt", .datetime).notNull()
                table.column("deletedCount", .integer).notNull()
                table.column("triggerSource", .text).notNull()
                table.column("succeeded", .boolean).notNull()
                table.column("errorMessage", .text)
            }
            try database.create(
                index: "idx_cleanup_runs_executed_at",
                on: "cleanup_runs",
                columns: ["executedAt"]
            )
        }

        return migrator
```

(ersetzt die bisherige einzelne Zeile `return migrator` — der neue Migrationsblock kommt
davor.)

- [ ] **Step 2: `CleanupRunTrigger`-Enum anlegen**

Neue Datei `Feedivo/Models/CleanupRunTrigger.swift`:

```swift
import Foundation

// Wer eine automatische oder manuelle Bereinigung ausgelöst hat — wird als String in
// cleanup_runs.triggerSource gespeichert, in der Bereinigungs-History in den
// Einstellungen wieder in einen lesbaren Text übersetzt.
enum CleanupRunTrigger: String, Codable, Sendable {
    case manual
    case appStart
    case schedule
    case onQuit
    case settingsChange
}
```

- [ ] **Step 3: `CleanupRunRecord` anlegen**

Neue Datei `Feedivo/Database/Records/CleanupRunRecord.swift`:

```swift
import Foundation
import GRDB

struct CleanupRunRecord: Codable, FetchableRecord, MutablePersistableRecord, Equatable, Sendable {
    static let databaseTableName = "cleanup_runs"

    var id: String
    var executedAt: Date
    var deletedCount: Int
    var triggerSource: String
    var succeeded: Bool
    var errorMessage: String?

    init(
        id: String = UUID().uuidString,
        executedAt: Date,
        deletedCount: Int,
        triggerSource: String,
        succeeded: Bool,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.executedAt = executedAt
        self.deletedCount = deletedCount
        self.triggerSource = triggerSource
        self.succeeded = succeeded
        self.errorMessage = errorMessage
    }
}
```

- [ ] **Step 4: `CleanupRunHistoryStore` anlegen**

Neue Datei `Feedivo/Stores/CleanupRunHistoryStore.swift`:

```swift
import Foundation
import GRDB

// Ein Store pro Tabelle (Projektkonvention, siehe FeedLogStore). Hält nur die neuesten
// maxEntries Läufe — ältere werden bei jedem neuen Eintrag automatisch entfernt, damit
// die History der Einstellungen-Liste nie unbegrenzt wächst.
struct CleanupRunHistoryStore {
    static let maxEntries = 10

    private let database: FeedivoDatabase

    init(database: FeedivoDatabase) {
        self.database = database
    }

    func record(
        triggerSource: CleanupRunTrigger,
        deletedCount: Int,
        succeeded: Bool,
        errorMessage: String?,
        now: Date = Date()
    ) throws {
        try database.write { db in
            var run = CleanupRunRecord(
                executedAt: now,
                deletedCount: deletedCount,
                triggerSource: triggerSource.rawValue,
                succeeded: succeeded,
                errorMessage: errorMessage
            )
            try run.insert(db)

            try db.execute(sql: """
                DELETE FROM cleanup_runs
                WHERE id NOT IN (
                    SELECT id FROM cleanup_runs
                    ORDER BY executedAt DESC
                    LIMIT ?
                )
                """, arguments: [Self.maxEntries])
        }
    }

    func recentRuns() throws -> [CleanupRunRecord] {
        try database.read { db in
            try CleanupRunRecord
                .order(Column("executedAt").desc)
                .limit(Self.maxEntries)
                .fetchAll(db)
        }
    }
}
```

- [ ] **Step 5: Migrations-Regressionstest ergänzen**

In `FeedivoTests/SQLiteDatabaseMigrationTests.swift`, direkt nach
`migrationV17IstIdempotentBeiBereitsVorhandenerSpalte()` (vor der schließenden `}` des
Structs, Zeile 690-691):

```swift
    @Test func migrationCreatesCleanupRunsTable() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        let tableNames = try database.debugTableNames()

        #expect(tableNames.contains("cleanup_runs"))
    }
}
```

(ersetzt die bisherige schließende `}` — die neue Methode kommt davor, die Struct-Klammer
danach.)

- [ ] **Step 6: Store-Tests schreiben**

Neue Datei `FeedivoTests/CleanupRunHistoryStoreTests.swift`:

```swift
import Foundation
import GRDB
import Testing
@testable import Feedivo

struct CleanupRunHistoryStoreTests {
    @Test func recordSpeichertEinenErfolgreichenLauf() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = CleanupRunHistoryStore(database: database)
        let now = Date(timeIntervalSince1970: 10_000_000)

        try store.record(triggerSource: .manual, deletedCount: 5, succeeded: true, errorMessage: nil, now: now)

        let runs = try store.recentRuns()
        #expect(runs.count == 1)
        #expect(runs[0].deletedCount == 5)
        #expect(runs[0].triggerSource == CleanupRunTrigger.manual.rawValue)
        #expect(runs[0].succeeded == true)
        #expect(runs[0].errorMessage == nil)
    }

    @Test func recordSpeichertFehlgeschlagenenLaufMitMeldung() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = CleanupRunHistoryStore(database: database)
        let now = Date(timeIntervalSince1970: 10_000_000)

        try store.record(triggerSource: .schedule, deletedCount: 0, succeeded: false, errorMessage: "DB-Fehler", now: now)

        let runs = try store.recentRuns()
        #expect(runs.count == 1)
        #expect(runs[0].succeeded == false)
        #expect(runs[0].errorMessage == "DB-Fehler")
    }

    @Test func recordTrimmtAufDieNeuesten10Laeufe() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = CleanupRunHistoryStore(database: database)
        let baseDate = Date(timeIntervalSince1970: 10_000_000)

        for index in 0..<15 {
            try store.record(
                triggerSource: .appStart,
                deletedCount: index,
                succeeded: true,
                errorMessage: nil,
                now: baseDate.addingTimeInterval(TimeInterval(index * 60))
            )
        }

        let runs = try store.recentRuns()
        #expect(runs.count == 10)
        #expect(runs.first?.deletedCount == 14)
        #expect(runs.last?.deletedCount == 5)
    }

    @Test func recentRunsLiefertAbsteigendSortiert() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = CleanupRunHistoryStore(database: database)
        let baseDate = Date(timeIntervalSince1970: 10_000_000)

        try store.record(triggerSource: .manual, deletedCount: 1, succeeded: true, errorMessage: nil, now: baseDate)
        try store.record(
            triggerSource: .manual, deletedCount: 2, succeeded: true, errorMessage: nil,
            now: baseDate.addingTimeInterval(60)
        )

        let runs = try store.recentRuns()
        #expect(runs.map(\.deletedCount) == [2, 1])
    }
}
```

- [ ] **Step 7: Tests ausführen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CleanupRunHistoryStoreTests -only-testing:FeedivoTests/SQLiteDatabaseMigrationTests`
Expected: Alle Tests PASS.

- [ ] **Step 8: Build verifizieren**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 9: Commit**

```bash
git add Feedivo/Database/FeedivoDatabaseMigrator.swift \
  Feedivo/Database/Records/CleanupRunRecord.swift \
  Feedivo/Models/CleanupRunTrigger.swift \
  Feedivo/Stores/CleanupRunHistoryStore.swift \
  FeedivoTests/CleanupRunHistoryStoreTests.swift \
  FeedivoTests/SQLiteDatabaseMigrationTests.swift
git commit -m "Feature: Persistenz-Fundament für Bereinigungs-History (Migration v18)"
```

---

### Task 2: `CleanupScheduleSettings` (Zeitplan-Schalter + Nachhol-Prüfung)

**Files:**
- Create: `Feedivo/Services/CleanupScheduleSettings.swift`
- Test: `FeedivoTests/CleanupScheduleSettingsTests.swift`

**Interfaces:**
- Consumes: nichts (reine `UserDefaults`+`Calendar`-Logik, keine Abhängigkeit zu Task 1).
- Produces: `CleanupScheduleSettings` mit `runOnAppStartKey`/`defaultRunOnAppStart`,
  `runOnWeekdayTimeKey`/`defaultRunOnWeekdayTime`, `weekdayKey`/`defaultWeekday`,
  `timeMinutesKey`/`defaultTimeMinutes`, `runOnQuitKey`/`defaultRunOnQuit`,
  `lastScheduleRunAtKey` sowie `func runOnAppStart(in:) -> Bool`, `func
  runOnWeekdayTime(in:) -> Bool`, `func runOnQuit(in:) -> Bool`, `func weekday(in:) ->
  Int`, `func timeMinutes(in:) -> Int`, `func isWeekdayTimeScheduleDue(now:calendar:defaults:)
  -> Bool`, `func recordScheduleRun(now:in:)`. Wird von Task 4 (BackgroundRefreshService),
  Task 5 (AppDelegate) und Task 6 (Settings-UI) konsumiert.

- [ ] **Step 1: `CleanupScheduleSettings` anlegen**

Neue Datei `Feedivo/Services/CleanupScheduleSettings.swift`:

```swift
import Foundation

// Drei unabhängig schaltbare automatische Auslöser für die Artikel-Bereinigung.
// Ersetzt den bisherigen unbedingten Trigger bei jedem Hintergrund-Refresh-Zyklus
// (Feature 17.3a).
enum CleanupScheduleSettings {
    static let runOnAppStartKey = "cleanupSchedule.runOnAppStart"
    static let defaultRunOnAppStart = true

    static let runOnWeekdayTimeKey = "cleanupSchedule.runOnWeekdayTime"
    static let defaultRunOnWeekdayTime = false

    static let weekdayKey = "cleanupSchedule.weekday"          // 1...7, Calendar.weekday (1 = Sonntag)
    static let defaultWeekday = 1

    static let timeMinutesKey = "cleanupSchedule.timeMinutes"  // Minuten seit Mitternacht, 0...1439
    static let defaultTimeMinutes = 180                        // 03:00 Uhr

    static let runOnQuitKey = "cleanupSchedule.runOnQuit"
    static let defaultRunOnQuit = false

    static let lastScheduleRunAtKey = "cleanupSchedule.lastScheduleRunAt"

    static func runOnAppStart(in defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: runOnAppStartKey) != nil else {
            return defaultRunOnAppStart
        }
        return defaults.bool(forKey: runOnAppStartKey)
    }

    static func runOnWeekdayTime(in defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: runOnWeekdayTimeKey) != nil else {
            return defaultRunOnWeekdayTime
        }
        return defaults.bool(forKey: runOnWeekdayTimeKey)
    }

    static func runOnQuit(in defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: runOnQuitKey) != nil else {
            return defaultRunOnQuit
        }
        return defaults.bool(forKey: runOnQuitKey)
    }

    static func weekday(in defaults: UserDefaults = .standard) -> Int {
        guard defaults.object(forKey: weekdayKey) != nil else {
            return defaultWeekday
        }
        return defaults.integer(forKey: weekdayKey)
    }

    static func timeMinutes(in defaults: UserDefaults = .standard) -> Int {
        guard defaults.object(forKey: timeMinutesKey) != nil else {
            return defaultTimeMinutes
        }
        return defaults.integer(forKey: timeMinutesKey)
    }

    static func recordScheduleRun(now: Date, in defaults: UserDefaults = .standard) {
        defaults.set(now, forKey: lastScheduleRunAtKey)
    }

    /// Nachhol-Prüfung: liefert true, wenn der konfigurierte Wochentag+Uhrzeit seit dem
    /// letzten geloggten Zeitplan-Lauf bereits erreicht/verstrichen ist. Feedivo läuft
    /// nicht durchgehend — ein verpasster Zeitpunkt wird beim nächsten Kontakt (App-Start,
    /// Hintergrund-Refresh-Tick) nachgeholt, statt komplett auszufallen.
    static func isWeekdayTimeScheduleDue(
        now: Date,
        calendar: Calendar = .current,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard runOnWeekdayTime(in: defaults) else {
            return false
        }

        let mostRecentDue = mostRecentOccurrence(
            weekday: weekday(in: defaults),
            timeMinutes: timeMinutes(in: defaults),
            atOrBefore: now,
            calendar: calendar
        )

        guard let lastRunAt = defaults.object(forKey: lastScheduleRunAtKey) as? Date else {
            return true
        }

        return mostRecentDue > lastRunAt
    }

    /// Letzter Zeitpunkt in der Vergangenheit (oder jetzt), an dem weekday+timeMinutes
    /// zugetroffen hätte. Ist heute bereits der Zielwochentag, die Zielzeit aber noch
    /// nicht erreicht, zählt das heutige Vorkommen noch nicht — es wird eine Woche
    /// zurückgerechnet.
    private static func mostRecentOccurrence(
        weekday: Int,
        timeMinutes: Int,
        atOrBefore now: Date,
        calendar: Calendar
    ) -> Date {
        let currentWeekday = calendar.component(.weekday, from: now)
        let daysBack = (currentWeekday - weekday + 7) % 7

        func candidate(daysBack: Int) -> Date {
            let todayStart = calendar.startOfDay(for: now)
            let dayStart = calendar.date(byAdding: .day, value: -daysBack, to: todayStart) ?? todayStart
            return calendar.date(byAdding: .minute, value: timeMinutes, to: dayStart) ?? dayStart
        }

        let result = candidate(daysBack: daysBack)
        if result > now {
            return candidate(daysBack: daysBack + 7)
        }
        return result
    }
}
```

- [ ] **Step 2: Tests schreiben**

Neue Datei `FeedivoTests/CleanupScheduleSettingsTests.swift`:

```swift
import Foundation
import Testing
@testable import Feedivo

struct CleanupScheduleSettingsTests {
    @Test func defaultsSindWieDokumentiert() {
        #expect(CleanupScheduleSettings.runOnAppStartKey == "cleanupSchedule.runOnAppStart")
        #expect(CleanupScheduleSettings.defaultRunOnAppStart == true)
        #expect(CleanupScheduleSettings.runOnWeekdayTimeKey == "cleanupSchedule.runOnWeekdayTime")
        #expect(CleanupScheduleSettings.defaultRunOnWeekdayTime == false)
        #expect(CleanupScheduleSettings.runOnQuitKey == "cleanupSchedule.runOnQuit")
        #expect(CleanupScheduleSettings.defaultRunOnQuit == false)
    }

    @Test func runOnAppStartLiefertDefaultBeiFehlendemKey() throws {
        let defaults = try temporaryUserDefaults()
        #expect(CleanupScheduleSettings.runOnAppStart(in: defaults) == true)
    }

    @Test func runOnAppStartLiestExplizitGespeichertesFalse() throws {
        let defaults = try temporaryUserDefaults()
        defaults.set(false, forKey: CleanupScheduleSettings.runOnAppStartKey)
        #expect(CleanupScheduleSettings.runOnAppStart(in: defaults) == false)
    }

    @Test func runOnWeekdayTimeLiefertDefaultBeiFehlendemKey() throws {
        let defaults = try temporaryUserDefaults()
        #expect(CleanupScheduleSettings.runOnWeekdayTime(in: defaults) == false)
    }

    @Test func runOnQuitLiefertDefaultBeiFehlendemKey() throws {
        let defaults = try temporaryUserDefaults()
        #expect(CleanupScheduleSettings.runOnQuit(in: defaults) == false)
    }

    @Test func isWeekdayTimeScheduleDueLiefertFalseWennSchalterAus() throws {
        let defaults = try temporaryUserDefaults()
        let now = Date(timeIntervalSince1970: 10_000_000)

        #expect(CleanupScheduleSettings.isWeekdayTimeScheduleDue(now: now, defaults: defaults) == false)
    }

    @Test func isWeekdayTimeScheduleDueLiefertTrueBeiNieGelaufenemZeitplan() throws {
        let defaults = try temporaryUserDefaults()
        defaults.set(true, forKey: CleanupScheduleSettings.runOnWeekdayTimeKey)
        let now = Date(timeIntervalSince1970: 10_000_000)

        #expect(CleanupScheduleSettings.isWeekdayTimeScheduleDue(now: now, defaults: defaults) == true)
    }

    @Test func isWeekdayTimeScheduleDueLiefertFalseWennGenauZurSollzeitBereitsGelaufen() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let defaults = try temporaryUserDefaults()
        defaults.set(true, forKey: CleanupScheduleSettings.runOnWeekdayTimeKey)

        let now = Date(timeIntervalSince1970: 10_000_000)
        let todayWeekday = calendar.component(.weekday, from: now)
        let todayStart = calendar.startOfDay(for: now)
        let scheduledTime = calendar.date(byAdding: .minute, value: 60, to: todayStart)!

        defaults.set(todayWeekday, forKey: CleanupScheduleSettings.weekdayKey)
        defaults.set(60, forKey: CleanupScheduleSettings.timeMinutesKey)
        defaults.set(scheduledTime, forKey: CleanupScheduleSettings.lastScheduleRunAtKey)

        #expect(CleanupScheduleSettings.isWeekdayTimeScheduleDue(now: now, calendar: calendar, defaults: defaults) == false)
    }

    @Test func isWeekdayTimeScheduleDueLiefertTrueBeiNachholBedarfNachMehrerenWochen() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let defaults = try temporaryUserDefaults()
        defaults.set(true, forKey: CleanupScheduleSettings.runOnWeekdayTimeKey)

        let now = Date(timeIntervalSince1970: 10_000_000)
        let todayWeekday = calendar.component(.weekday, from: now)
        defaults.set(todayWeekday, forKey: CleanupScheduleSettings.weekdayKey)
        defaults.set(60, forKey: CleanupScheduleSettings.timeMinutesKey)

        // Letzter Lauf liegt 3 Wochen zurück — mehrere fällige Termine wurden verpasst
        // (App war nicht offen), muss trotzdem als fällig erkannt werden (Nachholen).
        let lastRunAt = now.addingTimeInterval(-21 * 24 * 60 * 60)
        defaults.set(lastRunAt, forKey: CleanupScheduleSettings.lastScheduleRunAtKey)

        #expect(CleanupScheduleSettings.isWeekdayTimeScheduleDue(now: now, calendar: calendar, defaults: defaults) == true)
    }

    @Test func isWeekdayTimeScheduleDueBleibtFalseWennHeutigeZielzeitNochNichtErreichtWurde() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let defaults = try temporaryUserDefaults()
        defaults.set(true, forKey: CleanupScheduleSettings.runOnWeekdayTimeKey)

        // now liegt bei diesem Referenz-Timestamp bei ca. 17:46 UTC.
        let now = Date(timeIntervalSince1970: 10_000_000)
        let todayWeekday = calendar.component(.weekday, from: now)
        let todayStart = calendar.startOfDay(for: now)
        let futureTimeMinutesToday = 23 * 60 // 23:00 Uhr, noch nicht erreicht

        defaults.set(todayWeekday, forKey: CleanupScheduleSettings.weekdayKey)
        defaults.set(futureTimeMinutesToday, forKey: CleanupScheduleSettings.timeMinutesKey)

        // Letzter Lauf: exakt vor 7 Tagen zur selben (damals bereits erreichten) Zielzeit.
        let scheduledTimeToday = calendar.date(byAdding: .minute, value: futureTimeMinutesToday, to: todayStart)!
        let lastRunAt = calendar.date(byAdding: .day, value: -7, to: scheduledTimeToday)!
        defaults.set(lastRunAt, forKey: CleanupScheduleSettings.lastScheduleRunAtKey)

        #expect(CleanupScheduleSettings.isWeekdayTimeScheduleDue(now: now, calendar: calendar, defaults: defaults) == false)
    }
}

private func temporaryUserDefaults() throws -> UserDefaults {
    let suiteName = "FeedivoTests.CleanupSchedule.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
```

- [ ] **Step 3: Tests ausführen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CleanupScheduleSettingsTests`
Expected: Alle Tests PASS.

- [ ] **Step 4: Build verifizieren**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Services/CleanupScheduleSettings.swift FeedivoTests/CleanupScheduleSettingsTests.swift
git commit -m "Feature: CleanupScheduleSettings mit Nachhol-Prüfung für Wochentag+Uhrzeit"
```

---

### Task 3: `runAutomaticCleanup` erweitern + alle Bestandsaufrufer aktualisieren

**Files:**
- Modify: `Feedivo/Services/ArticleRetentionCleanupService.swift:88-118`
- Create: `Feedivo/Services/CleanupToastSignal.swift`
- Modify: `Feedivo/App/FeedivoApp.swift:251-263`
- Modify: `Feedivo/Views/Sidebar/FeedPropertiesView.swift:747-757`
- Modify: `Feedivo/Views/Settings/SettingsView.swift:1252-1272`
- Modify: `FeedivoTests/ArticleRetentionCleanupServiceTests.swift:402-428`

**Interfaces:**
- Consumes: `CleanupRunTrigger`, `CleanupRunHistoryStore` (Task 1).
- Produces: `ArticleRetentionCleanupService.runAutomaticCleanup(database:isEnabled:
  retentionDays:minimumArticlesPerFeed:includeProtectedArticles:triggerSource:
  userDefaults:now:) -> Result<Int, Error>` (jetzt `@discardableResult`, neuer
  Pflichtparameter `triggerSource`). `CleanupToastSignal.notify(deletedCount:in:)`,
  `CleanupToastSignal.versionKey`, `CleanupToastSignal.deletedCountKey` — werden von
  Task 7 (Toast-UI) konsumiert.

- [ ] **Step 1: `CleanupToastSignal` anlegen**

Neue Datei `Feedivo/Services/CleanupToastSignal.swift`:

```swift
import Foundation

// Bump-Counter-Signal nach dem Muster von SQLiteDataInvalidation — GRDB bietet keinen
// @Query/Observation-Mechanismus, Views beobachten stattdessen einen hochzählenden
// UserDefaults-Wert per @AppStorage + .onChange.
enum CleanupToastSignal {
    static let versionKey = "cleanupToast.version"
    static let deletedCountKey = "cleanupToast.deletedCount"

    static func notify(deletedCount: Int, in defaults: UserDefaults = .standard) {
        defaults.set(defaults.integer(forKey: versionKey) + 1, forKey: versionKey)
        defaults.set(deletedCount, forKey: deletedCountKey)
    }
}
```

- [ ] **Step 2: `runAutomaticCleanup` erweitern**

In `Feedivo/Services/ArticleRetentionCleanupService.swift`, den bestehenden Block
(Zeile 88-118) ersetzen:

```swift
    /// Führt eine Bereinigung aus (manuell oder automatisch: App-Start, Zeitplan,
    /// App-Beenden, Feed-/Retention-Einstellungsänderung) und hält Ergebnis/Fehler
    /// persistent in `UserDefaults` UND in der `cleanup_runs`-History fest (Feature
    /// 17.3a). Feuert bei tatsächlich gelöschten Artikeln zusätzlich das
    /// `CleanupToastSignal` für den In-App-Toast. Vorher landeten Fehler des
    /// automatischen Pfads ausschließlich im Apple-Systemlog, ohne jede Sichtbarkeit in
    /// der App selbst (Befund C, Nutzer-Report 2026-07-13).
    @discardableResult
    @MainActor
    static func runAutomaticCleanup(
        database: FeedivoDatabase,
        isEnabled: Bool,
        retentionDays: Int,
        minimumArticlesPerFeed: Int = ArticleRetentionSettings.defaultMinimumArticlesPerFeed,
        includeProtectedArticles: Bool = false,
        triggerSource: CleanupRunTrigger,
        userDefaults: UserDefaults = .standard,
        now: Date = Date()
    ) -> Result<Int, Error> {
        do {
            let removedCount = try removeExpiredSQLiteArticles(
                database: database,
                isEnabled: isEnabled,
                retentionDays: retentionDays,
                minimumArticlesPerFeed: minimumArticlesPerFeed,
                includeProtectedArticles: includeProtectedArticles,
                now: now
            )
            recordAutomaticCleanupSuccess(removedCount: removedCount, now: now, userDefaults: userDefaults)
            try? CleanupRunHistoryStore(database: database).record(
                triggerSource: triggerSource,
                deletedCount: removedCount,
                succeeded: true,
                errorMessage: nil,
                now: now
            )
            if removedCount > 0 {
                CleanupToastSignal.notify(deletedCount: removedCount, in: userDefaults)
            }
            return .success(removedCount)
        } catch {
            recordAutomaticCleanupFailure(error.localizedDescription, now: now, userDefaults: userDefaults)
            try? CleanupRunHistoryStore(database: database).record(
                triggerSource: triggerSource,
                deletedCount: 0,
                succeeded: false,
                errorMessage: error.localizedDescription,
                now: now
            )
            AppLogger.dataAccess.error("Automatisches Retention-Cleanup: \(error.localizedDescription, privacy: .public)")
            return .failure(error)
        }
    }
```

- [ ] **Step 3: `FeedivoApp.swift` aktualisieren**

In `Feedivo/App/FeedivoApp.swift:256-262`, `triggerSource` ergänzen:

```swift
        ArticleRetentionCleanupService.runAutomaticCleanup(
            database: feedivoDatabase,
            isEnabled: articleRetentionIsEnabled,
            retentionDays: articleRetentionDays,
            minimumArticlesPerFeed: articleRetentionMinimumArticlesPerFeed,
            includeProtectedArticles: articleRetentionIncludesProtectedArticles,
            triggerSource: .settingsChange
        )
```

- [ ] **Step 4: `FeedPropertiesView.swift` aktualisieren**

In `Feedivo/Views/Sidebar/FeedPropertiesView.swift:748-754`, `triggerSource` ergänzen:

```swift
            ArticleRetentionCleanupService.runAutomaticCleanup(
                database: feedivoDatabase,
                isEnabled: globalArticleRetentionIsEnabled,
                retentionDays: globalArticleRetentionDays,
                minimumArticlesPerFeed: globalArticleRetentionMinimumArticlesPerFeed,
                includeProtectedArticles: globalArticleRetentionIncludesProtectedArticles,
                triggerSource: .settingsChange
            )
```

- [ ] **Step 5: Manuellen Button in `SettingsView.swift` umstellen**

In `Feedivo/Views/Settings/SettingsView.swift:1252-1272`, `runArticleRetentionCleanup()`
ersetzen:

```swift
    private func runArticleRetentionCleanup() {
        guard let feedivoDatabase else {
            return
        }

        let result = ArticleRetentionCleanupService.runAutomaticCleanup(
            database: feedivoDatabase,
            isEnabled: articleRetentionIsEnabled,
            retentionDays: articleRetentionDays,
            minimumArticlesPerFeed: articleRetentionMinimumArticlesPerFeed,
            includeProtectedArticles: articleRetentionIncludesProtectedArticles,
            triggerSource: .manual
        )

        switch result {
        case .success(let removedCount):
            retentionCleanupResult = L10n.settingsArticleRetentionResult(count: removedCount)
            retentionCleanupError = nil
        case .failure(let error):
            retentionCleanupResult = nil
            retentionCleanupError = error.localizedDescription
        }
    }
```

(Ersetzt die bisherige `do/catch`-Implementierung, die direkt
`removeExpiredSQLiteArticles` aufrief.)

- [ ] **Step 6: Bestehenden Test aktualisieren**

In `FeedivoTests/ArticleRetentionCleanupServiceTests.swift:416-423`, `triggerSource`
ergänzen:

```swift
        ArticleRetentionCleanupService.runAutomaticCleanup(
            database: database,
            isEnabled: true,
            retentionDays: 90,
            minimumArticlesPerFeed: 0,
            triggerSource: .manual,
            userDefaults: defaults,
            now: now
        )
```

- [ ] **Step 7: Neue Tests für History-Schreiben und Toast-Signal ergänzen**

In `FeedivoTests/ArticleRetentionCleanupServiceTests.swift`, direkt nach
`runAutomaticCleanupLoeschtArtikelUndSpeichertErfolgsstatus()` (vor der schließenden `}`
des Structs):

```swift
    @Test func runAutomaticCleanupSchreibtHistoryEintragBeiErfolg() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let defaults = try temporaryUserDefaults()
        let now = Date(timeIntervalSince1970: 10_000_000)
        let oldDate = now.addingTimeInterval(-91 * 24 * 60 * 60)
        let feedID = UUID().uuidString

        try FeedStore(database: database).save(
            FeedRecord(id: feedID, url: "https://example.com/feed.xml", title: "Feed", unreadCount: 1)
        )
        _ = try ArticleStore(database: database).upsert(
            ArticleUpsertInput(feedID: feedID, title: "Alt", publishedAt: oldDate)
        )

        ArticleRetentionCleanupService.runAutomaticCleanup(
            database: database,
            isEnabled: true,
            retentionDays: 90,
            minimumArticlesPerFeed: 0,
            triggerSource: .schedule,
            userDefaults: defaults,
            now: now
        )

        let history = try CleanupRunHistoryStore(database: database).recentRuns()
        #expect(history.count == 1)
        #expect(history[0].deletedCount == 1)
        #expect(history[0].succeeded == true)
        #expect(history[0].triggerSource == CleanupRunTrigger.schedule.rawValue)
    }

    @Test func runAutomaticCleanupSetztToastSignalNurBeiTatsaechlichGeloeschtenArtikeln() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let defaults = try temporaryUserDefaults()
        let now = Date(timeIntervalSince1970: 10_000_000)

        ArticleRetentionCleanupService.runAutomaticCleanup(
            database: database,
            isEnabled: true,
            retentionDays: 90,
            minimumArticlesPerFeed: 0,
            triggerSource: .manual,
            userDefaults: defaults,
            now: now
        )

        #expect(defaults.integer(forKey: CleanupToastSignal.versionKey) == 0)

        let feedID = UUID().uuidString
        try FeedStore(database: database).save(
            FeedRecord(id: feedID, url: "https://example.com/feed.xml", title: "Feed", unreadCount: 1)
        )
        _ = try ArticleStore(database: database).upsert(
            ArticleUpsertInput(feedID: feedID, title: "Alt", publishedAt: now.addingTimeInterval(-91 * 24 * 60 * 60))
        )

        ArticleRetentionCleanupService.runAutomaticCleanup(
            database: database,
            isEnabled: true,
            retentionDays: 90,
            minimumArticlesPerFeed: 0,
            triggerSource: .manual,
            userDefaults: defaults,
            now: now
        )

        #expect(defaults.integer(forKey: CleanupToastSignal.versionKey) == 1)
        #expect(defaults.integer(forKey: CleanupToastSignal.deletedCountKey) == 1)
    }
}
```

(Ersetzt die bisherige schließende `}` des Structs — die beiden neuen Methoden kommen
davor.)

- [ ] **Step 8: Tests ausführen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ArticleRetentionCleanupServiceTests`
Expected: Alle Tests PASS.

- [ ] **Step 9: Build verifizieren**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 10: Commit**

```bash
git add Feedivo/Services/ArticleRetentionCleanupService.swift \
  Feedivo/Services/CleanupToastSignal.swift \
  Feedivo/App/FeedivoApp.swift \
  Feedivo/Views/Sidebar/FeedPropertiesView.swift \
  Feedivo/Views/Settings/SettingsView.swift \
  FeedivoTests/ArticleRetentionCleanupServiceTests.swift
git commit -m "Feature: runAutomaticCleanup schreibt History und feuert Toast-Signal"
```

---

### Task 4: `BackgroundRefreshService` aufteilen (App-Start / Zeitplan)

**Files:**
- Modify: `Feedivo/Services/BackgroundRefreshService.swift:101-159`
- Modify: `Feedivo/Views/ContentView.swift:363-366`
- Modify: `FeedivoTests/BackgroundRefreshServiceTests.swift:130-224`

**Interfaces:**
- Consumes: `CleanupScheduleSettings` (Task 2), `runAutomaticCleanup(...triggerSource:...)`
  (Task 3).
- Produces: `BackgroundRefreshService.cleanupOnAppStartIfNeeded(database:userDefaults:now:)`,
  `BackgroundRefreshService.cleanupOnScheduleIfDue(database:userDefaults:now:)` — ersetzen
  `cleanupExpiredArticlesIfNeeded`, die entfällt vollständig. Werden von Task 5
  (indirekt, gleiches Muster) und `ContentView`/`refreshAllFeeds` konsumiert.

- [ ] **Step 1: `cleanupExpiredArticlesIfNeeded` durch zwei Funktionen ersetzen**

In `Feedivo/Services/BackgroundRefreshService.swift`, den `refreshAllFeeds`-Body
(Zeile 107-117) UND die bestehende `cleanupExpiredArticlesIfNeeded`-Funktion
(Zeile 119-159) durch Folgendes ersetzen:

```swift
    @MainActor
    static func refreshAllFeeds(
        database: FeedivoDatabase,
        intervalMinutes: Int = 60,
        userDefaults: UserDefaults = .standard,
        feedViewModel: FeedViewModel
    ) async {
        await feedViewModel.refreshAllFeeds(sqliteDatabase: database)

        recordRefreshOutcome(
            from: feedViewModel,
            intervalMinutes: intervalMinutes,
            userDefaults: userDefaults
        )

        cleanupOnScheduleIfDue(database: database, userDefaults: userDefaults)
    }

    /// App-Start-Auslöser der Bereinigung (Feature 17.3a) — läuft nur, wenn der
    /// Zeitplan-Schalter "Bei App-Start" aktiv ist (Standard: an, bewahrt das bisherige
    /// Verhalten für Bestandsnutzer).
    ///
    /// Liest die Retention-Einstellungen direkt aus `UserDefaults`, da diese Funktion
    /// außerhalb einer SwiftUI-View läuft und kein `@AppStorage` zur Verfügung hat —
    /// bewusst `object(forKey:) as? T ?? default` statt `bool(forKey:)`/`integer(forKey:)`,
    /// da Letztere bei einem noch nie gespeicherten Wert `false`/`0` liefern (bei
    /// `retentionDays` würde `0` auf den kleinsten erlaubten Wert `30` statt auf den
    /// korrekten 90-Tage-Standard geklemmt).
    @MainActor
    static func cleanupOnAppStartIfNeeded(
        database: FeedivoDatabase,
        userDefaults: UserDefaults = .standard,
        now: Date = Date()
    ) {
        guard CleanupScheduleSettings.runOnAppStart(in: userDefaults) else {
            return
        }

        ArticleRetentionCleanupService.runAutomaticCleanup(
            database: database,
            isEnabled: userDefaults.object(forKey: ArticleRetentionSettings.isEnabledKey) as? Bool
                ?? ArticleRetentionSettings.defaultIsEnabled,
            retentionDays: userDefaults.object(forKey: ArticleRetentionSettings.retentionDaysKey) as? Int
                ?? ArticleRetentionSettings.defaultRetentionDays,
            minimumArticlesPerFeed: userDefaults.object(forKey: ArticleRetentionSettings.minimumArticlesPerFeedKey) as? Int
                ?? ArticleRetentionSettings.defaultMinimumArticlesPerFeed,
            includeProtectedArticles: userDefaults.object(forKey: ArticleRetentionSettings.includesProtectedArticlesKey) as? Bool
                ?? ArticleRetentionSettings.defaultIncludesProtectedArticles,
            triggerSource: .appStart,
            userDefaults: userDefaults,
            now: now
        )
    }

    /// Zeitplan-Auslöser der Bereinigung (Feature 17.3a) — ersetzt den bisherigen
    /// unbedingten Trigger bei jedem Hintergrund-Refresh-Zyklus (Befund A, 2026-07-14).
    /// Läuft bei jedem periodischen `NSBackgroundActivityScheduler`-Tick, prüft aber
    /// zuerst per Nachhol-Logik, ob der konfigurierte Wochentag+Uhrzeit tatsächlich
    /// fällig ist (Standard: Schalter aus, nie fällig).
    @MainActor
    static func cleanupOnScheduleIfDue(
        database: FeedivoDatabase,
        userDefaults: UserDefaults = .standard,
        now: Date = Date()
    ) {
        guard CleanupScheduleSettings.isWeekdayTimeScheduleDue(now: now, defaults: userDefaults) else {
            return
        }

        ArticleRetentionCleanupService.runAutomaticCleanup(
            database: database,
            isEnabled: userDefaults.object(forKey: ArticleRetentionSettings.isEnabledKey) as? Bool
                ?? ArticleRetentionSettings.defaultIsEnabled,
            retentionDays: userDefaults.object(forKey: ArticleRetentionSettings.retentionDaysKey) as? Int
                ?? ArticleRetentionSettings.defaultRetentionDays,
            minimumArticlesPerFeed: userDefaults.object(forKey: ArticleRetentionSettings.minimumArticlesPerFeedKey) as? Int
                ?? ArticleRetentionSettings.defaultMinimumArticlesPerFeed,
            includeProtectedArticles: userDefaults.object(forKey: ArticleRetentionSettings.includesProtectedArticlesKey) as? Bool
                ?? ArticleRetentionSettings.defaultIncludesProtectedArticles,
            triggerSource: .schedule,
            userDefaults: userDefaults,
            now: now
        )
        CleanupScheduleSettings.recordScheduleRun(now: now, in: userDefaults)
    }
```

- [ ] **Step 2: `ContentView.handleContentAppear` aktualisieren**

In `Feedivo/Views/ContentView.swift:363-366`:

```swift
    private func handleContentAppear() {
        if let feedivoDatabase {
            BackgroundRefreshService.cleanupOnAppStartIfNeeded(database: feedivoDatabase)
        }
        updateFirstRunWizardPresentation()
        selectDefaultSmartFolderIfNeeded()
        updateAppIconBadge()
        restoreArticleWindowsIfNeeded()
        refreshFeedsOnLaunchIfNeeded()
    }
```

- [ ] **Step 3: Bestehende drei Tests auf `cleanupOnAppStartIfNeeded` umstellen**

In `FeedivoTests/BackgroundRefreshServiceTests.swift`, in allen drei bestehenden Tests
(`cleanupExpiredArticlesIfNeededLoeschtAlteArtikelWennAktiviert`,
`cleanupExpiredArticlesIfNeededTutNichtsWennKeineEinstellungenGespeichertSind`,
`cleanupExpiredArticlesIfNeededNutztStandardAufbewahrungWennNurAktivierungGespeichertIst`)
den Funktionsnamen im Aufruf sowie im Testnamen ersetzen:

```swift
    @MainActor
    @Test func cleanupOnAppStartIfNeededLoeschtAlteArtikelWennAktiviert() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let defaults = try temporaryUserDefaults()
        let now = Date(timeIntervalSince1970: 10_000_000)
        let oldDate = now.addingTimeInterval(-91 * 24 * 60 * 60)
        let feedID = UUID().uuidString

        try FeedStore(database: database).save(
            FeedRecord(id: feedID, url: "https://example.com/feed.xml", title: "Feed", unreadCount: 1)
        )
        let expiredID = try ArticleStore(database: database).upsert(
            ArticleUpsertInput(feedID: feedID, title: "Alt", publishedAt: oldDate)
        )

        defaults.set(true, forKey: ArticleRetentionSettings.isEnabledKey)
        defaults.set(90, forKey: ArticleRetentionSettings.retentionDaysKey)
        defaults.set(0, forKey: ArticleRetentionSettings.minimumArticlesPerFeedKey)
        defaults.set(false, forKey: ArticleRetentionSettings.includesProtectedArticlesKey)

        BackgroundRefreshService.cleanupOnAppStartIfNeeded(
            database: database,
            userDefaults: defaults,
            now: now
        )

        #expect(try ArticleStatusStore(database: database).status(articleID: expiredID) == nil)
    }

    @MainActor
    @Test func cleanupOnAppStartIfNeededTutNichtsWennKeineEinstellungenGespeichertSind() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let defaults = try temporaryUserDefaults()
        let now = Date(timeIntervalSince1970: 10_000_000)
        let oldDate = now.addingTimeInterval(-400 * 24 * 60 * 60)
        let feedID = UUID().uuidString

        try FeedStore(database: database).save(
            FeedRecord(id: feedID, url: "https://example.com/feed.xml", title: "Feed", unreadCount: 1)
        )
        let expiredID = try ArticleStore(database: database).upsert(
            ArticleUpsertInput(feedID: feedID, title: "Sehr alt", publishedAt: oldDate)
        )

        BackgroundRefreshService.cleanupOnAppStartIfNeeded(
            database: database,
            userDefaults: defaults,
            now: now
        )

        #expect(try ArticleStatusStore(database: database).status(articleID: expiredID) != nil)
    }

    @MainActor
    @Test func cleanupOnAppStartIfNeededNutztStandardAufbewahrungWennNurAktivierungGespeichertIst() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let defaults = try temporaryUserDefaults()
        let now = Date(timeIntervalSince1970: 10_000_000)
        let fortyDaysOld = now.addingTimeInterval(-40 * 24 * 60 * 60)
        let feedID = UUID().uuidString

        try FeedStore(database: database).save(
            FeedRecord(id: feedID, url: "https://example.com/feed.xml", title: "Feed", unreadCount: 1)
        )
        let articleID = try ArticleStore(database: database).upsert(
            ArticleUpsertInput(feedID: feedID, title: "40 Tage alt", publishedAt: fortyDaysOld)
        )

        defaults.set(true, forKey: ArticleRetentionSettings.isEnabledKey)

        BackgroundRefreshService.cleanupOnAppStartIfNeeded(
            database: database,
            userDefaults: defaults,
            now: now
        )

        #expect(try ArticleStatusStore(database: database).status(articleID: articleID) != nil)
    }

    @MainActor
    @Test func cleanupOnAppStartIfNeededTutNichtsWennSchalterAus() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let defaults = try temporaryUserDefaults()
        let now = Date(timeIntervalSince1970: 10_000_000)
        let oldDate = now.addingTimeInterval(-91 * 24 * 60 * 60)
        let feedID = UUID().uuidString

        try FeedStore(database: database).save(
            FeedRecord(id: feedID, url: "https://example.com/feed.xml", title: "Feed", unreadCount: 1)
        )
        let expiredID = try ArticleStore(database: database).upsert(
            ArticleUpsertInput(feedID: feedID, title: "Alt", publishedAt: oldDate)
        )

        defaults.set(true, forKey: ArticleRetentionSettings.isEnabledKey)
        defaults.set(90, forKey: ArticleRetentionSettings.retentionDaysKey)
        defaults.set(false, forKey: CleanupScheduleSettings.runOnAppStartKey)

        BackgroundRefreshService.cleanupOnAppStartIfNeeded(
            database: database,
            userDefaults: defaults,
            now: now
        )

        #expect(try ArticleStatusStore(database: database).status(articleID: expiredID) != nil)
    }

    @Test func cleanupOnScheduleIfDueTutNichtsWennZeitplanNichtFaellig() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let defaults = try temporaryUserDefaults()
        let now = Date(timeIntervalSince1970: 10_000_000)
        let oldDate = now.addingTimeInterval(-91 * 24 * 60 * 60)
        let feedID = UUID().uuidString

        try FeedStore(database: database).save(
            FeedRecord(id: feedID, url: "https://example.com/feed.xml", title: "Feed", unreadCount: 1)
        )
        let expiredID = try ArticleStore(database: database).upsert(
            ArticleUpsertInput(feedID: feedID, title: "Alt", publishedAt: oldDate)
        )

        defaults.set(true, forKey: ArticleRetentionSettings.isEnabledKey)
        defaults.set(90, forKey: ArticleRetentionSettings.retentionDaysKey)
        // CleanupScheduleSettings.runOnWeekdayTimeKey bewusst NICHT gesetzt → Default false.

        BackgroundRefreshService.cleanupOnScheduleIfDue(database: database, userDefaults: defaults, now: now)

        #expect(try ArticleStatusStore(database: database).status(articleID: expiredID) != nil)
    }

    @Test func cleanupOnScheduleIfDueLoeschtArtikelUndProtokolliertLaufWennFaellig() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let defaults = try temporaryUserDefaults()
        let now = Date(timeIntervalSince1970: 10_000_000)
        let oldDate = now.addingTimeInterval(-91 * 24 * 60 * 60)
        let feedID = UUID().uuidString

        try FeedStore(database: database).save(
            FeedRecord(id: feedID, url: "https://example.com/feed.xml", title: "Feed", unreadCount: 1)
        )
        let expiredID = try ArticleStore(database: database).upsert(
            ArticleUpsertInput(feedID: feedID, title: "Alt", publishedAt: oldDate)
        )

        defaults.set(true, forKey: ArticleRetentionSettings.isEnabledKey)
        defaults.set(90, forKey: ArticleRetentionSettings.retentionDaysKey)
        defaults.set(true, forKey: CleanupScheduleSettings.runOnWeekdayTimeKey)
        // lastScheduleRunAtKey bewusst nie gesetzt → beim ersten Aufruf immer fällig.

        BackgroundRefreshService.cleanupOnScheduleIfDue(database: database, userDefaults: defaults, now: now)

        #expect(try ArticleStatusStore(database: database).status(articleID: expiredID) == nil)
        #expect(defaults.object(forKey: CleanupScheduleSettings.lastScheduleRunAtKey) as? Date == now)
    }
}
```

(Diese Blöcke ersetzen die bisherigen drei `cleanupExpiredArticlesIfNeeded...`-Tests
Zeile 137-223 vollständig samt der schließenden `}` des Structs — die vier neuen Tests
kommen davor, die Struct-Klammer danach.)

- [ ] **Step 4: Tests ausführen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/BackgroundRefreshServiceTests`
Expected: Alle Tests PASS.

- [ ] **Step 5: Build verifizieren**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Services/BackgroundRefreshService.swift \
  Feedivo/Views/ContentView.swift \
  FeedivoTests/BackgroundRefreshServiceTests.swift
git commit -m "Feature: Zeitplan-gesteuerte Bereinigung ersetzt unbedingten Refresh-Trigger"
```

---

### Task 5: App-Beenden-Auslöser (`FeedivoAppDelegate.applicationWillTerminate`)

**Files:**
- Modify: `Feedivo/App/FeedivoAppDelegate.swift`

**Interfaces:**
- Consumes: `CleanupScheduleSettings.runOnQuit(in:)` (Task 2),
  `ArticleRetentionCleanupService.runAutomaticCleanup(...triggerSource: .onQuit...)`
  (Task 3), `menubarFeedivoDatabase` (bestehende private Property).

- [ ] **Step 1: `applicationWillTerminate` ergänzen**

In `Feedivo/App/FeedivoAppDelegate.swift`, direkt nach `applicationDidFinishLaunching`
(nach Zeile 44, vor `func userNotificationCenter`):

```swift
    // Feature 17.3a: optionaler Auslöser "Beim Beenden der App" für die automatische
    // Bereinigung. Bewusst fire-and-forget — `applicationWillTerminate` garantiert
    // keine Ausführungszeit für asynchrone Arbeit, ein durch die Terminierung
    // abgebrochener Lauf ist unkritisch, die nächste Gelegenheit (App-Start oder
    // Zeitplan) holt ihn nach. Liest UserDefaults direkt statt @AppStorage, da dieser
    // Delegate außerhalb einer SwiftUI-View läuft (analog zu
    // BackgroundRefreshService.cleanupOnAppStartIfNeeded).
    func applicationWillTerminate(_ notification: Notification) {
        guard CleanupScheduleSettings.runOnQuit(), let feedivoDatabase = menubarFeedivoDatabase else {
            return
        }

        let defaults = UserDefaults.standard
        Task {
            ArticleRetentionCleanupService.runAutomaticCleanup(
                database: feedivoDatabase,
                isEnabled: defaults.object(forKey: ArticleRetentionSettings.isEnabledKey) as? Bool
                    ?? ArticleRetentionSettings.defaultIsEnabled,
                retentionDays: defaults.object(forKey: ArticleRetentionSettings.retentionDaysKey) as? Int
                    ?? ArticleRetentionSettings.defaultRetentionDays,
                minimumArticlesPerFeed: defaults.object(forKey: ArticleRetentionSettings.minimumArticlesPerFeedKey) as? Int
                    ?? ArticleRetentionSettings.defaultMinimumArticlesPerFeed,
                includeProtectedArticles: defaults.object(forKey: ArticleRetentionSettings.includesProtectedArticlesKey) as? Bool
                    ?? ArticleRetentionSettings.defaultIncludesProtectedArticles,
                triggerSource: .onQuit
            )
        }
    }
```

- [ ] **Step 2: Build verifizieren**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`
Expected: `BUILD SUCCEEDED`.

Kein automatisierter Test (kein Mock-Seam für App-Terminierung im Projekt) — der Pfad
wird in der abschließenden manuellen Verifikation geprüft: Schalter aktivieren, ablaufene
Artikel anlegen, App über Cmd+Q beenden, neu starten, History-Liste in den Einstellungen
prüfen.

- [ ] **Step 3: Commit**

```bash
git add Feedivo/App/FeedivoAppDelegate.swift
git commit -m "Feature: App-Beenden-Auslöser für automatische Bereinigung (best-effort)"
```

---

### Task 6: Einstellungen-UI — Zeitplan-Schalter + History-Liste

**Files:**
- Modify: `Feedivo/Views/Settings/SettingsView.swift` (`CleanupSettingsView`, Zeile
  1102-1277)
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `CleanupScheduleSettings` (Task 2), `CleanupRunHistoryStore`,
  `CleanupRunRecord`, `CleanupRunTrigger` (Task 1).

- [ ] **Step 1: Neue L10n-Keys ergänzen**

In `Feedivo/Resources/L10n.swift`, direkt nach der bestehenden Zeile
`static let settingsArticleRetentionRunNow = LocalizedStringKey("settings.articleRetention.runNow")`
(Zeile 410):

```swift
    static let settingsCleanupScheduleAppStartTitle = LocalizedStringKey("settings.cleanupSchedule.appStart.title")
    static let settingsCleanupScheduleAppStartDescription = LocalizedStringKey("settings.cleanupSchedule.appStart.description")
    static let settingsCleanupScheduleWeekdayTimeTitle = LocalizedStringKey("settings.cleanupSchedule.weekdayTime.title")
    static let settingsCleanupScheduleWeekdayTimeDescription = LocalizedStringKey("settings.cleanupSchedule.weekdayTime.description")
    static let settingsCleanupScheduleOnQuitTitle = LocalizedStringKey("settings.cleanupSchedule.onQuit.title")
    static let settingsCleanupScheduleOnQuitDescription = LocalizedStringKey("settings.cleanupSchedule.onQuit.description")
    static let cleanupHistoryTitle = LocalizedStringKey("cleanup.history.title")
    static let cleanupHistoryDescription = LocalizedStringKey("cleanup.history.description")
    static let cleanupHistoryEmpty = LocalizedStringKey("cleanup.history.empty")
    static let cleanupHistoryTriggerManual = LocalizedStringKey("cleanup.history.trigger.manual")
    static let cleanupHistoryTriggerAppStart = LocalizedStringKey("cleanup.history.trigger.appStart")
    static let cleanupHistoryTriggerSchedule = LocalizedStringKey("cleanup.history.trigger.schedule")
    static let cleanupHistoryTriggerOnQuit = LocalizedStringKey("cleanup.history.trigger.onQuit")
    static let cleanupHistoryTriggerSettingsChange = LocalizedStringKey("cleanup.history.trigger.settingsChange")
```

- [ ] **Step 2: `Localizable.xcstrings`-Einträge ergänzen**

In `Feedivo/Resources/Localizable.xcstrings` per **Edit-Tool** (keine
`json.load`/`json.dump`-Rewrite, das reformatiert die gesamte Datei — siehe bekannter
Gotcha in CLAUDE.md) direkt nach dem Ende des bestehenden Eintrags
`"settings.articleRetention.runNow"` einfügen. Anker (exakter bestehender Text, Zeile
21363-21366):

```
        }
      }
    },
    "settings.articleRetention.title" : {
```

Ersetzen durch (bestehenden Anker unverändert lassen, neue Einträge dazwischen):

```
        }
      }
    },
    "cleanup.history.description" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Die letzten 10 Bereinigungsläufe, manuell und automatisch."
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "The last 10 cleanup runs, manual and automatic."
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Les 10 derniers nettoyages, manuels et automatiques."
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Le ultime 10 pulizie, manuali e automatiche."
          }
        }
      }
    },
    "cleanup.history.empty" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Noch keine Bereinigung ausgeführt."
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "No cleanup has run yet."
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Aucun nettoyage effectué pour l'instant."
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Nessuna pulizia ancora eseguita."
          }
        }
      }
    },
    "cleanup.history.title" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Bereinigungsverlauf"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Cleanup History"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Historique de nettoyage"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Cronologia pulizia"
          }
        }
      }
    },
    "cleanup.history.trigger.appStart" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "App-Start"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "App Launch"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Démarrage de l'app"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Avvio app"
          }
        }
      }
    },
    "cleanup.history.trigger.manual" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Manuell"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Manual"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Manuel"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Manuale"
          }
        }
      }
    },
    "cleanup.history.trigger.onQuit" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "App-Beenden"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "App Quit"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Fermeture de l'app"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Chiusura app"
          }
        }
      }
    },
    "cleanup.history.trigger.schedule" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Zeitplan"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Schedule"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Planification"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Pianificazione"
          }
        }
      }
    },
    "cleanup.history.trigger.settingsChange" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Einstellungsänderung"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Settings Change"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Modification des réglages"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Modifica impostazioni"
          }
        }
      }
    },
    "settings.cleanupSchedule.appStart.description" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Bereinigung bei jedem Start von Feedivo ausführen."
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Run cleanup every time Feedivo launches."
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Exécuter le nettoyage à chaque démarrage de Feedivo."
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Esegui la pulizia a ogni avvio di Feedivo."
          }
        }
      }
    },
    "settings.cleanupSchedule.appStart.title" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Bei App-Start"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "On App Launch"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Au démarrage de l'app"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "All'avvio dell'app"
          }
        }
      }
    },
    "settings.cleanupSchedule.onQuit.description" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Bereinigung ausführen, wenn Feedivo beendet wird."
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Run cleanup when Feedivo quits."
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Exécuter le nettoyage à la fermeture de Feedivo."
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Esegui la pulizia alla chiusura di Feedivo."
          }
        }
      }
    },
    "settings.cleanupSchedule.onQuit.title" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Beim Beenden der App"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "On App Quit"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "À la fermeture de l'app"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Alla chiusura dell'app"
          }
        }
      }
    },
    "settings.cleanupSchedule.weekdayTime.description" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Bereinigung wöchentlich zum gewählten Wochentag und zur gewählten Uhrzeit ausführen."
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Run cleanup weekly on the chosen weekday and time."
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Exécuter le nettoyage chaque semaine au jour et à l'heure choisis."
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Esegui la pulizia settimanalmente nel giorno e nell'ora scelti."
          }
        }
      }
    },
    "settings.cleanupSchedule.weekdayTime.title" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "An einem bestimmten Wochentag"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "On a Specific Weekday"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Un jour de la semaine précis"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "In un giorno della settimana specifico"
          }
        }
      }
    },
    "settings.articleRetention.title" : {
```

Nach dem Einfügen: `grep -c "cleanup.history.title\|settings.cleanupSchedule.appStart.title"
Feedivo/Resources/Localizable.xcstrings` muss `2` liefern (je ein Key-Vorkommen).

- [ ] **Step 3: `CleanupSettingsView` — bestehenden Status-Block entfernen, neue
  History-Liste + Zeitplan-Abschnitt ergänzen**

In `Feedivo/Views/Settings/SettingsView.swift`, den bestehenden `CleanupSettingsView`
(Zeile 1102-1277) komplett ersetzen:

```swift
private struct CleanupSettingsView: View {
    @Environment(\.feedivoDatabase) private var feedivoDatabase

    @AppStorage(ArticleRetentionSettings.isEnabledKey)
    private var articleRetentionIsEnabled = ArticleRetentionSettings.defaultIsEnabled

    @AppStorage(ArticleRetentionSettings.retentionDaysKey)
    private var articleRetentionDays = ArticleRetentionSettings.defaultRetentionDays

    @AppStorage(ArticleRetentionSettings.minimumArticlesPerFeedKey)
    private var articleRetentionMinimumArticlesPerFeed = ArticleRetentionSettings.defaultMinimumArticlesPerFeed

    @AppStorage(ArticleRetentionSettings.includesProtectedArticlesKey)
    private var articleRetentionIncludesProtectedArticles = ArticleRetentionSettings.defaultIncludesProtectedArticles

    @AppStorage(CleanupScheduleSettings.runOnAppStartKey)
    private var cleanupRunOnAppStart = CleanupScheduleSettings.defaultRunOnAppStart

    @AppStorage(CleanupScheduleSettings.runOnWeekdayTimeKey)
    private var cleanupRunOnWeekdayTime = CleanupScheduleSettings.defaultRunOnWeekdayTime

    @AppStorage(CleanupScheduleSettings.weekdayKey)
    private var cleanupWeekday = CleanupScheduleSettings.defaultWeekday

    @AppStorage(CleanupScheduleSettings.timeMinutesKey)
    private var cleanupTimeMinutes = CleanupScheduleSettings.defaultTimeMinutes

    @AppStorage(CleanupScheduleSettings.runOnQuitKey)
    private var cleanupRunOnQuit = CleanupScheduleSettings.defaultRunOnQuit

    @AppStorage(SQLiteDataInvalidation.statusVersionKey)
    private var sqliteStatusVersionForCleanupHistory = 0

    @State private var retentionCleanupResult: String?
    @State private var retentionCleanupError: String?
    @State private var cleanupHistory: [CleanupRunRecord] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsBlock(eyebrow: "Alte Artikel") {
                SettingRow(
                    title: L10n.settingsArticleRetentionTitle,
                    description: L10n.settingsArticleRetentionDescription
                ) {
                    Toggle("", isOn: $articleRetentionIsEnabled)
                        .labelsHidden()
                }

                SettingRow(
                    title: L10n.settingsArticleRetentionIntervalPicker,
                    description: "Artikel werden nach diesem Zeitraum automatisch entfernt."
                ) {
                    Picker(L10n.settingsArticleRetentionIntervalPicker, selection: $articleRetentionDays) {
                        ForEach(ArticleRetentionSettings.allowedRetentionDays, id: \.self) { days in
                            Text(L10n.settingsArticleRetentionInterval(days: days))
                                .tag(days)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .disabled(!articleRetentionIsEnabled)
                    .onChange(of: articleRetentionDays) {
                        articleRetentionDays = ArticleRetentionSettings.clampedRetentionDays(articleRetentionDays)
                    }
                }

                SettingRow(
                    title: "Mindestens pro Feed behalten",
                    description: "So viele der neuesten Artikel bleiben pro Feed erhalten, auch wenn sie älter sind."
                ) {
                    Picker("Mindestens pro Feed behalten", selection: $articleRetentionMinimumArticlesPerFeed) {
                        ForEach(ArticleRetentionSettings.allowedMinimumArticlesPerFeed, id: \.self) { count in
                            Text(minimumArticlesLabel(count))
                                .tag(count)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .disabled(!articleRetentionIsEnabled)
                    .onChange(of: articleRetentionMinimumArticlesPerFeed) {
                        articleRetentionMinimumArticlesPerFeed = ArticleRetentionSettings.clampedMinimumArticlesPerFeed(
                            articleRetentionMinimumArticlesPerFeed
                        )
                    }
                }

                SettingRow(
                    title: L10n.settingsArticleRetentionIncludesProtectedArticles,
                    description: "Auch markierte oder geschützte Artikel in die Bereinigung einbeziehen."
                ) {
                    Toggle("", isOn: $articleRetentionIncludesProtectedArticles)
                        .labelsHidden()
                        .disabled(!articleRetentionIsEnabled)
                }

                SettingRow(
                    title: L10n.settingsArticleRetentionRunNow,
                    description: "Bereinigung direkt mit den aktuellen Einstellungen starten."
                ) {
                    Button(L10n.settingsArticleRetentionRunNow) {
                        runArticleRetentionCleanup()
                    }
                    .disabled(!articleRetentionIsEnabled)
                }

                if let retentionCleanupResult {
                    Text(retentionCleanupResult)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                if let retentionCleanupError {
                    Text(retentionCleanupError)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }

            SettingsBlock(eyebrow: "Zeitplan") {
                SettingRow(
                    title: L10n.settingsCleanupScheduleAppStartTitle,
                    description: L10n.settingsCleanupScheduleAppStartDescription
                ) {
                    Toggle("", isOn: $cleanupRunOnAppStart)
                        .labelsHidden()
                }

                SettingRow(
                    title: L10n.settingsCleanupScheduleWeekdayTimeTitle,
                    description: L10n.settingsCleanupScheduleWeekdayTimeDescription
                ) {
                    Toggle("", isOn: $cleanupRunOnWeekdayTime)
                        .labelsHidden()
                }

                if cleanupRunOnWeekdayTime {
                    HStack(spacing: 12) {
                        Spacer(minLength: 202)

                        Picker("", selection: $cleanupWeekday) {
                            ForEach(Array(Calendar.current.weekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                                Text(symbol).tag(index + 1)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 130)

                        DatePicker("", selection: cleanupScheduleTimeBinding, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .datePickerStyle(.stepperField)

                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                }

                SettingRow(
                    title: L10n.settingsCleanupScheduleOnQuitTitle,
                    description: L10n.settingsCleanupScheduleOnQuitDescription
                ) {
                    Toggle("", isOn: $cleanupRunOnQuit)
                        .labelsHidden()
                }
            }

            SettingsBlock(eyebrow: L10n.cleanupHistoryTitle) {
                Text(L10n.cleanupHistoryDescription)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)

                if cleanupHistory.isEmpty {
                    Text(L10n.cleanupHistoryEmpty)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                } else {
                    VStack(spacing: 5) {
                        ForEach(cleanupHistory, id: \.id) { run in
                            cleanupHistoryRow(run)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .onAppear(perform: loadCleanupHistory)
        .onChange(of: sqliteStatusVersionForCleanupHistory) {
            loadCleanupHistory()
        }
    }

    private var cleanupScheduleTimeBinding: Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.hour = cleanupTimeMinutes / 60
                components.minute = cleanupTimeMinutes % 60
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                cleanupTimeMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            }
        )
    }

    private func cleanupHistoryRow(_ run: CleanupRunRecord) -> some View {
        HStack {
            Text(run.executedAt.formatted(date: .abbreviated, time: .shortened))
                .foregroundStyle(.tertiary)
            Text(cleanupTriggerLabel(run.triggerSource))
                .foregroundStyle(.tertiary)
            Spacer()
            if run.succeeded {
                Text("\(run.deletedCount)")
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else {
                Text(run.errorMessage ?? "")
                    .fontWeight(.medium)
                    .foregroundStyle(.red)
            }
        }
        .font(.system(size: 11))
        .padding(.horizontal, 9)
        .frame(minHeight: 26)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.85), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func cleanupTriggerLabel(_ rawValue: String) -> LocalizedStringKey {
        switch CleanupRunTrigger(rawValue: rawValue) {
        case .manual, nil:
            L10n.cleanupHistoryTriggerManual
        case .appStart:
            L10n.cleanupHistoryTriggerAppStart
        case .schedule:
            L10n.cleanupHistoryTriggerSchedule
        case .onQuit:
            L10n.cleanupHistoryTriggerOnQuit
        case .settingsChange:
            L10n.cleanupHistoryTriggerSettingsChange
        }
    }

    private func loadCleanupHistory() {
        guard let feedivoDatabase else {
            cleanupHistory = []
            return
        }
        cleanupHistory = (try? CleanupRunHistoryStore(database: feedivoDatabase).recentRuns()) ?? []
    }

    private func runArticleRetentionCleanup() {
        guard let feedivoDatabase else {
            return
        }

        let result = ArticleRetentionCleanupService.runAutomaticCleanup(
            database: feedivoDatabase,
            isEnabled: articleRetentionIsEnabled,
            retentionDays: articleRetentionDays,
            minimumArticlesPerFeed: articleRetentionMinimumArticlesPerFeed,
            includeProtectedArticles: articleRetentionIncludesProtectedArticles,
            triggerSource: .manual
        )

        switch result {
        case .success(let removedCount):
            retentionCleanupResult = L10n.settingsArticleRetentionResult(count: removedCount)
            retentionCleanupError = nil
        case .failure(let error):
            retentionCleanupResult = nil
            retentionCleanupError = error.localizedDescription
        }

        loadCleanupHistory()
    }

    private func minimumArticlesLabel(_ count: Int) -> String {
        count == 0 ? "Keine Mindestanzahl" : "\(count) Artikel"
    }
}
```

(Ersetzt den kompletten bisherigen `CleanupSettingsView`-Block inklusive der alten
`@AppStorage(ArticleRetentionSettings.lastAutomaticCleanup*)`-Properties, des
"Automatischer Bereinigungsstatus"-Blocks und der `automaticCleanupStatusText`-Property —
diese entfallen ersatzlos zugunsten der neuen History-Liste. **Wichtig:** Die
file-privaten freien Funktionen `statusLine(...)` und `formattedAutomaticStatusDate(...)`
(Zeile 988-1029, außerhalb von `CleanupSettingsView`) NICHT anfassen — sie werden
weiterhin von `RefreshSettingsView`s eigenem Status-Block gebraucht.)

- [ ] **Step 4: Build verifizieren**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: xcstrings-Vollständigkeit prüfen**

Run: `grep -c "settings.cleanupSchedule.weekdayTime.title\|cleanup.history.trigger.onQuit" Feedivo/Resources/Localizable.xcstrings`
Expected: `2`

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Views/Settings/SettingsView.swift Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings
git commit -m "Feature: Zeitplan-Einstellungen + Bereinigungsverlauf in den Einstellungen"
```

---

### Task 7: In-App-Toast im Hauptfenster

**Files:**
- Modify: `Feedivo/Views/ContentView.swift`
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `CleanupToastSignal.versionKey`/`deletedCountKey` (Task 3).

- [ ] **Step 1: L10n-Key ergänzen**

In `Feedivo/Resources/L10n.swift`, direkt nach
`static func settingsArticleRetentionResult(count: Int) -> String { ... }` (nach
Zeile 847):

```swift

    static func cleanupToastMessage(count: Int) -> String {
        String.localizedStringWithFormat(
            String(localized: "cleanup.toast.message"),
            count
        )
    }
```

- [ ] **Step 2: `Localizable.xcstrings`-Eintrag ergänzen**

Per **Edit-Tool** direkt nach dem Ende des bestehenden Eintrags
`"settings.articleRetention.result"` einfügen. Anker (exakter bestehender Text,
unmittelbar nach dem `it`-Block dieses Eintrags):

```
        }
      }
    },
    "settings.articleRetention.runNow" : {
```

Ersetzen durch:

```
        }
      }
    },
    "cleanup.toast.message" : {
      "localizations" : {
        "de" : {
          "variations" : {
            "plural" : {
              "one" : {
                "stringUnit" : {
                  "state" : "translated",
                  "value" : "%lld Artikel bereinigt"
                }
              },
              "other" : {
                "stringUnit" : {
                  "state" : "translated",
                  "value" : "%lld Artikel bereinigt"
                }
              }
            }
          }
        },
        "en" : {
          "variations" : {
            "plural" : {
              "one" : {
                "stringUnit" : {
                  "state" : "translated",
                  "value" : "%lld article cleaned up"
                }
              },
              "other" : {
                "stringUnit" : {
                  "state" : "translated",
                  "value" : "%lld articles cleaned up"
                }
              }
            }
          }
        },
        "fr" : {
          "variations" : {
            "plural" : {
              "one" : {
                "stringUnit" : {
                  "state" : "translated",
                  "value" : "%lld article nettoyé"
                }
              },
              "other" : {
                "stringUnit" : {
                  "state" : "translated",
                  "value" : "%lld articles nettoyés"
                }
              }
            }
          }
        },
        "it" : {
          "variations" : {
            "plural" : {
              "many" : {
                "stringUnit" : {
                  "state" : "translated",
                  "value" : "%lld articoli puliti"
                }
              },
              "one" : {
                "stringUnit" : {
                  "state" : "translated",
                  "value" : "%lld articolo pulito"
                }
              }
            }
          }
        }
      }
    },
    "settings.articleRetention.runNow" : {
```

**Wichtig:** Dieser Anker (`"settings.articleRetention.runNow"` als Ende-Marker) ist nach
Task 6 unverändert vorhanden, da Task 6 seine eigenen Einträge an einer anderen Stelle
(vor `"settings.articleRetention.title"`) eingefügt hat — beide Einfügestellen
überschneiden sich nicht.

- [ ] **Step 3: Toast-State und -View in `ContentView.swift` ergänzen**

Neue `@AppStorage`-Properties direkt nach der bestehenden
`@AppStorage(SQLiteDataInvalidation.statusVersionKey) private var sqliteStatusVersion = 0`
(Zeile 24-25):

```swift
    @AppStorage(CleanupToastSignal.versionKey)
    private var cleanupToastVersion = 0
    @AppStorage(CleanupToastSignal.deletedCountKey)
    private var cleanupToastDeletedCount = 0
    @State private var activeCleanupToast: CleanupToast?
```

Neuer `overlay`-Modifier direkt nach dem bestehenden
`.overlay(alignment: .bottomTrailing) { BottomStatusIndicators(...) }`-Block (nach
Zeile 266, vor `.task(id: recentRefreshStatusID) { ... }`):

```swift
        .overlay(alignment: .bottom) {
            if let activeCleanupToast {
                CleanupToastView(deletedCount: activeCleanupToast.deletedCount)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.18), value: activeCleanupToast)
        .onChange(of: cleanupToastVersion) {
            guard cleanupToastDeletedCount > 0 else {
                return
            }
            activeCleanupToast = CleanupToast(id: cleanupToastVersion, deletedCount: cleanupToastDeletedCount)
        }
        .task(id: activeCleanupToast?.id) {
            await clearCleanupToastIfNeeded()
        }
```

Neue private Funktion direkt nach `clearRecentRefreshStatusIfNeeded()` (nach Zeile 418):

```swift
    private func clearCleanupToastIfNeeded() async {
        guard let toastID = activeCleanupToast?.id else {
            return
        }

        try? await Task.sleep(for: .seconds(4))
        guard activeCleanupToast?.id == toastID else {
            return
        }

        activeCleanupToast = nil
    }
```

Neue Typen am Ende der Datei, direkt vor `enum NetworkConnectionStatus` (nach Zeile 779):

```swift
private struct CleanupToast: Equatable {
    let id: Int
    let deletedCount: Int
}

private struct CleanupToastView: View {
    let deletedCount: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.secondary)
            Text(L10n.cleanupToastMessage(count: deletedCount))
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(.separator.opacity(0.35), lineWidth: 1)
        }
    }
}
```

- [ ] **Step 4: Build verifizieren**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: xcstrings-Vollständigkeit prüfen**

Run: `grep -c "cleanup.toast.message" Feedivo/Resources/Localizable.xcstrings`
Expected: `1`

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Views/ContentView.swift Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings
git commit -m "Feature: In-App-Toast bei Bereinigungsläufen mit gelöschten Artikeln"
```

---

## Abschließende manuelle Live-Verifikation (nicht automatisierbar)

Nach Abschluss aller 7 Tasks, vor einem eventuellen Push:

1. Einstellungen → Alte Artikel: Zeitplan-Schalter "Bei App-Start" ist standardmäßig an,
   "An einem bestimmten Wochentag" und "Beim Beenden der App" standardmäßig aus.
2. Wochentag+Uhrzeit aktivieren, Picker bedienen — Auswahl bleibt nach Fenster
   schließen/öffnen erhalten.
3. "Jetzt bereinigen" mit vorhandenen abgelaufenen Artikeln klicken — Toast erscheint im
   Hauptfenster, History-Liste zeigt neuen Eintrag mit Auslöser "Manuell".
4. "Jetzt bereinigen" ohne abgelaufene Artikel (0 gelöscht) — kein Toast, aber History
   bekommt trotzdem einen Eintrag mit "0".
5. App beenden (Cmd+Q) bei aktiviertem "Beim Beenden der App"-Schalter und vorhandenen
   abgelaufenen Artikeln, neu starten — History zeigt einen "App-Beenden"-Eintrag.
6. Mehr als 10 Bereinigungsläufe auslösen (z. B. wiederholt "Jetzt bereinigen" klicken) —
   Liste zeigt nur die neuesten 10.
