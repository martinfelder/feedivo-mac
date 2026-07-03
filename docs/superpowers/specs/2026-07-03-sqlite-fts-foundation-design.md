# SQLite FTS Foundation Design

## Ziel

Feedivo bekommt ein SQLite-FTS-Fundament für schnelle Artikelsuche über große
Datenmengen. Dieser Slice baut nur Index und Store-Abfrage; die Such-UI wird in
einem Folgeslice angeschlossen.

## Scope

Die Migration legt eine FTS5-Tabelle `article_search` an, die `title`, `summary`,
`content` und `author` indiziert. Der Index ist über SQLite-Trigger an die
`articles`-Tabelle gekoppelt und bleibt bei Insert, Update und Delete automatisch
synchron.

`ArticleStore` bekommt eine einfache Suchabfrage, die FTS-Treffer als
`ArticleListSnapshot`s zurückgibt. Damit kann die spätere Listen- und
Suchfenster-UI dieselben leichten SQLite-Zeilen verwenden wie Feed-, Tag- und
SmartFilter-Timelines.

## Architektur

Die FTS-Tabelle nutzt `content='articles'` und `content_rowid='rowid'`, damit
SQLite die bestehende Artikel-Tabelle als Quelle verwendet. Trigger
`articles_ai`, `articles_au` und `articles_ad` pflegen den Index. Eine
`rebuild`-Anweisung am Ende der Migration indexiert bereits vorhandene Artikel.

Die Suche bleibt vorerst bewusst einfach: Query-Text wird als FTS-Query an SQLite
übergeben, Treffer werden mit `articles`, `feeds` und `article_statuses` gejoint,
Hidden-Artikel werden standardmäßig ausgeschlossen und die Ausgabe wird wie die
Timeline nach Artikeldatum sortiert.

## Tests

Migrationstests prüfen FTS-Tabelle und Trigger. Store-Tests prüfen, dass Insert,
Update und Delete im FTS-Index sichtbar werden und dass die Suche Titel, Summary,
Content und Author findet.
