# SQLite-Only Audit (Feedivo)

Stand: 03.07.2026

## Ziel von Phase 1

Phase 1 ist eine Sauberkeitsrunde: Wir mappen, wo SwiftData noch produktiv ist, und trennen klar zwischen

1. produktiver Feed-/Artikel-Liste-Logik,
2. Legacy-Admin- oder Fallback-Logik,
3. reiner UI-/Settings-Logik.

Erst wenn die produktive Feed-/Artikel-Pipeline sauber getrennt und mit SQLite-Backends arbeitet, beginnt Phase 2 (gezielte Rückbau-Implementierung).

---

## 1) Produktivpfad: noch SwiftData-kritisch

Folgende Stellen sind nach heutigem Stand noch kritisch für die Live-Feed-/Artikel-Hot-Pfade und sollten in Phase 1 zuerst stabilisiert/isoliert werden:

- `Feedivo/App/FeedivoApp.swift` – `ModelContainer` ist aktiv, inklusive `Feed`, `FeedFolder`, `Article`, `Tag`, `Rule`, `SmartFolder` und Log-Models.
- `Feedivo/Views/ContentView.swift`
  - `@Query(sort: \Feed.title)` für Feeds
  - `@Query(sort: \Tag.name)` für Tags
  - `@Query(sort: \SmartFolder.sortOrder)` für SmartFolders
  - produktive Pfade lesen dadurch noch direkt SwiftData-Modelle für Sidebar-Auswahl
- `Feedivo/Views/Sidebar/SidebarView.swift` – SwiftData-Queries auf Feeds/Folder/Tag/SmartFolder.
- `Feedivo/Views/ArticleList/ArticleListView.swift` – weiterhin SwiftData-Queries auf `Article` und Tags.
- `Feedivo/Views/Reader/ReaderView.swift` – SwiftData-basierte Aktionen/Tag-Zugriffe im Reader-Kontext.
- `Feedivo/ViewModels/ArticleViewModel.swift` – Mutationspfade `toggleRead`, `toggleStarred`, `markAllRead`, `deleteArticle`, `synchronizeUnreadCounts` arbeiten gegen SwiftData-`Article`.
- `Feedivo/ViewModels/FeedViewModel.swift` – mehrere produktive Refresh-/Persistenz-Pfade mit SwiftData-Kontexten.
- `Feedivo/Views/Reader/ArticleMetadataInspectorView.swift` – Queries auf `FeedFolder`/`Tag` in der metadatennahen UI.

---

## 2) Mischpfad (Teilproduktive + Legacy)

Folgende Module haben sowohl produktive als auch Legacy-Nutzung und brauchen in Phase 1 klare Abschottung:

- `Feedivo/Services/FeedBackgroundRefreshService.swift`
- `Feedivo/Services/BackgroundRefreshService.swift`
- `Feedivo/Views/Sidebar/FeedPropertiesView.swift`
- `Feedivo/Views/Sidebar/FeedPropertiesView.swift` (und `FeedPropertiesQuery.swift`) – Feed-Property-Ermittlung ist noch SwiftData-lastig.
- `Feedivo/Services/ArticleRetentionCleanupService.swift` – Cleanup auf SwiftData- und SQLite-Pfade gemischt.
- `Feedivo/Views/ArticleList/ArticleSearchWindowView.swift` – nutzt zwar SQLite-Search, hält aber weiterhin `@Query` auf `Article`-Modelle.

---

## 3) Deutlich non-Produktiv / Verwaltung / Fallback

Diese Dateien sind für Einstellungen, Verwaltung oder Übergangswiederstände klarer isolierbar:

- Tag-Management: `TagViewModel.swift`, `Views/Tags/TagManagerView.swift`, `Views/Rules/RuleSettingsView.swift`, `ViewModels/RuleViewModel.swift`, `Views/Rules/RuleWizardView.swift`, `ViewModels/SmartFolderViewModel.swift`, `Views/SmartFolders/*`
- Backfills/Housekeeping:
  - `ArticleFeedIDBackfillService.swift`
  - `FeedUnreadCountBackfillService.swift`
  - `FeedTagBackfillService.swift` (falls vorhanden)
  - `SmartFolderDefaultKeyBackfillService.swift`
  - `OrphanedArticleCleanupService.swift`
  - `SQLiteAdminDefinitionBackfillService.swift` falls aktiv genutzt
- Metadaten und Hilfspfad:
  - `OPMLImportPreviewController.swift`
  - `FirstRunWizardView.swift`
  - `SettingsView.swift`
  - `ReaderPreparedArticle.swift` und andere reine Snapshot-/Bridge-Strukturen.

---

## 4) Regression Protection (Phase-1 Maßnahmen)

Bis zum nächsten Umbau dürfen diese Regeln gelten:

1. Für jede produktive Änderung in Feed-/Artikel-Liste/Refresh wird zuerst entschieden: **SQLite-First oder Legacy-Path**.
2. Neue produktive Features dürfen keine neuen SwiftData-Queries auf `Article` für normale List- oder Timeline-Zugriff einführen.
3. `Feed`, `Tag`, `Rule`, `SmartFolder` dürfen in produktiven Callchains nur noch als Read-Model bzw. Kompilierungs-Bridge auftauchen.
4. `Feedivo`-UI ohne SQL-Liste darf nur dann auf SwiftData zurückgreifen, wenn der entsprechende Bereich ausdrücklich als Legacy-/Fallback gekennzeichnet ist.
5. Jede neue Änderung in `FeedViewModel`, `ArticleViewModel`, `ReaderView`, `SidebarView`, `ArticleListView` braucht eine Mini-Notiz im Audit mit Grund/Status (in dieser Datei am unteren “Tracking”-Abschnitt).
6. Während der Übergangszeit bleibt `FeedivoApp`-Container aktiv, aber produktive Codepfade dürfen keine neuen Modellbeziehungen als Datenquelle für Live-Zählung oder Timeline nutzen.

---

## 5) Tracking für den Rückbau (aktuelle Priorität)

### Sofort (in dieser Phase)

- `FeedivoApp.swift`: neue SQLite-First-App-Einstiegsdoktrin in einem zentralen Environment-Speicher abbilden.
- `ContentView.swift`, `SidebarView.swift`, `ArticleListView.swift`: Produktivzugriffe gegen SQLite-Snapshots/TimelineStores führen.
- `ArticleViewModel.swift`:
  - Statusänderungen auf SQLite-Statusstore umziehen,
  - SwiftData nur noch Fallback/Bridge.
- `FeedViewModel.swift`: Refresh/RefreshAll auf SQLite-Writer-Pfade.
  - Teilweiser Schritt: Einzel-Feed-Refresh läuft jetzt über `FeedBackgroundRefreshService`, damit der eigentliche Refresh-Pfad in einer separaten Komponente liegt.
- `ReaderView.swift` + `ArticleMetadataInspectorView.swift`: Artikeldetail wird aus SQLite-Reader-Snapshot geladen.
- `ArticleSearchWindowView.swift`: Suche vollständig auf FTS/SQLite-Query stützen.

### Nächster Schritt nach Phase 1

- Phase 2 startet mit schrittweisem Entfernen von SwiftData in `Feedivo/Services/*` Backfill/Refresh-Pfaden.
- Danach entfernen wir alte `@Model`-Verwendungen im Produktivbereich; anschließend nur noch isolierte Admin/Legacy-Pfade.

---

## 6) Akzeptanzkriterien für „Phase 1 abgeschlossen“

- Alle produktiven Feed-/Artikel-Liste-/Reader-/Refresh-Cycles sind über SQLite-Store-Pfade nachweisbar.
- Neue Rückrufe und Aktionen ändern keine produktiven Daten mehr primär über `SwiftData.ModelContext`.
- Migration-Plan für Legacy-Pfade (Regeln, Tags, SmartFolders, Backfills) liegt explizit vor.
- Nächster Zustand: Phase-2-Umsetzplan kann ohne neue Architekturentscheidungen gestartet werden.
