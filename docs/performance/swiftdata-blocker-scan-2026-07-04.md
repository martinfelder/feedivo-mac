# SwiftData-Blocker-Scan (2026-07-04)

Ausgeführt mit:

```bash
rg -n 'import SwiftData|@Model|@Query|ModelContext|ModelContainer|FetchDescriptor<' Feedivo -g '*.swift'
```

Gesamtanzahl Trefferdateien: 42

## Ergebnis: erlaubte Übergangs-Treffer

Diese Treffer sind Stand heute bewusst noch als Übergang/Fallback bzw. Legacy-Verbleib dokumentiert:

- `Feedivo/App/FeedivoApp.swift`  
  Übergangsstart inkl. `ModelContainer`/`modelContainer(...)`-Injektion.

- `Feedivo/App/FeedivoModelContainerFactory.swift`  
  Hilfstyp für den SwiftData-Container; noch produktiv benötigt, solange
  Legacy-Rückfälle laufen.

- `Feedivo/Models/*.swift` (`Article`, `Feed`, `Tag`, `Rule`, `SmartFolder`, `FeedFolder`, `FeedLogEntry`)  
  SwiftData-Modelle werden als Übergang/Backfill-Ziel weitergeführt.

- `Feedivo/Services/*Backfill*.swift` sowie weitere Backfill-Services  
  `ArticleFeedIDBackfillService`, `FeedTagBackfillService`,
  `FeedUnreadCountBackfillService`, `FeedIcon...` usw. – reine
  Migrations-/Datenbereinigungs-Pfade.

- `Feedivo/Services/SmartFolderDefaultKeyBackfillService.swift`,
  `SQLiteAdminDefinitionBackfillService.swift`  
  Struktur-Migration für Default-Definitionen.

- `Feedivo/Views/ArticleList/ArticleListView.swift`,  
  `Feedivo/Views/ArticleList/ArticleListQuery.swift`,  
  `Feedivo/Views/Reader/ReaderView.swift`  
  als Legacy-Views markiert und **nicht** produktiv geroutet.

- `Feedivo/Views/Reader/LegacyArticleMetadataInspectorView.swift`  
  klarer Legacy-Inspector.

- `Feedivo/Views/Sidebar/FeedPropertiesView.swift`,
  `Feedivo/Views/Sidebar/FeedPropertiesQuery.swift`  
  Legacy-Property-View inklusive SwiftData-Abfragen.

- `Feedivo/ViewModels/TagViewModel.swift`, `ArticleMetadataEditor.swift`,
  `ArticleViewModel.swift`, `FeedViewModel.swift`, `SmartFolderViewModel.swift`  
  Teilweise noch produktive Fallback-/Kompatibilitätslogik (z. B. Delete/Update/
  Kontext-Metadaten), klar in Kommentaren als Legacy markiert oder isoliert.

## Konkrete Produktiv-Blocker, die noch Phase 8 verhindern

Folgende Stellen halten die SQLite-only-Produktiv-Pipeline noch daran, den
`ModelContainer` komplett loszuwerden:

- App-Start und globaler Environment-Graph hängen noch am SwiftData-Container
  (`FeedivoApp`, `FeedivoModelContainerFactory`).
- `BackgroundRefreshService` und `FeedBackgroundRefreshService` nutzen noch
  SwiftData-Kontexte für Legacy-Schnittstellen.
- `Feedivo/Views/Settings/SettingsView.swift` enthält noch `@Query`-Zweige und ist
  produktiv für Einstellungen noch nicht vollständig auf SQLite zurückgeführt.
- Artikel-Metadaten- und Feed-Eigenschaften-Editoren haben noch
  SwiftData-basierte Schreib-/Lese-Pfade.

## Nächster Schritt

Phase 8 kann erst nach folgenden Maßnahmen sinnvoll abgeschlossen werden:

1. produktive UI-Pfade für Settings/Refresh/Hintergrund/Jour-Funktion auf reine
   SQLite-Services umstellen,
2. `FeedivoApp` auf Datenbankstart ohne SwiftData-Haupt-Container umstellen,
3. vorhandene Legacy-Editoren/Brücken entweder eindeutig als nicht-produktiv
   markieren oder entfernen.
