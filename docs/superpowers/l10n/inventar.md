# L10n-Inventar (Task 0)

> Verbindlich für Tasks 3–8. Legt je Literal fest: Key, DE-Source-Wert, Typ,
> und ob der Key im Katalog vor Task-Ausführung existierte.

## Cluster Sidebar (SidebarView.swift): 9 Literale (8 neu + 1 bestehend)
- 110 confirmationDialog „Intelligenten Ordner löschen“ -> sidebar.smartFolder.deleteConfirm [fehlt]
- 121 Button „Löschen“ -> common.delete [fehlt]
- 238 Section „Intelligente Ordner“ -> sidebar.smartFilters.section [bestehend: L10n.sidebarSmartFiltersSection]
- 241 actionHelp „Intelligenten Ordner erstellen“ -> sidebar.smartFolder.create [fehlt]
- 249 „Keine intelligenten Ordner“ -> sidebar.smartFolders.empty [fehlt]
- 288 „Duplizieren“ -> common.duplicate [fehlt]
- 493 smartFolder.name -> localizedDisplayName (Task 1, kein Literal)
- 865 „Dieser Feed liefert aktuell keine Artikel für die Vorschau.“ -> sidebar.feedPreview.empty [fehlt]
- 870 „Letzte Artikel“ -> sidebar.feedPreview.recent [fehlt]
- 934 „Abonnieren“ -> sidebar.subscribe [fehlt]

## Cluster SmartFolderSettings (10 neu, 1 bestehend)
… (vollständige Liste siehe Task 4) …

## Cluster SmartFolderEditor (15 neu) — siehe Task 5
## Cluster RuleSettings (7 neu) — siehe Task 6
## Cluster FirstRun (Plain + View) — siehe Task 7
## Cluster OPMLImportReview — siehe Task 8
## Cluster OPMLImportPreviewController (Plain-String) — siehe Task 9
## Plural-Strings (24) — siehe Task 2

Gesamt echte Lücken: 67 Literale + 24 Plural-Strings + 8 Default-Namen (Task 1).

## Verifikationsstand (Folge-Task Katalog-Lücken, 2026-06-28)

Alle Cluster-Tasks 0–9 + Folge-Task (Katalog-Lücken) sind committet.

Katalog (`Feedivo/Resources/Localizable.xcstrings`):
- Total Keys: 789
- Vollständig übersetzt (de+en+fr+it): 781
- Fehlende EN/FR/IT: 8 distinct Keys (24 Sprach-Paare) — alle bewusst nicht lokalisiert.

Reale Lücken geschlossen:
- `article.search.window.description` (REAL, aus ArticleSearchWindowView.swift:78)
- `article.search.matchCount` (REAL, Plural, aus ArticleSearchWindowView.swift:86)
- 5 Category-B Keys übersetzt: `feed.error.alreadyRunning`, `feed.error.duplicate`,
  `feed.import.alreadyRunning`, `offline.archive.error.message`, `offline.archive.error.title`

Geister bereinigt (16 leere `{}`-Einträge entfernt, da Quelle ersetzt):
  `Abonnieren`, `Dieser Feed liefert aktuell keine Artikel für die Vorschau.`,
  `Durchsuche alle gespeicherten Artikel …`, `Eigener Ordner`, `Import abgeschlossen`,
  `Import abgeschlossen mit Hinweisen`, `Intelligenten Ordner bearbeiten/erstellen/löschen`,
  `Keine intelligenten Ordner`, `Letzte Artikel`, `Nach oben`, `Nach unten`,
  `Standardordner`, `Zum Sortieren ziehen`, `%lld Treffer`.

Bewusst nicht lokalisiert (verbleibend, alle mit Quelle als auto-extrahiert):
  `Feedivo` (App-Name), `https://example.com/feed.xml` (URL-Placeholder),
  `%lld px` (Pixel-Wert aus ReaderView/SettingsView), `#%@` (Tag-Chip-Präfix),
  `.%@` (Dateiendung-Punkt), `·` (Trenn-Symbol), `%lld` ( nackte Zahlen-Anzeige),
  `` (leerer Key).

Build: SUCCEEDED. Tests: SUCCEEDED.