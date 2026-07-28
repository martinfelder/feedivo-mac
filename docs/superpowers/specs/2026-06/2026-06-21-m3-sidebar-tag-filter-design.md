# M3 Sidebar Tag Filter Design

## Ziel

M3 Block B macht gespeicherte Artikel-Tags in der Sidebar nutzbar. Benutzer koennen
einen Tag anklicken und sehen dann die passenden Artikel in der mittleren Spalte.

## Umfang

Implementiert wird bewusst nur der schmale Filter-Schnitt:

- Die Sidebar zeigt vorhandene `Tag`-Eintraege unter der Section `Tags`.
- Jede Tag-Zeile zeigt den Tag-Namen und einen kleinen Farbindikator aus
  `Tag.colorHex`.
- Ein Klick auf eine Tag-Zeile setzt eine eigene Sidebar-Auswahl fuer Tags.
- `ContentView` loest die gewaehlte Tag-Auswahl wie Feeds und Smart Filter auf.
- `ArticleListView` erhaelt einen Tag-Scope und zeigt nur Artikel, die diesen Tag
  direkt besitzen.
- Die bestehende Tag-Verwaltung bleibt ueber den Action-Button im Tags-Header
  erreichbar.

Nicht in diesem Block enthalten:

- Tag-Zaehler in der Sidebar.
- Feed-Tags.
- Automatische Regeln.
- Drag & Drop.
- Smart Folder oder kombinierte Filter.

## Architektur

`SidebarSelection` bekommt neben Smart Filter und Feed eine dritte Variante fuer
Tags. Als stabiler UI-Auswahlschluessel wird wie bei Feeds der
`PersistentIdentifier` des SwiftData-Modells verwendet.

`SidebarView` liest Tags per gezielter `@Query(sort: \Tag.name)` und rendert sie in
der bestehenden dunklen Sidebar-Struktur. Die Row bleibt leichtgewichtig: Name,
Farbindikator, Auswahlhintergrund. Es wird kein Count berechnet, damit die Sidebar
nicht ueber Tag-Relationships Artikel laden muss.

`ContentView` haelt zusaetzlich zur Feed-Query eine Tag-Query und mappt die
ausgewaehlte `PersistentIdentifier` auf das aktuelle `Tag`-Objekt. Wird ein Tag
ausgewaehlt, wird die Artikelauswahl zurueckgesetzt und `ArticleListView(tag:)`
angezeigt.

`ArticleListView` folgt dem vorhandenen Muster der Feed- und Smart-Filter-Scopes.
Die eigentliche SwiftData-Query fuer Tags wird in `ArticleListQuery` gekapselt,
damit sie separat testbar bleibt.

## Datenfluss

1. `SidebarView` zeigt alle Tags aus SwiftData.
2. Benutzer klickt eine Tag-Zeile.
3. `SidebarSelection.tag(tag.persistentModelID)` wird gesetzt.
4. `ContentView` findet den passenden Tag in seiner Tag-Query.
5. `ArticleListView(tag:)` erstellt eine Query fuer Artikel mit diesem Tag.
6. Die sichtbare Artikelliste wird wie bisher an die Reader-Navigation gemeldet.

## Fehler- und Leerzustand

Wenn keine Tags existieren, bleibt die Section ruhig leer; der Tag-Manager ist
weiterhin erreichbar. Wenn eine gespeicherte Auswahl auf keinen vorhandenen Tag mehr
zeigt, zeigt `ContentView` den bestehenden Platzhalter fuer fehlende Auswahl.

Eine leere Tag-Artikelliste nutzt den bestehenden `ArticleListContent`-Leerzustand.

## Tests

Die Umsetzung bekommt fokussierte Tests fuer die neue Query-Hilfslogik:

- Artikel mit dem ausgewaehlten Tag werden gefunden.
- Artikel ohne diesen Tag werden nicht gefunden.
- Die Sortierung bleibt `publishedAt` absteigend.

Die bestehende Build-/Test-Verifikation bleibt:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -skip-testing:FeedivoUITests -derivedDataPath /private/tmp/feedivo-m3-sidebar-tag-filter-derived-data
```

## Dokumentation

Nach der Umsetzung werden `AGENTS.md` und `docs/FEATURES.md` aktualisiert:

- M3 Block B als fertig markieren.
- Sidebar-Tag-Filter in Projektstruktur und Feature-Roadmap beschreiben.
- Den bewusst verschobenen Umfang, besonders Tag-Zaehler und automatische Regeln,
  klar benennen.
