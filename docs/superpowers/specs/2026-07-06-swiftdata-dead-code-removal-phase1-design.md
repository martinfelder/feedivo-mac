# Toten SwiftData-Code entfernen — Phase 1 Design

## Ziel

Eine vollständige Analyse des Codes zeigt: Es existiert nirgends mehr ein `.modelContainer(...)`-Aufruf
in der App (`FeedivoApp.swift` öffnet nur noch `FeedivoDatabase`/SQLite). Jeder verbliebene
`@Query`/`ModelContext`-abhängige Code ist damit zwangsläufig unerreichbar — würde eine solche View
tatsächlich gerendert, würde SwiftUI mangels injiziertem Container abstürzen. Phase 1 entfernt den
größten, eindeutig toten Block: einen komplett isolierten View-/ViewModel-/Service-Baum, der
nachweislich null externe Aufrufer aus dem aktiven (SQLite-only) Code hat.

Nicht Ziel dieser Phase: die 9 `@Model`-Klassen selbst (`Article`, `Feed`, `FeedFolder`, `FeedLogEntry`,
`Rule`, `RuleCondition`, `SmartFolder`, `SmartFolderCondition`, `Tag`) oder Dateien, die sowohl toten als
auch aktiven Code enthalten (`ArticleListQuery.swift`, `ArticleListItemSnapshot.swift`,
`TagViewModel.swift`, `ArticleRetentionCleanupService.swift`, `SidebarUnreadCount.swift`,
`ReaderPreparedArticle.swift`) — diese brauchen chirurgisches Aufteilen statt Löschen und sind spätere
Phasen.

## Verifizierte Fakten (Grundlage dieser Spec)

- `grep -rn "\.modelContainer(\|ModelContainer(for:" Feedivo --include="*.swift"` liefert null Treffer.
- `ContentView.swift`/`ArticleWindowView.swift` (die einzigen Stellen, die Reader/Artikelliste
  instanziieren) verwenden ausschließlich `SQLiteReaderView`/`SQLiteFeedArticleListView`.
- Jede der unten gelisteten Dateien/Typen hat null externe Referenzen aus aktivem Code (verifiziert per
  gezieltem `grep` je Symbol, nicht nur je Dateiname).
- Ausnahme, die die Spec-Erstellung erst richtig gemacht hat: `LegacyArticleMetadataInspectorView.swift`
  enthält `struct FlowLayout: Layout` — dieses Layout wird aktiv von `SQLiteReaderView.swift`,
  `ArticleMetadataInspectorView.swift` und `FeedPropertiesView.swift` verwendet und muss vor dem Löschen
  der restlichen Datei extrahiert werden.

## Umfang dieser Phase

### Vollständig löschbar (production + zugehörige Tests)

| Produktivdatei | Enthält (u. a.) | Zugehöriger Test |
|---|---|---|
| `Feedivo/ViewModels/ArticleViewModel.swift` | `ArticleViewModel` | `FeedivoTests/ArticleViewModelTests.swift` (deckt auch `ArticleNavigationState` ab) |
| `Feedivo/ViewModels/ArticleNavigationState.swift` | `ArticleNavigationState` | — (in ArticleViewModelTests.swift getestet) |
| `Feedivo/ViewModels/SmartFolderViewModel.swift` | `SmartFolderViewModel` | `FeedivoTests/SmartFolderViewModelTests.swift` |
| `Feedivo/ViewModels/ArticleMetadataEditor.swift` | `ArticleMetadataEditor` | `FeedivoTests/ArticleMetadataEditorTests.swift` |
| `Feedivo/Views/Sidebar/FeedPropertiesQuery.swift` | `FeedPropertiesQuery` | `FeedivoTests/FeedPropertiesQueryTests.swift` |
| `Feedivo/Views/ArticleList/ArticleListView.swift` | `LegacyArticleListView` + private Helfer-Structs | keine eigene Testdatei |
| `Feedivo/Views/Reader/ReaderView.swift` | `LegacyReaderView` + private Helfer-Structs | keine eigene Testdatei |
| `Feedivo/Services/ArticleFeedIDBackfillService.swift` | Backfill-Service | keine |
| `Feedivo/Services/FeedTagBackfillService.swift` | Backfill-Service | keine |
| `Feedivo/Services/FeedUnreadCountBackfillService.swift` | Backfill-Service | keine |
| `Feedivo/Services/OrphanedArticleCleanupService.swift` | Cleanup-Service | keine |
| `Feedivo/Services/SQLiteAdminDefinitionBackfillService.swift` | Backfill-Service | keine |
| `Feedivo/Services/FeedBackgroundRefreshService.swift` | Legacy-Refresh-Service | keine |

### Braucht Extraktion vor dem Löschen

`Feedivo/Views/Reader/LegacyArticleMetadataInspectorView.swift` enthält drei Top-Level-Typen:
- `struct LegacyArticleMetadataInspectorView: View` — tot, null externe Referenzen.
- `struct ArticleInspectorDetails: Equatable` — tot, null externe Referenzen.
- `struct FlowLayout: Layout` — **aktiv genutzt**, muss erhalten bleiben.

`FlowLayout` wird nach `Feedivo/Views/Reader/FlowLayout.swift` verschoben (reiner Datei-Move des
Struct-Codes, keine inhaltliche Änderung). Anschließend wird der Rest der ursprünglichen Datei
gelöscht.

## Vorgehen

1. `FlowLayout` extrahieren, bauen, testen (keine funktionale Änderung erwartet — reiner Verschiebe-Schritt).
2. Die 13 vollständig toten Produktivdateien + ihre 4 zugehörigen Testdateien löschen.
3. Nach jedem Lösch-Schritt bauen, um sicherzustellen, dass keine unerwartete Referenz übersehen wurde.
4. Am Ende volle Testsuite laufen lassen.

## Fehlerbehandlung

Sollte der Build nach einem Löschschritt fehlschlagen (unerwartete Referenz übersehen), wird der Schritt
rückgängig gemacht und die übersehene Referenz zusätzlich dokumentiert, bevor erneut gelöscht wird —
kein Weiterarbeiten mit rotem Build zwischen den Schritten.

## Tests

Kein neuer Testcode nötig — dies ist eine reine Lösch-Operation. Erfolgskriterium: Build bleibt grün,
volle bestehende Testsuite bleibt grün, `import SwiftData` verschwindet aus den 13 gelisteten
Produktivdateien vollständig.

## Nicht Teil dieser Phase

- `ArticleListQuery.swift`, `ArticleListItemSnapshot.swift`, `TagViewModel.swift`,
  `ArticleRetentionCleanupService.swift`, `SidebarUnreadCount.swift`, `ReaderPreparedArticle.swift` —
  enthalten sowohl toten als auch aktiven Code, brauchen chirurgisches Aufteilen (spätere Phase).
- Vestigiale `context: ModelContext?`/`existingFeeds: [Feed]`-Parameter in `FeedViewModel.swift` und
  `SQLiteFeedSubscriptionService.swift` (spätere Phase).
- Die 9 `@Model`-Klassen selbst und `import SwiftData` App-weit (spätere Phase, abhängig vom Ergebnis
  der vorherigen Phasen).
