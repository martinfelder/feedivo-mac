# feed_logs-Bereinigung (Retention) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Alte `feed_logs`-Einträge automatisch und zeitbasiert löschen, um das
im `sidebarFeeds()`-Whole-Branch-Review gefundene unbegrenzte
Tabellenwachstum zu beheben.

**Architecture:** Neue `FeedLogRetentionSettings` (UserDefaults-Wrapper,
analog zu `ArticleRetentionSettings`) + neue Methode
`FeedLogStore.deleteOlderThan(_:)` (reines `DELETE`). Beide werden als
zusätzlicher, von der Artikel-Aufbewahrung unabhängiger Schritt in
`ArticleRetentionCleanupService.runAutomaticCleanup(...)` eingehängt — läuft
dadurch bei jedem bestehenden Trigger (App-Start, Zeitplan, App-Beenden,
Settings-Änderung) automatisch mit, ohne neuen Trigger-Pfad. Neue
Einstellungs-Zeile in `CleanupSettingsView` macht die Aufbewahrungsdauer
konfigurierbar.

**Tech Stack:** Swift, GRDB, SwiftUI, Swift Testing.

## Global Constraints

- Kommentare im Code auf Deutsch.
- Direktes Committen auf `main` (kein Feature-Branch/Worktree).
- `xcodebuild build` muss grün sein.
- Kein Schema-/Migrationsbedarf.
- Neue indirekt referenzierte `L10n.swift`-Keys erzeugen keinen automatischen
  xcstrings-Stub — alle neuen Keys manuell per gezieltem `Edit` (kein
  `json.dump`-Rewrite) in allen 4 Sprachen (de/en/fr/it) ergänzen.
- `xcodebuild test` immer mit `-only-testing:FeedivoTests/<SuiteName>`
  scopen (unscoped hängt).
- feed_logs-Bereinigung läuft **unabhängig** von `articleRetentionIsEnabled`
  — kein eigener Enable/Disable-Schalter, kein Eintrag in
  `CleanupRunHistoryStore`, kein Toast.

---

### Task 1: Datenschicht (`FeedLogRetentionSettings` + `FeedLogStore.deleteOlderThan`)

**Files:**
- Create: `Feedivo/Services/FeedLogRetentionSettings.swift`
- Create: `FeedivoTests/FeedLogRetentionSettingsTests.swift`
- Modify: `Feedivo/Stores/FeedLogStore.swift`
- Modify: `FeedivoTests/SQLiteFeedLogStoreTests.swift`

**Interfaces:**
- Produces: `FeedLogRetentionSettings.retentionDaysKey: String`,
  `FeedLogRetentionSettings.defaultRetentionDays: Int` (= 30),
  `FeedLogRetentionSettings.allowedRetentionDays: [Int]` (= `[7, 14, 30, 60, 90]`),
  `FeedLogRetentionSettings.retentionDays(in: UserDefaults = .standard) -> Int`.
  Produces: `FeedLogStore.deleteOlderThan(_ cutoffDate: Date) throws -> Int`
  (`@discardableResult`).
- Consumed von Task 2 (`ArticleRetentionCleanupService.runAutomaticCleanup`)
  und Task 3 (UI-Picker).

- [ ] **Step 1: Failing Tests für `FeedLogRetentionSettings` schreiben**

Neue Datei `FeedivoTests/FeedLogRetentionSettingsTests.swift`:

```swift
import Foundation
import Testing
@testable import Feedivo

struct FeedLogRetentionSettingsTests {
    @Test func retentionDaysLiefertDefaultBeiFehlendemKey() throws {
        let defaults = try temporaryUserDefaults()
        #expect(FeedLogRetentionSettings.retentionDays(in: defaults) == 30)
    }

    @Test func retentionDaysLiestGespeichertenWert() throws {
        let defaults = try temporaryUserDefaults()
        defaults.set(14, forKey: FeedLogRetentionSettings.retentionDaysKey)
        #expect(FeedLogRetentionSettings.retentionDays(in: defaults) == 14)
    }
}

private func temporaryUserDefaults() throws -> UserDefaults {
    let suiteName = "FeedivoTests.FeedLogRetention.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
```

- [ ] **Step 2: Failing Tests für `FeedLogStore.deleteOlderThan(_:)` ergänzen**

In `FeedivoTests/SQLiteFeedLogStoreTests.swift` (bestehende Datei, aktuell 1
Test `appendLogPersistsNewestFirst`) zwei neue `@Test`-Funktionen innerhalb
des bestehenden `struct SQLiteFeedLogStoreTests`-Blocks ergänzen, direkt nach
`appendLogPersistsNewestFirst`:

```swift
    @Test func deleteOlderThanEntferntNurAeltereEintraege() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let logStore = FeedLogStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))
        try logStore.append(FeedLogRecord(
            id: "old",
            feedID: "feed-1",
            createdAt: Date(timeIntervalSince1970: 1_000),
            level: "info",
            message: "Old"
        ))
        try logStore.append(FeedLogRecord(
            id: "new",
            feedID: "feed-1",
            createdAt: Date(timeIntervalSince1970: 5_000),
            level: "info",
            message: "New"
        ))

        let deletedCount = try logStore.deleteOlderThan(Date(timeIntervalSince1970: 3_000))

        #expect(deletedCount == 1)
        let remaining = try logStore.logs(feedID: "feed-1", limit: 10)
        #expect(remaining.map(\.id) == ["new"])
    }

    @Test func deleteOlderThanFunktioniertBeiLeererTabelle() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let logStore = FeedLogStore(database: database)

        let deletedCount = try logStore.deleteOlderThan(Date())

        #expect(deletedCount == 0)
    }
```

- [ ] **Step 3: Tests ausführen, Fehlschlag bestätigen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedLogStoreTests -only-testing:FeedivoTests/FeedLogRetentionSettingsTests -parallel-testing-enabled NO`
Expected: Kompilierfehler — `FeedLogRetentionSettings`/`deleteOlderThan`
existieren noch nicht.

- [ ] **Step 4: `FeedLogRetentionSettings.swift` implementieren**

Neue Datei `Feedivo/Services/FeedLogRetentionSettings.swift`:

```swift
import Foundation

// Aufbewahrungsdauer für feed_logs-Einträge (reine technische Diagnose-
// Historie pro Feed). Läuft unabhängig von ArticleRetentionSettings — siehe
// ArticleRetentionCleanupService.runAutomaticCleanup, das diese Einstellung
// bei jedem automatischen Bereinigungslauf konsultiert, unabhängig davon, ob
// die Artikel-Aufbewahrung selbst aktiviert ist.
enum FeedLogRetentionSettings {
    static let retentionDaysKey = "feedLogRetention.retentionDays"
    static let defaultRetentionDays = 30
    static let allowedRetentionDays = [7, 14, 30, 60, 90]

    static func retentionDays(in defaults: UserDefaults = .standard) -> Int {
        guard defaults.object(forKey: retentionDaysKey) != nil else {
            return defaultRetentionDays
        }
        return defaults.integer(forKey: retentionDaysKey)
    }
}
```

- [ ] **Step 5: `FeedLogStore.deleteOlderThan(_:)` implementieren**

In `Feedivo/Stores/FeedLogStore.swift` nach der bestehenden Methode
`logs(feedID:limit:)` (vor der schließenden `}` der Struct) ergänzen:

```swift
    /// Löscht alle feed_logs-Einträge, die älter sind als cutoffDate
    /// (Feature feed_logs-Retention) — reines Housekeeping ohne
    /// Nebenbedingungen, anders als die Artikel-Bereinigung (keine
    /// Identity-History, keine Schutz-Ausnahmen wie Stern/Archiv).
    @discardableResult
    func deleteOlderThan(_ cutoffDate: Date) throws -> Int {
        try database.write { db in
            try db.execute(sql: "DELETE FROM feed_logs WHERE createdAt < ?", arguments: [cutoffDate])
            return db.changesCount
        }
    }
```

- [ ] **Step 6: Tests ausführen, Erfolg bestätigen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedLogStoreTests -only-testing:FeedivoTests/FeedLogRetentionSettingsTests -parallel-testing-enabled NO`
Expected: Alle Tests bestehen (3 in `SQLiteFeedLogStoreTests`, 2 in
`FeedLogRetentionSettingsTests`).

- [ ] **Step 7: Build verifizieren**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 8: Commit**

```bash
git add Feedivo/Services/FeedLogRetentionSettings.swift \
  Feedivo/Stores/FeedLogStore.swift \
  FeedivoTests/FeedLogRetentionSettingsTests.swift \
  FeedivoTests/SQLiteFeedLogStoreTests.swift
git commit -m "Feature: FeedLogRetentionSettings + FeedLogStore.deleteOlderThan"
```

---

### Task 2: Integration in `runAutomaticCleanup`

**Files:**
- Modify: `Feedivo/Services/ArticleRetentionCleanupService.swift` (Methode
  `runAutomaticCleanup`, aktuell Zeilen 95-140)
- Modify: `FeedivoTests/ArticleRetentionCleanupServiceTests.swift`

**Interfaces:**
- Consumes: `FeedLogRetentionSettings.retentionDays(in:)` und
  `FeedLogStore.deleteOlderThan(_:)` aus Task 1.
- Produces: keine neuen öffentlichen Interfaces — `runAutomaticCleanup`
  behält Signatur `static func runAutomaticCleanup(database:isEnabled:
  retentionDays:minimumArticlesPerFeed:includeProtectedArticles:
  triggerSource:userDefaults:now:) -> Result<Int, Error>` unverändert.

- [ ] **Step 1: Failing Test schreiben**

In `FeedivoTests/ArticleRetentionCleanupServiceTests.swift`, direkt nach der
bestehenden Testfunktion
`runAutomaticCleanupSetztToastSignalNurBeiTatsaechlichGeloeschtenArtikeln`
(vor der schließenden `}` des `struct`-Blocks, vor `private func
temporaryUserDefaults()`) ergänzen:

```swift
    @Test func runAutomaticCleanupBereinigtFeedLogsUnabhaengigVonIsEnabled() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let defaults = try temporaryUserDefaults()
        let now = Date(timeIntervalSince1970: 10_000_000)
        let feedID = UUID().uuidString

        try FeedStore(database: database).save(
            FeedRecord(id: feedID, url: "https://example.com/feed.xml", title: "Feed")
        )
        try FeedLogStore(database: database).append(FeedLogRecord(
            id: "old-log",
            feedID: feedID,
            createdAt: now.addingTimeInterval(-31 * 24 * 60 * 60),
            level: "info",
            message: "Alt"
        ))
        try FeedLogStore(database: database).append(FeedLogRecord(
            id: "new-log",
            feedID: feedID,
            createdAt: now,
            level: "info",
            message: "Neu"
        ))

        ArticleRetentionCleanupService.runAutomaticCleanup(
            database: database,
            isEnabled: false,
            retentionDays: 90,
            minimumArticlesPerFeed: 0,
            triggerSource: .manual,
            userDefaults: defaults,
            now: now
        )

        let remainingLogs = try FeedLogStore(database: database).logs(feedID: feedID, limit: 10)
        #expect(remainingLogs.map(\.id) == ["new-log"])
    }
```

Dieser Test setzt bewusst `isEnabled: false` (Artikel-Aufbewahrung aus) und
verwendet die Standard-Aufbewahrungsdauer von `FeedLogRetentionSettings`
(30 Tage, da `defaults` frisch/leer ist) — `old-log` liegt 31 Tage zurück
(älter als der 30-Tage-Cutoff, wird gelöscht), `new-log` liegt bei `now`
(bleibt erhalten). Das ist der entscheidende Regressionstest für die
Kopplungs-Entscheidung: feed_logs-Bereinigung darf NICHT von
`articleRetentionIsEnabled` abhängen.

- [ ] **Step 2: Test ausführen, Fehlschlag bestätigen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ArticleRetentionCleanupServiceTests -parallel-testing-enabled NO`
Expected: Der neue Test schlägt fehl (`remainingLogs` enthält noch
`["new-log", "old-log"]` oder in anderer Reihenfolge — `old-log` wurde
noch nicht gelöscht, da die Integration fehlt).

- [ ] **Step 3: Integration implementieren**

In `Feedivo/Services/ArticleRetentionCleanupService.swift`, den Body von
`runAutomaticCleanup` (aktuell direkt beginnend mit `do { let removedCount =
try removeExpiredSQLiteArticles(...`) ersetzen. Alt:

```swift
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
```

Neu:

```swift
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
        // Feed-Log-Bereinigung läuft immer mit, unabhängig vom Artikel-
        // Aufbewahrung-Schalter (isEnabled) — rein internes Housekeeping ohne
        // History-/Toast-Sichtbarkeit (Feature feed_logs-Retention).
        let feedLogCutoff = Calendar.current.date(
            byAdding: .day,
            value: -FeedLogRetentionSettings.retentionDays(in: userDefaults),
            to: now
        ) ?? now
        do {
            try FeedLogStore(database: database).deleteOlderThan(feedLogCutoff)
        } catch {
            AppLogger.dataAccess.error("Feed-Log-Bereinigung: \(error.localizedDescription, privacy: .public)")
        }

        do {
            let removedCount = try removeExpiredSQLiteArticles(
```

(Nur diese Zeilen ändern sich — der Rest der Methode, inklusive dem
`catch`-Block der äußeren `removeExpiredSQLiteArticles`-`do`, bleibt exakt
wie bisher.)

- [ ] **Step 4: Test ausführen, Erfolg bestätigen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ArticleRetentionCleanupServiceTests -parallel-testing-enabled NO`
Expected: Alle Tests in dieser Suite bestehen (der neue Test sowie alle
vorherigen, unverändert grün — insbesondere
`runAutomaticCleanupLoeschtArtikelUndSpeichertErfolgsstatus`,
`runAutomaticCleanupSchreibtHistoryEintragBeiErfolg`,
`runAutomaticCleanupSetztToastSignalNurBeiTatsaechlichGeloeschtenArtikeln`).

- [ ] **Step 5: Build verifizieren**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 6: Bestehende BackgroundRefreshServiceTests grün verifizieren**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/BackgroundRefreshServiceTests -parallel-testing-enabled NO`
Expected: Alle Tests bestehen unverändert (diese Suite ruft
`runAutomaticCleanup` indirekt über `cleanupOnAppStartIfNeeded`/
`cleanupOnScheduleIfDue` auf — die neue feed_logs-Bereinigung darf daran
nichts brechen).

- [ ] **Step 7: Commit**

```bash
git add Feedivo/Services/ArticleRetentionCleanupService.swift \
  FeedivoTests/ArticleRetentionCleanupServiceTests.swift
git commit -m "Feature: runAutomaticCleanup bereinigt feed_logs unabhängig von der Artikel-Aufbewahrung"
```

---

### Task 3: Einstellungen-UI + Lokalisierung

**Files:**
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`
- Modify: `Feedivo/Views/Settings/SettingsView.swift` (`CleanupSettingsView`)

**Interfaces:**
- Consumes: `FeedLogRetentionSettings.retentionDaysKey`,
  `FeedLogRetentionSettings.defaultRetentionDays`,
  `FeedLogRetentionSettings.allowedRetentionDays` aus Task 1.
- Produces: keine neuen Interfaces — reine UI-Ergänzung.

- [ ] **Step 1: Neue L10n-Keys ergänzen**

In `Feedivo/Resources/L10n.swift`, direkt nach Zeile 428
(`static let cleanupHistoryTriggerSettingsChange = LocalizedStringKey("cleanup.history.trigger.settingsChange")`)
und vor Zeile 429 (`static let settingsSyncSection = ...`):

```swift
    static let settingsFeedLogRetentionTitle = LocalizedStringKey("settings.feedLogRetention.title")
    static let settingsFeedLogRetentionDaysTitle = LocalizedStringKey("settings.feedLogRetention.days.title")
    static let settingsFeedLogRetentionDaysDescription = LocalizedStringKey("settings.feedLogRetention.days.description")
```

- [ ] **Step 2: `Localizable.xcstrings`-Einträge ergänzen**

Per **Edit-Tool** (kein `json.dump`-Rewrite) direkt nach dem Ende des
Eintrags `"settings.cleanupSchedule.weekdayTime.title"` einfügen. Anker
(exakter bestehender Text):

```
        }
      }
    },
    "settings.feeds.articleCount.help" : {
```

Ersetzen durch:

```
        }
      }
    },
    "settings.feedLogRetention.days.description" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Wie lange technische Protokolleinträge pro Feed aufbewahrt werden, bevor sie automatisch gelöscht werden."
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "How long technical log entries per feed are kept before being automatically deleted."
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Combien de temps les entrées de journal techniques par flux sont conservées avant d'être automatiquement supprimées."
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Per quanto tempo le voci di registro tecniche per feed vengono conservate prima di essere eliminate automaticamente."
          }
        }
      }
    },
    "settings.feedLogRetention.days.title" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Aufbewahrungsdauer"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Retention Period"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Durée de conservation"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Periodo di conservazione"
          }
        }
      }
    },
    "settings.feedLogRetention.title" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Feed-Protokolle"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Feed Logs"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Journaux des flux"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Registri dei feed"
          }
        }
      }
    },
    "settings.feeds.articleCount.help" : {
```

Nach dem Einfügen: `grep -c "settings.feedLogRetention" Feedivo/Resources/Localizable.xcstrings` muss `3` liefern.

- [ ] **Step 3: Neue `@AppStorage`-Property ergänzen**

In `Feedivo/Views/Settings/SettingsView.swift`, in `CleanupSettingsView`,
direkt nach:

```swift
    @AppStorage(CleanupScheduleSettings.runOnQuitKey)
    private var cleanupRunOnQuit = CleanupScheduleSettings.defaultRunOnQuit
```

und vor:

```swift
    @Environment(\.openWindow) private var openWindow
```

ergänzen:

```swift

    @AppStorage(FeedLogRetentionSettings.retentionDaysKey)
    private var feedLogRetentionDays = FeedLogRetentionSettings.defaultRetentionDays
```

- [ ] **Step 4: Neuen Settings-Block einfügen**

Direkt nach dem Ende des bestehenden "Zeitplan"-`SettingsBlock` und vor dem
"Bereinigungsverlauf"-`SettingsBlock` einfügen. Anker (exakter bestehender
Text):

```swift
                    .padding(.vertical, 4)
                }
            }

            SettingsBlock(eyebrow: L10n.cleanupHistoryTitle) {
```

Ersetzen durch:

```swift
                    .padding(.vertical, 4)
                }
            }

            SettingsBlock(eyebrow: L10n.settingsFeedLogRetentionTitle) {
                SettingRow(
                    title: L10n.settingsFeedLogRetentionDaysTitle,
                    description: L10n.settingsFeedLogRetentionDaysDescription
                ) {
                    Picker(L10n.settingsFeedLogRetentionDaysTitle, selection: $feedLogRetentionDays) {
                        ForEach(FeedLogRetentionSettings.allowedRetentionDays, id: \.self) { days in
                            Text("\(days) Tage")
                                .tag(days)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }

            SettingsBlock(eyebrow: L10n.cleanupHistoryTitle) {
```

- [ ] **Step 5: Build verifizieren**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 6: Repo-weite Grep-Prüfung**

Run: `grep -c "settingsFeedLogRetention" Feedivo/Resources/L10n.swift`
Expected: `3` (drei Vorkommen — jeweils Definition der drei neuen Keys).

- [ ] **Step 7: Commit**

```bash
git add Feedivo/Resources/L10n.swift \
  Feedivo/Resources/Localizable.xcstrings \
  Feedivo/Views/Settings/SettingsView.swift
git commit -m "Feature: Einstellungen-UI für feed_logs-Aufbewahrungsdauer"
```

---

### Task 4: Wirksamkeitsnachweis im Performance-Benchmark

**Files:**
- Modify: `FeedivoTests/SQLiteLargeDatasetPerformanceTests.swift`

**Interfaces:**
- Consumes: `FeedLogStore.deleteOlderThan(_:)`,
  `FeedLogRetentionSettings.defaultRetentionDays` aus Task 1.
- Produces: keine — reine Testergänzung, schließt die im Spec-Dokument unter
  "Risiken / offene Punkte" verlangte Nachmessung ab (der ursprüngliche
  Auslöser dieses gesamten Features war, dass der bestehende Benchmark
  `feed_logs` komplett leer ließ und das Skalierungsrisiko der
  `latest_feed_logs`-CTE dadurch ungemessen blieb).

- [ ] **Step 1: Neuen Seed-Helper + Test schreiben**

In `FeedivoTests/SQLiteLargeDatasetPerformanceTests.swift`, nach der
bestehenden privaten Funktion `measureMilliseconds` (vor `@Suite(.serialized)
struct SQLiteLargeDatasetPerformanceTests {`) einen neuen privaten Helper
ergänzen:

```swift
private func seedFeedLogsHistory(
    database: FeedivoDatabase,
    feedIDs: [String],
    entriesPerFeed: Int,
    now: Date
) throws {
    try database.write { db in
        for feedID in feedIDs {
            for entryIndex in 0..<entriesPerFeed {
                // Genau 1 Eintrag pro Feed bleibt innerhalb der 30-Tage-
                // Standard-Aufbewahrung (1 Tag alt), der Rest liegt bewusst weit
                // außerhalb (200 Tage alt) — macht die erwartete Zeilenzahl nach
                // der Bereinigung deterministisch prüfbar.
                let createdAt = entryIndex == 0
                    ? now.addingTimeInterval(-1 * 24 * 60 * 60)
                    : now.addingTimeInterval(-200 * 24 * 60 * 60)
                try db.execute(
                    sql: """
                        INSERT INTO feed_logs (
                            id, feedID, createdAt, level, message, newArticleCount
                        ) VALUES (?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        "\(feedID)-log-\(entryIndex)",
                        feedID,
                        createdAt,
                        "info",
                        "Refresh \(entryIndex)",
                        1
                    ]
                )
            }
        }
    }
}
```

Und innerhalb von `struct SQLiteLargeDatasetPerformanceTests`, nach der
bestehenden Testfunktion
`sidebarUndArtikelCountsLassenSichSchnellBerechnen` (vor der schließenden `}`
der Struct), einen neuen Test ergänzen:

```swift
    @Test func feedLogsRetentionHaeltSidebarFeedsSchnellBeiGrosserHistorie() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let now = Date()

        let feedIDs = (0..<500).map { "feed-\($0)" }
        try database.write { db in
            for feedID in feedIDs {
                try db.execute(
                    sql: """
                        INSERT INTO feeds (id, url, title, createdAt, updatedAt)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                    arguments: [feedID, "https://example.com/\(feedID).xml", "Feed \(feedID)", now, now]
                )
            }
        }
        try seedFeedLogsHistory(database: database, feedIDs: feedIDs, entriesPerFeed: 200, now: now)

        let totalBeforePruning = try database.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM feed_logs") ?? 0
        }
        #expect(totalBeforePruning == 500 * 200)

        let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -FeedLogRetentionSettings.defaultRetentionDays,
            to: now
        )!
        try FeedLogStore(database: database).deleteOlderThan(cutoff)

        let totalAfterPruning = try database.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM feed_logs") ?? 0
        }
        #expect(totalAfterPruning == 500)

        let sidebarMeasurement = try measureMilliseconds("sidebar_500_feeds_after_feedlog_retention") {
            try feedStore.sidebarFeeds()
        }
        #expect(sidebarMeasurement.value.count == 500)
        #expect(sidebarMeasurement.milliseconds < 1_000)
    }
```

- [ ] **Step 2: Test ausführen**

Run:
```bash
xcodebuild test \
  -project Feedivo.xcodeproj \
  -scheme Feedivo \
  -configuration Release \
  ENABLE_TESTABILITY=YES \
  -destination 'platform=macOS' \
  -only-testing:'FeedivoTests/SQLiteLargeDatasetPerformanceTests/feedLogsRetentionHaeltSidebarFeedsSchnellBeiGrosserHistorie()' \
  -parallel-testing-enabled NO
```
Expected: PASS. Aus der Ausgabe die `PERF_METRIC
sidebar_500_feeds_after_feedlog_retention`-Zeile notieren.

- [ ] **Step 3: Restliche Tests derselben Suite grün verifizieren**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteLargeDatasetPerformanceTests -parallel-testing-enabled NO`
Expected: Alle bestehenden Tests in dieser Suite bleiben unverändert grün
(insbesondere die beiden bereits vom sidebarFeeds()-Performance-Fix
entfernten `withKnownIssue`-Marker bleiben entfernt — dieser Task fügt nur
einen zusätzlichen Test hinzu, ändert keinen bestehenden).

- [ ] **Step 4: Performance-Bericht um Wirksamkeitsnachweis ergänzen**

In `docs/performance/sqlite-large-dataset-results.md`, im Abschnitt
"### Nachmessung nach Query-Umbau (2026-07-16)" (aus dem vorherigen
sidebarFeeds()-Performance-Fix-Plan) einen Satz ergänzen, der auf den neuen
Test verweist, z. B.:

```markdown
Ergänzender Test `feedLogsRetentionHaeltSidebarFeedsSchnellBeiGrosserHistorie`
(feed_logs-Retention-Feature, 2026-07-16) belegt zusätzlich, dass
`sidebarFeeds()` auch nach einer groß befüllten, durch die neue
zeitbasierte `feed_logs`-Bereinigung wieder auf ~500 Zeilen begrenzten
Log-Historie schnell bleibt (< 1000ms) — der im Whole-Branch-Review offen
gelassene Wirksamkeitsnachweis für die `latest_feed_logs`-CTE.
```

- [ ] **Step 5: Commit**

```bash
git add FeedivoTests/SQLiteLargeDatasetPerformanceTests.swift \
  docs/performance/sqlite-large-dataset-results.md
git commit -m "Test: Wirksamkeitsnachweis feed_logs-Retention hält sidebarFeeds() schnell"
```

---

## Abschließende manuelle Live-Verifikation (nicht automatisierbar)

1. Einstellungen → Bereinigung → neuer Block "Feed-Protokolle" sichtbar,
   Picker zeigt 7/14/30/60/90 Tage zur Auswahl, Standardwert 30 Tage.
2. Wert ändern, Einstellungen schließen und neu öffnen — Auswahl bleibt
   erhalten (persistiert über `@AppStorage`).
