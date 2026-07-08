# Sidebar: Intelligente Ordner in Standard/Eigene aufteilen

## Ziel

In der linken Seitenleiste soll der bisher einzelne Abschnitt "Intelligente Ordner"
in zwei Abschnitte aufgeteilt werden:

- **"Intelligente Ordner"** — die 8 mitgelieferten Standard-Ordner (Alle, Ungelesen,
  Mit Stern, Heute, Ausgeblendet, Archiviert, Diese Woche, Gespeichert)
- **"Eigene Intelligente Ordner"** — alle vom Nutzer selbst angelegten (und
  duplizierten) Intelligenten Ordner

## Trennkriterium

`SQLiteSmartFolderSnapshot.defaultKey`:
- gesetzt (`!= nil`) → Standard-Ordner → Abschnitt "Intelligente Ordner"
- `nil` → benutzerdefiniert → Abschnitt "Eigene Intelligente Ordner"

Bestätigt durch `SQLiteSmartFolderStore.duplicate(...)`: Kopien werden immer mit
`isDefault: false, defaultKey: nil` angelegt — landen also automatisch unter
"Eigene Intelligente Ordner", auch wenn das Original ein Standard-Ordner war.
Inhaltlich korrekt, da eine Kopie kein mitgeliefertes Objekt mehr ist.

Die relative Reihenfolge innerhalb jeder Gruppe bleibt wie bisher (aus
`sqliteSidebarState.smartFolderSnapshots`, nur gefiltert statt neu sortiert).

## UI-Aufbau

`SidebarView.smartFoldersSection(...)` wird durch zwei separate Aufrufe von
`CollapsibleSidebarSection` ersetzt:

1. **Standard-Abschnitt**
   - Titel: bestehender Key `L10n.sidebarSmartFoldersSection` ("Intelligente Ordner"),
     unverändert
   - Kein "+"-Aktionsbutton (Standard-Ordner können nicht neu angelegt werden)
   - Leerer Zustand: bestehender Text `L10n.sidebarSmartFoldersEmpty` als Fallback
     (praktisch nie leer, da die Standard-Ordner beim Start geseedet werden)

2. **Eigene-Abschnitt**
   - Titel: neuer Key `sidebar.smartFolders.custom.section` = "Eigene Intelligente Ordner"
   - "+"-Aktionsbutton öffnet wie bisher `isCreatingSmartFolder = true`
     (`SmartFolderEditorView`-Sheet)
   - Leerer Zustand: neuer Text `sidebar.smartFolders.custom.empty` = "Keine eigenen Ordner"
   - Immer sichtbar, auch ohne eigene Ordner (Nutzerentscheidung aus dem Brainstorming)

Beide Abschnitte teilen sich weiterhin dieselbe `SmartFolderSidebarRow`-Darstellung,
denselben Selection-/Kontextmenü-Code (Bearbeiten/Duplizieren/Löschen) und dieselben
`badgeSnapshot`/`mixedCountsByDefaultKey`-Daten wie bisher — nur die Filterung und
das Section-Wrapping ändern sich.

## Collapse-State

Zwei unabhängige, persistente Einklapp-Zustände:

- Standard-Abschnitt: bestehender `SidebarSectionCollapseState.Section.smartFolders`
  (Storage-Key `sidebar.section.smartFolders.isCollapsed`) — **unverändert**, damit
  die bisherige Nutzer-Einstellung nicht zurückgesetzt wird.
- Eigene-Abschnitt: neuer Fall `customSmartFolders` in
  `SidebarSectionCollapseState.Section` mit Storage-Key
  `sidebar.section.customSmartFolders.isCollapsed`, Default: aufgeklappt.

## Lokalisierung

Zwei neue Keys in `L10n.swift` + `Localizable.xcstrings` (de/en/fr/it, wie die
bestehenden `sidebar.smartFolders.*`-Keys):

- `sidebar.smartFolders.custom.section` → "Eigene Intelligente Ordner"
- `sidebar.smartFolders.custom.empty` → "Keine eigenen Ordner"

## Out of Scope

- Keine Änderung an `SmartFolderEditorView`, `SQLiteSmartFolderStore` oder der
  Datenbank-Schicht — reine Sidebar-Darstellungsänderung.
- Kein Drag & Drop zwischen den beiden Abschnitten.
- Keine Änderung am Verhalten von Bearbeiten/Duplizieren/Löschen im Kontextmenü.

## Testing

- Bestehende Sidebar-/SmartFolder-Tests (falls vorhanden) weiterhin grün.
- Manuelle Verifikation in der laufenden App: Standard-Ordner erscheinen unter
  "Intelligente Ordner", ein neu angelegter bzw. duplizierter Ordner erscheint
  unter "Eigene Intelligente Ordner", beide Abschnitte unabhängig einklappbar,
  "+"-Button nur im Eigene-Abschnitt.
