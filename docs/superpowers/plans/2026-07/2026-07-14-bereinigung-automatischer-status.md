# Persistenter Status für automatische Bereinigung — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Der letzte automatische Bereinigungslauf (App-Start, Hintergrund-Refresh,
Feed-Einstellungsänderung) wird persistent festgehalten und in den Einstellungen sichtbar
gemacht — analog zum bereits bestehenden Aktualisierungsstatus für den Feed-Refresh.

**Architecture:** Ein neuer gemeinsamer Einstiegspunkt
`ArticleRetentionCleanupService.runAutomaticCleanup(...)` ersetzt die bisher dreifach
duplizierte `logIfThrows { try removeExpiredSQLiteArticles(...) }`-Stelle in allen
automatischen Aufrufern und schreibt Ergebnis/Fehler in neue `UserDefaults`-Keys. Ein neuer
UI-Block in den Einstellungen liest diese Keys und zeigt sie an — im selben visuellen Stil
wie der bestehende Aktualisierungsstatus-Block.

**Tech Stack:** SwiftUI (macOS 14+), GRDB/SQLite, `UserDefaults`/`@AppStorage`.

## Global Constraints

- Kommentare im Code auf Deutsch.
- Verlässliche Verifikation ausschließlich über einen echten `xcodebuild build`-Lauf, nicht
  über SourceKit/IDE-Diagnosen.
- Für `SettingsView.swift`-Views existieren projektweit keine dedizierten View-Unit-Tests —
  Verifikation dieser Anteile erfolgt über Build-Erfolg plus manuelle Prüfung.
- Der manuelle "Jetzt bereinigen"-Button (`SettingsView.swift`, `runArticleRetentionCleanup()`)
  bleibt vollständig unverändert — er aktualisiert die neuen Keys NICHT (Nutzerentscheidung
  2026-07-14: automatische und manuelle Läufe bleiben getrennt sichtbar).
- Der Fehlerpfad von `runAutomaticCleanup` selbst wird NICHT per erzwungenem DB-Fehler
  getestet (vorbestehende, dokumentierte Einschränkung: keine DB-Fehler-Injektion in diesem
  Projekt) — nur die reinen Recording-Funktionen (`recordAutomaticCleanupSuccess`/
  `recordAutomaticCleanupFailure`) werden isoliert unit-getestet.
- Build-Befehl für alle Verifikations-Schritte:
  `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo build`

---

### Task 1: Neue Keys + `runAutomaticCleanup` in `ArticleRetentionCleanupService`

**Files:**
- Modify: `Feedivo/Services/ArticleRetentionSettings.swift`
- Modify: `Feedivo/Services/ArticleRetentionCleanupService.swift`
- Test: `FeedivoTests/ArticleRetentionCleanupServiceTests.swift`

**Interfaces:**
- Produces: `ArticleRetentionSettings.lastAutomaticCleanupDateKey/StatusKey/ErrorKey/RemovedCountKey: String`,
  `ArticleRetentionSettings.statusSuccess/statusFailed: String` — werden von Task 3 (UI) und
  von den drei Aufrufern in Task 2 konsumiert.
  `ArticleRetentionCleanupService.runAutomaticCleanup(database:isEnabled:retentionDays:minimumArticlesPerFeed:includeProtectedArticles:userDefaults:now:) -> Void`
  (alle Parameter außer `database`/`isEnabled`/`retentionDays` mit Defaults) — wird von allen
  drei Aufrufern in Task 2 anstelle von `removeExpiredSQLiteArticles` aufgerufen.
- Consumes: nichts Neues — nutzt die bereits existierende `removeExpiredSQLiteArticles(...)`.

- [ ] **Step 1: Neue Keys in `ArticleRetentionSettings.swift` ergänzen**

Aktuell (`Feedivo/Services/ArticleRetentionSettings.swift:4-13`):

```swift
enum ArticleRetentionSettings {
    static let isEnabledKey = "articleRetention.isEnabled"
    static let retentionDaysKey = "articleRetention.retentionDays"
    static let minimumArticlesPerFeedKey = "articleRetention.minimumArticlesPerFeed"
    static let includesProtectedArticlesKey = "articleRetention.includesProtectedArticles"
    static let defaultIsEnabled = false
    static let defaultRetentionDays = 90
    static let defaultMinimumArticlesPerFeed = 20
    static let defaultIncludesProtectedArticles = false
```

Ändere zu:

```swift
enum ArticleRetentionSettings {
    static let isEnabledKey = "articleRetention.isEnabled"
    static let retentionDaysKey = "articleRetention.retentionDays"
    static let minimumArticlesPerFeedKey = "articleRetention.minimumArticlesPerFeed"
    static let includesProtectedArticlesKey = "articleRetention.includesProtectedArticles"
    static let lastAutomaticCleanupDateKey = "articleRetention.lastAutomaticCleanupDate"
    static let lastAutomaticCleanupStatusKey = "articleRetention.lastAutomaticCleanupStatus"
    static let lastAutomaticCleanupErrorKey = "articleRetention.lastAutomaticCleanupError"
    static let lastAutomaticCleanupRemovedCountKey = "articleRetention.lastAutomaticCleanupRemovedCount"
    static let statusSuccess = "success"
    static let statusFailed = "failed"
    static let defaultIsEnabled = false
    static let defaultRetentionDays = 90
    static let defaultMinimumArticlesPerFeed = 20
    static let defaultIncludesProtectedArticles = false
```

- [ ] **Step 2: Failing Tests für Recording-Funktionen und `runAutomaticCleanup` schreiben**

Füge in `FeedivoTests/ArticleRetentionCleanupServiceTests.swift` am Ende der Struct (vor der
letzten schließenden `}` der Datei) folgenden Block ein:

```swift

    // MARK: - Persistenter Status für automatische Bereinigung (Befund C)

    @Test func recordAutomaticCleanupSuccessSpeichertStatusUndAnzahl() throws {
        let defaults = try temporaryUserDefaults()
        let now = Date(timeIntervalSince1970: 5_000)

        ArticleRetentionCleanupService.recordAutomaticCleanupSuccess(
            removedCount: 7,
            now: now,
            userDefaults: defaults
        )

        #expect(defaults.double(forKey: ArticleRetentionSettings.lastAutomaticCleanupDateKey) == now.timeIntervalSince1970)
        #expect(defaults.string(forKey: ArticleRetentionSettings.lastAutomaticCleanupStatusKey) == ArticleRetentionSettings.statusSuccess)
        #expect(defaults.integer(forKey: ArticleRetentionSettings.lastAutomaticCleanupRemovedCountKey) == 7)
        #expect(defaults.string(forKey: ArticleRetentionSettings.lastAutomaticCleanupErrorKey) == nil)
    }

    @Test func recordAutomaticCleanupFailureSpeichertStatusUndFehlermeldung() throws {
        let defaults = try temporaryUserDefaults()
        let now = Date(timeIntervalSince1970: 5_000)

        ArticleRetentionCleanupService.recordAutomaticCleanupFailure(
            "DB-Fehler",
            now: now,
            userDefaults: defaults
        )

        #expect(defaults.double(forKey: ArticleRetentionSettings.lastAutomaticCleanupDateKey) == now.timeIntervalSince1970)
        #expect(defaults.string(forKey: ArticleRetentionSettings.lastAutomaticCleanupStatusKey) == ArticleRetentionSettings.statusFailed)
        #expect(defaults.string(forKey: ArticleRetentionSettings.lastAutomaticCleanupErrorKey) == "DB-Fehler")
    }

    @Test func runAutomaticCleanupLoeschtArtikelUndSpeichertErfolgsstatus() throws {
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

        ArticleRetentionCleanupService.runAutomaticCleanup(
            database: database,
            isEnabled: true,
            retentionDays: 90,
            minimumArticlesPerFeed: 0,
            userDefaults: defaults,
            now: now
        )

        #expect(try ArticleStatusStore(database: database).status(articleID: expiredID) == nil)
        #expect(defaults.string(forKey: ArticleRetentionSettings.lastAutomaticCleanupStatusKey) == ArticleRetentionSettings.statusSuccess)
        #expect(defaults.integer(forKey: ArticleRetentionSettings.lastAutomaticCleanupRemovedCountKey) == 1)
    }
}

private func temporaryUserDefaults() throws -> UserDefaults {
    let suiteName = "FeedivoTests.ArticleRetentionCleanup.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
```

Achtung: Die Datei endet aktuell mit einer einzelnen schließenden `}` für die Struct
(letzte Zeile). Ersetze GENAU diese letzte `}` durch den obigen Block (der seinerseits mit
`}` die Struct schließt und danach die neue freie Funktion `temporaryUserDefaults()`
ergänzt) — nicht zusätzlich anhängen, sonst entsteht eine doppelte schließende Klammer.

- [ ] **Step 3: Tests ausführen, RED bestätigen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -only-testing:FeedivoTests/ArticleRetentionCleanupServiceTests -destination 'platform=macOS'`
Expected: FAIL — `Type 'ArticleRetentionCleanupService' has no member 'recordAutomaticCleanupSuccess'` (und analog für die anderen beiden neuen Symbole).

- [ ] **Step 4: `runAutomaticCleanup` + Recording-Funktionen implementieren**

In `Feedivo/Services/ArticleRetentionCleanupService.swift` direkt nach dem Ende von
`removeExpiredSQLiteArticles` (nach der schließenden `}` in Zeile 81, vor
`private static func shouldRemove` in Zeile 83) einfügen:

```swift

    /// Führt eine automatische Bereinigung aus (App-Start, Hintergrund-Refresh,
    /// Feed-Einstellungsänderung) und hält Ergebnis/Fehler persistent in
    /// `UserDefaults` fest. Vorher landeten Fehler des automatischen Pfads
    /// ausschließlich im Apple-Systemlog, ohne jede Sichtbarkeit in der App
    /// selbst (Befund C, Nutzer-Report 2026-07-13). Ersetzt die zuvor an drei
    /// Stellen duplizierte `logIfThrows { try removeExpiredSQLiteArticles(...) }`.
    @MainActor
    static func runAutomaticCleanup(
        database: FeedivoDatabase,
        isEnabled: Bool,
        retentionDays: Int,
        minimumArticlesPerFeed: Int = ArticleRetentionSettings.defaultMinimumArticlesPerFeed,
        includeProtectedArticles: Bool = false,
        userDefaults: UserDefaults = .standard,
        now: Date = Date()
    ) {
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
        } catch {
            recordAutomaticCleanupFailure(error.localizedDescription, now: now, userDefaults: userDefaults)
            AppLogger.dataAccess.error("Automatisches Retention-Cleanup: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func recordAutomaticCleanupSuccess(
        removedCount: Int,
        now: Date = Date(),
        userDefaults: UserDefaults = .standard
    ) {
        userDefaults.set(now.timeIntervalSince1970, forKey: ArticleRetentionSettings.lastAutomaticCleanupDateKey)
        userDefaults.set(ArticleRetentionSettings.statusSuccess, forKey: ArticleRetentionSettings.lastAutomaticCleanupStatusKey)
        userDefaults.set(removedCount, forKey: ArticleRetentionSettings.lastAutomaticCleanupRemovedCountKey)
        userDefaults.removeObject(forKey: ArticleRetentionSettings.lastAutomaticCleanupErrorKey)
    }

    static func recordAutomaticCleanupFailure(
        _ message: String,
        now: Date = Date(),
        userDefaults: UserDefaults = .standard
    ) {
        userDefaults.set(now.timeIntervalSince1970, forKey: ArticleRetentionSettings.lastAutomaticCleanupDateKey)
        userDefaults.set(ArticleRetentionSettings.statusFailed, forKey: ArticleRetentionSettings.lastAutomaticCleanupStatusKey)
        userDefaults.set(message, forKey: ArticleRetentionSettings.lastAutomaticCleanupErrorKey)
    }
```

Ergänze außerdem `import OSLog` ganz oben in der Datei (für `AppLogger.dataAccess`, definiert
in `Feedivo/Extensions/SilentErrorLogging.swift`, das bereits `import OSLog` nutzt — dieselbe
`AppLogger`-Instanz wird hier direkt referenziert, kein neuer Logger).

Aktuell (`Feedivo/Services/ArticleRetentionCleanupService.swift:1-2`):

```swift
import Foundation
import GRDB
```

Ändere zu:

```swift
import Foundation
import GRDB
import OSLog
```

- [ ] **Step 5: Tests ausführen, GREEN bestätigen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -only-testing:FeedivoTests/ArticleRetentionCleanupServiceTests -destination 'platform=macOS'`
Expected: PASS — alle Tests (bestehende 10 + 3 neue = 13) grün.

- [ ] **Step 6: Build verifizieren**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo build`
Expected: `** BUILD SUCCEEDED **`. `runAutomaticCleanup` wird an dieser Stelle noch von
niemandem aufgerufen — erwarteter Zwischenzustand, wird in Task 2 verdrahtet.

- [ ] **Step 7: Commit**

```bash
git add Feedivo/Services/ArticleRetentionSettings.swift Feedivo/Services/ArticleRetentionCleanupService.swift FeedivoTests/ArticleRetentionCleanupServiceTests.swift
git commit -m "Feature: Persistenter Status für automatische Bereinigung (Datenschicht)"
```

---

### Task 2: Drei automatische Aufrufer auf `runAutomaticCleanup` umstellen

**Files:**
- Modify: `Feedivo/App/FeedivoApp.swift`
- Modify: `Feedivo/Views/Sidebar/FeedPropertiesView.swift`
- Modify: `Feedivo/Services/BackgroundRefreshService.swift`

**Interfaces:**
- Consumes: `ArticleRetentionCleanupService.runAutomaticCleanup(...)` aus Task 1.
- Produces: keine neuen Interfaces — reine Umleitung, DB-Verhalten unverändert.

- [ ] **Step 1: `FeedivoApp.swift` umstellen**

Aktuell (`Feedivo/App/FeedivoApp.swift:212-223`):

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

Ändere zu:

```swift
    @MainActor
    private func cleanupExpiredArticlesIfNeeded() {
        ArticleRetentionCleanupService.runAutomaticCleanup(
            database: feedivoDatabase,
            isEnabled: articleRetentionIsEnabled,
            retentionDays: articleRetentionDays,
            minimumArticlesPerFeed: articleRetentionMinimumArticlesPerFeed,
            includeProtectedArticles: articleRetentionIncludesProtectedArticles
        )
    }
```

- [ ] **Step 2: `FeedPropertiesView.swift` umstellen**

Aktuell (`Feedivo/Views/Sidebar/FeedPropertiesView.swift:747-756`):

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

Ändere zu:

```swift
        if let feedivoDatabase {
            ArticleRetentionCleanupService.runAutomaticCleanup(
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

- [ ] **Step 3: `BackgroundRefreshService.swift` umstellen**

Aktuell (`Feedivo/Services/BackgroundRefreshService.swift:140-160`):

```swift
    @MainActor
    static func cleanupExpiredArticlesIfNeeded(
        database: FeedivoDatabase,
        userDefaults: UserDefaults = .standard,
        now: Date = Date()
    ) {
        logIfThrows(context: "Automatisches Retention-Cleanup nach Hintergrund-Refresh") {
            _ = try ArticleRetentionCleanupService.removeExpiredSQLiteArticles(
                database: database,
                isEnabled: userDefaults.object(forKey: ArticleRetentionSettings.isEnabledKey) as? Bool
                    ?? ArticleRetentionSettings.defaultIsEnabled,
                retentionDays: userDefaults.object(forKey: ArticleRetentionSettings.retentionDaysKey) as? Int
                    ?? ArticleRetentionSettings.defaultRetentionDays,
                minimumArticlesPerFeed: userDefaults.object(forKey: ArticleRetentionSettings.minimumArticlesPerFeedKey) as? Int
                    ?? ArticleRetentionSettings.defaultMinimumArticlesPerFeed,
                includeProtectedArticles: userDefaults.object(forKey: ArticleRetentionSettings.includesProtectedArticlesKey) as? Bool
                    ?? ArticleRetentionSettings.defaultIncludesProtectedArticles,
                now: now
            )
        }
    }
```

Ändere zu:

```swift
    @MainActor
    static func cleanupExpiredArticlesIfNeeded(
        database: FeedivoDatabase,
        userDefaults: UserDefaults = .standard,
        now: Date = Date()
    ) {
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
            userDefaults: userDefaults,
            now: now
        )
    }
```

- [ ] **Step 4: Bestehende Tests ausführen, Regressionsfreiheit bestätigen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -only-testing:FeedivoTests/BackgroundRefreshServiceTests -destination 'platform=macOS'`
Expected: PASS — alle 10 bestehenden Tests (inkl. der 3 `cleanupExpiredArticlesIfNeeded*`-Tests
aus dem Befund-A-Fix) weiterhin grün, unverändert. Diese Tests prüfen nur DB-Zustand nach
dem Aufruf, nicht die interne Implementierung — die Umleitung auf `runAutomaticCleanup` ändert
daran nichts.

- [ ] **Step 5: Build verifizieren**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add Feedivo/App/FeedivoApp.swift Feedivo/Views/Sidebar/FeedPropertiesView.swift Feedivo/Services/BackgroundRefreshService.swift
git commit -m "Refactor: Automatische Bereinigungs-Aufrufer nutzen runAutomaticCleanup"
```

---

### Task 3: UI-Status-Block in den Einstellungen

**Files:**
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Views/Settings/SettingsView.swift`

**Interfaces:**
- Consumes: `ArticleRetentionSettings.lastAutomaticCleanupDateKey/StatusKey/ErrorKey/RemovedCountKey`,
  `ArticleRetentionSettings.statusSuccess/statusFailed` aus Task 1.
- Produces: keine neuen Interfaces — UI-Endpunkt dieses Features.

- [ ] **Step 1: Neue L10n-Keys ergänzen**

Aktuell (`Feedivo/Resources/L10n.swift:336-343`):

```swift
    static let settingsAutomaticRefreshLastRun = LocalizedStringKey("settings.automaticRefresh.lastRun")
    static let settingsAutomaticRefreshStatus = LocalizedStringKey("settings.automaticRefresh.status")
    static let settingsAutomaticRefreshNextRun = LocalizedStringKey("settings.automaticRefresh.nextRun")
    static let settingsAutomaticRefreshLastError = LocalizedStringKey("settings.automaticRefresh.lastError")
    static let settingsAutomaticRefreshStatusSuccess = LocalizedStringKey("settings.automaticRefresh.status.success")
    static let settingsAutomaticRefreshStatusFailed = LocalizedStringKey("settings.automaticRefresh.status.failed")
    static let settingsAutomaticRefreshStatusPartial = LocalizedStringKey("settings.automaticRefresh.status.partial")
    static let settingsAutomaticRefreshStatusNever = LocalizedStringKey("settings.automaticRefresh.status.never")
```

Ändere zu (bestehende acht Zeilen unverändert, sieben neue danach ergänzt):

```swift
    static let settingsAutomaticRefreshLastRun = LocalizedStringKey("settings.automaticRefresh.lastRun")
    static let settingsAutomaticRefreshStatus = LocalizedStringKey("settings.automaticRefresh.status")
    static let settingsAutomaticRefreshNextRun = LocalizedStringKey("settings.automaticRefresh.nextRun")
    static let settingsAutomaticRefreshLastError = LocalizedStringKey("settings.automaticRefresh.lastError")
    static let settingsAutomaticRefreshStatusSuccess = LocalizedStringKey("settings.automaticRefresh.status.success")
    static let settingsAutomaticRefreshStatusFailed = LocalizedStringKey("settings.automaticRefresh.status.failed")
    static let settingsAutomaticRefreshStatusPartial = LocalizedStringKey("settings.automaticRefresh.status.partial")
    static let settingsAutomaticRefreshStatusNever = LocalizedStringKey("settings.automaticRefresh.status.never")
    static let settingsAutomaticCleanupLastRun = LocalizedStringKey("settings.automaticCleanup.lastRun")
    static let settingsAutomaticCleanupStatus = LocalizedStringKey("settings.automaticCleanup.status")
    static let settingsAutomaticCleanupRemovedCount = LocalizedStringKey("settings.automaticCleanup.removedCount")
    static let settingsAutomaticCleanupLastError = LocalizedStringKey("settings.automaticCleanup.lastError")
    static let settingsAutomaticCleanupStatusSuccess = LocalizedStringKey("settings.automaticCleanup.status.success")
    static let settingsAutomaticCleanupStatusFailed = LocalizedStringKey("settings.automaticCleanup.status.failed")
    static let settingsAutomaticCleanupStatusNever = LocalizedStringKey("settings.automaticCleanup.status.never")
```

- [ ] **Step 2: `statusLine`/`formattedRefreshDate` zu file-privaten Funktionen anheben**

Diese Änderung ist EIN zusammenhängender Suchen/Ersetzen-Block (nicht in Teilschritten
anwenden — die alten Methoden würden sonst nicht eindeutig lokalisierbar sein).

Aktuell (`Feedivo/Views/Settings/SettingsView.swift:918-975`, Ende von
`private struct RefreshSettingsView` bis zum Beginn der nächsten Struct):

```swift
    private func statusLine(title: LocalizedStringKey, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.tertiary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .font(.system(size: 11))
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.85), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func statusLine(title: LocalizedStringKey, value: LocalizedStringKey) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.tertiary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .font(.system(size: 11))
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.85), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var automaticRefreshStatusText: LocalizedStringKey {
        switch lastAutomaticRefreshStatus {
        case BackgroundRefreshSettings.statusSuccess:
            L10n.settingsAutomaticRefreshStatusSuccess
        case BackgroundRefreshSettings.statusFailed:
            L10n.settingsAutomaticRefreshStatusFailed
        case BackgroundRefreshSettings.statusPartial:
            L10n.settingsAutomaticRefreshStatusPartial
        default:
            L10n.settingsAutomaticRefreshStatusNever
        }
    }

    private func formattedRefreshDate(_ timestamp: Double) -> String {
        guard timestamp > 0 else {
            return String(localized: "settings.automaticRefresh.noDate")
        }

        return Date(timeIntervalSince1970: timestamp).formatted(
            date: .abbreviated,
            time: .shortened
        )
    }
}

private struct SyncSettingsView: View {
```

Ändere zu (beide `statusLine`-Overloads und `formattedRefreshDate` — umbenannt zu
`formattedAutomaticStatusDate` — als file-private freie Funktionen NACH der Struct;
`automaticRefreshStatusText` bleibt unverändert als Property INNERHALB der Struct, da sie
struct-eigenen State (`lastAutomaticRefreshStatus`) liest):

```swift
    private var automaticRefreshStatusText: LocalizedStringKey {
        switch lastAutomaticRefreshStatus {
        case BackgroundRefreshSettings.statusSuccess:
            L10n.settingsAutomaticRefreshStatusSuccess
        case BackgroundRefreshSettings.statusFailed:
            L10n.settingsAutomaticRefreshStatusFailed
        case BackgroundRefreshSettings.statusPartial:
            L10n.settingsAutomaticRefreshStatusPartial
        default:
            L10n.settingsAutomaticRefreshStatusNever
        }
    }
}

private func statusLine(title: LocalizedStringKey, value: String) -> some View {
    HStack {
        Text(title)
            .foregroundStyle(.tertiary)
        Spacer()
        Text(value)
            .fontWeight(.medium)
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }
    .font(.system(size: 11))
    .padding(.horizontal, 9)
    .frame(height: 26)
    .background(Color(nsColor: .controlBackgroundColor).opacity(0.85), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
}

private func statusLine(title: LocalizedStringKey, value: LocalizedStringKey) -> some View {
    HStack {
        Text(title)
            .foregroundStyle(.tertiary)
        Spacer()
        Text(value)
            .fontWeight(.medium)
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }
    .font(.system(size: 11))
    .padding(.horizontal, 9)
    .frame(height: 26)
    .background(Color(nsColor: .controlBackgroundColor).opacity(0.85), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
}

private func formattedAutomaticStatusDate(_ timestamp: Double) -> String {
    guard timestamp > 0 else {
        return String(localized: "settings.automaticRefresh.noDate")
    }

    return Date(timeIntervalSince1970: timestamp).formatted(
        date: .abbreviated,
        time: .shortened
    )
}

private struct SyncSettingsView: View {
```

Passe außerdem die beiden Aufrufstellen von `formattedRefreshDate` innerhalb von
`RefreshSettingsView.body` an (aktuell Zeilen 902 und 904):

Aktuell:

```swift
                        statusLine(title: L10n.settingsAutomaticRefreshLastRun, value: formattedRefreshDate(lastAutomaticRefreshTimestamp))
                        statusLine(title: L10n.settingsAutomaticRefreshStatus, value: automaticRefreshStatusText)
                        statusLine(title: L10n.settingsAutomaticRefreshNextRun, value: formattedRefreshDate(nextAutomaticRefreshTimestamp))
```

Ändere zu:

```swift
                        statusLine(title: L10n.settingsAutomaticRefreshLastRun, value: formattedAutomaticStatusDate(lastAutomaticRefreshTimestamp))
                        statusLine(title: L10n.settingsAutomaticRefreshStatus, value: automaticRefreshStatusText)
                        statusLine(title: L10n.settingsAutomaticRefreshNextRun, value: formattedAutomaticStatusDate(nextAutomaticRefreshTimestamp))
```

- [ ] **Step 3: Build verifizieren (Zwischenstand)**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo build`
Expected: `** BUILD SUCCEEDED **`. `RefreshSettingsView` nutzt jetzt die file-privaten freien
Funktionen, Verhalten unverändert.

- [ ] **Step 4: Neue `@AppStorage`-Properties und Status-Block in `CleanupSettingsView` ergänzen**

Aktuell (`Feedivo/Views/Settings/SettingsView.swift:1052-1056`):

```swift
    @AppStorage(ArticleRetentionSettings.includesProtectedArticlesKey)
    private var articleRetentionIncludesProtectedArticles = ArticleRetentionSettings.defaultIncludesProtectedArticles

    @State private var retentionCleanupResult: String?
    @State private var retentionCleanupError: String?
```

Ändere zu:

```swift
    @AppStorage(ArticleRetentionSettings.includesProtectedArticlesKey)
    private var articleRetentionIncludesProtectedArticles = ArticleRetentionSettings.defaultIncludesProtectedArticles

    @AppStorage(ArticleRetentionSettings.lastAutomaticCleanupDateKey)
    private var lastAutomaticCleanupTimestamp = 0.0

    @AppStorage(ArticleRetentionSettings.lastAutomaticCleanupStatusKey)
    private var lastAutomaticCleanupStatus = ""

    @AppStorage(ArticleRetentionSettings.lastAutomaticCleanupErrorKey)
    private var lastAutomaticCleanupError = ""

    @AppStorage(ArticleRetentionSettings.lastAutomaticCleanupRemovedCountKey)
    private var lastAutomaticCleanupRemovedCount = 0

    @State private var retentionCleanupResult: String?
    @State private var retentionCleanupError: String?
```

Aktuell (`Feedivo/Views/Settings/SettingsView.swift:1126-1139`, letzter Teil von
`CleanupSettingsView.body`, direkt vor der schließenden `}` von `SettingsBlock`):

```swift
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
        }
    }
```

Ändere zu:

```swift
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

                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Automatischer Bereinigungsstatus")
                            .font(.system(size: 14))
                        Text("Letzter automatischer Lauf (App-Start, Hintergrund-Refresh, Feed-Einstellungsänderung).")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }

                    VStack(spacing: 5) {
                        statusLine(title: L10n.settingsAutomaticCleanupLastRun, value: formattedAutomaticStatusDate(lastAutomaticCleanupTimestamp))
                        statusLine(title: L10n.settingsAutomaticCleanupStatus, value: automaticCleanupStatusText)

                        if lastAutomaticCleanupStatus == ArticleRetentionSettings.statusSuccess {
                            statusLine(title: L10n.settingsAutomaticCleanupRemovedCount, value: "\(lastAutomaticCleanupRemovedCount)")
                        }

                        if lastAutomaticCleanupStatus == ArticleRetentionSettings.statusFailed, !lastAutomaticCleanupError.isEmpty {
                            statusLine(title: L10n.settingsAutomaticCleanupLastError, value: lastAutomaticCleanupError)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var automaticCleanupStatusText: LocalizedStringKey {
        switch lastAutomaticCleanupStatus {
        case ArticleRetentionSettings.statusSuccess:
            L10n.settingsAutomaticCleanupStatusSuccess
        case ArticleRetentionSettings.statusFailed:
            L10n.settingsAutomaticCleanupStatusFailed
        default:
            L10n.settingsAutomaticCleanupStatusNever
        }
    }
```

- [ ] **Step 5: Build verifizieren**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Manuell prüfen**

App starten, Einstellungen → "Alte Artikel" öffnen. Erwartung: Nach dem App-Start (sofern
Bereinigung aktiviert ist) zeigt der neue Block "Automatischer Bereinigungsstatus" den
aktuellen Zeitstempel, Status "Erfolgreich" und die Anzahl entfernter Artikel (0, sofern
nichts abgelaufen war). Manuelles "Jetzt bereinigen" verändert diesen Block NICHT — nur sein
bereits bestehendes eigenes Ergebnis-/Fehler-Feld direkt darüber. Zusätzlich: bestehender
Aktualisierungsstatus-Block (Feed-Refresh) im Tab "Aktualisierung" sieht optisch unverändert
aus (Refactor in Step 2 darf keine visuelle Änderung verursachen).

- [ ] **Step 7: Commit**

```bash
git add Feedivo/Resources/L10n.swift Feedivo/Views/Settings/SettingsView.swift
git commit -m "Feature: Status-Anzeige für automatische Bereinigung in den Einstellungen"
```
