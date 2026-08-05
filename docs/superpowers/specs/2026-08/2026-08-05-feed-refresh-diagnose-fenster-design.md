# Design: Feed-Status-Fenster (Ladefehler-Diagnose)

**Datum:** 2026-08-05
**Status:** Zur Review

## Kontext

Beim Aktualisieren aller Feeds gibt es aktuell nur ein flüchtiges Status-Panel unten
rechts (`FeedRefreshDetailPanel` in `Feedivo/Views/ContentView.swift`), das ausschließlich
für den gerade laufenden bzw. zuletzt abgeschlossenen "Alle aktualisieren"-Vorgang
existiert (`FeedViewModel.refreshItems`, ein reiner In-Memory-State, wird bei jedem neuen
Refresh und beim manuellen Schließen zurückgesetzt). Pro Feed zeigt es nur ein
Status-Icon (Ausstehend/Läuft/OK/Fehler) plus einen generischen Text
(`L10n.refreshStatusItemFailed`, immer "Fehlgeschlagen") — ohne echten Fehlergrund, ohne
Historie, und ohne jede Möglichkeit, direkt auf einen betroffenen Feed zu reagieren.

Der tatsächliche Fehlergrund existiert bereits persistent in der `feed_logs`-Tabelle
(`FeedLogRecord`: `level`, `message`, `httpStatusCode`, `createdAt`, `newArticleCount` —
siehe `Feedivo/Stores/FeedLogStore.swift`) — jeder Refresh-Versuch (Erfolg, "Nicht
geändert" ODER Fehler) schreibt dort einen Eintrag. Genutzt wird das bisher nur punktuell
in der Feed-Status-Zeile im Artikellisten-Header (nur bei Einzel-Feed-Auswahl sichtbar).

## Ziel

Ein eigenständiges, jederzeit über das Feed-Menü aufrufbares Fenster, das alle Feeds mit
fehlgeschlagenem letzten Aktualisierungsversuch übersichtlich auflistet — mit echtem
Fehlergrund, HTTP-Status, Zeitpunkt und Länge der Fehlerserie — und direkte Aktionen
(erneut versuchen, Eigenschaften öffnen, Website öffnen, URL kopieren, löschen) anbietet,
ohne dass der Nutzer dafür jeden Feed einzeln in der Sidebar aufsuchen muss.

## Betrachtete Ansätze

1. **Neues eigenständiges Fenster, zusätzlich zum bestehenden Panel (gewählt).** Folgt
   dem bereits etablierten Muster für Organizer/Statistik/Bereinigungsverlauf
   (`Window(id:)`-Scene in `FeedivoApp.swift`, Menüpunkt in `FeedCommands.swift`). Liest
   `feed_logs` statt des flüchtigen `refreshItems`-State — dadurch persistent und mit
   echten Fehlerdetails. Das bestehende Panel unten rechts bleibt unverändert für den
   Live-Fortschritt während eines laufenden Refreshs; beide Mechanismen haben
   unterschiedliche Zwecke (Live-Fortschritt vs. Diagnose/Nacharbeit) und schließen sich
   nicht aus.
2. **Bestehendes Panel erweitern (verworfen).** Das Panel ist an den Lebenszyklus eines
   einzelnen `refreshAllFeeds()`-Aufrufs gebunden und verschwindet nach Schließen/nächstem
   Refresh — ungeeignet für eine dauerhafte Diagnose-Ansicht, die auch Tage alte
   Fehlerserien zeigen soll. Ein Umbau auf `feed_logs`-Persistenz plus Aktionsleiste hätte
   die Popover-UI strukturell zu einem eigenen Fenster gemacht, nur unter beengteren
   Platzverhältnissen.

## Datenquelle

Neue Abfrage-Funktion (z. B. `FeedLogStore.failureDiagnostics()` oder ein neuer, dünner
Diagnose-Typ) liefert pro Feed **nur den aktuell fehlgeschlagenen Zustand**:

- Letzter Log-Eintrag je Feed hat `level == "error"` — ermittelt über
  `ROW_NUMBER() OVER (PARTITION BY feedID ORDER BY createdAt DESC)`, analog dem bereits
  etablierten `latest_feed_logs`-CTE-Muster in `FeedStore.sidebarFeeds()`.
- **Anzahl aufeinanderfolgender Fehlschläge:** über ein Fenster-Funktions-CTE berechnet,
  das von den neuesten Einträgen je Feed rückwärts läuft und bei jedem erfolgreichen
  Auffinden eines Nicht-Fehler-Eintrags stoppt (Konstruktion über eine laufende Summe von
  "ist kein Fehler"-Flags, Gruppierung auf dem ersten erreichten Nicht-Fehler-Eintrag).
- **Bekannte, akzeptierte Einschränkung:** Die Serienlänge ist durch die konfigurierbare
  `feed_logs`-Aufbewahrungsdauer gedeckelt (Standard 30 Tage, siehe
  `FeedLogRetentionSettings`) — bei einem seit über 30 Tagen kaputten Feed zeigt der
  Zähler nur die innerhalb der Aufbewahrungsfrist protokollierten Fehlschläge, nicht die
  tatsächliche Gesamtzahl seit dem ersten Fehlschlag.
- Feeds ohne jeden `feed_logs`-Eintrag (noch nie versucht) erscheinen nicht in der Liste.

## Fensterinhalt

Pro fehlgeschlagenem Feed eine Zeile mit:

- Favicon + Feed-Titel
- Fehlertext (`feed_logs.message`, der tatsächliche Fehlergrund)
- Zeitpunkt des letzten Versuchs (`date.formatted(date:time:)`, wie in der bestehenden
  Feed-Status-Zeile im Artikellisten-Header)
- HTTP-Status-Code, falls vorhanden
- Anzahl aufeinanderfolgender Fehlschläge
- Feed-URL (sekundär, kleiner)

Leerer Zustand: "Keine fehlgeschlagenen Feeds" mit Erfolgs-Icon statt einer leeren Liste.

## Aktionen

Pro Zeile (Kontextmenü, ggf. zusätzlich als Icon-Buttons für die wichtigste Aktion):

- **Erneut versuchen** — ruft `FeedViewModel.refreshFeed(feedID:sqliteDatabase:)` auf.
  Bewusst der throttle-freie Einzel-Feed-Pfad (`FeedRefreshThrottle`/9-Minuten-Cooldown
  gilt laut bestehender Doku ausdrücklich nur für `refreshAllFeeds`, nicht für den
  gezielten Einzel-Feed-Refresh) — ein manueller Retry-Klick darf nie durch den
  Bulk-Throttle blockiert werden.
- **Feed-Eigenschaften öffnen** — präsentiert den bestehenden
  `FeedPropertiesView(feedID:)`-Sheet (identischer Aufruf wie in `SidebarView.swift`,
  keine Änderung an `FeedPropertiesView` nötig).
- **Website öffnen** — öffnet `websiteURL ?? url` im Standardbrowser via
  `NSWorkspace.shared.open(...)` (gleicher Fallback wie in `FeedPropertiesView`).
- **Feed-URL kopieren** — kopiert `feed.url` in die Zwischenablage
  (`NSPasteboard.general`, gleiches Muster wie in `FeedPropertiesView`).
- **Löschen** — mit destruktivem Bestätigungsdialog (analog Organizer/Sidebar), ruft
  `FeedViewModel.deleteFeed(feedID:sqliteDatabase:)` auf.

Zusätzlich ein Button oben im Fenster: **"Alle fehlgeschlagenen erneut versuchen"** —
löst `refreshFeed` für alle aktuell gelisteten Feeds aus, **ohne Bestätigungsdialog**
(nicht-destruktive Aktion, Nutzerentscheidung).

## Aktualisierung der Liste

Kein Live-Abo eines Reaktivitäts-Signals: `SQLiteFeedRefreshService.refresh(feedID:)`
schreibt bei einem Fehlschlag zwar den `feed_logs`-Eintrag, bumpt aber bewusst
`SQLiteDataInvalidation` nicht (das würde bei jedem einzelnen Hintergrund-Fehlschlag
unnötige Reloads app-weit auslösen) — ein Live-Abo wäre für dieses Fenster deshalb
unzuverlässig. Stattdessen:

- Neu laden beim Öffnen des Fensters (`.task`)
- Neu laden nach jeder im Fenster selbst ausgelösten Aktion (Retry, Retry-alle, Löschen)
- Ein manueller "Aktualisieren"-Button oben im Fenster für den Fall, dass zwischenzeitlich
  anderswo (Hintergrund-Refresh, Menü-Refresh) neue Fehler aufgetreten sind

## Einstiegspunkt

- `Window(L10n.feedRefreshDiagnosticsTitle, id: FeedRefreshDiagnosticsWindowView.windowID)`
  in `Feedivo/App/FeedivoApp.swift`, nach dem Muster von
  `Window(OrganizerWindowView.windowTitle, id: OrganizerWindowView.windowID)`.
- Neuer Menüpunkt "Feed-Status…" im bestehenden Feed-Menü
  (`Feedivo/App/FeedCommands.swift`), direkt neben "Verwaltung…"/"Statistik" — inkl.
  eigenem `CustomizableShortcut`-Fall (analog `.feedOrganizerOpen`/`.statisticsOpen`),
  damit es sich ins bestehende Shortcut-Einstellungen-System einreiht.

## Testing

- Neue Store-Ebene (Failure-Diagnostics-Query inkl. Serienzähler) gegen eine echte
  In-Memory-GRDB-Datenbank testen: keine Fehler → leeres Ergebnis; ein Fehler nach mehreren
  Erfolgen → Serienlänge 1; mehrere aufeinanderfolgende Fehler → korrekte Serienlänge;
  Fehler, gefolgt von einem späteren Erfolg → Feed erscheint nicht mehr in der Liste.
- Retry-Aktion (Einzeln und "Alle"): nutzt den bestehenden, bereits getesteten
  `FeedViewModel.refreshFeed`-Pfad — kein neuer Refresh-Mechanismus, daher kein neuer
  Test für den Refresh selbst nötig, nur dafür, dass die Fensterliste danach neu lädt.
- Manuelle Live-Verifikation (kein computer-use für native macOS-Apps verfügbar):
  Menüpunkt öffnet das Fenster, ein absichtlich kaputter Feed (z. B. ungültige URL)
  erscheint mit echtem Fehlertext, "Erneut versuchen" funktioniert unabhängig vom
  Bulk-Throttle, "Löschen" fragt nach Bestätigung, "Website öffnen"/"URL kopieren"
  funktionieren.

## Out of Scope

- Keine Anzeige erfolgreicher Feeds in diesem Fenster (bewusste Nutzerentscheidung —
  reines Fehler-Diagnose-Fenster, kein allgemeiner Feed-Status-Überblick).
- Keine Änderung am bestehenden Panel unten rechts oder an `FeedRefreshItem`/
  `refreshItems`.
- Keine Erweiterung von `feed_logs` um neue Spalten — alle benötigten Daten sind bereits
  vorhanden.
