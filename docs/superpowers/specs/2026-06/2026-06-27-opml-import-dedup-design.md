# OPML-Import-Deduplikation (M1) — Design

> Refactor: Die OPML-Vorschau-Logik wird aus `OPMLImportReviewView` und
> `FirstRunWizardView` in einen gemeinsamen Controller + eine einheitliche
> Feed-Zeile extrahiert. Reines Verhaltens-Erhaltungs-Refactor; keine
> nutzer­sichtbare Änderung.

Datum: 2026-06-27
Review-Fund: M1 (OPML-Duplikation, Aufwand L) aus dem vollständigen Code-Review
vom 2026-06-27 — „OPMLImportReviewView vs FirstRunWizardView (~identische
Logik + Zeilenkomponenten, zweifach gepflegt). Controller + gemeinsame Tabelle
extrahieren."

## Ziel

Eine einzelne Quelle der Wahrheit für die OPML-Import-Vorschau (State, Logik,
Helfer, Feed-Zeile). Beide Views (`OPMLImportReviewView` und
`FirstRunWizardView`) binden an denselben Controller und dieselbe Zeile. Die
Tabellen-Layouts bleiben pro View, weil sie sich in Spalten, Progress-Platzierung
und Leer-Modus echt unterscheiden (eine Einheits-Tabelle bräuchte eine schwere
Config mit Closures — bewusst vermieden).

## Bestandsaufnahme der Duplikation

Zwischen den beiden Views existierten zweifach gepflegte Bestandteile:

- **State + abgeleitete Properties:** `rows`, `allowsDuplicates`,
  `allowsUnreachable`, `refreshAfterImport`, `statusFilter`, `newFolderName`,
  `customFolders`, `selectedFileName`, `previewProgressText`,
  `errorMessage`/`resultMessage`, `isPreparingPreview` sowie identische
  computed props (`selectionOptions`, `selectedImportRows`, `duplicateCount`,
  `unreachableCount`, `folderCount`, `availableFolders`, `visibleRowIDs`).
- **Logik-Methoden (byte-identisch):** `selectAllImportableRows`,
  `deselectVisibleRows`, `createFolder`, `trimmedFolderName`,
  die `onChange`-Handler für Duplikate/Unreachable, `fileImporter`/`onDrop`.
- **Async-Preview-Flow (`loadOPML`, `preparePreview`, `handleDroppedFiles`):**
  bis auf die Beschreibungs-Feld-Namen (`fileDescription` vs. `sourceDescription`)
  und FirstRun-only Step-Wechsel identisch.
- **Feed-Zeile (`OPMLImportFeedRow` vs `FirstRunImportFeedRow`):** Status-Badge,
  `folderBinding`, `rowBackground`, `statusText`, `statusColor`, `isSelectable`,
  `trimmedFolderName`, `onChange`-Bewachung identisch; Unterschiede: OPML hat
  eine Website-Spalte + Höhe 58, FirstRun keine Website-Spalte + Höhe 42.

Bereits geteilt (in `OPMLImportReviewView.swift`): `OPMLImportStatusFilter`,
`OPMLImportSelectionOptions`, `OPMLImportDroppedFile`.

## Architektur

### `OPMLImportPreviewController` (neu, `@Observable @MainActor`)

Datei: `Feedivo/Views/OPMLImport/OPMLImportPreviewController.swift`.

Reiner State + Logik + Helfer, **ohne externe Abhängigkeiten als Felder**
(kein `feeds`, kein `feedViewModel`, kein `modelContext` als gespeicherter
Zustand). `feeds`, `feedViewModel` und `modelContext` werden pro Aufruf
übergeben. Begründung: `feeds` aus `@Query` kann sich ändern → kein Stale-Cache;
parameterloser Init hält das SwiftUI-`@State`-Default-Pattern des Projekts.

**State (gespeichert):**
`rows`, `isPreparingPreview`, `allowsDuplicates`, `allowsUnreachable`,
`refreshAfterImport`, `statusFilter`, `newFolderName`, `customFolders`,
`selectedFileName`, `sourceDescription` (vereinheitlicht
`fileDescription`/`sourceDescription`), `previewProgressText`, `errorMessage`,
`resultMessage`, `isFileImporterPresented`, `isDropTargeted`.

**Abgeleitete Properties:** `selectionOptions`, `selectedImportRows`,
`duplicateCount`, `unreachableCount`, `folderCount`, `visibleRowIDs`,
`visibleRowCount`.

**Methoden:**
- `selectAllImportableRows()`, `deselectVisibleRows()`, `createFolder()`,
  `reset()`, `trimmedFolderName(_:)`, `availableFolders(existingFeeds:)`.
- `loadOPML(from:existingFeeds:feedViewModel:onStart:)`,
  `preparePreview(feeds:existingFeeds:feedViewModel:sourceText:)`,
  `handleDroppedFiles(_:existingFeeds:feedViewModel:onValidFile:)`.

**Nicht im Controller** (divergent, bleibt pro View):
- `importSelectedFeeds` + Ergebnis-Handling: OPML schreibt `resultMessage`-Text,
  FirstRun baut `FirstRunCompletionSummary` und wechselt zum `.finish`-Step.
- Formatierte Zusammenfassungs-Strings (`selectionSummaryText`,
  `previewSummaryText`, `selectedCountText`) — View-Chrome; greifen nur auf
  Controller-Zahlen zu.
- Step-Navigation (`step`, `inputStep`, `completionSummary`) — FirstRun-only.

**Nähte zu den Views (schmal, sichtbar):**
- FirstRun setzt `inputStep = .importOPML` direkt im `fileImporter`-Handler vor
  `controller.loadOPML(…)`.
- `handleDroppedFiles` bekommt optionalen `onValidFile: (URL) -> Void`-Closure
  (wird auf Main nach URL-Validierung gerufen, vor `loadOPML`). OPML: `nil`;
  FirstRun: `{ _ in step = .importOPML; inputStep = .importOPML }`.
- `controller.reset()` resettet gemeinsamen State auf konfigurierte
  Initial-Strings; Views wrappen ihn für Extras (OPML: `selectedFileName`;
  FirstRun: `completionSummary`/`feedURLString`/`step`).

**Konfiguration der Initial-Strings:** `OPMLImportPreviewConfiguration` mit
`initialSourceDescription` + `initialPreviewProgressText`. Zwei vorgefertigte
Werte: `.importSheet` (OPML-Strings, der Default) und `.firstRun`
(FirstRun-Strings). Controller-Init:
`init(configuration: OPMLImportPreviewConfiguration = .importSheet)`.

`@State`-Default im View (`OPMLImportReviewView`):
`@State private var controller = OPMLImportPreviewController()` → nutzt
`.importSheet`. FirstRun:
`@State private var controller = OPMLImportPreviewController(configuration: .firstRun)`.
Beide Default-Ausdrücke sind statisch (keine Abhängigkeit von Instanz-`let`s wie
`feedViewModel`) → keine SwiftUI-Init-Reihenfolge-Falle (M3-Pattern bleibt
intakt).

### Einheitliche `OPMLImportFeedRow` (neu, `internal`)

Datei: `Feedivo/Views/OPMLImport/OPMLImportFeedRow.swift`. Ersetzt die beiden
Zeilen-Structs. Parameterisiert via:

```swift
struct OPMLImportFeedRowLayout {
    var showsWebsite: Bool     // OPML: true, FirstRun: false
    var rowHeight: CGFloat      // OPML: 58, FirstRun: 42
    var folderWidth: CGFloat     // OPML: 154, FirstRun: 140
    var statusWidth: CGFloat     // OPML: 108, FirstRun: 110
}
```

- Website-Spalte per `@ViewBuilder` nur bei `showsWebsite`; `hostName`-Helfer
  wandert in diese Datei.
- `statusBadge`, `folderBinding`, `rowBackground`, `statusText`, `statusColor`,
  `isSelectable`, `trimmedFolderName`, `onChange(row.isSelected)` einmal gepflegt.

### Dateistruktur

- Neu `OPMLImportPreviewController.swift`: Controller +
  `OPMLImportPreviewConfiguration` + die bisherigen Shared-Typen
  (`OPMLImportStatusFilter`, `OPMLImportSelectionOptions`,
  `OPMLImportDroppedFile` — thematisch verschoben).
- Neu `OPMLImportFeedRow.swift`: einheitliche Zeile +
  `OPMLImportFeedRowLayout` + `hostName`.
- `OPMLImportReviewView.swift`: verliert State/Logik/Zeile; behält
  Header/Toolbar/Footer/Tabellen-Layout + Import-Nachbearbeitung.
- `FirstRunWizardView.swift`: verliert State/Logik/Zeile; behält
  Step-Rail/Welcome/AddFeed/Defaults/Finish-Steps + `FirstRunCompletionSummary`
  + Drop-/Step-Nähte.
- Neue Dateien auto-inkludiert (`PBXFileSystemSynchronizedRootGroup`) → kein
  `.pbxproj`-Edit.

## Tests

Neu `FeedivoTests/OPMLImportPreviewControllerTests.swift`. Charakterisieren die
bisher ungetestete reine Logik (TDD: Tests auf aktuelles Verhalten, dann
Refactor, dann grün):

- `selectAllImportableRows` respektiert Sichtbarkeit (`statusFilter`) +
  `selectionOptions` (Duplikate/Unreachable nur wenn erlaubt).
- `deselectVisibleRows` löscht nur sichtbare.
- `createFolder` fügt hinzu, dedupelt case-insensitiv, leert das Feld.
- `availableFolders(existingFeeds:)` merged existing+preview+custom, sortiert,
  dedupelt.
- `duplicateCount`/`unreachableCount`/`folderCount`/`selectedImportRows` zählen
  korrekt.
- `reset()` stellt konfigurierte Initial-Strings wieder her + leert `rows`.

Async-Pfade (`loadOPML`/`importOPMLFeeds`) brauchen Netz/`FeedViewModel` →
keine neuen Unit-Tests; abgesichert via Build + manuellem Spot-Check.

## Verhaltenserhalt & Verifikation

Reines Refactor, keine nutzer­sichtbare Änderung. Prüfung:

1. `xcodebuild build` grün.
2. `xcodebuild test` — 351 bestehende Tests grün + neue Controller-Tests.
3. Manueller Spot-Check: Import-Sheet öffnen, FirstRun-Wizard öffnen, Drop,
   Datei-Auswahl, Alle auswählen/abwählen, Ordner erstellen, Import,
   Statusfilter.