# Design: Konfigurierbare Standard-Artikelanzeige (Alle/Nur ungelesen) für Intelligente Ordner

**Datum:** 2026-07-15
**Status:** Genehmigt, bereit für Implementierungsplan

## Ausgangslage

Die Artikelliste (`SQLiteFeedArticleListView`) hat bereits ein Filter-Menü
("Nur ungelesen" / "Alle") mit dem der Nutzer pro Sitzung manuell umschalten
kann, ob gelesene Artikel mit angezeigt werden. Beim erneuten Betreten eines
Smart Folders wird dieser Zustand aber immer wieder auf einen Default
zurückgesetzt (`.onChange(of: scopeToken)`,
`SQLiteFeedArticleListView.swift:164-167`).

Dieser Default kommt aktuell aus einer fest im Code verdrahteten Regel
(`SmartFolderDefaultDisplayPolicy.alwaysShowsReadArticles(defaultKey:)`,
`SQLiteSidebarState.swift`), die nur die vier eingebauten Standard-Ordner
kennt (`defaultKey` in `starred`/`thisWeek`/`hidden`/`saved` → immer "Alle"),
alle anderen Ordner (inkl. aller selbst angelegten) bekommen immer "Nur
ungelesen" — ohne Möglichkeit, das für einen konkreten Ordner dauerhaft
anders einzustellen.

## Ziel

Im Smart-Folder-Editor (`SmartFolderEditorView.swift`) eine neue, pro Ordner
gespeicherte Einstellung: "Artikel-Anzeige" mit den Optionen "Nur ungelesen"
(Default für neue Ordner) und "Alle Artikel". Dieser Wert bestimmt künftig
den Ausgangszustand des Filter-Menüs beim Betreten des jeweiligen Ordners —
für **alle** Smart Folder, auch die vier eingebauten Standard-Ordner.

Die neue Einstellung ersetzt die bisherige fest verdrahtete Policy komplett
als alleinige Quelle der Wahrheit. Für bestehende Standard-Ordner bleibt das
heutige Verhalten über eine Migrations-Backfill exakt erhalten.

## Nicht-Ziele

- Keine Änderung an der Sidebar-Badge-Logik (gemischter Gelesen/Ungelesen-
  Zähler neben dem Ordnernamen, `SmartFolderDefaultDisplayPolicy.mixedCountKeys`
  in `SQLiteSidebarState.swift`) — die bleibt unverändert nur für die vier
  Standard-Ordner aktiv.
- Keine Änderung am bestehenden manuellen Filter-Menü in der Artikelliste
  selbst — es bleibt exakt wie heute, überschreibt den neuen Default nur
  temporär für die laufende Sitzung.
- Keine Änderung an Feeds/Tags/Smart-Filtern (`.feed`/`.tagID`/`.smartFilter`
  in `SQLiteFeedArticleListView.Scope`) — die neue Einstellung betrifft
  ausschließlich `.smartFolder`.

## Datenbank-Migration (`FeedivoDatabaseMigrator.swift`)

Neue Migration `v17_add_smart_folder_default_shows_read_articles` (aktueller
Stand ist v16, siehe `grep -n registerMigration` — vor Implementierung erneut
prüfen, siehe CLAUDE.md-Warnung zu Migrations-Drift):

```swift
migrator.registerMigration("v17_add_smart_folder_default_shows_read_articles") { database in
    try database.alter(table: "smart_folders") { table in
        table.add(column: "defaultShowsReadArticles", .boolean)
            .notNull()
            .defaults(to: false)
    }

    try backfillSmartFolderDefaultShowsReadArticles(database)
}
```

Neue private Helper-Funktion (analog zu `backfillTagSortIndex`), die für
bereits vorhandene Zeilen mit `defaultKey` in
`("starred", "thisWeek", "hidden", "saved")` `defaultShowsReadArticles = 1`
setzt — exakt die Menge, die heute `SmartFolderDefaultDisplayPolicy.
alwaysShowsReadArticleKeys` definiert. Alle anderen bestehenden Zeilen
(inkl. `all`/`today`/`unread`/`archived` sowie alle eigenen Ordner) behalten
den Spalten-Default `false`, was ihrem heutigen Verhalten entspricht.

## Datenmodell

`SmartFolderRecord` (`Feedivo/Database/Records/SmartFolderRecord.swift`)
bekommt ein neues Feld:

```swift
var defaultShowsReadArticles: Bool
```

mit Default `false` im Initializer (analog zu den bestehenden Bool-Feldern
wie `isShownInSidebar`).

`SQLiteSmartFolderSnapshot` bekommt dasselbe Feld, propagiert in beiden
bestehenden Initializern:
- `init(folder:conditions:)` übernimmt `folder.defaultShowsReadArticles`.
- `init(id:name:matchMode:conditionDrafts:)` (Vorschau-Konstruktor im Editor)
  bekommt einen neuen Parameter `defaultShowsReadArticles: Bool = false`.

`SQLiteSmartFolderStore`:
- `sidebarSnapshots()` liest die neue Spalte mit (Snapshot-Konstruktion um
  das Feld ergänzen).
- `duplicate(id:copyName:)` übernimmt `source.defaultShowsReadArticles` in
  den neu erzeugten `SmartFolderRecord` (analog zu `iconName`/`colorHex`).
- `restoreDefaultFolders()`: `DefaultSmartFolderDefinition` bekommt ein neues
  Feld `defaultShowsReadArticles: Bool`, gesetzt auf `true` für die vier
  betroffenen Definitionen (`starred`, `thisWeek`, `hidden`, `saved`), sonst
  `false` — damit ein Nutzer, der einen gelöschten Standard-Ordner über
  "Standardordner wiederherstellen" neu anlegt, wieder das korrekte
  Verhalten bekommt (nicht nur per Migrations-Backfill für bereits
  existierende Zeilen).

## UI (`SmartFolderEditorView.swift`)

Neuer `@State private var defaultShowsReadArticles = false`, geladen in
`loadInitialState()` aus `folder?.defaultShowsReadArticles ?? false` und
persistiert in `save()` als Teil des konstruierten `SmartFolderRecord`.

Neue Segmented-Control-Zeile direkt unter `sidebarCheckbox` (gleicher
Baustein `RuleSegmentedControl` wie bei der bestehenden
"Verknüpfung"-Zeile/`operatorRow`):

```swift
private func articleVisibilityRow(theme: RuleDialogTheme) -> some View {
    HStack(spacing: 12) {
        Text(L10n.smartFolderDefaultArticleVisibility)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(theme.text2)

        RuleSegmentedControl(
            options: [
                (false, L10n.articleListReadDisplayUnreadOnly),
                (true, L10n.articleListReadDisplayAll)
            ],
            selection: $defaultShowsReadArticles,
            theme: theme
        )
    }
}
```

Eingebunden in `body` als `articleVisibilityRow(theme: theme).padding(.top, 12)`
nach `sidebarCheckbox`. Die Beschriftungen der beiden Optionen sind bewusst
dieselben bestehenden L10n-Keys wie im Artikellisten-Filter-Menü
(`L10n.articleListReadDisplayUnreadOnly`/`...All`) — ein Begriff, zwei
Stellen. Neuer L10n-Key nur für das Zeilen-Label selbst
(`smartfolder.defaultArticleVisibility`, „Artikel-Anzeige"), in allen vier
Sprachen (de/en/fr/it) zu übersetzen.

`RuleSegmentedControl<Option: RuleSelectOption>` verlangt `Option:
RuleSelectOption` (`protocol RuleSelectOption: Hashable {}`,
`RuleDialogTheme.swift`). `Bool` ist dafür noch nicht erweitert (bisher nur
`String` und die Rule-/SmartFolder-Enums, siehe Konformitäts-Block am Ende
von `SmartFolderEditorView.swift`) — dort ergänzen: `extension Bool:
RuleSelectOption {}`.

Der neue Control ist für **alle** Ordner gleichermaßen aktiv, auch die mit
gesperrtem Namensfeld (`folder?.defaultKey != nil`) — analog dazu, dass
Bedingungen für Standard-Ordner in diesem Dialog schon heute editierbar sind.

## Konsument (`SQLiteFeedArticleListView.swift`)

`defaultShowsReadArticles` (computed property, Zeile 795) wird vereinfacht:

```swift
private var defaultShowsReadArticles: Bool {
    if case let .smartFolder(smartFolder) = scope {
        return smartFolder.defaultShowsReadArticles
    }
    return false
}
```

`SmartFolderDefaultDisplayPolicy.alwaysShowsReadArticles(defaultKey:)` und
`alwaysShowsReadArticleKeys` in `SQLiteSidebarState.swift` entfallen (toter
Code nach diesem Umbau) — `mixedCountKeys` bleibt bestehen (siehe
Nicht-Ziele).

## Fehlerbehandlung

Keine neuen Fehlerfälle. Die neue Spalte ist `NOT NULL` mit Datenbank-Default
`false`, GRDBs Codable-Decodierung deckt das ab wie die bestehenden
Bool-Felder auf `SmartFolderRecord`. Fehlt die Datenbank beim Laden des
Editors (`feedivoDatabase == nil`), bleibt `defaultShowsReadArticles` auf
seinem Default `false` (Vorschau-Zähler zeigt in diesem Fall ohnehin `0`,
siehe bestehendes Verhalten für `previewMatchingCount`).

## Testabdeckung

Neue/angepasste Tests:

1. **Migration:** Neuer Test in `FeedivoDatabaseMigratorTests.swift` (oder
   passende bestehende Suite), der verifiziert, dass nach der Migration
   bestehende Zeilen mit `defaultKey` in
   (`starred`, `thisWeek`, `hidden`, `saved`) `defaultShowsReadArticles = true`
   haben, alle anderen `false`.
2. **`SQLiteSmartFolderStoreTests`:** `save()`/`folders()` roundtrip mit
   gesetztem `defaultShowsReadArticles`; `duplicate(id:copyName:)` übernimmt
   den Wert; `restoreDefaultFolders()` legt die vier betroffenen Ordner mit
   `defaultShowsReadArticles = true` an.
3. **`SQLiteFeedArticleListStateTests`** oder passende View-Level-Tests:
   `defaultShowsReadArticles`-Computed-Property liefert für einen
   `.smartFolder`-Scope den Snapshot-Wert direkt (Regressionsschutz für die
   Vereinfachung).

UI-seitig (Segmented-Control im Editor-Dialog) wie bei anderen SwiftUI-
Interaktionen in diesem Projekt keine automatisierte Testabdeckung —
manuelle Verifikation nach Implementierung, inkl. Sichttest bei einem
Standard-Ordner (Name-Feld gesperrt, neue Zeile trotzdem aktiv).
