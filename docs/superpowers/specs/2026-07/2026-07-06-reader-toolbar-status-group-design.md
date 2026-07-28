# Reader-Toolbar Status-Gruppe Design

## Ziel

Im Artikel-Reader (`SQLiteReaderView`) sollen Stern, Archivieren und Als-ungelesen-markieren als
zusammenhängende Gruppe in der Toolbar erreichbar sein, statt nur über Tastaturkürzel/Menü
(`ArticleCommandActions`) bzw. den bisher einzeln stehenden Archivieren-Button.

## Design

Der bestehende einzelne Archivieren-Button in der Toolbar wird entfernt und zusammen mit zwei neuen
Buttons (Stern, Ungelesen) zu einer Gruppe zusammengefasst: drei Icon-Buttons nebeneinander, davor
ein `Divider()` zur Abgrenzung von den übrigen Toolbar-Items. Position: nach "Original öffnen"
(Safari-Icon), vor "Exportieren".

Alle drei sind Toggle-Buttons, die den aktuellen Artikelstatus per gefülltem/leerem SF-Symbol
zeigen — dasselbe Muster wie der bisherige Archivieren-Button:

- Stern: `star` / `star.fill`, ruft `state.toggleStarred(database:)`
- Archivieren: `archivebox` / `archivebox.fill` (unverändert, nur verschoben), ruft
  `state.toggleArchived(database:)`
- Ungelesen: `circle` / `circle.fill` (Konvention aus `ArticleFilterOption`), ruft
  `state.toggleRead(database:)`

Alle drei Methoden existieren bereits auf `SQLiteReaderState` — reine UI-Ergänzung, keine neue
Business-Logik. Tooltips nutzen die vorhandenen L10n-Keys (`articleRowStarAdd`/`articleRowStarRemove`,
`articleArchiveCommand`/`articleUnarchiveCommand`, `articleRowMarkRead`/`articleRowMarkUnread`),
abhängig vom aktuellen `state.snapshot`-Status. Alle drei Buttons sind deaktiviert, wenn
`state.snapshot == nil` (kein Artikel geladen), analog zum bisherigen Archivieren-Button.

Die separate `ArticleCommandActions`-Ebene in `ContentView` (Tastaturkürzel/Menü) bleibt unverändert
bestehen; die neue Toolbar-Gruppe ist ein zusätzlicher, gleichwertiger Zugriffsweg auf dieselben
Status-Felder.

## Tests

Reine UI-Änderung ohne neue Zustandslogik — die vorhandenen `SQLiteReaderState`-Methoden
(`toggleStarred`, `toggleArchived`, `toggleRead`) sind bereits über bestehende Tests abgedeckt.
Manuelle Verifikation im Reader genügt (Toolbar-Gruppe klicken, Icon-Zustand prüfen).
