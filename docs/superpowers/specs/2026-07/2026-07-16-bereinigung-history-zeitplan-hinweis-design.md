# Design: Bereinigung — History, Zeitplan und Hinweis (Feature 17.3a)

**Datum:** 2026-07-16
**Status:** Zur Review

## Kontext

Feature 17.3 (Automatisches Löschen) läuft produktiv, inklusive einer bereits umgesetzten,
aber noch minimalen Status-Anzeige (Befund C, 2026-07-13/14): der Bereinigung-Tab
("Alte Artikel") zeigt einen "Automatischer Bereinigungsstatus"-Block mit genau dem
**letzten** automatischen Lauf (Zeitpunkt, Erfolg/Fehler, Anzahl gelöschter Artikel),
gespeist aus `UserDefaults` (`ArticleRetentionSettings.lastAutomaticCleanup*`-Keys).

Automatische Bereinigung wird heute an vier unabhängigen Stellen unbedingt ausgelöst,
sobald die globale Bereinigungs-Einstellung aktiv ist:

1. **App-Start** — `ContentView.handleContentAppear()` ruft
   `BackgroundRefreshService.cleanupExpiredArticlesIfNeeded(database:)` auf.
2. **Jeder periodische Hintergrund-Refresh** — derselbe
   `cleanupExpiredArticlesIfNeeded`-Aufruf am Ende von
   `BackgroundRefreshService.refreshAllFeeds(...)` (Befund A, 2026-07-14): läuft bei
   jedem `NSBackgroundActivityScheduler`-Tick, unabhängig von Uhrzeit.
3. **Retention-Einstellungsänderung** — `FeedivoApp.cleanupExpiredArticlesIfNeeded()`,
   angehängt an vier `.onChange`-Handler in `FeedivoApp.swift` (Toggle, Tage,
   Mindestanzahl, Stern/Archiv-Einschluss).
4. **Manueller Button** — `CleanupSettingsView.runArticleRetentionCleanup()` in
   `SettingsView.swift`, ruft direkt `ArticleRetentionCleanupService
   .removeExpiredSQLiteArticles(...)` auf (nicht über `runAutomaticCleanup`), mit
   eigenem lokalem Ergebnis-/Fehlertext unter dem Button.

17.3a baut auf dieser Basis drei zusätzliche Bausteine:

1. **History** der letzten 10 Bereinigungsläufe (statt nur des letzten).
2. **Konfigurierbarer Zeitplan** mit drei unabhängig schaltbaren Auslösern: App-Start,
   bestimmter Wochentag+Uhrzeit, App-Beenden. Ersetzt den heutigen unbedingten
   Trigger #2 (jeder Hintergrund-Refresh-Zyklus).
3. **Sichtbarer In-App-Toast** im Hauptfenster bei jedem Lauf mit tatsächlich gelöschten
   Artikeln — manuell wie automatisch ausgelöst.

## Ziele

1. Die letzten 10 Bereinigungsläufe (Zeitpunkt, Anzahl gelöschter Artikel bzw. Fehler,
   Auslöser) persistent und einsehbar machen — ersetzt den heutigen Einzel-Status-Block.
2. Drei unabhängig konfigurierbare automatische Ausläser: App-Start (Default an, bewahrt
   heutiges Verhalten), Wochentag+Uhrzeit (Default aus, neu), App-Beenden (Default aus,
   neu).
3. Der heutige unbedingte Trigger bei *jedem* Hintergrund-Refresh-Zyklus entfällt —
   automatische Bereinigung läuft künftig nur noch, wenn einer der drei Zeitplan-Schalter
   das erlaubt.
4. In-App-Toast im Hauptfenster ("{N} Artikel bereinigt") bei jedem Lauf mit
   `deletedCount > 0`, egal ob manuell oder automatisch ausgelöst; kein Toast bei 0
   gelöschten Artikeln.

## Nicht-Ziele

- Kein Toast bei 0 gelöschten Artikeln (bewusste Nutzerentscheidung — vermeidet
  bedeutungsloses Aufploppen bei jedem App-Start).
- Keine Änderung an der eigentlichen Lösch-/Schutzlogik (`shouldRemove`,
  Mindestanzahl-pro-Feed-Schutz, `wasRemovedByRetention`-Sperre) — 17.3a ist reine
  Sichtbarkeit + Zeitplan, keine neue Bereinigungssemantik.
- Die Retention-Settings-Änderung als Trigger (#3 oben) bleibt unverändert unbedingt —
  gehört nicht zu den drei in FEATURES.md geplanten Zeitplan-Optionen.
- Keine exakte Echtzeit-Alarmierung für Wochentag+Uhrzeit (App läuft nicht durchgehend) —
  stattdessen Nachhol-Semantik (siehe unten).

## Datenmodell: History

Neue Migration `v18_create_cleanup_run_history` (aktueller Stand laut
`FeedivoDatabaseMigrator.swift` ist `v17_add_smart_folder_default_shows_read_articles` —
**vor Implementierung per `grep -n registerMigration` erneut den tatsächlichen letzten
Stand prüfen**, nicht diese Spec als Quelle der Wahrheit nehmen, siehe bekannter Gotcha
in CLAUDE.md):

```swift
migrator.registerMigration("v18_create_cleanup_run_history") { database in
    try database.create(table: "cleanup_runs") { table in
        table.column("id", .text).notNull().primaryKey()
        table.column("executedAt", .datetime).notNull()
        table.column("deletedCount", .integer).notNull()
        table.column("triggerSource", .text).notNull()
        table.column("succeeded", .boolean).notNull()
        table.column("errorMessage", .text)
    }
    try database.create(
        index: "idx_cleanup_runs_executedAt",
        on: "cleanup_runs",
        columns: ["executedAt"]
    )
}
```

Neues `Feedivo/Database/Records/CleanupRunRecord.swift`:

```swift
struct CleanupRunRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "cleanup_runs"

    var id: String
    var executedAt: Date
    var deletedCount: Int
    var triggerSource: String
    var succeeded: Bool
    var errorMessage: String?
}
```

Neues `Feedivo/Stores/CleanupRunHistoryStore.swift` — ein Store pro Tabelle, analog zu
`FeedLogStore`:

```swift
enum CleanupRunHistoryStore {
    static let maxEntries = 10

    static func record(
        triggerSource: CleanupRunTrigger,
        deletedCount: Int,
        succeeded: Bool,
        errorMessage: String?,
        now: Date,
        database: FeedivoDatabase
    ) throws {
        try database.write { db in
            try CleanupRunRecord(
                id: UUID().uuidString,
                executedAt: now,
                deletedCount: deletedCount,
                triggerSource: triggerSource.rawValue,
                succeeded: succeeded,
                errorMessage: errorMessage
            ).insert(db)

            // Nur die neuesten maxEntries behalten.
            try db.execute(sql: """
                DELETE FROM cleanup_runs
                WHERE id NOT IN (
                    SELECT id FROM cleanup_runs
                    ORDER BY executedAt DESC
                    LIMIT ?
                )
                """, arguments: [maxEntries])
        }
    }

    static func recentRuns(database: FeedivoDatabase) throws -> [CleanupRunRecord] {
        try database.read { db in
            try CleanupRunRecord
                .order(Column("executedAt").desc)
                .limit(maxEntries)
                .fetchAll(db)
        }
    }
}
```

Neues `CleanupRunTrigger`-Enum (in `Feedivo/Models/`, nach dem Muster der übrigen reinen
Value-Type-Enums dort):

```swift
enum CleanupRunTrigger: String, Codable {
    case manual
    case appStart
    case schedule
    case onQuit
    case settingsChange
}
```

## `ArticleRetentionCleanupService.runAutomaticCleanup` erweitern

Bekommt einen neuen Pflichtparameter `triggerSource: CleanupRunTrigger` (bewusst ohne
Default — zwingt jede Aufrufstelle zur expliziten Angabe) und wird `@discardableResult`,
damit der manuelle Aufrufer weiterhin `removedCount`/Fehler für seine eigene lokale
Inline-Anzeige bekommt:

```swift
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
        let removedCount = try removeExpiredSQLiteArticles(...)
        recordAutomaticCleanupSuccess(removedCount: removedCount, now: now, userDefaults: userDefaults)
        try? CleanupRunHistoryStore.record(
            triggerSource: triggerSource, deletedCount: removedCount,
            succeeded: true, errorMessage: nil, now: now, database: database
        )
        if removedCount > 0 {
            CleanupToastSignal.notify(deletedCount: removedCount, in: userDefaults)
        }
        return .success(removedCount)
    } catch {
        recordAutomaticCleanupFailure(error.localizedDescription, now: now, userDefaults: userDefaults)
        try? CleanupRunHistoryStore.record(
            triggerSource: triggerSource, deletedCount: 0,
            succeeded: false, errorMessage: error.localizedDescription, now: now, database: database
        )
        AppLogger.dataAccess.error("Automatisches Retention-Cleanup: \(error.localizedDescription, privacy: .public)")
        return .failure(error)
    }
}
```

Der History-Schreibvorgang selbst nutzt bewusst `try?` (analog zum bestehenden
`logIfThrows`-Muster) — ein Fehler beim Loggen der History darf die eigentliche
Bereinigung nicht rückwirkend als fehlgeschlagen erscheinen lassen.

**Alle vier bestehenden Aufrufstellen werden angepasst:**

- `BackgroundRefreshService.cleanupExpiredArticlesIfNeeded` → aufgeteilt in zwei
  getrennte Funktionen (siehe nächster Abschnitt), beide übergeben ihren jeweiligen
  `triggerSource`.
- `FeedivoApp.cleanupExpiredArticlesIfNeeded()` → `triggerSource: .settingsChange`,
  unverändert unbedingt.
- `CleanupSettingsView.runArticleRetentionCleanup()` → ruft künftig
  `ArticleRetentionCleanupService.runAutomaticCleanup(..., triggerSource: .manual)` statt
  `removeExpiredSQLiteArticles(...)` direkt, liest `removedCount`/Fehler aus dem
  zurückgegebenen `Result` für die bestehende lokale Inline-Anzeige.

## Zeitplan-Architektur

Neues `Feedivo/Services/CleanupScheduleSettings.swift`, nach dem etablierten Muster von
`NotificationSettings`/`CloudSyncSettings` (`object(forKey:) != nil`-Guard gegen den
UserDefaults-Default-Bug):

```swift
enum CleanupScheduleSettings {
    static let runOnAppStartKey = "cleanupSchedule.runOnAppStart"
    static let defaultRunOnAppStart = true

    static let runOnWeekdayTimeKey = "cleanupSchedule.runOnWeekdayTime"
    static let defaultRunOnWeekdayTime = false

    static let weekdayKey = "cleanupSchedule.weekday"          // 1...7, Calendar.weekday
    static let defaultWeekday = 1                              // Sonntag

    static let timeMinutesKey = "cleanupSchedule.timeMinutes"  // 0...1439 Minuten seit Mitternacht
    static let defaultTimeMinutes = 180                        // 03:00

    static let runOnQuitKey = "cleanupSchedule.runOnQuit"
    static let defaultRunOnQuit = false

    static let lastScheduleRunAtKey = "cleanupSchedule.lastScheduleRunAt"

    static func runOnAppStart(in defaults: UserDefaults = .standard) -> Bool { ... }
    static func runOnWeekdayTime(in defaults: UserDefaults = .standard) -> Bool { ... }
    static func runOnQuit(in defaults: UserDefaults = .standard) -> Bool { ... }

    /// Nachhol-Prüfung: liefert true, wenn der konfigurierte Wochentag+Uhrzeit seit dem
    /// letzten geloggten Zeitplan-Lauf bereits erreicht/verstrichen ist. Wird bei jeder
    /// Gelegenheit aufgerufen (App-Start, jeder Hintergrund-Refresh-Tick,
    /// Vordergrund-Wechsel) statt exakter Alarmierung — Feedivo läuft nicht
    /// durchgehend, ein verpasster Zeitpunkt muss beim nächsten Kontakt nachgeholt
    /// werden, nicht komplett ausfallen.
    static func isWeekdayTimeScheduleDue(
        now: Date,
        calendar: Calendar = .current,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard runOnWeekdayTime(in: defaults) else { return false }
        let mostRecentDue = mostRecentOccurrence(
            weekday: weekday(in: defaults), timeMinutes: timeMinutes(in: defaults),
            atOrBefore: now, calendar: calendar
        )
        guard let lastRunAt = defaults.object(forKey: lastScheduleRunAtKey) as? Date else {
            return true // noch nie gelaufen → fällig
        }
        return mostRecentDue > lastRunAt
    }

    static func recordScheduleRun(now: Date, in defaults: UserDefaults = .standard) {
        defaults.set(now, forKey: lastScheduleRunAtKey)
    }

    /// Letzter Zeitpunkt in der Vergangenheit (oder jetzt), an dem weekday+timeMinutes
    /// zugetroffen hätte — reine Kalenderarithmetik, kein Datenbankzugriff. Algorithmus:
    /// ausgehend von `now` rückwärts bis zum letzten Auftreten von `weekday` gehen
    /// (0...6 Tage zurück) und dort `timeMinutes` als Uhrzeit setzen. Liegt dieser
    /// Zeitpunkt NACH `now` — der Fall, wenn heute bereits der Zielwochentag ist, die
    /// Zielzeit heute aber noch nicht erreicht wurde —, zusätzlich exakt 7 Tage
    /// zurückrechnen (das heutige Vorkommen zählt erst, sobald die Uhrzeit auch wirklich
    /// erreicht ist).
    private static func mostRecentOccurrence(
        weekday: Int, timeMinutes: Int, atOrBefore now: Date, calendar: Calendar
    ) -> Date { ... }
}
```

**Aufrufstellen:**

- **App-Start** — `BackgroundRefreshService.cleanupOnAppStartIfNeeded(database:userDefaults:now:)`
  (ersetzt den bisherigen `cleanupExpiredArticlesIfNeeded`-Aufruf in
  `ContentView.handleContentAppear`): prüft `CleanupScheduleSettings.runOnAppStart(in:)`,
  ruft bei `true` `runAutomaticCleanup(..., triggerSource: .appStart)`.
- **Zeitplan** — `BackgroundRefreshService.cleanupOnScheduleIfDue(database:userDefaults:now:)`
  (ersetzt den bisherigen unbedingten Aufruf am Ende von `refreshAllFeeds`): prüft
  `CleanupScheduleSettings.isWeekdayTimeScheduleDue(now:in:)`, ruft bei `true`
  `runAutomaticCleanup(..., triggerSource: .schedule)` und anschließend
  `CleanupScheduleSettings.recordScheduleRun(now:)` — unabhängig vom Enable-Zustand der
  globalen Bereinigung selbst wird `isEnabled` weiterhin aus den bestehenden
  Retention-Settings gelesen und an `runAutomaticCleanup` durchgereicht (kein
  Doppel-Gate: der Zeitplan-Schalter entscheidet *ob geprüft wird*, die globale
  Bereinigungs-Einstellung entscheidet wie bisher *ob tatsächlich gelöscht wird*).
- **App-Beenden** — neuer `FeedivoAppDelegate.applicationWillTerminate(_:)`: prüft
  `CleanupScheduleSettings.runOnQuit(in:)`, feuert bei `true` einen **fire-and-forget**
  `Task { ArticleRetentionCleanupService.runAutomaticCleanup(..., triggerSource: .onQuit) }`
  auf `menubarFeedivoDatabase`, **ohne** den Quit-Vorgang zu blockieren oder abzuwarten.
  Bewusst best-effort: ein durch die Terminierung abgebrochener Lauf ist unkritisch, die
  nächste Gelegenheit (App-Start oder Zeitplan) holt ihn nach.

Der heutige unbedingte Aufruf in `refreshAllFeeds` entfällt ersatzlos zugunsten von
`cleanupOnScheduleIfDue`.

## In-App-Toast

Neues `Feedivo/Services/CleanupToastSignal.swift` — folgt demselben
Bump-Counter-Muster wie `SQLiteDataInvalidation` (kein `@Query`/Observation-Mechanismus
bei GRDB, siehe CLAUDE.md „Kernarchitektur"):

```swift
enum CleanupToastSignal {
    static let versionKey = "cleanupToast.version"
    static let deletedCountKey = "cleanupToast.deletedCount"

    static func notify(deletedCount: Int, in defaults: UserDefaults = .standard) {
        defaults.set(defaults.integer(forKey: versionKey) + 1, forKey: versionKey)
        defaults.set(deletedCount, forKey: deletedCountKey)
    }
}
```

`ContentView` bekommt zwei neue `@AppStorage`-Properties (`cleanupToastVersion`,
`cleanupToastDeletedCount`) plus einen neuen `@State private var activeCleanupToast:
CleanupToast?` mit `.onChange(of: cleanupToastVersion)`, das bei einem neuen Wert (und
`cleanupToastDeletedCount > 0`) `activeCleanupToast` setzt und nach ca. 4 Sekunden per
`Task.sleep` wieder auf `nil` zurücksetzt. Neue leichtgewichtige `CleanupToastView`
(eigene kleine Datei oder private Struct in `ContentView.swift`, visuell an
`FeedRefreshStatusControl` angelehnt — Capsule, `.regularMaterial`, gleiche
Schriftgrößen —, aber ein eigenständiges Overlay statt Teil von
`BottomStatusIndicators`, da Letzteres eng an feed-refresh-spezifischen State gekoppelt
ist). Platzierung: `.overlay(alignment: .bottom)` mittig über der Statusleiste, mit
`.transition(.move(edge: .bottom).combined(with: .opacity))`.

Sowohl `runAutomaticCleanup` (automatische Läufe) als auch der manuelle Button (der ab
jetzt ebenfalls durch `runAutomaticCleanup` läuft) triggern denselben Signalweg — kein
separater Code-Pfad nötig.

## UI: Einstellungen „Bereinigung"

`CleanupSettingsView` in `SettingsView.swift`:

1. Bestehende Zeilen (Bereinigung an/aus, Tage-Picker, Mindestanzahl, Stern/Archiv
   einschließen, "Jetzt bereinigen"-Button) bleiben unverändert.
2. **Neuer Abschnitt „Zeitplan"** (eigener `SettingsBlock`, unterhalb des bestehenden):
   - Toggle „Bei App-Start" (`runOnAppStart`)
   - Toggle „An einem bestimmten Wochentag" (`runOnWeekdayTime`) + bei aktiviertem
     Schalter: `Picker` für Wochentag (`Calendar.current.weekdaySymbols`) +
     `DatePicker(.hourAndMinute)` für die Uhrzeit
   - Toggle „Beim Beenden der App" (`runOnQuit`)
3. **Der bestehende „Automatischer Bereinigungsstatus"-Block wird ersetzt** durch eine
   neue `CleanupHistoryView`: lädt beim Erscheinen (und bei `.onChange` des bestehenden
   `SQLiteDataInvalidation.statusVersion`, da eine Bereinigung Artikel löscht) die
   letzten 10 `CleanupRunRecord`s über `CleanupRunHistoryStore.recentRuns(database:)`.
   Pro Zeile: formatiertes Datum, `triggerSource`-Icon+Text (manuell/App-Start/
   Zeitplan/App-Beenden/Einstellungsänderung), Anzahl gelöschter Artikel bzw. bei
   `succeeded == false` der Fehlertext in `theme.destructiveText`-artiger Farbe
   (analog zum bestehenden `RuleWizardView`-Muster für Vorschau-Fehler).
   Leerer Zustand („Noch keine Bereinigung ausgeführt") bei leerer History.

## Neue L10n-Keys

- `settings.cleanupSchedule.appStart.title` / `.description`
- `settings.cleanupSchedule.weekdayTime.title` / `.description`
- `settings.cleanupSchedule.onQuit.title` / `.description`
- `settings.cleanupHistory.title` / `.description` / `.empty`
- `settings.cleanupHistory.trigger.manual` / `.appStart` / `.schedule` / `.onQuit` /
  `.settingsChange`
- `cleanupToast.message` (Format mit `{N}` Platzhalter, z. B. per
  `String(format:)`/`L10n`-Interpolationsmuster wie bestehende Count-basierte Keys, siehe
  `L10n.settingsArticleRetentionResult(count:)`)

**Wichtig (bekannter Gotcha):** Alle neuen `L10n.swift`-Keys nach Implementierung per
`grep -c "<key>" Feedivo/Resources/Localizable.xcstrings` prüfen, da indirekt
referenzierte Keys keinen automatischen Stub-Eintrag erzeugen.

## Tests

- `CleanupRunHistoryStoreTests`: `record(...)` fügt ein, trimmt korrekt auf `maxEntries`
  bei mehr als 10 Läufen (ältester fällt raus), `recentRuns` liefert absteigend sortiert.
- `CleanupScheduleSettingsTests`: `isWeekdayTimeScheduleDue` mit leerem `lastRunAt` (immer
  fällig), mit `lastRunAt` nach der letzten Sollzeit (nicht fällig), mit `lastRunAt` vor
  der letzten Sollzeit (fällig — Nachhol-Fall über mehrere Tage Differenz), mit
  deaktiviertem Schalter (nie fällig unabhängig vom Datum). `runOnAppStart`/`runOnQuit`
  Default-Fallback-Tests analog zum bestehenden `NotificationSettingsTests`-Muster.
- `ArticleRetentionCleanupServiceTests`: `runAutomaticCleanup` schreibt bei Erfolg und bei
  Fehler jeweils einen `CleanupRunRecord`; setzt `CleanupToastSignal` nur bei
  `removedCount > 0`, nicht bei `0`.
- `BackgroundRefreshServiceTests`: `cleanupOnScheduleIfDue` ruft die Bereinigung nur bei
  fälligem Zeitplan auf, `cleanupOnAppStartIfNeeded` nur bei aktivem Schalter.
- Kein automatisierter Test für `applicationWillTerminate` (kein Mock-Seam für
  App-Terminierung im Projekt) — manuell zu verifizieren.

## Risiken / offene Punkte

- **App-Beenden ist best-effort:** `applicationWillTerminate` garantiert keine
  Ausführungszeit für asynchrone Arbeit; ein während der Terminierung abgebrochener
  GRDB-Schreibvorgang ist bewusst in Kauf genommen (deine Entscheidung) — nächste
  Gelegenheit holt ihn nach.
- **Kein exaktes Timing für Wochentag+Uhrzeit:** Nachhol-Semantik bedeutet, dass ein
  fälliger Lauf ggf. erst Stunden nach dem konfigurierten Zeitpunkt tatsächlich ausgeführt
  wird (abhängig davon, wann als nächstes App-Start/Hintergrund-Refresh-Tick/
  Vordergrund-Wechsel stattfindet) — akzeptiert, da Feedivo keine dauerhaft laufende
  Hintergrund-Instanz mit exakter Alarmierung ist.
- **Verhaltensänderung für Bestandsnutzer:** Der heutige unbedingte Trigger bei jedem
  Refresh-Zyklus entfällt vollständig; nur `runOnAppStart` bleibt standardmäßig aktiv.
  Nutzer, die sich auf häufige Zwischen-Bereinigung während langer Sessions verlassen
  haben, müssen den Wochentag+Uhrzeit-Schalter aktiv einschalten.
- **Manuelle Live-Verifikation nötig** für: Toast-Timing/Optik, Wochentag+Uhrzeit-Picker
  UX, App-Beenden-Pfad (lässt sich nur bedingt automatisiert testen), Nachhol-Verhalten
  nach mehrtägiger App-Abwesenheit.
