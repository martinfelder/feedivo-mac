# Fehler-UX-Konsistenz (Findings 2.1 + 2.2 + 2.4, volles Feature 20.1/20.2) — Design

> Gruppe 6 des Code-Qualitäts-Review-Remediation-Programms
> (`docs/superpowers/reviews/2026-07-11-code-quality-review.md`). Umfang laut
> Nutzerentscheidung: volles FEATURES.md Feature 20.1/20.2, nicht nur die 3 eng
> zitierten Review-Funde — siehe „Scope-Entscheidungen" unten.

## Kontext

Aktueller Stand: `main` bei `0bae97d2d` (nach Gruppen 1-5 dieser Session:
Artikel-Löschen absichern, Bulk-Aktionen-/Sidebar-Fehleranzeige, Regex-Validierung,
SQL-/HTML-Duplikation, Lokalisierungslücken).

Feature 20 (`FEATURES.md`, Abschnitt „20. Fehler- und Problembehandlung") ist als
„✅ Entschieden — bereit zur Implementierung" markiert, aber nie umgesetzt worden.
Es umfasst mehr als die 3 im Review zitierten Funde (2.1 Sidebar-Badge, 2.2 Retry-
Buttons, 2.4 Alert-vs-Inline-Inkonsistenz) — konkret auch einen globalen Offline-
Banner und "Feed aktualisieren"-Buttons in Leerzuständen.

## Scope-Entscheidungen (mit Nutzer geklärt)

1. **Umfang:** Volles Feature 20.1/20.2, nicht nur die 3 engen Review-Funde.
2. **Globaler Offline-Banner:** Bereits funktional erfüllt durch die bestehende
   `NetworkConnectionStatusMonitor`/`NetworkConnectionStatusIndicator`-Infrastruktur
   (`ContentView.swift:832-880`, dauerhaft sichtbare Online/Offline-Kapsel unten
   rechts). **Kein Umbau zu einem Banner oben** — bleibt unverändert, kein Task in
   diesem Plan.
3. **"Download-Fehler: Inline-Meldung mit Retry-Option":** Interpretiert als
   Feed-Refresh-Fehler (deckt sich mit 2.1/2.2). Das bewusst stillgelegte
   Offline-Artikel-Download-Feature (siehe CLAUDE.md-Gotcha „Offline-Artikel-
   Download-Backend ist bewusst quarantäniert") wird **nicht angetastet** — das ist
   eine eigenständige, hier nicht zu treffende Produktentscheidung.
4. **Finding 2.4 (Alert-vs-Inline):** Regel dokumentieren + die 2 im Review genannten
   `SidebarView.swift`-Fälle nur prüfen (nicht pauschal alle Fehlerpfade der App
   umschreiben).

**Bereits erledigt, kein Task nötig:**
- „Erster Start ohne Feeds" — `FirstRunWizardView` existiert bereits.
- „Suche ohne Resultate" — bereits korrekt über `L10n` lokalisiert (im Review selbst
  unter „Positiv verifiziert" bestätigt).
- „Tag ohne Artikel"-Hinweis — durch Gruppe 5 bereits über
  `L10n.articleListEmptyDescriptionTag` abgedeckt.
- „Feed hat keine Artikel: Erklärung" — Erklärungstext existiert bereits seit
  Gruppe 5 (`L10n.articleListEmptyDescriptionFeed`); es fehlt nur noch der
  **Button** (Task 3 unten).

## Architektur

Fünf unabhängige, aber zusammengehörige Komponenten:

### 1. Fehler-Signal + Sidebar-Badge (Finding 2.1)

**Datenquelle:** `feed_logs`-Tabelle bekommt bei jedem Refresh garantiert einen
frischen Eintrag — `level: "info"` bei Erfolg (`SQLiteFeedRefreshService.swift:87,
142`), `level: "error"` bei Fehlschlag (`SQLiteFeedRefreshService.swift:166`). Der
jüngste Log-Eintrag pro Feed ist damit ein zuverlässiges, immer aktuelles Signal —
kein neues persistiertes Feld, keine Migration nötig (Nutzerentscheidung, siehe
Scope-Frage 2 oben).

**Änderung:** `FeedSidebarSnapshot` (`Feedivo/Snapshots/FeedSidebarSnapshot.swift`)
bekommt ein neues Feld `hasRecentError: Bool`. `FeedStore.sidebarFeeds()`
(`Feedivo/Stores/FeedStore.swift:250-269`) erweitert die bestehende SQL-Query um
eine korrelierte Subquery nach demselben Muster wie das bereits vorhandene
`unreadCount`-Feld:

```sql
(
    SELECT level = 'error'
    FROM feed_logs
    WHERE feedID = f.id
    ORDER BY createdAt DESC
    LIMIT 1
) AS hasRecentError
```

`FeedRowView` (`Feedivo/Views/Sidebar/FeedRowView.swift`) zeigt bei
`snapshot.hasRecentError == true` ein ⚠️-Warn-Icon (`exclamationmark.triangle.fill`,
orange) neben dem Favicon — Tooltip mit einer lokalisierten Kurzbeschreibung
("Feed nicht erreichbar — Details in den Feed-Eigenschaften").

### 2. "Erneut versuchen" im Fehler-Ladezustand (Finding 2.2, Teil 1)

`SQLiteFeedArticleListView` bekommt einen neuen optionalen Closure-Parameter
`onRetryFeed: (() -> Void)?` — nur im `.feed`-Init (die anderen 3 Scopes
(tag/smartFilter/smartFolder) haben keinen einzelnen Feed zum Neuladen, bleiben
`nil`). `ContentView.swift` verdrahtet ihn an der `.feed`-Scope-
Instanziierungsstelle (aktuell Zeilen ~95-102) mit demselben Aufruf, den der
bestehende "Feed aktualisieren"-Menüpunkt schon nutzt
(`feedViewModel.refreshFeed(feedID:sqliteDatabase:)`, siehe
`ContentView.swift:301-309`) — kein neuer Code-Pfad, dieselbe bewährte Logik.

Der `.failed(let message)`-Fall in `articleContent` wechselt von der
String-Convenience-Initialisierung von `ContentUnavailableView` auf die
Label/Description/Actions-ViewBuilder-Variante, um einen Retry-Button zu zeigen.

### 3. "Feed aktualisieren" im leeren Feed-Zustand (Finding 2.2, Teil 2 + Feature 20.2)

Derselbe `onRetryFeed`-Closure aus Komponente 2 wird zusätzlich am
`.loaded where state.rows.isEmpty`-Fall verwendet — aber nur wenn `scope == .feed`
(bei Tag/Smart-Filter/Smart-Folder ergibt "Feed aktualisieren" für einen einzelnen
Feed keinen Sinn, dort bleibt der Zustand wie bisher ohne Button).

### 4. Inline-Fehlerhinweis in der Artikelliste bei fehlgeschlagenem Refresh (Feature 20.1, zweite Hälfte)

Bislang unsichtbarer Fall: ein Feed ist ausgewählt, hat bereits Artikel geladen
(`state.rows` nicht leer), aber der letzte Refresh ist fehlgeschlagen. `FeedStore`
bekommt eine neue, leichtgewichtige Einzelfeed-Methode
`hasRecentError(feedID:) throws -> Bool` (dieselbe Subquery-Logik wie Komponente 1,
aber für genau einen Feed statt für die ganze Sidebar-Liste — `FeedSidebarSnapshot`
ist innerhalb von `SQLiteFeedArticleListView` nicht ohne Weiteres verfügbar).
`SQLiteFeedArticleListView` lädt diesen Status in einem neuen `@State`, aktualisiert
bei jedem `reload()` (analog zum bestehenden `state`-Reload-Zyklus), und zeigt bei
`true` UND `scope == .feed` UND `!state.rows.isEmpty` ein kompaktes Banner oberhalb
der Artikelliste (in `articleListContainer`, zwischen `articleListHeader` und der
Liste) mit Fehlertext + demselben Retry-Button wie Komponente 2/3.

### 5. Alert-vs-Inline-Regel dokumentieren (Finding 2.4)

Regel als kurzer Kommentarblock bei `ContentView.swift`s erster `.alert(`-Stelle
(Zeile ~214) festgehalten: **Modal-Alert nur für App-blockierende Zustände
(DB-Init-Fehler) oder destruktive Bestätigungen; alle Formular-/Validierungsfehler
bleiben inline neben dem betroffenen Feld.** Die beiden im Review genannten
`SidebarView.swift`-Fälle (`Feedivo/Views/Sidebar/SidebarView.swift:842-843`
Feed-Hinzufügen-Fehler, `:1155-1218` Ordner-Name-Duplikat) werden gegen diese Regel
geprüft — nach aktueller Verifikation sind **beide bereits korrekt** (Formular-
lokale Validierungsfehler, sheet-inline, kein Modal nötig) — hier ist vermutlich
kein Code-Fix nötig, nur die Bestätigung + Dokumentation.

## Datenfluss

```
feed_logs (level: info/error, geschrieben bei jedem Refresh)
    │
    ├─→ FeedStore.sidebarFeeds() ──→ FeedSidebarSnapshot.hasRecentError ──→ FeedRowView (Badge)
    │
    └─→ FeedStore.hasRecentError(feedID:) ──→ SQLiteFeedArticleListView (@State) ──→ Inline-Banner

feedViewModel.refreshFeed(feedID:sqliteDatabase:) (bestehend, unverändert)
    │
    └─→ onRetryFeed-Closure ──→ SQLiteFeedArticleListView (3 Aufrufstellen: .failed,
         leerer Feed-Zustand, Inline-Banner)
```

## Fehlerbehandlung

Keine neuen Fehlerpfade — `hasRecentError`/`hasRecentError(feedID:)` sind reine
`SELECT`-Lesezugriffe ohne Fehlschlagmöglichkeit außerhalb der bereits
existierenden DB-Fehlerbehandlung (`throws`, propagiert wie alle anderen
Store-Methoden). Der Retry-Button ruft eine bereits gehärtete, getestete Methode
auf (`feedViewModel.refreshFeed`, deren Fehlerbehandlung außerhalb des Scopes
dieser Gruppe liegt — bereits vorhanden).

## Testing

- `FeedStoreTests` (neu oder Erweiterung): `sidebarFeeds()` liefert
  `hasRecentError == true` nach einem `error`-Log-Eintrag, `false` nach einem
  nachfolgenden `info`-Eintrag (Erfolg überschreibt den Fehlerstatus).
- Neue Tests für `FeedStore.hasRecentError(feedID:)` (Einzelfeed-Variante,
  gleiches Muster).
- `SQLiteFeedArticleListView`/`FeedRowView` sind SwiftUI-Views ohne bestehende
  Unit-Test-Abdeckung (kein UI-Testing-Framework in diesem Projekt verfügbar) —
  Verhalten wird über die Store-Ebene getestet; die reine UI-Verdrahtung
  (Badge-Sichtbarkeit, Button-Callback) bleibt wie bei allen bisherigen
  SwiftUI-Änderungen dieses Projekts der abschließenden manuellen Verifikation
  durch den Nutzer vorbehalten.

## Out of Scope

- Globaler Top-Banner (Nutzerentscheidung: bestehende Kapsel reicht).
- Offline-Artikel-Download-Reaktivierung (eigenständige, hier nicht zu treffende
  Entscheidung).
- Vollständige Alert-vs-Inline-Überarbeitung aller Fehlerpfade der App
  (Nutzerentscheidung: nur dokumentieren + die 2 genannten Fälle prüfen).
