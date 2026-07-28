# SQLite Feed Reader Path

Stand: 2026-07-02

## Ziel

Feedivo soll für den normalen Feed-Pfad sichtbar auf die NetNewsWire-nahe
SQLite-Mechanik wechseln:

1. Ein Feed in der Sidebar wird ausgewählt.
2. Die Artikelliste dieses Feeds kommt aus SQLite-Snapshots.
3. Die Auswahl arbeitet für diesen Pfad mit SQLite-Artikel-IDs.
4. Der Reader zeigt den Artikel aus einem SQLite-Reader-Snapshot.
5. Gelesen/Stern/Archiv/Hidden-Status werden direkt in `article_statuses`
   geändert.

Der Slice ist bewusst auf die Feed-Auswahl begrenzt. Smart Folders, Tags,
vordefinierte Filter, Regeln, Export und OPML bleiben vorerst auf dem bisherigen
SwiftData-Pfad oder werden für SQLite-Artikel noch nicht angeboten. Dadurch wird
der wichtigste Performancepfad schnell nutzbar, ohne die komplette App in einem
Schritt umzubauen.

## Entscheidung

Wir kombinieren die kleine Feed-Listen-Anbindung mit der Reader-Anbindung, statt
nur eine isolierte SQLite-Liste zu bauen. Das vermeidet eine kurzlebige
Zwischenlösung: Wenn die Liste bereits SQLite-IDs nutzt, soll der Reader direkt
denselben Artikel-ID-Pfad verwenden.

Nicht alle Artikelquellen werden gleichzeitig umgestellt. `ContentView` darf
während des Übergangs zwei Auswahlarten halten:

- `selectedArticle: Article?` für bestehende SwiftData-Pfade.
- `selectedSQLiteArticleID: String?` für den neuen Feed-SQLite-Pfad.

Sobald eine Feed-SQLite-Liste aktiv ist, wird `selectedArticle` geleert. Sobald
ein Legacy-Pfad aktiv ist, wird `selectedSQLiteArticleID` geleert. Das hält die
Übergangslogik sichtbar und vermeidet gemischte Readerzustände.

## Geplanter Scope

### 1. App-Datenbank in SwiftUI bereitstellen

Der neue UI-Pfad braucht Zugriff auf `FeedivoDatabase`. Dafür wird ein kleiner
Environment-Wert eingeführt, z.B. `\.feedivoDatabase`. `FeedivoApp` öffnet die
SQLite-Datenbank und stellt sie der View-Hierarchie bereit.

Für Tests bleibt `FeedivoDatabase.inMemoryForTests()` nutzbar.

### 2. Feed-Zuordnung zwischen SwiftData und SQLite

Die Sidebar liefert heute SwiftData-`Feed`-Objekte. Für den neuen Feed-Pfad muss
der passende SQLite-Feed gefunden werden.

Für diesen Slice wird die URL als Brücke verwendet:

- SwiftData-Feed hat `url`.
- `FeedStore.feed(url:)` findet den SQLite-Feed.
- Wenn kein SQLite-Feed existiert, zeigt die SQLite-Feedliste einen leeren oder
  nicht-bereiten Zustand und fällt nicht still auf globale SwiftData-Queries
  zurück.

Eine spätere Migration kann stabile Cross-Store-IDs ergänzen. Für diesen Slice
reicht URL-Matching, weil `feeds.url` in SQLite eindeutig indiziert ist.

### 3. SQLite Feed Article List

Es entsteht ein Feed-spezifischer Listenpfad, z.B. `SQLiteFeedArticleListView`.

Der View lädt über `TimelineStore.articles(scope: .feed(feedID), ...)`:

- `ArticleListSnapshot` für sichtbare Zeilen.
- Filter `includeRead` und `includeHidden` passend zur bestehenden Listenlogik.
- Limit/Pagination wie bisher in kleinen Batches.

Die Zeile rendert über einen Snapshot und hält kein SwiftData-`Article` mehr.
Die bestehende `ArticleRowView` kann wiederverwendet werden, wenn
`ArticleListItemSnapshot` zusätzlich aus `ArticleListSnapshot` gebaut werden kann.
Offline-Status ist in diesem Slice für SQLite-Artikel `none`, bis Offline-Archiv
auf SQLite umgestellt wird.

### 4. SQLite Reader

Es entsteht ein Reader-Pfad, z.B. `SQLiteReaderView`, der über
`ArticleStore.readerArticle(id:)` einen `ArticleReaderSnapshot` lädt.

Der Reader soll in diesem Slice nicht alle vorhandenen Reader-Features
verdoppeln. Er muss aber den Kern können:

- Titel
- Feedname
- Datum
- Summary/Content
- Link öffnen/kopieren, sofern vorhanden
- Statusanzeige und Statusaktionen

Vollartikel-Modus, Metadaten-Inspector, Export, Regel-Erstellung, Tag-Zuweisung
und Offline-Download bleiben für SQLite-Artikel zunächst nicht verfügbar oder
werden deaktiviert angezeigt.

### 5. Statusaktionen direkt über SQLite

Feed-SQLite-Liste und SQLite-Reader verwenden `ArticleStatusStore`:

- gelesen/ungelesen
- Stern
- Archiv
- Hidden, falls bereits im UI-Pfad benötigt

Nach einer Statusänderung wird der betroffene Snapshot neu geladen. Für die
Sidebar-Zähler kann in diesem Slice zunächst der SQLite-Feed-Zähler aktualisiert
werden; eine vollständige Sidebar-Umstellung kommt danach.

### 6. Navigation

Für den SQLite-Feed-Pfad wird eine leichte Navigation über Artikel-IDs eingeführt:

- Vorherige/nächste ID aus der sichtbaren Snapshot-Liste.
- Reader-Navigation nutzt diese IDs.
- Legacy `ArticleNavigationState` bleibt für SwiftData-Pfade bestehen.

Das vermeidet, dass `ArticleNavigationState` sofort generisch werden muss. Eine
spätere Vereinheitlichung ist möglich, aber nicht nötig für diesen Slice.

## Nicht-Ziele dieses Slices

- Keine vollständige SwiftData-Entfernung.
- Keine Migration bestehender SwiftData-Artikel in SQLite.
- Keine SQLite-Anbindung für Smart Folders, Tags oder globale Filter.
- Keine Regel-Engine auf SQLite.
- Kein Export für SQLite-Artikel.
- Keine Offline-Download-Umstellung.
- Keine Vollartikel-Readability-Integration im SQLite-Reader.
- Keine iCloud-/Sync-Arbeit.

## Tests

Der Slice gilt als fertig, wenn die neuen Einheiten testbar sind:

- Environment-Wert liefert eine gesetzte `FeedivoDatabase`.
- `ArticleListItemSnapshot` kann aus `ArticleListSnapshot` gebaut werden.
- SQLite-Feedliste lädt Snapshots für einen Feed und sortiert/paginiert über
  `TimelineStore`.
- Statusaktionen ändern nur `article_statuses` und laden den Snapshot neu.
- SQLite-Reader lädt `ArticleReaderSnapshot` und wählt Summary/Content
  deterministisch für die Anzeige.
- Feed-Wechsel räumt die jeweils andere Auswahlart auf:
  `selectedArticle` versus `selectedSQLiteArticleID`.

Zusätzlich muss ein fokussierter `xcodebuild test` für die neuen SQLite-UI-
Hilfstypen und Stores laufen sowie ein normaler App-Build.

## Risiken

- Der vorhandene Reader ist umfangreich. Eine direkte Wiederverwendung mit
  `ArticleReaderSnapshot` könnte zu groß werden. Deshalb darf der SQLite-Reader
  zunächst ein schlanker Reader sein, solange der Kernpfad performant und korrekt
  ist.
- Die App hat während des Übergangs zwei Auswahlmodelle. Das ist akzeptiert, muss
  aber in `ContentView` klar getrennt werden.
- Wenn SQLite noch keine Feeds/Artikel enthält, wirkt der neue Feed-Pfad leer.
  Das ist erwartbar, bis Import/Refresh sichtbar auf SQLite umgestellt sind.

## Ergebnis nach diesem Slice

Nach diesem Slice ist der wichtigste lokale Nutzungspfad NetNewsWire-nah:

Feed auswählen → Artikelliste aus SQLite → Artikel-ID auswählen → Reader aus
SQLite → Statusänderung direkt in `article_statuses`.

Damit ist der größte sichtbare SwiftData-Objektgraph aus dem Feed-Lesepfad
entfernt. Danach können Sidebar-Zähler, Smart Folders, Tags, Export und Regeln
einzeln nachgezogen werden.
