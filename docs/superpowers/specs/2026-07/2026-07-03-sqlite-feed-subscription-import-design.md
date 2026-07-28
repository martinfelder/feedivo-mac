# SQLite Feed Subscription Import Design

## Ziel

Feed hinzufügen, OPML-Import und First-Run-Wizard sollen neue Feeds SQLite-first
anlegen. SQLite ist danach die kanonische Quelle für Feed-Metadaten, Artikel,
Status, Logs, Ordner und spätere Refreshes.

Die bestehende Oberfläche bleibt unverändert. Add-Feed-Sheet, OPML-Review und
First-Run-Wizard behalten ihre sichtbaren Abläufe und Texte.

## Kontext

Die Artikelliste und der Reader lesen bereits SQLite-Daten. Auch die Sidebar nutzt
SQLite-Snapshots für Titel, URL, Favicon, Ordner und Ungelesen-Zähler.

Ein Übergangspunkt ist noch offen: `ContentView` und `SidebarView` beziehen ihre
Feed-Identitäten weiterhin aus `@Query [Feed]`. Wenn neue Feeds ausschließlich in
SQLite gespeichert würden, könnten sie zwar importiert sein, aber in der aktuellen
Sidebar-Auswahl unsichtbar bleiben.

## Gewählter Schnitt

Die neue Feed-Abo-/Importlogik schreibt SQLite als Wahrheit und legt zusätzlich
eine minimale SwiftData-Feed-Zeile als Übergangsidentität an.

Diese SwiftData-Zeile dient nur dazu, dass bestehende Navigation, Auswahl und
Kontextmenüs den Feed weiter finden. Artikel werden nicht mehr als SwiftData-
Importquelle aufgebaut. Der erste Abruf neuer Artikel läuft über
`SQLiteFeedRefreshService`.

## Komponenten

### SQLiteFeedSubscriptionService

Ein neuer Service kapselt die Mutationen für neue Feed-Abos:

- einzelnen Feed anlegen
- OPML-Batch importieren
- Duplikate gegen SQLite erkennen
- Ordner aus OPML in `FeedFolderStore` sichern
- Feed-Tags aus OPML über `TagStore` anlegen und dem Feed zuweisen
- Erst-Refresh über `SQLiteFeedRefreshService` ausführen
- kompakte Ergebniswerte für bestehende UI-Flows zurückgeben

Der Service hängt an `FeedivoDatabase` und nutzt `FeedStore`,
`FeedFolderStore`, `TagStore`, `FeedLogStore` und `SQLiteFeedRefreshService`.

### SwiftDataBridge

Die Brücke bleibt bewusst klein:

- pro neuem SQLite-Feed wird eine SwiftData-`Feed`-Zeile mit derselben ID
  angelegt
- Metadaten wie Titel, URL, Website, Favicon, Ordner und Refresh-Intervall
  werden gespiegelt
- es werden keine importierten Artikel in SwiftData erzeugt

Diese Brücke kann entfernt werden, sobald Sidebar und ContentView vollständig auf
SQLite-Feed-Records als Identität umgestellt sind.

### OPMLImportPreviewController

Die Vorschau soll Duplikate gegen SQLite prüfen. Ordnerlisten kommen aus SQLite
plus Preview-Zeilen und benutzerdefinierten Ordnern. Falls SQLite nicht geladen
ist, zeigt der Import einen sichtbaren Fehler statt einen stillen Legacy-Pfad zu
verwenden.

### AddFeedSheet

Discovery und Preview bleiben gleich. Beim Abonnieren ruft das Sheet den neuen
SQLite-first Service auf. Nach Erfolg wird die Sidebar durch die vorhandenen
SQLite-Snapshots und die SwiftData-Übergangsidentität sichtbar aktualisiert.

### FirstRunWizard

Der Wizard nutzt dieselbe OPML-Preview- und Importlogik wie das normale
Import-Sheet. Ein einzelner manuell eingegebener Feed wird als Ein-Feed-Import
behandelt, damit Duplikatprüfung, Ordnerlogik und Ergebniszusammenfassung gleich
bleiben.

## Datenfluss

1. UI sammelt Feed-URL oder OPML-Feeds.
2. Vorschau prüft Erreichbarkeit und Duplikate gegen SQLite.
3. Import-Service legt FeedRecords in SQLite an.
4. Übergangsbrücke legt minimale SwiftData-Feeds mit derselben ID an.
5. Optionaler Erst-Refresh lädt Artikel über SQLite.
6. UI zeigt Ergebnis oder Teilfehler.

## Fehlerbehandlung

Ein nicht geladener SQLite-Store ist ein sichtbarer Fehler. Duplikate werden
übersprungen, außer der User erlaubt sie explizit. Nicht erreichbare Feeds werden
nur importiert, wenn der User das erlaubt. Refresh-Fehler nach erfolgreicher
Feed-Anlage erscheinen als Teilfehler, nicht als kompletter Importabbruch.

## Tests

Neue Tests sollen den Service isoliert prüfen:

- einzelner Feed wird in SQLite gespeichert und SwiftData gespiegelt
- Duplikate werden über normalisierte SQLite-URLs erkannt
- OPML-Ordner werden gespeichert
- OPML-Tags werden gespeichert und Feeds zugewiesen
- Erst-Refresh nutzt `SQLiteFeedRefreshService` und legt Artikel in SQLite an
- Refresh-Fehler blockieren bereits angelegte Feeds nicht

Zusätzlich bleibt ein App-Build Pflicht, weil die betroffenen Views stark über
SwiftUI-Environment und SwiftData-Query zusammenhängen.

## Nicht Teil dieses Schritts

Sidebar und ContentView werden noch nicht vollständig von SwiftData-`Feed` auf
SQLite-`FeedRecord` umgebaut. Das ist der spätere Schritt, mit dem die
Übergangsbrücke wieder entfernt werden kann.
