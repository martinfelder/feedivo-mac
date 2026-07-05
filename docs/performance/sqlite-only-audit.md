# SQLite-only Audit (Feedivo)

Stand: 03.07.2026

## Phase 1 Zielbild (erreicht)

Phase 1 ist die Sicherheitslage für den Umstieg auf einen NetNewsWire-artigen produktiven Pfad:

- Produktive Feed-/Artikelnavigation läuft über SQLite-Snapshots/Stores.
- Legacy-Ansichten für Artikel/Listen verbleiben im Code, sind aber nicht mehr im produktiven Haupt-Flow.
- SwiftData bleibt als Übergang: minimale Feed-Übergangsidentität, historische Datenmodelle und Backfills.

## Produktiver Pfad – ist bereits SQLite-only

- `ContentView`: steuert die Auswahl über `FeedSidebarSnapshot`/`selectedSQLiteArticleID`, lädt über `FeedStore(database: database).sidebarFeeds()` und rendert ausschließlich `SQLiteFeedArticleListView` + `SQLiteReaderView`.
- `SidebarView` und `SQLiteSidebarState`: laden Feeds, Ordner, Tags und SmartFolder aus SQLite-Snapshots.
- `SQLiteFeedArticleListView` / `SQLiteReaderView`: sind der produktive Leser-/Listpfad; keine neuen `@Query` auf produktive Artikel-Objekte.
- `FeedivoApp` startet `FeedivoDatabase` und injectiert sie als Environment.
- `SQLiteFeedSubscriptionService`: Add/Import in SQLite, Artikel-Identität über `ArticleStore`.

## Bewusste SwiftData-Reste (ausdrücklich isoliert)

- Übergangs-Bridge: `SQLiteFeedSubscriptionService.saveSwiftDataBridge` und `FeedViewModel.deleteFeed`/`update`-Pfad halten `Feed`-Identität (`Feed.id`, Sidebar/Command-Kompatibilität) konsistent.
- Backfills und Migration: `FeedTagBackfillService`, `SQLiteAdminDefinitionBackfillService`, `ArticleFeedIDBackfillService`, `FeedUnreadCountBackfillService`, `OrphanedArticleCleanupService` etc. lesen/ziehen Daten vom alten Modell in neue Stores.
- Legacy-Views: `ArticleListView` und `ReaderView` sind als `// Legacy SwiftData` markiert und nicht mehr in die produktive Content-Routingkette eingebunden.
- `ArticleViewModel` bleibt als Fallback-Schicht teilweise aktiv, während Aktionen im produktiven Pfad über SQLite-Snapshots/Status laufen.

## Aktive Rückfallschutz-Regeln für Phase 1 (nachweisbar)

- Neue produktive UI-Pfade dürfen keine neuen SwiftData-Queries auf `Article` als Hauptquelle einführen.
- Für Feed-/Artikel-Listen/Reader in produktiven Pfaden gilt: `FeedStore` / `TimelineStore` / `ArticleStore` / `ArticleStatusStore`.
- Legacy-Dateien dürfen SQLite-Notizen/Kommentare tragen und müssen nicht produktiv geroutet werden.
- Kritische Übergänge werden in `FeedivoTests/FeedivoAppSceneConfigurationTests.swift` per Source-Tests abgesichert.

## Abschlusskriterium für Phase 1

- `FeedivoTests/FeedivoAppSceneConfigurationTests.swift` enthält einen Regressionstest, der den produktiven Inhaltspfad explizit als SQLite-only validiert.
- Der Audit beschreibt die noch erlaubten SwiftData-Quellen klar, damit jede spätere Änderung sofort auffällt.

## Final Closure Scan

Stand: 2026-07-05 (nach Merge von `feature/sqlite-only-app-start`)

- App-Start: SQLite-only, kein produktiver `ModelContainer` und kein `.modelContainer(...)`
  mehr in `FeedivoApp.swift`. `FeedivoApp` erzeugt nur noch `FeedivoDatabase` und injiziert
  sie per Environment.
- Feed-/Artikelproduktpfad: SQLite-only (`SQLiteFeedArticleListView`, `SQLiteReaderView`,
  `FeedStore`, `TimelineStore`, `ArticleStore`, `ArticleStatusStore`).
- SwiftData-Reste nach dem Scan als konkrete Datei-Liste:
  - `remove` (im Abschluss gelöscht):
    - `Feedivo/App/FeedivoModelContainerFactory.swift` (Task 5)
    - `FeedivoTests/FeedivoModelContainerFactoryTests.swift` (Task 5)
    - `Feedivo/Services/SmartFolderDefaultKeyBackfillService.swift` (Task 6, keine Aufrufer mehr)
  - `legacy-isolate` (bleiben vorerst, klar Legacy, nicht produktiv geroutet):
    - `Feedivo/Views/ArticleList/ArticleListView.swift` (Legacy-View, Typealias in Task 4 entfernt)
    - `Feedivo/Views/Reader/ReaderView.swift` (Legacy-View, Typealias in Task 4 entfernt)
    - `Feedivo/Views/Reader/LegacyArticleMetadataInspectorView.swift`
    - `Feedivo/Views/Sidebar/FeedPropertiesQuery.swift`
    - `Feedivo/Views/Sidebar/SidebarUnreadCount.swift`
    - `Feedivo/Services/SQLiteFeedSubscriptionService.swift` (Bridge-Verhalten, Tasks 2/3)
    - `Feedivo/ViewModels/ArticleMetadataEditor.swift`
    - `Feedivo/ViewModels/ArticleViewModel.swift`
    - `Feedivo/ViewModels/SmartFolderViewModel.swift`
    - `Feedivo/ViewModels/TagViewModel.swift`
    - `Feedivo/ViewModels/FeedViewModel.swift` (Task 3: MARK-Regionen trennen Legacy von SQLite-Delegation)
    - Legacy-Backfill-Services als `@available(*, deprecated)` markiert (Task 6), weil sie
      noch in Migrations-/Kompatibilitätstests referenziert werden:
      - `Feedivo/Services/FeedBackgroundRefreshService.swift`
      - `Feedivo/Services/ArticleFeedIDBackfillService.swift`
      - `Feedivo/Services/FeedTagBackfillService.swift`
      - `Feedivo/Services/FeedUnreadCountBackfillService.swift`
      - `Feedivo/Services/OrphanedArticleCleanupService.swift`
      - `Feedivo/Services/SQLiteAdminDefinitionBackfillService.swift`
  - `test-only`: SwiftData-Treffer in `FeedivoTests/` (alte Migrations-/Kompatibilitätstests);
    nicht Teil des produktiven Pfads.
  - `model-only` (alte SwiftData-Modelle, werden erst gelöscht, wenn alle Tests umgestellt
    sind):
    - `Feedivo/Models/Article.swift`, `Feed.swift`, `FeedFolder.swift`, `FeedLogEntry.swift`,
      `Rule.swift`, `RuleCondition.swift`, `SmartFolder.swift`, `SmartFolderCondition.swift`,
      `Tag.swift`
  - produktiv verbleibend mit leichten SwiftData-Spuren (kein eigener Task, beobachten):
    - `Feedivo/Services/ArticleRetentionCleanupService.swift` (noch produktiv über
      `FeedivoApp`; hat SQLite-Methode `removeExpiredSQLiteArticles` und eine Legacy-
      SwiftData-Methode).
    - `Feedivo/Views/ContentView.swift`, `ArticleSearchWindowView.swift`,
      `OPMLImportPreviewController.swift`, `ArticleListQuery.swift`,
      `ArticleListItemSnapshot.swift`, `ReaderPreparedArticle.swift` (überwiegend Kommentare
      oder vereinzelte Legacy-Helfer, kein produktiver SwiftData-Hauptpfad).

Entscheidung: SwiftData wird nicht mehr als produktive Persistenzschicht verwendet.
Verbleibende Treffer sind entweder zu entfernen (Tasks 5/6) oder als Legacy/Test/Model
bewusst isoliert.
