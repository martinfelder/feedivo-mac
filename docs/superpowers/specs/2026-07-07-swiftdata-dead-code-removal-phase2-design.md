# Toten SwiftData-Code entfernen — Phase 2 Design

## Ziel

Phase 1 hat den komplett isolierten, toten View-/ViewModel-/Service-Baum entfernt (13 Dateien
gelöscht, 5 Extraktions-Dateien für noch aktive Teiltypen). Phase 2 nimmt sich die 6 Dateien vor, die
in Phase 1 bewusst zurückgestellt wurden, weil sie sowohl toten als auch aktiven Code enthalten:
`ArticleListQuery.swift`, `ArticleListItemSnapshot.swift`, `TagViewModel.swift`,
`ArticleRetentionCleanupService.swift`, `SidebarUnreadCount.swift`, `ReaderPreparedArticle.swift`.

Anders als in Phase 1 reicht hier oft keine reine Typ-Extraktion — teilweise sind einzelne Methoden
innerhalb eines sonst noch aktiven Structs tot (z. B. `ArticleSearchQuery.filtered(_:)` arbeitet auf dem
toten SwiftData-`Article`, während `ArticleSearchQuery.isActive` weiterhin gebraucht wird). Phase 2
erfordert deshalb methodengenaues statt nur typgenaues Aufräumen.

## Verifizierte Fakten (Grundlage dieser Spec)

Jede Aussage unten wurde per gezieltem `grep` über `Feedivo` und `FeedivoTests` verifiziert (nicht nur
Dateiname-Treffer, sondern echte Aufrufe unterschieden von String-Negations-Checks und Kommentaren).

### `Feedivo/Views/ArticleList/ArticleListQuery.swift` (14 Top-Level-Typen)

**Komplett tot** (null externe Referenzen außer ggf. der eigenen `ArticleListQueryTests.swift`):
`LegacyArticleListQuery`, `ArticleListDisplayState`, `ArticleListDisplaySnapshot`,
`ArticleListPaginationState`, `ArticleListFeedTitleSnapshot`, `ArticleListFeedTitleLookup`,
`ArticleSearchScope`, `ArticleListPreparedArticles`.

**Bleibt aktiv, aber mit toten Methoden**: `ArticleSearchFilters`/`ArticleSearchQuery` — ihre Datenfelder
und `.isActive`/`.normalizedText` werden von `ArticleSearchWindowView.swift`
(`searchState.query.filters.isActive`, `committedState.query.normalizedText`) gebraucht. Ihre
SwiftData-`Article`-Methoden (`ArticleSearchFilters.includes(_:now:calendar:)` +
`.matchesFeed/.matchesTag/.matchesDate/.matchesStatus`; `ArticleSearchQuery.includes(_:)`,
`.filtered(_:)`, `.textIncludes(_:)`, `.heavyContentIncludes(_:)`, `.contains(_:in:)`) haben keine
Aufrufer mehr — ihr einziger Aufrufer war `ArticleSearchWindowState.filteredArticles(from:)`, das selbst
0 Aufrufer hat.

**Bleibt vollständig unverändert**: `ArticleSearchField`, `ArticleSearchDateFilter`,
`ArticleSearchStatusFilter` (aktiv genutzt von `ArticleStore.swift`/`ArticleSearchWindowView.swift`),
`ArticleSearchWindowState` (aktiv genutzt von `ArticleStore.swift`/`ArticleDatabase.swift`/
`ArticleSearchWindowView.swift`), bis auf die eine tote Methode `filteredArticles(from:)`.

### `Feedivo/Views/ArticleList/ArticleListItemSnapshot.swift`

`init(article: Article, feedTitle: String?)` — tot (nur vom in Phase 1 gelöschten View-Baum genutzt).
`init(sqliteSnapshot: ArticleListSnapshot)` — aktiv (`SQLiteFeedArticleListView.swift`).

### `Feedivo/ViewModels/TagViewModel.swift`

`static func normalizedTagName(_:)`/`normalizedColorHex(_:)` — aktiv genutzt von `TagManagerView.swift`,
`FeedPropertiesView.swift`, `RuleWizardView.swift`, `TagColorPalette.swift`. Die Klasse `TagViewModel`
selbst (Instanzmethoden `createTag`/`renameTag`/`updateColor`/`deleteTag` + private Helfer `save`,
`mirrorTagToSQLite`, `deleteTagFromSQLite`, `containsTag`) wird nirgends instanziiert außer in ihrer
eigenen `FeedivoTests/TagViewModelTests.swift` — `TagManagerView.swift` ruft stattdessen direkt
`TagStore(database:).renameTag/updateColor/deleteTag` auf.

### `Feedivo/Services/ArticleRetentionCleanupService.swift`

`removeExpiredArticles(in context: ModelContext, ...)` (der alte SwiftData-Pfad) plus seine 5 privaten
Helfer, die ausschließlich von ihm aufgerufen werden (`retentionConfiguration`,
`protectedSwiftDataArticleIDs`, `swiftDataRetentionSort`, `feedsByID(in:)`, `syncUnreadCounts`) — tot,
0 externe Aufrufer der öffentlichen Methode. `removeExpiredSQLiteArticles` (zwei Overloads) plus ihre
Helfer (`sqliteFeedRetentionConfigurations`, `protectedSQLiteArticleIDs`, `shouldRemove`) — aktiv
genutzt von `FeedivoApp.swift`, `FeedPropertiesView.swift`, `SettingsView.swift`.

### `Feedivo/Views/Sidebar/SidebarUnreadCount.swift`

`SidebarUnreadCount.badgeText(for count: Int)` — aktiv (`SidebarView.swift`, `FeedRowView.swift`).
`SidebarUnreadCount.unreadArticleCount(for feed: Feed)`/`.totalUnreadArticleCount(in feeds: [Feed])` —
tot (nur eigene `SidebarUnreadCountTests.swift`). `SidebarTagCount` (ganzer Typ) — tot, 0 Aufrufer.
Von den vier `SmartFolderSidebarBadge.badgeText`/`badgeCount`-Overloads (getrennt nach
`feeds:context:`, `feeds:counts:`, `folder: SmartFolder, snapshot:`,
`folder: SQLiteSmartFolderSnapshot, snapshot:`) wird nur die letzte (SQLite-Snapshot-Variante) noch
aufgerufen (`SidebarView.swift:477`) — die anderen drei sind tot. `SidebarBadgeInvalidation`
(`bumpDirectTagVersion()`/`directTagVersionKey`) bleibt komplett unangetastet — stark genutzt u. a. von
`RuleEngine.swift`, `TagManagerView.swift`, `ArticleMetadataInspectorView.swift`,
`FeedPropertiesView.swift`, mehreren Views mit `@AppStorage`.

### `Feedivo/Views/Reader/ReaderPreparedArticle.swift`

`ReaderContentAvailability`, `ReaderArticleContentLoader` — 0 Referenzen irgendwo (auch nicht mehr
intern in `SQLiteReaderState.swift`, seit der SwiftData-`ReaderView` in Phase 1 gelöscht wurde) —
komplett tot. Der Rest der Datei (`ReaderArticleInput`, `ReaderPreparedArticle`,
`ReaderPreparedArticleCache`, `ReaderArticleTextFingerprint`, `ReaderArticleCacheKey`,
`ReaderArticleObservationSignature`) bleibt — aktiv genutzt von `SQLiteReaderState.swift`.

## Vorgehen

Wie in Phase 1: ein Plan mit 6 Tasks (einer pro Datei), Subagent-Driven-Development-Ausführung,
Task-Review nach jedem Task, finaler Whole-Branch-Review. Genau wie in Phase 1 ist zu erwarten, dass
die Implementierung während der Arbeit weitere Feinheiten aufdeckt (private Helfer-Abhängigkeiten,
versteckte Testreferenzen) — jeder Task-Implementierer verifiziert vor dem Löschen erneut per `grep`,
genau wie in Phase 1 etabliert.

## Nicht Teil dieser Phase

- Die 9 `@Model`-Klassen selbst (spätere Phase, abhängig vom Ergebnis dieser Phase).
- Vestigiale `context: ModelContext?`/`existingFeeds: [Feed]`-Parameter in `FeedViewModel.swift` und
  `SQLiteFeedSubscriptionService.swift` (spätere Phase).
- `ArticleSearchField`/`ArticleSearchDateFilter`/`ArticleSearchStatusFilter`/`ArticleSearchWindowState`
  selbst werden nicht gelöscht (aktiv), nur ihre toten Methoden/Geschwistertypen.

## Tests

Kein neuer Testcode nötig — reine Lösch-/Extraktions-Operation. Erfolgskriterium: Build bleibt grün,
bestehende (gescopte, nicht die volle hängende Suite) Tests bleiben grün — insbesondere alle Tests für
`ArticleSearchWindowView`/`ArticleStore.searchArticles`/`SQLiteReaderState`/`SidebarView`/
`ArticleRetentionCleanupService.removeExpiredSQLiteArticles`, da diese die überlebenden Pfade abdecken.
