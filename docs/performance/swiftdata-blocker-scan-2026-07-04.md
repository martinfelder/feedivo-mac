# SwiftData-Blocker-Scan (2026-07-04)

Ausgeführt mit:

```bash
rg -n 'import SwiftData|@Model|@Query|ModelContext|ModelContainer|FetchDescriptor<' Feedivo -g '*.swift'
```

Gesamtanzahl Trefferdateien: 42

## Ergebnis: erlaubte Übergangs-Treffer

Diese Treffer sind Stand heute bewusst noch als Übergang/Fallback bzw. Legacy-Verbleib dokumentiert:

- `Feedivo/App/FeedivoApp.swift`  
  App-Start läuft über `FeedivoDatabase`-Injektion; kein produktiver
  `modelContainer(...)`-Pfad mehr im `Scene`-Setup.

- `Feedivo/App/FeedivoModelContainerFactory.swift`  
  Hilfstyp für den SwiftData-Container; aktuell nur noch als klarer Legacy-Baukasten
  dokumentiert, im Produktivfluss nicht verwendet.

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

- App-Start und globaler Environment-Graph laufen jetzt produktiv ohne
  `SwiftData.ModelContainer`.
- `FeedivoModelContainerFactory` ist derzeit noch als klarer Legacy-/Fallback-
  Helfer in der Codebase erhalten, aktuell nicht im produktiven
  App-Pfad verwendet.
- `FeedBackgroundRefreshService` bleibt als isolierter Legacy-Pfad in der Codebase
  und darf produktiv nicht mehr verwendet werden. Der produktive Refresh nutzt
  `SQLiteFeedRefreshService`/`SQLiteFeedRefreshCoordinator`.

## Aktueller Stand nach Phase-8-Teilabnahme

- Settings/Refresh/Editor-Pfade sind aus produktiven Flows vom
  `ModelContext`/`ModelContainer` entkoppelt.
- App-Start injiziert noch direkt `FeedivoDatabase` per Environment und enthält
  keine produktive SwiftData-Container-Initialisierung mehr.

## Nächster Schritt

Phase-8-Closure (vollständige Phase-8-Bereinigung) ist konkret jetzt an
folgender Restarbeit gekoppelt:

1. `FeedivoModelContainerFactory` entfernen, sobald die verbleibenden
   Legacy-Tests und Fallback-Pfade explizit neu bewertet wurden.
2. Die letzten Legacy-Backfill-/Editor-Flüsse auf produktive Lesezugriffe prüfen,
   falls nötig klar in legacy-markierte Dateien isolieren.
3. Vollständiger Durchlauf der Test-Suite nach diesen Aufräumen.
