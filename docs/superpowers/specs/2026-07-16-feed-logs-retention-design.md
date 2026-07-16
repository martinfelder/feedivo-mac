# Design: feed_logs-Bereinigung (Retention)

**Datum:** 2026-07-16
**Status:** Zur Review

## Kontext

Der finale Whole-Branch-Review des `FeedStore.sidebarFeeds()`-Performance-Fixes
(`docs/superpowers/specs/2026-07-16-sidebar-feeds-performance-design.md`,
Commits `607e4e50b..db00e730c`, bereits auf `main`) fand ein Important-Finding:
die Tabelle `feed_logs` (`Feedivo/Database/Records/FeedLogRecord.swift`,
`Feedivo/Stores/FeedLogStore.swift`) wird nirgends bereinigt — es gibt keine
einzige `DELETE FROM feed_logs`-Stelle im Code. `FeedLogStore.append(_:)` fügt
bei jedem Feed-Refresh-Versuch (Erfolg oder Fehler, siehe Aufrufstellen in
`SQLiteFeedRefreshService.swift` und `SQLiteFeedSubscriptionService.swift`)
eine neue Zeile hinzu, ohne je etwas zu löschen. Bei 500 Feeds mit
regelmäßigem Hintergrund-Refresh wächst die Tabelle dadurch unbegrenzt.

Die neue `latest_feed_logs`-CTE in `sidebarFeeds()`
(`ROW_NUMBER() OVER (PARTITION BY feedID ORDER BY createdAt DESC)`) liest für
den `hasRecentError`-Zähler die komplette Tabelle in einem Rutsch — anders als
die alte korrelierte Subquery, die pro Feed einen index-gestützten Zugriff
über `idx_feed_logs_feed_created` machte. Ohne Bereinigung könnte dieser
Anteil der neuen Query bei sehr großer, über Monate/Jahre gewachsener
`feed_logs`-Tabelle langsamer werden als die alte Lösung.

Im Brainstorming geklärt:
- **Retention-Kriterium:** zeitbasiert (Logs älter als X Tage löschen),
  analog zu `ArticleRetentionSettings`, nicht mengenbasiert.
- **Integration:** nutzt die bestehende Zeitplan-Infrastruktur aus Feature
  17.3a (`CleanupScheduleSettings`, `ArticleRetentionCleanupService.
  runAutomaticCleanup`) — kein eigener Zeitplan-Schalter.
- **Konfigurierbarkeit:** Aufbewahrungsdauer ist eine eigene, konfigurierbare
  Einstellung (nicht fest im Code).
- **Kopplung:** läuft **unabhängig** von `articleRetentionIsEnabled` — sonst
  bliebe das Wachstumsproblem bei allen Nutzern mit deaktivierter
  Artikel-Aufbewahrung (dem laut Feature-Doku standardmäßigen Zustand)
  ungelöst, obwohl genau diese Nutzergruppe den Fix am nötigsten hätte.

## Ziel

Alte `feed_logs`-Einträge automatisch und regelmäßig löschen, ohne die
bestehende Artikel-Bereinigung, deren UI oder deren History/Toast-Anbindung
zu verändern.

## Nicht-Ziele

- Kein Mindestanzahl-Schutz pro Feed (anders als bei Artikeln via
  `minimumArticlesPerFeed`) — keine bestehende Funktion setzt eine
  Mindest-Log-Tiefe pro Feed voraus (`FeedLogStore.logs(feedID:limit:)` liest
  ohnehin nur die letzten N über `LIMIT`).
- Kein eigener Enable/Disable-Schalter — läuft immer (nur die
  Aufbewahrungsdauer ist konfigurierbar).
- Kein Eintrag in `CleanupRunHistoryStore`, kein In-App-Toast — rein internes
  Housekeeping, keine für den Nutzer sichtbare "X gelöscht"-Meldung.
- Kein Rollback des `sidebarFeeds()`-CTE-Fixes selbst (der bleibt unverändert
  bestehen, dieses Feature löst nur das darin gefundene Skalierungsrisiko).

## Neue Komponenten

### `FeedLogRetentionSettings` (neu, `Feedivo/Services/FeedLogRetentionSettings.swift`)

Analog zu `ArticleRetentionSettings`, aber ohne Enable-Flag:

```swift
enum FeedLogRetentionSettings {
    static let retentionDaysKey = "feedLogRetention.retentionDays"
    static let defaultRetentionDays = 30

    static func retentionDays(in defaults: UserDefaults = .standard) -> Int {
        guard defaults.object(forKey: retentionDaysKey) != nil else {
            return defaultRetentionDays
        }
        return defaults.integer(forKey: retentionDaysKey)
    }
}
```

### `FeedLogStore.deleteOlderThan(_:)` (neue Methode, `Feedivo/Stores/FeedLogStore.swift`)

```swift
@discardableResult
func deleteOlderThan(_ cutoffDate: Date) throws -> Int {
    try database.write { db in
        try db.execute(sql: "DELETE FROM feed_logs WHERE createdAt < ?", arguments: [cutoffDate])
        return db.changesCount
    }
}
```

Reines `DELETE`, keine Identity-History, keine Spotlight-Deindexierung, keine
Schutz-Ausnahmen — feed_logs-Zeilen haben keine dieser Artikel-spezifischen
Nebenbedingungen.

### Integration in `ArticleRetentionCleanupService.runAutomaticCleanup(...)`

Ergänzt einen zusätzlichen, von `isEnabled` (Artikel-Aufbewahrung)
**unabhängigen** Schritt direkt in `runAutomaticCleanup` (nicht in
`removeExpiredSQLiteArticles`, das bleibt rein artikel-bezogen):

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
    // History-/Toast-Sichtbarkeit, deshalb Fehler hier nur geloggt, nicht
    // Teil des Result<Int, Error>-Rückgabewerts.
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
        let removedCount = try removeExpiredSQLiteArticles(...)
        // ... unverändert
```

Läuft dadurch bei jedem der vier bestehenden Trigger (App-Start, Zeitplan,
App-Beenden, Settings-Änderung) automatisch mit — kein neuer Trigger-Pfad.

### UI

Neue `SettingsBlock(eyebrow: "Feed-Protokolle")` in `CleanupSettingsView`
(`Feedivo/Views/Settings/SettingsView.swift`), direkt nach dem bestehenden
"Zeitplan"-Block und vor dem "Bereinigungsverlauf"-Block:

```swift
SettingsBlock(eyebrow: L10n.settingsFeedLogRetentionTitle) {
    SettingRow(
        title: L10n.settingsFeedLogRetentionDaysTitle,
        description: L10n.settingsFeedLogRetentionDaysDescription
    ) {
        Picker(L10n.settingsFeedLogRetentionDaysTitle, selection: $feedLogRetentionDays) {
            ForEach([7, 14, 30, 60, 90], id: \.self) { days in
                Text("\(days) Tage").tag(days)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
    }
}
```

(Exakte Picker-Werte/Label-Formatierung wird im Implementierungsplan final
festgelegt — ggf. wiederverwendbar mit dem bestehenden
`ArticleRetentionSettings.allowedRetentionDays`-Muster, falls dessen Werte
passen.)

## Tests

- Neue Unit-Tests für `FeedLogStore.deleteOlderThan(_:)`: löscht Einträge vor
  dem Cutoff, behält Einträge danach, funktioniert bei leerer Tabelle.
- Neuer Unit-Test für `FeedLogRetentionSettings.retentionDays(in:)`: liefert
  Default bei fehlendem Key, liefert gespeicherten Wert sonst (analog zum
  bestehenden Muster bei `ArticleRetentionSettings`/`CleanupScheduleSettings`-Tests).
- Erweiterter Test für `runAutomaticCleanup`: feed_logs werden auch bereinigt,
  wenn `isEnabled` (Artikel-Aufbewahrung) `false` ist — das ist der
  entscheidende Regressionstest für die im Brainstorming getroffene
  Kopplungs-Entscheidung.
- Bestehende `ArticleRetentionCleanupServiceTests`/`BackgroundRefreshServiceTests`
  müssen unverändert grün bleiben.

## Risiken / offene Punkte

- Kein Schema-Update nötig (keine neue Spalte/Tabelle, nur eine neue
  `UserDefaults`-Einstellung und eine neue `DELETE`-Methode).
- Erwartete Wirksamkeitsprüfung: nach Implementierung den bestehenden
  `SQLiteLargeDatasetPerformanceTests`-Benchmark um befüllte
  `feed_logs`-Zeilen erweitern (aktuell fehlt das komplett, siehe
  Whole-Branch-Review-Finding) und messen, ob die `latest_feed_logs`-CTE auch
  bei großzügig befüllter, aber durch Retention begrenzter Tabelle schnell
  bleibt — das war der ursprüngliche Auslöser dieses Features.
