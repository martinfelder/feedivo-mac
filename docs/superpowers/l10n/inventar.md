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