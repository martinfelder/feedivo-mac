# SQLite Custom Smart Folders Design

Stand: 2026-07-03

## Ziel

Benutzerdefinierte intelligente Ordner sollen ihre Artikellisten aus SQLite
laden, statt SwiftData-Artikel zu materialisieren und danach im Speicher durch
`SmartFolderEngine` zu filtern. Das schließt eine der letzten schweren
Hauptpfad-Lücken im SQLite/GRDB-Umbau.

## Scope

Die Smart-Folder-Verwaltung bleibt in diesem Slice in SwiftData. Name,
Darstellung, Reihenfolge und Bedingungen werden weiter über die bestehenden
Views und ViewModels gepflegt. Nur die Auswertung für die Artikelliste wechselt
auf SQLite.

`SmartFolder` wird dafür beim Anzeigen in einen leichten,
sendbaren SQLite-Snapshot übersetzt. `TimelineStore` bekommt einen neuen
Timeline-Scope für benutzerdefinierte Smart Folders und baut daraus eine
SQL-Where-Clause. Die UI nutzt anschließend wie bei Feeds, Tags und
vordefinierten SmartFiltern `SQLiteFeedArticleListView` und `SQLiteReaderView`.

## Semantik

- `RuleMatchMode.all` wird als `AND` übersetzt.
- `RuleMatchMode.any` wird als `OR` übersetzt.
- Leere Bedingungen matchen wie bisher alle sichtbaren Artikel.
- `tag` prüft direkte Artikel-Tags und Feed-Tags.
- `feed` prüft Feed-ID oder Feed-Titel.
- `feedFolder` prüft `feeds.folderName`.
- `date` unterstützt `today`, `thisWeek` und `olderThanDays`.
- `status` prüft `isRead`, `isStarred`, `isArchived` und `isHidden`.
- `title`, `author` und `text` werden SQL-seitig geprüft.
- `text contains` nutzt den vorhandenen FTS-Index `article_search`, damit
  Artikel-Content nicht in Swift geladen werden muss.

## Nicht-Ziele

- Keine Migration der Smart-Folder-Definitionen nach SQLite.
- Keine Änderung am Editor für intelligente Ordner.
- Kein neuer visueller Entwurf.
- Keine Umsetzung komplexer SQL-Optimierungen über diesen Scope hinaus.

## Tests

`SQLiteTimelineStoreTests` deckt Status, Feed, Feed-Ordner, Tags, Datum, Text,
`all`/`any`, `isNot` und Hidden-Verhalten ab. Ein Konfigurationstest prüft, dass
`ContentView` für `selectedSmartFolder` den SQLite-Listenpfad nutzt.
