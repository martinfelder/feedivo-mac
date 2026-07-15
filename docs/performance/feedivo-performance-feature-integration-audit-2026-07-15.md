# Feedivo: Performance- und Feature-Integrationsaudit

Stand: 2026-07-15

## Ziel und Umfang

Dieses Audit prüft den aktuellen `main`-Stand von Feedivo in zwei Richtungen:

1. Performance des produktiven SQLite-/GRDB-Pfads bei großen Beständen.
2. Vollständige Verdrahtung der in `FEATURES.md` als umgesetzt beschriebenen
   Funktionen.

Zusätzlich werden die Befunde mit der vorhandenen lokalen NetNewsWire-Referenz
unter `/Users/martinfelder/Developer/NetNewsWire-main` und dem bisherigen Bericht
`docs/performance/netnewswire-feedivo-mechanik-vergleich.md` verglichen.

## Kurzfazit

Feedivo hat die wichtigsten NetNewsWire-Prinzipien erfolgreich übernommen:

- SQLite als alleinige produktive Persistenz.
- getrennte Tabellen für Artikelinhalt und Artikelstatus.
- leichte Timeline-, Reader- und Sidebar-Snapshots.
- FTS-Suche in der Datenbankschicht.
- Conditional GET und Body-Hash-Skip beim Refresh.
- eine cancellable Latest-wins-Queue für Timeline-Loads.

Die aktuellen Risiken liegen nicht mehr im grundsätzlichen Datenmodell, sondern
an fünf Integrationsgrenzen:

- Datenbankfehler werden durch eine flüchtige In-Memory-Datenbank verdeckt.
- die Hauptartikelliste ist ohne Pagination auf 500 Artikel begrenzt.
- mehrere Sortierungen werden erst nach dem SQL-Limit angewendet.
- die Timeline-Queue koordiniert auf dem Main Actor und führt dort auch den
  synchronen GRDB-Read aus.
- mehrere sichtbare Features sind nur teilweise oder gar nicht verdrahtet.

Damit ist Feedivo strukturell bereits NetNewsWire-nah, im Laufzeitverhalten und
in der Feature-Konsistenz aber noch nicht auf demselben Reifegrad.

## Priorisierte Befunde

### P1 — Datenbankfehler starten unbemerkt eine flüchtige Datenbank

**Evidenz**

- `Feedivo/App/FeedivoApp.swift:197` öffnet die produktive Datenbank.
- Bei jedem Fehler wird in `FeedivoApp.openSQLiteDatabase()` mit
  `FeedivoDatabase.inMemoryForTests()` weitergestartet.
- `DatabaseLoadState.initializationError` wird anschließend immer auf `nil`
  gesetzt.

**Auswirkung**

Vorhandene Daten wirken verschwunden. Während dieser Sitzung neu angelegte
Feeds, Statusänderungen oder Einstellungen in SQLite gehen beim Beenden verloren.
Die UI kann den Fehler nicht erklären, weil der eigentliche Initialisierungsfehler
nicht gespeichert wird.

**Vergleich mit NetNewsWire**

NetNewsWire besitzt explizite Accounts und Datenbanken sowie sichtbare Error-
und Activity-Logging-Pfade. Ein lokaler Datenbankfehler wird nicht als scheinbar
erfolgreicher, leerer Account modelliert. Dieser Feedivo-Befund ist kein
Unterschied zwischen GRDB und NetNewsWires SQLite-Schicht, sondern eine
app-spezifische Sicherheitslücke im Startpfad.

**Empfehlung**

Den echten Fehler in `DatabaseLoadState` halten und einen klaren Read-only-/
Fehlerzustand anzeigen. Eine In-Memory-Datenbank darf nur in Tests oder nach
einer ausdrücklichen Benutzerentscheidung verwendet werden.

### P1 — Die Hauptartikelliste endet nach 500 Artikeln

**Evidenz**

- `Feedivo/Extensions/ArticleFetchLimits.swift:11` setzt
  `mainArticleList = 500`.
- `SQLiteFeedArticleListState.defaultTimelineLoader` übergibt dieses feste Limit.
- `SQLiteFeedArticleListView` besitzt keinen Cursor, Offset und keine
  Nachladezeile.

**Auswirkung**

Artikel hinter dem ersten 500er-Fenster sind in normalen Feed-, Tag- und
Smart-Folder-Listen nicht erreichbar. Der sichtbare Ungelesen-Zähler im
Listenheader zählt außerdem nur die geladenen Zeilen und kann daher ebenfalls
zu klein sein.

**Vergleich mit NetNewsWire**

NetNewsWire lädt Feed- und Folder-Timelines grundsätzlich als vollständige
Artikelmengen; Limits werden gezielt für spezielle Abfragen wie Ungelesen,
Heute oder Favoriten eingesetzt. Feedivo hat ein Spezialfall-Limit als globale
Obergrenze des Hauptpfads übernommen. Das schützt kurzfristig den SwiftUI-
View-Baum, verletzt aber die Timeline-Semantik.

**Empfehlung**

Keyset-Pagination mit stabiler Sortierkennung einführen. Die View soll kleine
Seiten halten, während der Store über `hasMore` beziehungsweise einen Cursor
anzeigt, ob weitere Ergebnisse existieren.

### P1 — Sortierungen werden auf den falschen Datenausschnitt angewendet

**Evidenz**

- `TimelineStore.articles()` sortiert SQL-seitig immer nach
  `COALESCE(publishedAt, arrivedAt) DESC` und begrenzt danach auf 500 Zeilen.
- `SQLiteFeedArticleListView.sortRows` wendet `oldestFirst`, `feed`, `title` und
  `shortReadingTimeFirst` erst auf diese 500 Snapshots an.

**Auswirkung**

`Älteste zuerst` zeigt nicht die ältesten Artikel des Scopes, sondern nur den
ältesten Artikel innerhalb der neuesten 500. Dasselbe gilt sinngemäß für Feed-,
Titel- und Lesezeit-Sortierung.

**Vergleich mit NetNewsWire**

NetNewsWire baut die Timeline aus der vollständigen Fetch-Menge und sortiert
die resultierende `ArticleArray`. Dadurch stimmen Fetch-Menge und UI-Sortierung
semantisch überein. Bei Feedivo müssen Sortieroption, SQL-`ORDER BY` und
Pagination als eine gemeinsame Store-Abfrage behandelt werden.

**Empfehlung**

Die Sortieroption in `TimelineStore` übergeben und jede Sortierung SQL-seitig
mit deterministischem Tie-Breaker ausführen. Der Pagination-Cursor muss zur
jeweiligen Sortierung passen.

### P1 — Artikel-Kontextmenü enthält tote Aktionen

**Evidenz**

`SQLiteFeedArticleListView.articleRow` übergibt aktuell:

- `hasAvailableTags: false`
- `onRequestAssignTag: {}`
- `onOpenInWindow: {}`

**Auswirkung**

`Tag zuweisen…` ist immer deaktiviert. `In neuem Fenster öffnen` ist sichtbar,
führt aber keine Aktion aus. Beide Funktionen sind in `FEATURES.md` als
umgesetzt beschrieben.

**Vergleich mit NetNewsWire**

Das ist kein Persistenz- oder Rendering-Unterschied. NetNewsWire routet
Kontextaktionen über seine Command-/Account-Schicht; Feedivo besitzt die
benötigten TagStore-, Reader- und Window-Pfade bereits, verbindet sie an dieser
Call-Site aber nicht.

**Empfehlung**

Die vorhandene SQLite-Tag-Zuweisungsansicht lazy öffnen und den bestehenden
`ArticleWindowRequest`-Pfad für die Row-Aktion verwenden. Zusätzlich einen
Integrationstest ergänzen, der nicht nur Quelltextfragmente, sondern das
ausgelöste Verhalten prüft.

### P1 — Der iCloud-Schalter meldet einen nicht vorhandenen Sync als aktiv

**Evidenz**

- `CloudSyncSettings` speichert nur ein UserDefaults-Flag.
- `FeedivoApp` liest das Flag, öffnet aber unabhängig davon dieselbe lokale
  SQLite-Datenbank.
- `SyncSettingsView` zeigt nach einem Neustart trotzdem den Status
  `iCloud Sync aktiv`.

**Auswirkung**

Die Oberfläche verspricht Datenabgleich, obwohl kein CloudKit-/Sync-Backend
ausgeführt wird. Benutzer könnten sich auf eine nicht vorhandene
Datensicherung oder Synchronisierung verlassen.

**Vergleich mit NetNewsWire**

NetNewsWire modelliert Sync als Account-Typ. Ein iCloud-Account wird über einen
echten Add-Account-Pfad angelegt und besitzt ein Backend. Feedivos einzelner
Bool-Schalter hat keine entsprechende Account-, Konflikt-, Fehler- oder
Fortschrittsschicht.

**Empfehlung**

Für v1 den Toggle deaktivieren oder als noch nicht verfügbar kennzeichnen. Eine
spätere Umsetzung sollte den Sync als eigene Account-/Sync-Schicht behandeln,
nicht als alternative Bedeutung derselben lokalen Datenbank-Checkbox.

### P2 — Der synchrone Timeline-Read läuft auf dem Main Actor

**Evidenz**

- Das Projekt setzt `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
- `SQLiteFeedArticleListState.TimelineLoader` ist ausdrücklich `@MainActor`.
- `defaultTimelineLoader` ruft dort synchrone `ArticleDatabase`-/GRDB-Methoden
  auf.
- Die produktive Datenbank nutzt eine `DatabaseQueue`.

**Auswirkung**

Ein langsamer Timeline-, Smart-Folder- oder FTS-Read blockiert den Main Actor,
bis GRDB fertig ist. Die Latest-wins-Queue verhindert veraltete Ergebnisse,
aber nicht den UI-Stall des aktuell laufenden Reads. Eine Cancellation setzt
nur ein Flag; die synchrone SQL-Abfrage selbst läuft weiter.

**Vergleich mit NetNewsWire**

NetNewsWire koordiniert `FetchRequestQueue` und `FetchRequestOperation` ebenfalls
auf dem Main Actor. Die eigentlichen Fetcher rufen jedoch asynchrone
`ArticlesDatabase.fetch…Async`-Methoden auf, die über die Datenbank-Queue und
Continuations ausgeführt werden. Die UI-Koordination bleibt main-actor-isoliert,
die Datenbankarbeit nicht.

Die richtige Schlussfolgerung lautet deshalb nicht automatisch
`DatabaseQueue` durch `DatabasePool` ersetzen. Zuerst muss Feedivo dieselbe
saubere asynchrone Ausführungsgrenze herstellen. Ein Pool ist erst nach
Messungen zu parallelen Reads und Write-Contention zu bewerten.

**Empfehlung**

Asynchrone Read-/Write-APIs in `FeedivoDatabase` beziehungsweise einen dedizierten
Datenbank-Executor einführen. `SQLiteFeedArticleListState` soll nur Start,
Cancellation und Ergebnisübernahme auf dem Main Actor koordinieren.

### P2 — Smart-Folder-Badges und Gelesen-Defaults sind unvollständig

**Evidenz**

- `SQLiteSidebarState` berechnet getrennte Read-/Unread-Counts nur für `all`
  und `today`.
- `SQLiteFeedArticleListView.defaultShowsReadArticles` aktiviert gelesene
  Treffer nur für `starred`.
- `FEATURES.md` verlangt das gemischte Badge- und Anzeigeverhalten auch für
  `starred`, `thisWeek`, `hidden` und `saved`.

**Auswirkung**

Sidebar und Artikelliste zeigen je nach Default-Smart-Folder unterschiedliche
Semantik. Das ist vor allem ein Integrationsproblem zwischen Store-Count,
Sidebar-Row und Listen-Default.

**Vergleich mit NetNewsWire**

NetNewsWire kapselt Smart-Feed-Counts über dedizierte Delegate-/Account-Abfragen.
Feedivo hat mit `TimelineStore.readUnreadCounts` bereits die passende
Store-Funktion, ruft sie aber nur für einen Teil der mitgelieferten Ordner auf.

**Empfehlung**

Die Default-Key-Policy zentral definieren und sowohl für Sidebar-Counts als auch
für Listen-Defaults verwenden. Dadurch können die beiden Oberflächen nicht mehr
auseinanderlaufen.

## Test- und Build-Befund

Ausgeführt wurde:

```text
xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' build
```

Ergebnis: `BUILD SUCCEEDED`.

Die vollständige Testsuite wurde ebenfalls gestartet. Mehrere bestehende
Architektur-/Source-Tests schlugen bereits vor dem Abbruch regulär fehl. Die
Suite wurde nach mehr als drei Minuten beendet, weil mehrere schwere Tests noch
liefen und Xcode beim Finalisieren der Testsession blockierte. Durch den Abbruch
nachträglich als `0.000 seconds` fehlgeschlagene Tests sind nicht als echte
Regression zu bewerten.

Zusätzlich erzeugt der Test-Build zahlreiche Warnungen zu Main-Actor-isolierten
Typen und Conformances. Der Compiler weist ausdrücklich darauf hin, dass diese
im Swift-6-Sprachmodus Fehler werden.

## Gesamtvergleich mit NetNewsWire

| Bereich | Feedivo heute | NetNewsWire-Mechanik | Bewertung |
|---|---|---|---|
| Persistenz | SQLite/GRDB-only | eigene SQLite-Schicht | strukturell gleichgerichtet |
| Artikelstatus | getrennte `article_statuses` | getrennte Status-Tabelle | gleichgerichtet |
| Suche | FTS5 im Store | eigene Search-Tabelle | gleichgerichtet |
| Timeline-Koordination | Latest-wins Queue | cancellable FetchRequestQueue | gleichgerichtet |
| DB-Ausführung | synchroner Read im Main-Actor-Loader | async Fetch über DB-Queue | relevante Lücke |
| Listenmenge | globales 500er-Limit | vollständige Feed-/Folder-Menge, gezielte Speziallimits | relevante Lücke |
| Sortierung | teilweise nach SQL-Limit im UI | konsistent über komplette Fetch-Menge | relevante Lücke |
| Rendering | SwiftUI `List` | AppKit `NSTableView` | bewusster Unterschied |
| Refresh | Conditional GET, Body-Hash, parallele Feeds | zusätzlich stärkere Skip-/Host-Policies | Feedivo gut, ausbaufähig |
| Sync | sichtbarer Bool ohne Backend | echte Account-Typen und Sync-Backend | nicht integriert |
| Fehlerzustand DB | stiller In-Memory-Fallback | explizite Account-/Fehlerpfade | Sicherheitslücke |

## Empfohlene Reihenfolge

1. Silent In-Memory-Fallback entfernen und echten Datenbankfehler anzeigen.
2. Tote Kontextmenüaktionen verbinden und iCloud-UI ehrlich zurückstufen.
3. Sortierung in die SQL-Abfrage verlagern und Keyset-Pagination ergänzen.
4. Asynchrone Datenbank-Ausführungsgrenze nach NetNewsWire-Prinzip einführen.
5. Smart-Folder-Policy zentralisieren.
6. Fehlgeschlagene Tests reparieren und Swift-6-Warnungen als eigenen
   Härtungsslice bearbeiten.
7. Erst danach mit Instruments entscheiden, ob SwiftUI `List` ausreicht oder
   eine `NSTableView`-Artikelliste nötig wird.

## Entscheidung

Feedivo sollte NetNewsWire weiterhin bei Datenmechanik, Fehlergrenzen und
asynchronen Fetch-Pfaden folgen. Eine vollständige UI-Kopie ist nicht nötig.
Der größte kurzfristige Hebel ist keine AppKit-Neuentwicklung, sondern die
korrekte Verbindung von SQL-Sortierung, Pagination und asynchroner
Datenbankausführung.
