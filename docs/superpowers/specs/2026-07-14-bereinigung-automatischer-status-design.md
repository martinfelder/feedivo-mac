# Design-Spec: Persistenter Status für automatische Artikel-Bereinigung

**Datum:** 2026-07-14
**Status:** Zur Nutzer-Review

## Kontext

Bei der Root-Cause-Analyse der automatischen Bereinigung (2026-07-13, Nutzer-Report
"Alte Artikel bleiben trotz aktivierter Bereinigung liegen") wurden drei unabhängige
Befunde gefunden. Befund A (Bereinigung lief nie während einer laufenden Session) und
Befund B (Artikel ohne Veröffentlichungsdatum wurden nie bereinigt) sind bereits behoben
und gepusht. Dieses Dokument spezifiziert Befund C: Der automatische Bereinigungspfad hat
keinerlei UI-Feedback — Fehler landen ausschließlich im Apple-Systemlog
(`AppLogger.dataAccess`), nirgends in der App selbst sichtbar. Nur der manuelle
"Jetzt bereinigen"-Button in den Einstellungen zeigt Ergebnis/Fehler an, und auch das nur
als flüchtigen `@State`-Wert für die aktuelle Sitzung (nicht gespeichert).

## Ziel

Ein persistenter, in den Einstellungen sichtbarer Status für den letzten **automatischen**
Bereinigungslauf (ausgelöst durch App-Start, periodischen Hintergrund-Refresh oder
Feed-Einstellungsänderung) — analog zum bereits bestehenden "Aktualisierungsstatus" für den
automatischen Feed-Refresh (`RefreshSettingsView`, `SettingsView.swift:845-973`).

## Nicht-Ziele

- Der manuelle "Jetzt bereinigen"-Button behält sein bestehendes, unverändertes sofortiges
  `@State`-Feedback (`retentionCleanupResult`/`retentionCleanupError`) — er aktualisiert den
  neuen persistenten Status NICHT (Nutzerentscheidung vom 2026-07-14: automatische und
  manuelle Läufe bleiben getrennt sichtbar, kein gemeinsamer Status).
- Keine Behebung des vorbestehenden, nicht mit diesem Befund verwandten Fehlens einer
  DB-Fehler-Injektionsmöglichkeit für Tests (dokumentiert seit 2026-07-12) — der
  Fehlerpfad von `runAutomaticCleanup` wird daher nur durch isoliert testbare
  Recording-Funktionen abgedeckt, nicht durch eine erzwungene DB-Fehler-Integration.

## Architektur-Überblick

Exakt dasselbe, bereits etablierte Muster wie `BackgroundRefreshSettings`/
`RefreshSettingsView` wird auf die Bereinigung übertragen:

1. **Neue persistente `UserDefaults`-Keys** in `ArticleRetentionSettings.swift`.
2. **Ein neuer, gemeinsamer Einstiegspunkt** `ArticleRetentionCleanupService.runAutomaticCleanup(...)`,
   der aufruft UND das Ergebnis persistent festhält. Ersetzt die bisher dreifach duplizierte
   `logIfThrows { try removeExpiredSQLiteArticles(...) }`-Stelle in allen drei automatischen
   Aufrufern.
3. **Neuer UI-Status-Block** in `CleanupSettingsView` (`SettingsView.swift:1040ff`), visuell
   identisch zum bestehenden Refresh-Status-Block. Dafür werden `statusLine(title:value:)`
   (zwei Overloads) und `formattedRefreshDate(_:)` aus `RefreshSettingsView` zu file-privaten
   freien Funktionen in `SettingsView.swift` angehoben, damit `CleanupSettingsView` sie
   mitnutzen kann, statt sie zu duplizieren (dieselbe Vermeidungs-Logik wie beim
   `ArticleTagAssignmentView`-Refactor vom 2026-07-13). `formattedRefreshDate` wird dabei zu
   `formattedAutomaticStatusDate` umbenannt (generischer Name, da jetzt für zwei
   Status-Blöcke genutzt) — die "noch kein Datum"-Fallback-Zeichenkette
   (`settings.automaticRefresh.noDate`) wird unverändert wiederverwendet, da sie
   inhaltlich nicht refresh-spezifisch ist.

## Komponente 1: Neue Keys in `ArticleRetentionSettings.swift`

```swift
static let lastAutomaticCleanupDateKey = "articleRetention.lastAutomaticCleanupDate"
static let lastAutomaticCleanupStatusKey = "articleRetention.lastAutomaticCleanupStatus"
static let lastAutomaticCleanupErrorKey = "articleRetention.lastAutomaticCleanupError"
static let lastAutomaticCleanupRemovedCountKey = "articleRetention.lastAutomaticCleanupRemovedCount"
static let statusSuccess = "success"
static let statusFailed = "failed"
```

Kein `statusPartial`-Äquivalent nötig: Anders als der Feed-Refresh (der pro Feed
fehlschlagen kann) ist die Bereinigung eine einzelne GRDB-Transaktion — entweder ganz
erfolgreich oder ganz fehlgeschlagen.

## Komponente 2: `ArticleRetentionCleanupService.runAutomaticCleanup(...)`

```swift
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

`recordAutomaticCleanupSuccess`/`recordAutomaticCleanupFailure` sind bewusst NICHT
`@MainActor` und nehmen alle Werte als einfache Parameter — dadurch isoliert unit-testbar
(reine `UserDefaults`-Schreiblogik, kein DB-Zugriff, kein erzwungener Fehlerfall nötig).
`runAutomaticCleanup` selbst bleibt `@MainActor` wie `removeExpiredSQLiteArticles`. Der
`AppLogger`-Aufruf im `catch`-Zweig bleibt erhalten (Console.app-Sichtbarkeit geht nicht
verloren, UI-Status kommt zusätzlich dazu).

### Anpassung der drei automatischen Aufrufer

Alle drei ersetzen ihren bisherigen `logIfThrows { try removeExpiredSQLiteArticles(...) }`-
Aufruf durch einen Aufruf von `runAutomaticCleanup(...)` mit identischen Parametern:

- **`FeedivoApp.cleanupExpiredArticlesIfNeeded()`** (`FeedivoApp.swift:212-223`): nutzt die
  eigenen `@AppStorage`-Werte direkt, `userDefaults` bleibt Default (`.standard`).
- **`FeedPropertiesView.syncFeedRetentionSettings()`** (`FeedPropertiesView.swift:727-760`):
  nutzt die globalen `@AppStorage`-Werte (`globalArticleRetentionIsEnabled` etc.), unverändert
  gegenüber heute — nur der Aufruf wechselt von `removeExpiredSQLiteArticles` auf
  `runAutomaticCleanup`.
- **`BackgroundRefreshService.cleanupExpiredArticlesIfNeeded(database:userDefaults:now:)`**
  (bereits existierende Funktion aus Befund-A-Fix, `BackgroundRefreshService.swift`): behält
  ihre bestehende Logik zum Lesen der Retention-Einstellungen direkt aus `UserDefaults` (da
  sie außerhalb einer SwiftUI-View läuft), reicht aber zusätzlich denselben `userDefaults`-
  Parameter an `runAutomaticCleanup(...)` durch, damit Tests mit isolierten
  `UserDefaults`-Suites weiterhin funktionieren.

## Komponente 3: UI-Status-Block in `CleanupSettingsView`

Neue `@AppStorage`-Properties (analog zu `RefreshSettingsView`):

```swift
@AppStorage(ArticleRetentionSettings.lastAutomaticCleanupDateKey)
private var lastAutomaticCleanupTimestamp = 0.0

@AppStorage(ArticleRetentionSettings.lastAutomaticCleanupStatusKey)
private var lastAutomaticCleanupStatus = ""

@AppStorage(ArticleRetentionSettings.lastAutomaticCleanupErrorKey)
private var lastAutomaticCleanupError = ""

@AppStorage(ArticleRetentionSettings.lastAutomaticCleanupRemovedCountKey)
private var lastAutomaticCleanupRemovedCount = 0
```

Neuer Block direkt nach dem bestehenden manuellen Ergebnis-/Fehler-Text (Zeilen 1126-1138),
vor dem schließenden `SettingsBlock`:

```swift
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
```

```swift
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

Die "Entfernte Artikel"-Zeile erscheint bewusst NUR bei Status `success` (bei `failed` ist
die Zahl bedeutungslos/veraltet, bei "noch nie gelaufen" gibt es keine).

### Neue L10n-Keys (`L10n.swift`, Muster identisch zu den bestehenden `settingsAutomaticRefresh*`-Keys)

```swift
static let settingsAutomaticCleanupLastRun = LocalizedStringKey("settings.automaticCleanup.lastRun")
static let settingsAutomaticCleanupStatus = LocalizedStringKey("settings.automaticCleanup.status")
static let settingsAutomaticCleanupRemovedCount = LocalizedStringKey("settings.automaticCleanup.removedCount")
static let settingsAutomaticCleanupLastError = LocalizedStringKey("settings.automaticCleanup.lastError")
static let settingsAutomaticCleanupStatusSuccess = LocalizedStringKey("settings.automaticCleanup.status.success")
static let settingsAutomaticCleanupStatusFailed = LocalizedStringKey("settings.automaticCleanup.status.failed")
static let settingsAutomaticCleanupStatusNever = LocalizedStringKey("settings.automaticCleanup.status.never")
```

## Fehlerbehandlung

Unverändert im Kern (Bereinigung selbst wird nicht riskanter): `runAutomaticCleanup` fängt
jeden Fehler von `removeExpiredSQLiteArticles` ab, schreibt ihn in die neuen
`UserDefaults`-Keys UND loggt ihn wie bisher über `AppLogger.dataAccess` — reine additive
Sichtbarkeitsverbesserung, kein Verhaltensrisiko.

## Testing / Verifikation

- Neue Unit-Tests in `ArticleRetentionCleanupServiceTests.swift` (TDD):
  `recordAutomaticCleanupSuccess`/`recordAutomaticCleanupFailure` isoliert (reine
  `UserDefaults`-Assertions, wie bei `BackgroundRefreshServiceTests.recordRefreshSuccess`-
  Tests), sowie `runAutomaticCleanup` end-to-end im Erfolgsfall (In-Memory-DB, prüft sowohl
  DB-Löschung als auch geschriebenen Status). Der Fehlerpfad von `runAutomaticCleanup`
  selbst bleibt ungetestet (siehe „Nicht-Ziele" — vorbestehende Einschränkung, nicht neu
  eingeführt).
- Bestehende `BackgroundRefreshServiceTests.cleanupExpiredArticlesIfNeeded*`-Tests (aus dem
  Befund-A-Fix) müssen nach der Umstellung auf `runAutomaticCleanup` weiterhin unverändert
  grün bleiben (reine interne Umleitung, keine Verhaltensänderung der DB-Seite).
- `xcodebuild build` nach jeder Änderung, da für `CleanupSettingsView`/`RefreshSettingsView`
  keine dedizierten View-Tests existieren (Projekt-Konvention).
- Manuelle Prüfung durch den Nutzer: neuer Status-Block erscheint in den Einstellungen unter
  "Alte Artikel", zeigt nach einem App-Start "Erfolgreich" mit Zeitstempel und Anzahl.

## Betroffene Dateien

- **Geändert:** `Feedivo/Services/ArticleRetentionSettings.swift` (+6 neue Keys)
- **Geändert:** `Feedivo/Services/ArticleRetentionCleanupService.swift` (neue
  `runAutomaticCleanup`/`recordAutomaticCleanupSuccess`/`recordAutomaticCleanupFailure`)
- **Geändert:** `Feedivo/App/FeedivoApp.swift` (Aufrufstelle umgestellt)
- **Geändert:** `Feedivo/Views/Sidebar/FeedPropertiesView.swift` (Aufrufstelle umgestellt)
- **Geändert:** `Feedivo/Services/BackgroundRefreshService.swift` (Aufrufstelle umgestellt)
- **Geändert:** `Feedivo/Views/Settings/SettingsView.swift` (`statusLine`/
  `formattedAutomaticStatusDate` zu file-privaten Funktionen angehoben, neuer Status-Block
  in `CleanupSettingsView`, neue `@AppStorage`-Properties)
- **Geändert:** `Feedivo/Resources/L10n.swift` (+7 neue Keys)
