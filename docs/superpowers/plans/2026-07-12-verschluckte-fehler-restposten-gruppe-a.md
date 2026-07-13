# Restposten Gruppe A — Verschluckte Fehler Implementierungsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Vier Stellen, an denen ein Fehler per `try?`/`catch` komplett verworfen
wird, statt ihn wenigstens sichtbar zu machen, beheben — ohne Kontrollfluss
oder Verhalten im Erfolgsfall zu ändern.

**Architecture:** Alle vier Fixes folgen demselben Muster: ein bislang
stummer Fehlerfall wird geloggt statt verschluckt, das Rückgabeverhalten bei
Erfolg bleibt exakt gleich. Da keiner der vier Fälle eine passende `feedID`
für `FeedLogStore` hat (siehe Global Constraints), wird ein neuer,
projektweiter `os.Logger`-Helfer eingeführt (`Feedivo/Extensions/
SilentErrorLogging.swift`) und in allen vier Fällen wiederverwendet — das ist
zugleich die einzige in dieser Gruppe echt isoliert unit-testbare Logik
(generische Funktion, keine GRDB-Abhängigkeit), alle anderen drei Tasks
verdrahten sie nur in bestehenden View-/Service-Methoden.

**Tech Stack:** SwiftUI, GRDB (SQLite), OSLog, Swift Testing (`@testable
import Feedivo`).

## Global Constraints

- Arbeitsweise für diese Gruppe: Commits direkt auf `main` (Nutzerentscheid,
  konsistent mit allen bisherigen Gruppen dieser Session).
- Kommentare im Code auf Deutsch (Projektkonvention laut CLAUDE.md).
- **Finding 2.5 aus dem ursprünglichen Review (OPML-Import-Refresh-Fehler in
  `SQLiteFeedSubscriptionService.swift:291-293`) ist NICHT Teil dieses Plans.**
  Verifiziert: `SQLiteFeedRefreshService.refresh(feedID:)`
  (`Feedivo/Services/SQLiteFeedRefreshService.swift:162-171`) loggt den
  Fehler bereits selbst über `FeedLogStore` (`level: "error"`,
  `httpStatusCode`, `message: error.localizedDescription`), bevor er ihn an
  `importOPMLFeeds` zurückwirft. Der bestehende Test
  `importOPMLMeldetRefreshFehlerAlsTeilproblem`
  (`FeedivoTests/SQLiteFeedSubscriptionServiceTests.swift:229-264`) beweist
  das bereits (`#expect(logs.contains { $0.level == "error" && … })`). Ein
  zusätzlicher Log-Eintrag im äußeren `catch`-Block von `importOPMLFeeds`
  würde nur ein Duplikat erzeugen, keinen neuen Nutzen stiften.
- **Kein `FeedLogStore` für 2.6 (Retention-Cleanup) und die
  TagStore-Maskierung:** Beide Fehlerfälle sind nicht an eine einzelne
  `feedID` gebunden (Retention-Cleanup ist global, `TagStore.tags()` listet
  über alle Feeds). `feed_logs.feedID` ist zudem `NOT NULL` mit
  `references("feeds", column: "id", onDelete: .cascade)` — ein Log-Eintrag
  für eine nicht (mehr) existierende `feedID` würde selbst einen
  Fremdschlüssel-Fehler werfen.
- **Kein `FeedLogStore` für den Rollback-Cleanup:** Auch dort ist `feedID`
  zwar bekannt, aber der Rollback läuft genau dann, wenn der vorangegangene
  DB-Schreibversuch bereits fehlgeschlagen ist — ob die `feeds`-Zeile zu
  diesem Zeitpunkt noch existiert, ist nicht garantiert. Ein zusätzlicher
  `FeedLogStore`-Schreibversuch während eines bereits fehlgeschlagenen
  DB-Vorgangs wäre selbst fehleranfällig. `os.Logger` (reines Systemlog,
  kein DB-Schreibzugriff) ist hier die robustere Wahl.
- SwiftUI-View-Structs sind in diesem Projekt nicht direkt unit-testbar
  (private Methoden, kein Test-Harness) — Task 2 und Teile von Task 3 werden
  daher nur über einen echten `xcodebuild build`-Lauf verifiziert, nicht über
  neue Unit-Tests (SourceKit-Diagnosen in der IDE sind laut
  CLAUDE.md-Gotcha unzuverlässig).
- Volle Testsuite hängt (CLAUDE.md-Gotcha) — immer gezielt mit
  `-only-testing:FeedivoTests/<SuiteName> -parallel-testing-enabled NO`
  testen.
- Bekannte, dauerhaft vorbestehende Testfehlschläge (siehe CLAUDE.md) nicht
  mit dieser Arbeit verwechseln: 9 Tests in
  `FeedivoAppSceneConfigurationTests.swift`, 2 flaky-unter-Last Tests in
  `FeedViewModelTests.swift`.

---

### Task 1: Gemeinsamer Logging-Helfer (`AppLogger` + `logIfThrows`)

**Files:**
- Create: `Feedivo/Extensions/SilentErrorLogging.swift`
- Test: `FeedivoTests/SilentErrorLoggingTests.swift`

**Interfaces:**
- Produces: `AppLogger.dataAccess: Logger` (öffentliche Konstante), sowie
  `func logIfThrows(context: String, logger: (String) -> Void = ..., _
  operation: () throws -> Void)` (öffentliche, freistehende Funktion, kein
  `throws`, wirft den Fehler von `operation` NICHT weiter). Beide werden von
  Task 2, 3 und 4 konsumiert.

- [ ] **Step 1: Fehlschlagenden Test schreiben**

Neue Datei `FeedivoTests/SilentErrorLoggingTests.swift`:

```swift
import Testing
@testable import Feedivo

struct SilentErrorLoggingTests {
    @Test func logIfThrowsRuftLoggerBeiErfolgNichtAuf() {
        var loggedMessages: [String] = []

        logIfThrows(context: "Test", logger: { loggedMessages.append($0) }) {
            // Kein throw — Erfolgsfall.
        }

        #expect(loggedMessages.isEmpty)
    }

    @Test func logIfThrowsLoggtKontextUndFehlerbeschreibungBeiFehlschlag() {
        struct SampleError: Error, LocalizedError {
            var errorDescription: String? { "Beispiel-Fehler" }
        }
        var loggedMessages: [String] = []

        logIfThrows(context: "Rollback", logger: { loggedMessages.append($0) }) {
            throw SampleError()
        }

        #expect(loggedMessages.count == 1)
        #expect(loggedMessages[0].contains("Rollback"))
        #expect(loggedMessages[0].contains("Beispiel-Fehler"))
    }

    @Test func logIfThrowsWirftDenFehlerNichtAnDenAufruferWeiter() {
        struct SampleError: Error {}

        // Kompiliert nur, wenn logIfThrows selbst nicht `throws` ist — kein
        // `try` am Aufruf nötig. Der Test besteht bereits durch erfolgreiches
        // Durchlaufen ohne Crash/Propagation.
        logIfThrows(context: "Egal", logger: { _ in }) {
            throw SampleError()
        }
    }
}
```

- [ ] **Step 2: Test laufen lassen, Fehlschlag bestätigen**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SilentErrorLoggingTests -parallel-testing-enabled NO`
Expected: BUILD FAILED — `logIfThrows` bzw. `AppLogger` existieren noch nicht.

- [ ] **Step 3: Minimale Implementierung schreiben**

Neue Datei `Feedivo/Extensions/SilentErrorLogging.swift`:

```swift
import OSLog

/// Zentrale `os.Logger`-Instanz für Fehlerfälle, die bewusst NICHT über
/// `FeedLogStore` protokolliert werden — entweder weil kein passendes
/// `feedID` existiert (z. B. globale Vorgänge wie das Retention-Cleanup)
/// oder weil ein erneuter DB-Schreibversuch während eines bereits
/// fehlgeschlagenen DB-Vorgangs selbst riskant wäre (Rollback-Cleanup).
/// Landet im vereinheitlichten Apple-Systemlog (Console.app), nicht in der
/// App-eigenen Datenbank. Vorbild: der bereits bestehende, aber private
/// `Logger` in `ArticleWebContentBlocker` (`WebContentView.swift`).
enum AppLogger {
    static let dataAccess = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ch.martin.Feedivo",
        category: "DataAccess"
    )
}

/// Führt `operation` aus und loggt einen eventuellen Fehler, statt ihn wie
/// bisher per `try?` still zu verschlucken. Der Fehler wird NICHT an den
/// Aufrufer weitergereicht — gedacht für Stellen, die bewusst weiterlaufen
/// wollen, wenn `operation` fehlschlägt, den Fehlschlag aber nicht mehr
/// völlig unsichtbar machen wollen. `logger` ist injizierbar, damit das
/// Verhalten ohne echten Fehlerfall testbar ist.
func logIfThrows(
    context: String,
    logger: (String) -> Void = { message in
        AppLogger.dataAccess.error("\(message, privacy: .public)")
    },
    _ operation: () throws -> Void
) {
    do {
        try operation()
    } catch {
        logger("\(context): \(error.localizedDescription)")
    }
}
```

- [ ] **Step 4: Test laufen lassen, Erfolg bestätigen**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SilentErrorLoggingTests -parallel-testing-enabled NO`
Expected: TEST SUCCEEDED — alle 3 Tests grün.

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Extensions/SilentErrorLogging.swift FeedivoTests/SilentErrorLoggingTests.swift
git commit -m "Add: Gemeinsamer os.Logger-Helfer für bislang stumme try?-Fehlerpfade"
```

---

### Task 2: Finding 2.6 — Retention-Cleanup loggt Fehler statt sie zu verschlucken

**Files:**
- Modify: `Feedivo/App/FeedivoApp.swift:209-218` (`cleanupExpiredArticlesIfNeeded`)
- Modify: `Feedivo/Views/Sidebar/FeedPropertiesView.swift:748-759` (Ende von `syncFeedRetentionSettings`)

**Interfaces:**
- Consumes: `logIfThrows(context:logger:_:)` aus Task 1.

**Vorher (`FeedivoApp.swift:209-218`):**
```swift
    @MainActor
    private func cleanupExpiredArticlesIfNeeded() {
        _ = try? ArticleRetentionCleanupService.removeExpiredSQLiteArticles(
            database: feedivoDatabase,
            isEnabled: articleRetentionIsEnabled,
            retentionDays: articleRetentionDays,
            minimumArticlesPerFeed: articleRetentionMinimumArticlesPerFeed,
            includeProtectedArticles: articleRetentionIncludesProtectedArticles
        )
    }
```

- [ ] **Step 1: `FeedivoApp.swift` ändern**

`cleanupExpiredArticlesIfNeeded()` (Zeilen 209-218) ersetzen durch:

```swift
    @MainActor
    private func cleanupExpiredArticlesIfNeeded() {
        logIfThrows(context: "Automatisches Retention-Cleanup beim App-Start") {
            _ = try ArticleRetentionCleanupService.removeExpiredSQLiteArticles(
                database: feedivoDatabase,
                isEnabled: articleRetentionIsEnabled,
                retentionDays: articleRetentionDays,
                minimumArticlesPerFeed: articleRetentionMinimumArticlesPerFeed,
                includeProtectedArticles: articleRetentionIncludesProtectedArticles
            )
        }
    }
```

**Vorher (`FeedPropertiesView.swift:748-759`):**
```swift
        if let feedivoDatabase {
            _ = try? ArticleRetentionCleanupService.removeExpiredSQLiteArticles(
                database: feedivoDatabase,
                isEnabled: globalArticleRetentionIsEnabled,
                retentionDays: globalArticleRetentionDays,
                minimumArticlesPerFeed: globalArticleRetentionMinimumArticlesPerFeed,
                includeProtectedArticles: globalArticleRetentionIncludesProtectedArticles
            )
            loadSQLiteArticleMetrics()
            loadSQLiteReadingStatistics()
        }
```

- [ ] **Step 2: `FeedPropertiesView.swift` ändern**

Diesen Block (Ende von `syncFeedRetentionSettings()`, Zeilen 748-759) ersetzen durch:

```swift
        if let feedivoDatabase {
            logIfThrows(context: "Automatisches Retention-Cleanup nach Feed-Einstellungsänderung") {
                _ = try ArticleRetentionCleanupService.removeExpiredSQLiteArticles(
                    database: feedivoDatabase,
                    isEnabled: globalArticleRetentionIsEnabled,
                    retentionDays: globalArticleRetentionDays,
                    minimumArticlesPerFeed: globalArticleRetentionMinimumArticlesPerFeed,
                    includeProtectedArticles: globalArticleRetentionIncludesProtectedArticles
                )
            }
            loadSQLiteArticleMetrics()
            loadSQLiteReadingStatistics()
        }
```

- [ ] **Step 3: Build verifizieren**

Run: `xcodebuild build -scheme Feedivo -destination 'platform=macOS'`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Bestehende Regressionstests laufen lassen**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ArticleRetentionCleanupServiceTests -parallel-testing-enabled NO`
Expected: Alle Tests weiterhin grün (Service-Logik selbst unverändert, nur die
beiden Aufrufstellen loggen jetzt zusätzlich).

- [ ] **Step 5: Commit**

```bash
git add Feedivo/App/FeedivoApp.swift Feedivo/Views/Sidebar/FeedPropertiesView.swift
git commit -m "Fix: Automatisches Retention-Cleanup loggt Fehler statt sie stumm zu verschlucken (Finding 2.6)"
```

---

### Task 3: Abschnitt 3 — TagStore-`try?`-Maskierung loggt Fehler statt „keine Tags" vorzutäuschen

**Files:**
- Modify: `Feedivo/Stores/TagStore.swift` (neue statische Helfer nach `tags(feedID:)`, Zeile 75)
- Modify: `Feedivo/Views/Rules/RuleSettingsView.swift:223`
- Modify: `Feedivo/Views/Rules/RuleWizardView.swift:714-721`
- Modify: `Feedivo/Views/ArticleList/ArticleSearchWindowView.swift:338-345`
- Modify: `Feedivo/Views/Sidebar/FeedPropertiesView.swift:629-639`

**Interfaces:**
- Consumes: `logIfThrows(context:logger:_:)` aus Task 1.
- Produces: `TagStore.tagsIgnoringErrors(database: FeedivoDatabase) ->
  [TagRecord]`, `TagStore.tagsIgnoringErrors(database: FeedivoDatabase,
  feedID: String) -> [TagRecord]` — beide statisch, ersetzen ab jetzt jedes
  `(try? TagStore(...).tags(...)) ?? []` im Projekt.

- [ ] **Step 1: Statische Helfer zu `TagStore.swift` hinzufügen**

In `Feedivo/Stores/TagStore.swift`, direkt nach der bestehenden Methode
`tags(feedID:)` (aktuell Zeile 65-75), einfügen:

```swift

    // MARK: - Fehler-loggende Convenience-Varianten

    /// Wie `tags()`, aber loggt einen DB-Fehler über `logIfThrows` statt ihn
    /// als „keine Tags vorhanden" zu maskieren. Rückgabewert bei Erfolg
    /// unverändert — nur der Fehlerfall wird jetzt sichtbar statt komplett
    /// verschluckt.
    static func tagsIgnoringErrors(database: FeedivoDatabase) -> [TagRecord] {
        var tags: [TagRecord] = []
        logIfThrows(context: "Tags laden") {
            tags = try TagStore(database: database).tags()
        }
        return tags
    }

    /// Wie `tagsIgnoringErrors(database:)`, aber für die feed-gebundene
    /// Tag-Liste (`tags(feedID:)`).
    static func tagsIgnoringErrors(database: FeedivoDatabase, feedID: String) -> [TagRecord] {
        var tags: [TagRecord] = []
        logIfThrows(context: "Feed-Tags laden") {
            tags = try TagStore(database: database).tags(feedID: feedID)
        }
        return tags
    }
```

- [ ] **Step 2: Build verifizieren (neue Helfer kompilieren isoliert)**

Run: `xcodebuild build -scheme Feedivo -destination 'platform=macOS'`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: `RuleSettingsView.swift:223` umstellen**

Vorher:
```swift
        let tags = (try? TagStore(database: database).tags()) ?? []
```

Nachher:
```swift
        let tags = TagStore.tagsIgnoringErrors(database: database)
```

- [ ] **Step 4: `RuleWizardView.swift:714-721` umstellen**

Vorher:
```swift
    private func loadTags() {
        guard let database = feedivoDatabase else {
            tags = []
            return
        }

        tags = (try? TagStore(database: database).tags()) ?? []
    }
```

Nachher:
```swift
    private func loadTags() {
        guard let database = feedivoDatabase else {
            tags = []
            return
        }

        tags = TagStore.tagsIgnoringErrors(database: database)
    }
```

- [ ] **Step 5: `ArticleSearchWindowView.swift:338-345` umstellen**

Vorher:
```swift
    private func loadTags() {
        guard let database else {
            tags = []
            return
        }

        tags = (try? TagStore(database: database).tags()) ?? []
    }
```

Nachher:
```swift
    private func loadTags() {
        guard let database else {
            tags = []
            return
        }

        tags = TagStore.tagsIgnoringErrors(database: database)
    }
```

- [ ] **Step 6: `FeedPropertiesView.swift:629-639` umstellen**

Vorher:
```swift
    private func loadSQLiteTags() {
        guard let database = feedivoDatabase else {
            tags = []
            feedTags = []
            return
        }

        let store = TagStore(database: database)
        tags = (try? store.tags()) ?? []
        feedTags = (try? TagStore(database: database).tags(feedID: feedID)) ?? []
    }
```

Nachher (der lokale `store`, der nur für den ersten Aufruf gebraucht wurde,
entfällt):
```swift
    private func loadSQLiteTags() {
        guard let database = feedivoDatabase else {
            tags = []
            feedTags = []
            return
        }

        tags = TagStore.tagsIgnoringErrors(database: database)
        feedTags = TagStore.tagsIgnoringErrors(database: database, feedID: feedID)
    }
```

- [ ] **Step 7: Build verifizieren**

Run: `xcodebuild build -scheme Feedivo -destination 'platform=macOS'`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 8: Bestehende Regressionstests laufen lassen**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteTagStoreTests -parallel-testing-enabled NO`
Expected: Alle Tests weiterhin grün — `SQLiteTagStoreTests` deckt `TagStore`
selbst ab (die neuen `tagsIgnoringErrors`-Helfer bauen direkt darauf auf).
Die 4 geänderten View-Methoden selbst bleiben unabhängig davon unbedeckt —
siehe Global Constraints zur Nicht-Testbarkeit privater View-Methoden in
diesem Projekt; der grüne Build (Step 7) ist dafür der Nachweis.

- [ ] **Step 9: Commit**

```bash
git add Feedivo/Stores/TagStore.swift Feedivo/Views/Rules/RuleSettingsView.swift Feedivo/Views/Rules/RuleWizardView.swift Feedivo/Views/ArticleList/ArticleSearchWindowView.swift Feedivo/Views/Sidebar/FeedPropertiesView.swift
git commit -m "Fix: TagStore-Ladefehler werden geloggt statt als 'keine Tags' maskiert (Abschnitt 3)"
```

---

### Task 4: Abschnitt 3 — Rollback-Cleanup bei Feed-Add/OPML-Import loggt eigene Fehlschläge

**Files:**
- Modify: `Feedivo/Services/SQLiteFeedSubscriptionService.swift:186-190` (`addFeed`-`catch`)
- Modify: `Feedivo/Services/SQLiteFeedSubscriptionService.swift:274-279` (`importOPMLFeeds`-`catch`)
- Test: `FeedivoTests/SQLiteFeedSubscriptionServiceTests.swift` (nur Regressionslauf, keine neuen Tests — siehe Begründung unten)

**Interfaces:**
- Consumes: `logIfThrows(context:logger:_:)` aus Task 1.

**Vorher (`addFeed`-`catch`, Zeilen 186-190):**
```swift
        } catch {
            try? cleanupSQLiteSubscription(feedID: feedID)
            try? cleanupCreatedFolder(createdFolder)
            throw error
        }
```

- [ ] **Step 1: `addFeed`-`catch`-Block ändern**

```swift
        } catch {
            logIfThrows(context: "Rollback nach addFeed-Fehler (Feed/Artikel-Status löschen)") {
                try cleanupSQLiteSubscription(feedID: feedID)
            }
            logIfThrows(context: "Rollback nach addFeed-Fehler (leeren Ordner entfernen)") {
                try cleanupCreatedFolder(createdFolder)
            }
            throw error
        }
```

**Vorher (`importOPMLFeeds`-`catch`, Zeilen 274-279):**
```swift
            } catch {
                try? cleanupSQLiteSubscription(feedID: feedID)
                try? cleanupCreatedTags(createdTagIDs)
                try? cleanupCreatedFolder(createdFolder)
                throw error
            }
```

- [ ] **Step 2: `importOPMLFeeds`-`catch`-Block ändern**

```swift
            } catch {
                logIfThrows(context: "Rollback nach OPML-Import-Fehler (Feed/Artikel-Status löschen)") {
                    try cleanupSQLiteSubscription(feedID: feedID)
                }
                logIfThrows(context: "Rollback nach OPML-Import-Fehler (neu angelegte Tags entfernen)") {
                    try cleanupCreatedTags(createdTagIDs)
                }
                logIfThrows(context: "Rollback nach OPML-Import-Fehler (leeren Ordner entfernen)") {
                    try cleanupCreatedFolder(createdFolder)
                }
                throw error
            }
```

- [ ] **Step 3: Build verifizieren**

Run: `xcodebuild build -scheme Feedivo -destination 'platform=macOS'`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Vollständige Regressionssuite für diese Datei laufen lassen**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedSubscriptionServiceTests -parallel-testing-enabled NO`
Expected: Alle bestehenden Tests weiterhin grün — insbesondere
`addFeedRaeumtSQLiteFeedNachArticleUpsertFehlerAuf`,
`addFeedRaeumtArticleStatusesNachFehlerNachArticleUpsertAuf`,
`addFeedMitNeuemFolderNameRaeumtOrdnerNachArticleUpsertFehlerAuf`,
`importOPMLRaeumtSQLiteFeedNachFehlerNachFeedSaveAuf`,
`importOPMLBehaeltVorhandenenOrdnerNachRollback`. Diese Tests prüfen bereits,
dass der Rollback selbst erfolgreich durchläuft (Cleanup-Aufrufe schlagen in
keinem bestehenden Test fehl) — `logIfThrows` verhält sich im Erfolgsfall
exakt wie das vorherige `try?` (Operation läuft, kein Log-Aufruf, kein
Fehler nach außen), daher ist an diesen Tests keine Änderung nötig.

Kein neuer Test für „Rollback schlägt selbst fehl und wird geloggt": Das
würde erfordern, `cleanupSQLiteSubscription` (rohes `database.write` mit
SQL) gezielt zum Scheitern zu bringen, ohne die Datenbank für den Rest des
Tests unbrauchbar zu machen — dafür existiert in diesem Projekt keine
Test-Infrastruktur (siehe Global Constraints), und sie für diesen
Nischenfall neu zu bauen wäre unverhältnismäßig. Der Logging-Mechanismus
selbst ist bereits in Task 1 isoliert getestet.

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Services/SQLiteFeedSubscriptionService.swift
git commit -m "Fix: Rollback-Cleanup nach Feed-Add/OPML-Import-Fehler loggt eigene Fehlschläge statt sie stumm zu verschlucken (Abschnitt 3)"
```

---

## Abschließender Whole-Branch-Review

Nach Task 4: gesamten Diff seit dem letzten gepushten Commit (`9dff5fed7`)
gegen diesen Plan und gegen CLAUDE.md prüfen (Opus-Review, wie bei den
Gruppen 1-6). Insbesondere: Finding 2.5 bewusst ausgeklammert (siehe Global
Constraints) — sicherstellen, dass diese Entscheidung im Review-Ergebnis
dokumentiert wird, nicht nur in diesem Plan.
