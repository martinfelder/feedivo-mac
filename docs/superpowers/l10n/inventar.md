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

## Verifikationsstand (Task 10, 2026-06-28)

Alle Cluster-Tasks 0–9 sind committet (HEAD: 56663901).

Katalog (`Feedivo/Resources/Localizable.xcstrings`):
- Total Keys: 803
- Vollständig übersetzt (de+en+fr+it): 774
- Fehlende EN/FR/IT: 29 distinct Keys (87 Sprach-Paare).

Offene Lücken (vom Cluster-Work nicht erfasst — zur Behebung an Controller delegiert):
- Rohe DE-Literale im Code (leere Katalog-Einträge, auto-extrahiert, keine L10n-Accessor-Nutzung):
  `Abonnieren`, `Letzte Artikel`, `Standardordner`, `Eigener Ordner`,
  `Intelligenten Ordner bearbeiten/erstellen/löschen`, `Keine intelligenten Ordner`,
  `Import abgeschlossen`, `Import abgeschlossen mit Hinweisen`,
  `Durchsuche alle gespeicherten Artikel …`, `Nach oben`, `Nach unten`,
  `Zum Sortieren ziehen`, `%lld Treffer`, `%lld px`, `#%@`, `.%@`, `·`, ``
- Benannte Keys nur mit DE (state "new"), ohne en/fr/it:
  `feed.error.alreadyRunning`, `feed.error.duplicate`, `feed.import.alreadyRunning`,
  `offline.archive.error.message`, `offline.archive.error.title`
- Proper-Noun/Format-Strings (bewusst nicht lokalisiert):
  `Feedivo`, `https://example.com/feed.xml`

Build: SUCCEEDED. Tests: BLOCKED — 3 fehlschlagende Tests (siehe Task-10-Report).