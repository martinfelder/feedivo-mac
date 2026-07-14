# Design-Spec: Bereinigte Artikel bleiben dauerhaft weg + Start-Reihenfolge

**Datum:** 2026-07-14
**Status:** Design genehmigt, Implementierung noch NICHT begonnen (neue Session empfohlen)

## Kontext

Nutzer-Report (Folge-Diagnose nach Befund A/B/C-Fixes): "Alte Artikel bleiben trotz
aktivierter Bereinigung liegen, auch nach Tagen im Hintergrund. Mache ich aber eine
manuelle Bereinigung, werden vermeintlich Artikel gelöscht. Aktualisiere ich die Feeds
wieder, sind die Artikel auch wieder da."

Root Cause (verifiziert via systematic-debugging):

1. **Reihenfolge-Problem beim App-Start:** Nutzer hat "Beim Start aktualisieren"
   (`BackgroundRefreshSettings.refreshOnLaunchIsEnabled`) aktiviert.
   `FeedivoApp.cleanupExpiredArticlesIfNeeded()` läuft in einem eigenen `.task`-Block
   (`FeedivoApp.swift:87-92`), während `ContentView.refreshFeedsOnLaunchIfNeeded()`
   (aufgerufen aus `handleContentAppear()`, `ContentView.swift:389-395`) ein komplett
   unabhängiger SwiftUI-Lifecycle-Hook ist. Keine garantierte Reihenfolge zwischen zwei
   unabhängigen `.task`/`.onAppear`-Blöcken — der Start-Refresh kann die gerade bereinigten
   Artikel sofort wieder einfügen, bevor der Nutzer sie als gelöscht sieht.
2. **Fundamentales Wiedereinfüge-Verhalten:** `ArticleStore.upsert()`
   (`ArticleStore.swift:357-436`) prüft beim Einfügen nur, ob ein Artikel **aktuell** in der
   `articles`-Tabelle existiert (`findExistingArticleID`, Zeile 438). Ein von der Bereinigung
   gelöschter Artikel ist dort weg, also fügt jeder folgende Feed-Refresh ihn erneut ein,
   falls der Feed ihn weiterhin liefert (üblich bei vielen Feeds, die dauerhaft die letzten
   N Einträge zeigen). Die bestehende `article_identity_history`-Tabelle
   (`findIdentityHistory`, Zeile 463) wird nur genutzt, um Gelesen-/Stern-Status
   wiederherzustellen — sie verhindert das Wiedereinfügen nicht.

## Ziel

1. Automatische Bereinigung beim App-Start läuft garantiert VOR einem eventuellen
   Start-Refresh, nicht parallel dazu.
2. Ein Artikel, der durch Bereinigung entfernt wurde, wird bei einem späteren Feed-Refresh
   NICHT automatisch wieder eingefügt, solange er nach den *aktuellen*
   Bereinigungs-Einstellungen weiterhin als abgelaufen gelten würde. Ändert der Nutzer die
   Einstellungen später (z. B. längere Aufbewahrung, Bereinigung deaktiviert), kann der
   Artikel beim nächsten Refresh wieder ganz regulär erscheinen.

## Nicht-Ziele

- Kein fester, von den Bereinigungs-Einstellungen unabhängiger Sperrzeitraum ("Snooze") —
  die Kopplung an die aktuellen Einstellungen ist bewusst die einzige Regel, um keinen
  zusätzlichen, separat zu pflegenden Zustand einzuführen.
- Brandneue, noch nie gesehene Artikel (kein Treffer in `article_identity_history`) sind
  von dieser Änderung nicht betroffen — nur zuvor per Bereinigung explizit entfernte.
- Keine Änderung an `minimumArticlesPerFeed`-Schutzlogik der periodischen Bereinigung selbst.

## Komponente 1: Start-Reihenfolge

`cleanupExpiredArticlesIfNeeded()`-Aufruf wird aus dem separaten `.task`-Block in
`FeedivoApp.swift:87-92` entfernt. Stattdessen ruft `ContentView.handleContentAppear()`
(`ContentView.swift:389-395`) als ALLERERSTEN Schritt
`BackgroundRefreshService.cleanupExpiredArticlesIfNeeded(database: feedivoDatabase)` auf
(bereits bestehende, aus Befund A stammende Funktion — liest Retention-Einstellungen direkt
aus `UserDefaults.standard`, kein neuer Code nötig), VOR `refreshFeedsOnLaunchIfNeeded()`.
Da beide synchron auf dem MainActor laufen (`removeExpiredSQLiteArticles` ist eine
synchrone, nicht-async `@MainActor`-Funktion), ist die Reihenfolge dadurch garantiert —
kein Race mehr möglich. `FeedivoApp.swift`s `.onChange`-Handler für Retention-Einstellungs-
änderungen (Zeilen 99-113) bleiben unverändert (kein Start-Timing-Problem dort).

## Komponente 2: `wasRemovedByRetention`-Flag verhindert Wiedereinfügen

### Migration v11

Neue Spalte auf `article_identity_history` (nur ANHÄNGEN, bestehende Migrationen bleiben
unverändert — Projekt-Konvention):

```swift
migrator.registerMigration("v11_add_article_identity_history_retention_flag") { db in
    try db.alter(table: "article_identity_history") { table in
        table.add(column: "wasRemovedByRetention", .boolean)
            .notNull()
            .defaults(to: false)
    }
}
```

### `ArticleIdentityHistoryRecord`

Neues Feld `var wasRemovedByRetention: Bool` (Default `false` im Initializer), analog zu den
bestehenden `Bool`-Feldern (`isRead`, `isStarred`, etc.).

### `ArticleRetentionCleanupService.swift`

`SQLiteArticleIdentityHistoryCandidate.saveHistory(now:db:)` (aktuell Zeilen 304-345 in
`ArticleRetentionCleanupService.swift`) setzt `history.wasRemovedByRetention = true` explizit
— sowohl im "existing history aktualisieren"- als auch im "neue history anlegen"-Zweig. Das
ist der EINZIGE Ort, an dem das Flag auf `true` gesetzt wird (Bereinigung ist die einzige
Quelle für "wurde entfernt").

### `ArticleStore.swift`

`saveIdentityHistory(forArticleID:input:status:db:)` (Zeilen 505-540, wird bei jedem
normalen Upsert eines weiterhin/wieder existierenden Artikels aufgerufen) setzt
`history.wasRemovedByRetention = false` — ein Artikel, der gerade erfolgreich eingefügt
wurde, ist per Definition nicht (mehr) entfernt.

In der privaten `upsert(_:db:)`-Methode (Zeilen 357-436), im "neuer Artikel"-Zweig (ab Zeile
400, wo `findIdentityHistory` bereits aufgerufen wird): NEUE Prüfung nach dem
`history`-Lookup, VOR dem `article.insert(db)`:

```swift
if let history, history.wasRemovedByRetention {
    let configuration = try currentRetentionConfiguration(forFeedID: input.feedID, db: db)
    let effectiveDate = input.publishedAt ?? input.arrivedAt
    if configuration.isEnabled, effectiveDate < configuration.cutoffDate {
        // Artikel wurde bewusst bereinigt und ist nach aktuellen Einstellungen
        // weiterhin abgelaufen — nicht wieder einfügen.
        return (history.lastArticleID, false)
    }
}
```

`currentRetentionConfiguration(forFeedID:db:)` ist eine neue private Hilfsfunktion in
`ArticleStore.swift`, die dieselbe Logik wie
`ArticleRetentionCleanupService.sqliteFeedRetentionConfigurations`/
`ArticleRetentionConfiguration` nutzt (globale `ArticleRetentionSettings` aus
`UserDefaults.standard` + Feed-eigenen Override aus `FeedRecord`) — **Detailfrage für die
Implementierungsplanung:** ob dafür der bestehende private Typ `ArticleRetentionConfiguration`
aus `ArticleRetentionCleanupService.swift` sichtbar gemacht (nicht mehr `private`) und
wiederverwendet wird, oder eine eigene, kleinere Berechnung in `ArticleStore.swift` reicht
(nur `isEnabled`+`cutoffDate` werden hier gebraucht, nicht die volle Konfiguration inkl.
`minimumArticlesPerFeed`/`includeProtectedArticles`) — Empfehlung: Wiederverwendung des
bestehenden Typs, um keine zweite, potenziell abweichende Cutoff-Berechnung zu haben (gleiche
Begründung wie bei Befund B: divergente Duplikate sind ein bereits dokumentiertes
Risikomuster in diesem Projekt).

Rückgabewert `(history.lastArticleID, false)` beim Überspringen: `lastArticleID` verweist auf
die zuletzt bekannte (jetzt gelöschte) Artikel-ID — Aufrufer, die die zurückgegebene ID für
UI-Updates nutzen, müssen tolerant gegenüber einer ID sein, die aktuell nicht (mehr) in
`articles` existiert. **Offene Frage für die Implementierungsplanung:** ob das
`ArticleUpsertResult`/der Rückgabetyp stattdessen einen expliziten "übersprungen"-Fall
braucht (z. B. `skippedArticleIDs: [String]` zusätzlich zu `insertedArticleIDs`/
`updatedArticleIDs`), damit Aufrufer (`SQLiteFeedRefreshService`,
`SQLiteFeedSubscriptionService`) diesen Fall nicht mit einem echten Update verwechseln —
beide aktuellen Aufrufer müssen darauf geprüft werden, ob sie mit einer "unsichtbaren" ID in
`updatedArticleIDs` fehlerhaft umgehen würden (z. B. Benachrichtigungen, Ungelesen-Zähler).

## Testing / Verifikation (für die Implementierungsplanung)

- Neue Migration testen wie bestehende v-Migrationen (Schema-Test).
- `ArticleRetentionCleanupServiceTests`: `saveHistory` setzt `wasRemovedByRetention = true`.
- `ArticleStoreTests` (oder passende bestehende Suite): Upsert eines Artikels mit
  `wasRemovedByRetention = true`-Historie UND weiterhin abgelaufenem Datum → NICHT
  eingefügt. Mit nicht mehr abgelaufenem Datum (z. B. Retention nachträglich deaktiviert)
  → WIRD eingefügt, Flag wird auf `false` zurückgesetzt.
- Manuelle Verifikation durch den Nutzer: exakt das ursprünglich gemeldete Szenario
  nachstellen (Bereinigung + Refresh, Artikel bleibt weg).

## Betroffene Dateien (vorläufig, für Implementierungsplanung zu verifizieren)

- `Feedivo/Database/FeedivoDatabaseMigrator.swift` (neue Migration v11)
- `Feedivo/Database/Records/ArticleIdentityHistoryRecord.swift` (neues Feld)
- `Feedivo/Services/ArticleRetentionCleanupService.swift` (`saveHistory` setzt Flag,
  evtl. `ArticleRetentionConfiguration`-Sichtbarkeit anheben)
- `Feedivo/Stores/ArticleStore.swift` (Suppression-Check im Upsert-Pfad,
  `saveIdentityHistory` setzt Flag zurück)
- `Feedivo/App/FeedivoApp.swift` (Cleanup-Aufruf aus `.task` entfernt)
- `Feedivo/Views/ContentView.swift` (Cleanup-Aufruf in `handleContentAppear()` ergänzt)
- Betroffene Test-Dateien (Migration, `ArticleRetentionCleanupServiceTests`,
  `ArticleStore`-bezogene Tests — exakte Dateinamen bei Planerstellung verifizieren)

## Hinweis zur Session

Dieses Dokument wurde am Ende einer sehr langen, kostenintensiven Session erstellt (Kontext
78 % ausgelastet). Die Design-Entscheidung ist getroffen und mit dem Nutzer abgestimmt —
Implementierungsplan (`writing-plans`) und Umsetzung (`subagent-driven-development`) sollten
in einer NEUEN Session erfolgen, die diese Spec-Datei als Ausgangspunkt liest.
