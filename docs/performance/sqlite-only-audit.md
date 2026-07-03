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
