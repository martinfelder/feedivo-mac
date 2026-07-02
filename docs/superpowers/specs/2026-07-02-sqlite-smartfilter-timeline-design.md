# SQLite SmartFilter Timeline Design

## Ziel

Die vordefinierten globalen SmartFilter sollen im Hauptfenster SQLite-first laufen,
damit große Artikelbestände nicht mehr über SwiftData-Queries und In-Memory-Filter
materialisiert werden.

## Scope

Dieser Slice umfasst `Alle Artikel`, `Ungelesen`, `Mit Stern`, `Heute` und
`Ausgeblendet`, weil diese Werte aktuell im bestehenden `SmartFilter`-Enum
existieren. Benutzerdefinierte Smart Folders, Volltextsuche/FTS, Export aus
SQLite-Artikeln und Offline-Aktionen bleiben eigene Folgeslices.

## Architektur

`TimelineScope` bekommt einen SmartFilter-Scope. `TimelineStore` übersetzt diesen
Scope in gezielte SQL-Where-Klauseln gegen `articles`, `feeds` und
`article_statuses`. `SQLiteFeedArticleListState` lädt diesen Scope wie Feed- und
Tag-Timelines und hält Navigation über SQLite-Artikel-IDs.

`SQLiteFeedArticleListView` erhält einen Initializer für `SmartFilter`.
`ContentView` routed `selectedSmartFilter` auf diese View, sodass Liste und Reader
über den vorhandenen SQLite-Pfad laufen.

## Fehlerverhalten

Fehlt die SQLite-Datenbank, zeigt die bestehende SQLite-Listen-View den vorhandenen
Fehlerzustand. Leere Ergebnisse zeigen den bestehenden leeren Zustand. Hidden-
Artikel werden nur für den Hidden-SmartFilter sichtbar geladen.

## Tests

Die Store-Tests prüfen, dass SmartFilter-SQL nur passende Artikel lädt. Die
State-Tests prüfen, dass der SmartFilter-Scope geladen und Navigation aufgebaut
wird. Ein Source-Test in `FeedivoAppSceneConfigurationTests` schützt das Routing in
`ContentView`.
