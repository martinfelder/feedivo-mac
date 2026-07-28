# SQLite Refresh and Snapshot Integration

Stand: 2026-07-02

## Ziel

Feedivo soll den Performance-kritischen Hauptpfad so nah wie sinnvoll an
NetNewsWire ausrichten:

1. Feed-Refresh schreibt direkt in SQLite.
2. Artikel und Artikelstatus bleiben getrennt.
3. Artikellisten, Reader-Daten und Zähler kommen aus gezielten SQLite-Queries.
4. Statusänderungen wie gelesen/ungelesen und Stern berühren nur die
   Status-Tabelle.

Der erste SQLite/GRDB-Slice hat dafür das Fundament gebaut. Dieser nächste Slice
verbindet das Fundament mit der Feed-Mechanik, ohne die komplette UI in einem
großen Schritt umzubauen.

## NetNewsWire-Referenz

NetNewsWire trennt die Mechanik bewusst in kleine, direkte Datenbankpfade:

- `ArticlesDatabase` schreibt und liest Artikel über SQLite.
- `ArticlesTable` speichert Artikelinhalt und Feed-Zuordnung.
- `StatusesTable` speichert pro Artikel nur Statuswerte wie gelesen und Stern.
- Feed-Refresh ruft eine Datenbankoperation auf, die Artikel einfügt oder
  aktualisiert und fehlende Statuszeilen ergänzt.
- Timeline- und Zählerabfragen laufen über SQL statt über geladene Objektgraphen.
- Feed-Metadaten, HTTP-Validatoren und Fehlerzustände liegen in eigenen
  Datenstrukturen, statt die Artikelliste zu belasten.

Feedivo soll diese Mechanik übernehmen, aber nicht blind Dateinamen oder
Implementierungsdetails kopieren. Wichtig ist die gleiche Architekturwirkung:
kleine SQL-Operationen, stabile Artikel-IDs, getrennte Statusdaten und
Snapshot-Reads.

## Entscheidung

Der nächste Umsetzungsschritt ist ein SQLite-first Refresh- und Snapshot-Kern.
Er ersetzt nicht sofort alle SwiftData-Views, sondern baut den neuen Hauptpfad so,
dass die UI danach gezielt umgestellt werden kann.

Konkret wird ein neuer Service eingeführt, der ungefähr NetNewsWires
`ArticlesDatabase.updateAsync(parsedItems:feedID:)` entspricht:

- Feed abrufen und parsen bleibt Aufgabe von `FeedService`.
- Der neue SQLite-Refresh-Service nimmt ein Feed-Ziel und die geparsten Daten.
- Artikel werden in einer GRDB-Transaktion upserted.
- Für neue Artikel werden Statuszeilen angelegt.
- Bestehende Statuswerte bleiben erhalten.
- Feed-Metadaten, `unreadCount`, Refresh-Zeiten und Fehlerlog werden in SQLite
  aktualisiert.
- Das Ergebnis enthält neue/geänderte Artikel-IDs und Zähler, damit UI und
  Background-Refresh später ohne Objektgraphen reagieren können.

## Geplanter Scope

### 1. Refresh-Service

Ein neuer Service, voraussichtlich `SQLiteFeedRefreshService`, koordiniert:

- Feed aus SQLite laden oder anhand URL anlegen.
- `FeedService.fetchFeed` aufrufen.
- `ParsedArticle` in `ArticleUpsertInput` übersetzen.
- Artikel gesammelt in SQLite speichern.
- Statuszeilen für neue Artikel sicherstellen.
- Feed-Zähler und Feed-Metadaten aktualisieren.
- Feed-Log schreiben.
- Ein kompaktes `SQLiteFeedRefreshResult` zurückgeben.

Der Service soll testbar sein. Dafür bekommt er eine kleine Fetching-Abstraktion
oder einen injizierbaren Parser/Fake, damit Tests nicht ins Netzwerk gehen.

### 2. Store-Erweiterungen

Die vorhandenen Stores werden erweitert, nicht ersetzt:

- `ArticleStore`
  - Batch-Upsert in einer einzigen GRDB-Transaktion.
  - Rückgabe, welche Artikel neu waren und welche aktualisiert wurden.
  - Identität bleibt wie im Fundament: erst `sourceID`, dann `link`.

- `ArticleStatusStore`
  - Statuszeilen für Artikel-IDs sicherstellen.
  - Ungelesen-Zähler pro Feed oder Feed-Gruppe effizient lesen.
  - Statusänderungen bleiben Status-only.

- `FeedStore`
  - Feed nach URL finden.
  - Refresh-Metadaten aktualisieren.
  - `unreadCount` aus SQLite setzen.
  - Feed-Metadaten aus `ParsedFeed` übernehmen, ohne User-Felder unnötig zu
    überschreiben.

- `FeedLogStore`
  - Refresh-Erfolg und Refresh-Fehler schreiben.
  - Später für Feed-Eigenschaften und Diagnose nutzbar.

### 3. Snapshot-Reads als UI-Vorbereitung

Die vorhandenen Snapshot-Typen bleiben die Zieloberfläche für spätere UI-Slices:

- Sidebar liest Feeds und Zähler als `FeedSidebarSnapshot`.
- Artikelliste liest `ArticleListSnapshot` statt SwiftData-Artikelobjekte.
- Reader liest `ArticleReaderSnapshot` über eine Artikel-ID.

In diesem Slice müssen noch nicht alle Views umgestellt werden. Der Kern soll
aber so gebaut werden, dass der nächste Slice die mittlere Liste und den Reader
ohne erneuten Datenbankumbau anbinden kann.

## Nicht-Ziele dieses Slices

- Keine SwiftData-Datenmigration.
- Keine iCloud-Sync-Integration.
- Keine vollständige UI-Umschaltung.
- Keine Regeln, Smart Folders, Tag-Engine oder Suche auf SQLite.
- Keine OPML-Komplettumstellung.
- Keine Änderung am visuellen Design.

Diese Punkte kommen später. Performance-relevant ist zuerst der vertikale Pfad:
Refresh rein, SQLite speichern, Snapshot raus, Status ändern.

## Tests

Der Slice gilt als fertig, wenn fokussierte Tests die neue Mechanik abdecken:

- Ein Refresh fügt Feed-Artikel ein und erzeugt Statuszeilen.
- Ein zweiter Refresh mit denselben Artikel-IDs erzeugt keine Duplikate.
- Aktualisierte Artikeldaten überschreiben Inhalt, erhalten aber Status.
- Ein später gelieferter `sourceID` wird nach Link-Fallback dauerhaft gespeichert.
- `unreadCount` wird nach Insert und Statusänderung korrekt berechnet.
- Refresh-Fehler erzeugen einen Logeintrag, ohne vorhandene Artikel zu beschädigen.
- Batch-Upsert läuft in einer Transaktion und ist für größere Mengen schnell genug
  für einen Smoke-Test.

## Risiken

- Die aktuelle SwiftUI-Auswahl arbeitet noch mit `Article?`. Für den SQLite-Pfad
  muss sie später auf Artikel-IDs und Snapshots wechseln.
- SwiftData-Modelle existieren während des Übergangs weiter. Neue
  Performance-Kernlogik soll trotzdem nicht mehr an SwiftData angebunden werden.
- Feedivo hat Features wie Tags, Regeln und Smart Folders, die NetNewsWire in
  dieser Form nicht abbildet. Diese Features werden später auf SQLite adaptiert,
  aber nicht im ersten Refresh-Slice.

## Ergebnis nach diesem Slice

Nach diesem Slice hat Feedivo einen testbaren SQLite-Refresh-Kern nach
NetNewsWire-Mechanik. Die App kann danach schrittweise auf diesen Kern umgestellt
werden:

1. Sidebar-Zähler aus SQLite.
2. Artikelliste aus SQLite-Snapshots.
3. Reader aus SQLite-Snapshots.
4. Statusaktionen direkt über `article_statuses`.
5. SwiftData-Hauptpfad entfernen oder nur noch als Altlast behandeln.
