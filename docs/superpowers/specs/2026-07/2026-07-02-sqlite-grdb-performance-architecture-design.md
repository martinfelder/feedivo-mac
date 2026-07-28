# SQLite/GRDB Performance-Architektur für Feedivo

Stand: 2026-07-02

## Kontext

Feedivo ist bei großen Datenmengen spürbar langsamer als NetNewsWire. Die
letzten Performance-Slices haben SwiftData bereits entlastet: Conditional GET,
Body-Hash-Skip, Batch-Refreshes, leichte Listen-Fetches, Reader-Snapshots,
Thumbnail-Caches und Snapshot-basierte Artikelzeilen sind umgesetzt.

Der Vergleich mit NetNewsWire zeigt aber, dass die verbleibenden Unterschiede
strukturell sind: NetNewsWire nutzt eine direkte SQLite-Schicht, getrennte
Artikel-/Status-Tabellen, gezielte SQL-Queries, Status-Caches, Suchindexe und
cancellable Timeline-Fetches. Feedivo nutzt aktuell SwiftData-Modelle und
SwiftUI-Queries. Das ist komfortabel, aber bei 100.000 Artikeln schwerer zu
kontrollieren.

Martin hat entschieden, dass Performance Vorrang vor iCloud Sync und
Bestandsdatenmigration hat. Da Feedivo aktuell nur von Martin genutzt wird, ist
eine frische SQLite-Datenbank ohne Migration bestehender SwiftData-Daten für
diese Umbauphase akzeptiert.

## Entscheidung

Feedivo wird schrittweise auf eine SQLite-only-Persistenz mit GRDB umgebaut. Der
erste Umbau ist keine komplette Produktmigration, sondern eine vertikale
Performance-Scheibe entlang des Hauptpfads: Feeds, Refresh, Artikelliste, Reader
und Artikelstatus.

SwiftData bleibt während des Übergangs im Projekt, aber der neue Hauptpfad soll
SQLite-first werden. iCloud Sync über SwiftData/CloudKit wird bewusst
zurückgestellt, bis die neue Persistenzarchitektur stabil ist.

## Ziele

- Artikellisten bei 500 Feeds und 100.000 Artikeln flüssig halten.
- SwiftUI nur kleine Werttypen geben, keine lebenden Persistenz-Objektgraphen.
- Artikelinhalt und Artikelstatus nach NetNewsWire-Vorbild trennen.
- Feed-Refresh idempotent und transaktional machen.
- Zähler und Statusänderungen über gezielte SQL-Operationen ausführen.
- Reader-Detaildaten erst beim Öffnen eines Artikels laden.
- Die Architektur testbar halten, bevor große UI-Pfade umgestellt werden.

## Nicht-Ziele der ersten Welle

- Keine Migration bestehender SwiftData-Daten.
- Kein iCloud Sync.
- Keine vollständige Portierung von Tags, Regeln, Smart Folders, OPML,
  Export, Offline-Download oder globaler Volltextsuche.
- Kein Design-/UI-Redesign.
- Kein AppKit-Umbau der Artikelliste. SwiftUI bleibt für die UI bestehen.

## Datenmodell

Die erste SQLite-Version nutzt UUID-Strings als Primärschlüssel. Das hält die
UI- und Snapshot-Schicht einfach und vermeidet eine zu frühe Bindung an
SQLite-RowIDs.

### Tabelle `feeds`

Speichert abonnierte Feeds und Refresh-Metadaten.

Wichtige Felder:

- `id`
- `url`
- `title`
- `websiteURL`
- `faviconURL`
- `folderName`
- `refreshIntervalMinutes`
- `lastRefreshedAt`
- `lastETag`
- `lastModified`
- `lastBodyHash`
- `lastHTTPStatusCode`
- `unreadCount`
- `createdAt`
- `updatedAt`

Wichtige Indizes:

- `feeds(url)` unique
- `feeds(title)`

### Tabelle `articles`

Speichert Inhalt und Metadaten eines Artikels, aber keine veränderlichen
Lesestatuswerte.

Wichtige Felder:

- `id`
- `feedID`
- `sourceID`
- `link`
- `title`
- `summary`
- `content`
- `imageURL`
- `author`
- `publishedAt`
- `arrivedAt`
- `updatedAt`
- `estimatedReadingMinutes`

Wichtige Indizes:

- `articles(feedID, publishedAt)`
- `articles(feedID, sourceID)`, eindeutig für nicht-leere `sourceID`
- `articles(feedID, link)`, eindeutig für nicht-leere Links als Fallback
- `articles(publishedAt)`

`sourceID` ist die bevorzugte Wiedererkennung, wenn ein Feed stabile IDs liefert.
`link` ist Fallback. Upserts müssen verhindern, dass gleiche Artikel bei
Refreshes dupliziert werden.

### Tabelle `article_statuses`

Speichert alle häufig veränderten Statuswerte getrennt vom Artikelinhalt.

Wichtige Felder:

- `articleID`
- `isRead`
- `isStarred`
- `isArchived`
- `isHidden`
- `readAt`
- `starredAt`
- `archivedAt`
- `hiddenAt`
- `dateArrived`

Wichtige Indizes:

- `article_statuses(articleID)` unique
- `article_statuses(isRead)`
- `article_statuses(isStarred)`
- `article_statuses(isArchived)`
- `article_statuses(isHidden)`

Statusänderungen schreiben nur diese Tabelle. Damit bleibt der große
Artikel-Datensatz unverändert, und Listen/Counts können gezielt über Joins und
Aggregate aktualisiert werden.

### Tabelle `feed_logs`

Speichert Refresh-Ergebnisse und Fehler pro Feed.

Wichtige Felder:

- `id`
- `feedID`
- `createdAt`
- `level`
- `message`
- `httpStatusCode`
- `newArticleCount`

### Spätere Tabelle `article_search`

Volltextsuche wird später über SQLite FTS ergänzt. Sie gehört nicht in die erste
Welle, weil Timeline, Reader und Status zuerst stabil sein müssen.

## Architektur

Die neue Persistenz wird in klaren Schichten eingeführt:

1. `Database/`
   - `FeedivoDatabase`
   - GRDB-Bootstrap
   - Migrationen
   - Record-Typen für Feeds, Artikel, Status und Logs

2. `Stores/`
   - `FeedStore`
   - `ArticleStore`
   - `ArticleStatusStore`
   - `TimelineStore`
   - `SearchStore` später

3. `Snapshots/`
   - `FeedSidebarSnapshot`
   - `ArticleListSnapshot`
   - `ArticleReaderSnapshot`
   - `ArticleStatusSnapshot`

4. `Services/`
   - `FeedService`, `FeedDiscoveryService`, `FaviconService` und Parsing bleiben
     grundsätzlich erhalten.
   - Refresh-Services schreiben über Stores nach SQLite.

Views greifen nicht direkt auf GRDB oder SQL zu. Sie erhalten Snapshots und rufen
ViewModels/Stores für Aktionen auf. Damit bleibt SQLite zentral kontrolliert und
die UI wird nicht zum Persistenz-Layer.

## Datenfluss

Beim App-Start öffnet Feedivo `Feedivo.sqlite`, führt GRDB-Migrationen aus und
stellt die Store-Schicht bereit.

Feed hinzufügen:

1. Discovery/Parsing findet Feed-Metadaten.
2. `FeedStore` legt den Feed an.
3. Optional startet direkt ein Refresh.
4. `ArticleStore` upsertet Artikel.
5. `ArticleStatusStore` erzeugt fehlende Statuszeilen.

Feed-Refresh:

1. Refresh lädt Feed mit Conditional GET.
2. Unveränderte Feeds enden ohne Parsing und ohne Artikel-Schreibarbeit.
3. Geänderte Feeds werden pro Feed in einer Transaktion verarbeitet.
4. Artikel werden anhand `sourceID` oder Link aktualisiert oder eingefügt.
5. Statuszeilen werden nur erzeugt, nicht überschrieben.
6. Feed-Zähler und Logs werden gezielt aktualisiert.

Timeline:

1. `TimelineStore.fetchArticles(scope:)` führt eine limitierte SQL-Query aus.
2. Die Query joint `articles`, `article_statuses` und `feeds`.
3. SwiftUI erhält nur `ArticleListSnapshot`-Werte.
4. Der ausgewählte Artikel wird per ID gehalten.

Reader:

1. Bei Auswahl lädt `ArticleStore.readerArticle(id:)` den vollständigen Inhalt.
2. Reader-Vorbereitung/HTML-Parsing bleibt asynchron.
3. Statusaktionen schreiben ausschließlich `article_statuses`.

Sidebar:

1. Feeds und Zähler kommen aus SQL-Snapshots.
2. Ungelesene Counts werden aggregiert oder aus gepflegten Feed-Zählern gelesen.
3. Status-Badges nutzen SQL-Counts statt SwiftData-Queries.

## Umsetzungs-Slices

1. DB-Fundament
   GRDB Dependency, SQLite-Datei, Migrationen und Record-Typen.

2. Store-Schicht
   Testbare Stores für Feeds, Artikel, Status, Timeline und Logs.

3. Refresh schreibt nach SQLite
   Der bestehende Feed-Abruf bleibt, aber neue/aktualisierte Artikel landen in
   SQLite.

4. Timeline liest Snapshots aus SQLite
   Artikelliste bekommt kompakte Snapshot-Queries mit Limit, Sortierung und
   Status-Join.

5. Reader liest Detaildaten aus SQLite
   Nur der ausgewählte Artikel wird vollständig geladen.

6. Status-Aktionen über SQLite
   Gelesen, Stern, Archiv und Hidden ändern nur `article_statuses`.

7. Suche später über FTS
   Die globale/in-list Suche wird nach Timeline und Reader auf SQLite FTS
   umgestellt.

## Scope der ersten Welle

In Scope:

- Feeds speichern und laden aus SQLite
- Feed-Refresh schreibt Artikel in `articles`
- Artikelstatus liegt getrennt in `article_statuses`
- Artikelliste liest Snapshots aus SQLite
- Reader lädt Detaildaten aus SQLite
- Gelesen/Ungelesen, Stern, Archiv und Hidden laufen über Status-Updates
- Sidebar-Zähler kommen aus SQL-Aggregaten oder gepflegten SQL-Zählern
- Feed-Logs werden in SQLite geschrieben

Bewusst später:

- iCloud Sync
- SwiftData-Bestandsdatenmigration
- Tags
- Regeln
- Smart Folders
- OPML Import/Export
- Artikel-Export
- Offline-Download
- SQLite FTS-Suche

## Fehlerverhalten

- Feed-Refresh läuft pro Feed in einer Transaktion.
- Ein kaputter Feed blockiert nicht die anderen Feeds.
- Feed-Fehler werden in `feed_logs` gespeichert.
- Upserts sind idempotent: gleiche `sourceID` oder gleicher Link erzeugt keine
  Duplikate.
- Statuszeilen werden bei Artikel-Updates nicht überschrieben.
- Alte Statusdaten dürfen länger leben als Artikeldaten, damit später wieder
  auftauchende Artikel ihren Status behalten können. Die genaue Retention-Policy
  kommt in einem späteren Cleanup-Slice.
- Die Status-Tabelle bekommt deshalb keine Cascade-Löschung, die Statusdaten
  automatisch mit alten Artikeln entfernen würde.
- Views führen keine direkten SQL-Schreiboperationen aus.

## Tests und Messpunkte

Die erste Implementierung braucht Tests vor dem UI-Umbau:

- Migrationstest: frische SQLite-DB erzeugen, Tabellen und Indizes prüfen.
- Store-Test: Feed anlegen, Artikel upserten, Status separat ändern.
- Refresh-Test: gleicher Artikel wird aktualisiert statt dupliziert.
- Status-Test: Gelesen/Stern/Archiv ändert nur `article_statuses`.
- Timeline-Test: Query liefert kompakte Snapshots mit korrekter Sortierung.
- Count-Test: ungelesene Zähler stimmen nach Statusänderungen.
- Performance-Smoke-Test mit synthetischen Daten, z. B. 100 Feeds und 50.000
  Artikel.

Das Ziel ist nicht ein perfekter Benchmark, sondern ein Frühwarnsystem: Timeline
und Counts müssen bei großem Datenbestand im erwarteten Bereich bleiben.

## Konsequenzen

Diese Entscheidung ersetzt mittelfristig ADR-001 (`SwiftData statt Core Data`) für
den Hauptdatenbestand. SwiftData kann temporär im Code bleiben, ist aber nicht
mehr die Zielarchitektur für Feeds, Artikel und Status.

Die iCloud-Beta wird zurückgestellt. Ein späterer Sync muss entweder auf der
SQLite-Architektur aufsetzen oder bewusst als getrennte zweite Schicht geplant
werden. Für die aktuelle Priorität ist lokale Performance wichtiger als Sync.

Die nächste Arbeit nach dieser Spec ist ein detaillierter Implementierungsplan,
kein direkter Code-Umbau.
