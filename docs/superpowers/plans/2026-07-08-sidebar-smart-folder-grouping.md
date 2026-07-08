# Sidebar Smart-Folder-Gruppierung Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Den Sidebar-Abschnitt "Intelligente Ordner" in zwei unabhängig einklappbare
Abschnitte aufteilen: "Intelligente Ordner" (die 8 mitgelieferten Standard-Ordner) und
"Eigene Intelligente Ordner" (alle benutzerdefinierten/duplizierten Ordner).

**Architecture:** Ein neuer, reiner Helper (`SmartFolderSidebarGrouping`) filtert die
bestehende `sqliteSidebarState.smartFolderSnapshots`-Liste anhand von
`defaultKey != nil` vs. `== nil` in zwei Teillisten, ohne die bestehende Reihenfolge
zu verändern. `SidebarView.smartFoldersSection(...)` wird durch zwei Aufrufe von
`CollapsibleSidebarSection` ersetzt, die sich Zeilen-Rendering und Kontextmenü-Code
teilen. Ein neuer Fall in `SidebarSectionCollapseState.Section` liefert den
persistenten Einklapp-Zustand für den neuen Abschnitt.

**Tech Stack:** SwiftUI (macOS), GRDB/SQLite-Snapshots, Swift Testing (`@Test`/`#expect`),
`L10n.swift` + `Localizable.xcstrings` für Lokalisierung (de/en/fr/it).

## Global Constraints

- Bestehender AppStorage-Key `sidebar.section.smartFolders.isCollapsed` bleibt für den
  Standard-Abschnitt unverändert (kein Reset bestehender Nutzer-Einstellungen).
- Kein Refactoring an `SmartFolderEditorView`, `SQLiteSmartFolderStore` oder der
  Datenbank-Schicht — reine Sidebar-Darstellungsänderung (siehe Spec, Abschnitt
  "Out of Scope").
- Volle Testsuite (`xcodebuild test` ohne `-only-testing`) hängt bekanntermaßen —
  immer gezielt mit `-only-testing:FeedivoTests/<SuiteName>` testen.
- SourceKit-Diagnosen in der IDE sind oft veraltet/falsch — verlässlich ist nur ein
  echter `xcodebuild build`-Lauf.
- Kommentare im Code auf Deutsch (Projekt-Konvention).

---

### Task 1: Neuer Collapse-State-Fall für "Eigene Intelligente Ordner"

**Files:**
- Modify: `Feedivo/Views/Sidebar/SidebarSectionCollapseState.swift`
- Test: `FeedivoTests/SidebarSectionCollapseStateTests.swift`

**Interfaces:**
- Produces: `SidebarSectionCollapseState.Section.customSmartFolders` (neuer Enum-Fall),
  `.storageKey == "sidebar.section.customSmartFolders.isCollapsed"`

- [ ] **Step 1: Schreibe den fehlschlagenden Test**

In `FeedivoTests/SidebarSectionCollapseStateTests.swift` die bestehende Methode
`appStorageKeysBleibenStabil()` um eine Zeile erweitern:

```swift
    @MainActor
    @Test func appStorageKeysBleibenStabil() {
        #expect(SidebarSectionCollapseState.Section.smartFilters.storageKey == "sidebar.section.smartFilters.isCollapsed")
        #expect(SidebarSectionCollapseState.Section.tags.storageKey == "sidebar.section.tags.isCollapsed")
        #expect(SidebarSectionCollapseState.Section.folders.storageKey == "sidebar.section.folders.isCollapsed")
        #expect(SidebarSectionCollapseState.Section.smartFolders.storageKey == "sidebar.section.smartFolders.isCollapsed")
        #expect(SidebarSectionCollapseState.Section.customSmartFolders.storageKey == "sidebar.section.customSmartFolders.isCollapsed")
    }
```

- [ ] **Step 2: Test laufen lassen, um das Fehlschlagen zu bestätigen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SidebarSectionCollapseStateTests`
Expected: FAIL — `type 'SidebarSectionCollapseState.Section' has no member 'customSmartFolders'`

- [ ] **Step 3: Enum-Fall implementieren**

In `Feedivo/Views/Sidebar/SidebarSectionCollapseState.swift` den kompletten Inhalt
ersetzen durch:

```swift
import Foundation

enum SidebarSectionCollapseState {
    enum Section: CaseIterable, Hashable {
        case smartFilters
        case tags
        case folders
        case smartFolders
        case customSmartFolders

        var storageKey: String {
            switch self {
            case .smartFilters:
                "sidebar.section.smartFilters.isCollapsed"
            case .tags:
                "sidebar.section.tags.isCollapsed"
            case .folders:
                "sidebar.section.folders.isCollapsed"
            case .smartFolders:
                "sidebar.section.smartFolders.isCollapsed"
            case .customSmartFolders:
                "sidebar.section.customSmartFolders.isCollapsed"
            }
        }
    }

    static func toggle(_ section: Section, in collapsedSections: inout Set<Section>) {
        if collapsedSections.contains(section) {
            collapsedSections.remove(section)
        } else {
            collapsedSections.insert(section)
        }
    }
}
```

- [ ] **Step 4: Test laufen lassen, um das Bestehen zu bestätigen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SidebarSectionCollapseStateTests`
Expected: PASS (alle Tests der Suite grün)

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Views/Sidebar/SidebarSectionCollapseState.swift FeedivoTests/SidebarSectionCollapseStateTests.swift
git commit -m "Sidebar: Collapse-State-Fall für Eigene Intelligente Ordner ergänzt"
```

---

### Task 2: Lokalisierungs-Keys für den neuen Abschnitt

**Files:**
- Modify: `Feedivo/Resources/L10n.swift:25-26` (direkt nach den bestehenden
  `sidebarSmartFolders*`-Keys)
- Modify: `Feedivo/Resources/Localizable.xcstrings:23295-23323` (Eintrag zwischen
  `"sidebar.smartFolder.duplicate"` und `"sidebar.smartFolders.empty"` einfügen —
  alphabetische Reihenfolge, `custom` < `empty`)

**Interfaces:**
- Produces: `L10n.sidebarSmartFoldersCustomSection` (LocalizedStringKey,
  "sidebar.smartFolders.custom.section"), `L10n.sidebarSmartFoldersCustomEmpty`
  (LocalizedStringKey, "sidebar.smartFolders.custom.empty")

Kein Unit-Test nötig — `LocalizedStringKey`/`String(localized:)` schlagen bei
fehlendem xcstrings-Eintrag nicht beim Compile fehl (nur sichtbarer Fallback auf den
Roh-Key), daher genügt hier die manuelle/visuelle Verifikation in Task 4.

- [ ] **Step 1: Neue Keys in L10n.swift ergänzen**

In `Feedivo/Resources/L10n.swift` direkt nach Zeile 26
(`static let sidebarSmartFoldersEmpty = LocalizedStringKey("sidebar.smartFolders.empty")`)
einfügen:

```swift
    static let sidebarSmartFoldersCustomSection = LocalizedStringKey("sidebar.smartFolders.custom.section")
    static let sidebarSmartFoldersCustomEmpty = LocalizedStringKey("sidebar.smartFolders.custom.empty")
```

- [ ] **Step 2: Neue Einträge in Localizable.xcstrings ergänzen**

In `Feedivo/Resources/Localizable.xcstrings` direkt vor dem Eintrag
`"sidebar.smartFolders.empty": {` (Zeile 23323 vor dieser Änderung) folgende zwei
Einträge einfügen:

```json
    "sidebar.smartFolders.custom.empty": {
      "localizations": {
        "de": {
          "stringUnit": {
            "state": "translated",
            "value": "Keine eigenen Ordner"
          }
        },
        "en": {
          "stringUnit": {
            "state": "translated",
            "value": "No custom folders"
          }
        },
        "fr": {
          "stringUnit": {
            "state": "translated",
            "value": "Aucun dossier personnalisé"
          }
        },
        "it": {
          "stringUnit": {
            "state": "translated",
            "value": "Nessuna cartella personalizzata"
          }
        }
      }
    },
    "sidebar.smartFolders.custom.section": {
      "localizations": {
        "de": {
          "stringUnit": {
            "state": "translated",
            "value": "Eigene Intelligente Ordner"
          }
        },
        "en": {
          "stringUnit": {
            "state": "translated",
            "value": "My Smart Folders"
          }
        },
        "fr": {
          "stringUnit": {
            "state": "translated",
            "value": "Mes dossiers intelligents"
          }
        },
        "it": {
          "stringUnit": {
            "state": "translated",
            "value": "Le mie cartelle smart"
          }
        }
      }
    },
```

- [ ] **Step 3: Build laufen lassen, um sicherzustellen, dass das JSON valide bleibt**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo | tail -20`
Expected: `** BUILD SUCCEEDED **` (ein defektes xcstrings-JSON lässt den Build mit
einem Ressourcen-Compile-Fehler fehlschlagen)

- [ ] **Step 4: Commit**

```bash
git add Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings
git commit -m "Sidebar: Lokalisierung für Eigene Intelligente Ordner ergänzt"
```

---

### Task 3: Reiner Grouping-Helper + Test

**Files:**
- Create: `Feedivo/Views/Sidebar/SmartFolderSidebarGrouping.swift`
- Test: `FeedivoTests/SmartFolderSidebarGroupingTests.swift`

**Interfaces:**
- Consumes: `SQLiteSmartFolderSnapshot` (bestehender Typ, Feld `defaultKey: String?`,
  siehe `Feedivo/Snapshots/SQLiteSmartFolderSnapshot.swift`)
- Produces: `SmartFolderSidebarGrouping.defaultFolders(from: [SQLiteSmartFolderSnapshot]) -> [SQLiteSmartFolderSnapshot]`,
  `SmartFolderSidebarGrouping.customFolders(from: [SQLiteSmartFolderSnapshot]) -> [SQLiteSmartFolderSnapshot]`
  — beide erhalten die Eingabe-Reihenfolge (stabiler Filter, kein Re-Sort).

- [ ] **Step 1: Schreibe die fehlschlagenden Tests**

Erstelle `FeedivoTests/SmartFolderSidebarGroupingTests.swift`:

```swift
import Testing
@testable import Feedivo

struct SmartFolderSidebarGroupingTests {

    private func makeSnapshot(id: String, defaultKey: String?) -> SQLiteSmartFolderSnapshot {
        SQLiteSmartFolderSnapshot(
            id: id,
            name: id,
            matchMode: .all,
            conditions: [],
            defaultKey: defaultKey
        )
    }

    @Test func defaultFoldersEnthaeltNurEintraegeMitDefaultKey() {
        let snapshots = [
            makeSnapshot(id: "all", defaultKey: "all"),
            makeSnapshot(id: "custom1", defaultKey: nil),
            makeSnapshot(id: "unread", defaultKey: "unread"),
            makeSnapshot(id: "custom2", defaultKey: nil)
        ]

        let result = SmartFolderSidebarGrouping.defaultFolders(from: snapshots)

        #expect(result.map(\.id) == ["all", "unread"])
    }

    @Test func customFoldersEnthaeltNurEintraegeOhneDefaultKey() {
        let snapshots = [
            makeSnapshot(id: "all", defaultKey: "all"),
            makeSnapshot(id: "custom1", defaultKey: nil),
            makeSnapshot(id: "unread", defaultKey: "unread"),
            makeSnapshot(id: "custom2", defaultKey: nil)
        ]

        let result = SmartFolderSidebarGrouping.customFolders(from: snapshots)

        #expect(result.map(\.id) == ["custom1", "custom2"])
    }

    @Test func beideGruppenBleibenLeerBeiLeererEingabe() {
        #expect(SmartFolderSidebarGrouping.defaultFolders(from: []).isEmpty)
        #expect(SmartFolderSidebarGrouping.customFolders(from: []).isEmpty)
    }
}
```

- [ ] **Step 2: Test laufen lassen, um das Fehlschlagen zu bestätigen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SmartFolderSidebarGroupingTests`
Expected: FAIL — `Cannot find 'SmartFolderSidebarGrouping' in scope`

- [ ] **Step 3: Minimale Implementierung schreiben**

Erstelle `Feedivo/Views/Sidebar/SmartFolderSidebarGrouping.swift`:

```swift
import Foundation

/// Trennt die (bereits nach Sichtbarkeit gefilterten) Intelligenten-Ordner-Snapshots
/// der Sidebar in Standard-Ordner (mitgeliefert, `defaultKey != nil`) und
/// benutzerdefinierte Ordner (`defaultKey == nil`, inklusive Duplikate von
/// Standard-Ordnern — siehe `SQLiteSmartFolderStore.duplicate`, das immer
/// `defaultKey: nil` setzt). Reiner Filter ohne Neusortierung, damit die
/// bestehende Reihenfolge innerhalb jeder Gruppe erhalten bleibt.
enum SmartFolderSidebarGrouping {
    static func defaultFolders(from snapshots: [SQLiteSmartFolderSnapshot]) -> [SQLiteSmartFolderSnapshot] {
        snapshots.filter { $0.defaultKey != nil }
    }

    static func customFolders(from snapshots: [SQLiteSmartFolderSnapshot]) -> [SQLiteSmartFolderSnapshot] {
        snapshots.filter { $0.defaultKey == nil }
    }
}
```

- [ ] **Step 4: Test laufen lassen, um das Bestehen zu bestätigen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SmartFolderSidebarGroupingTests`
Expected: PASS (alle drei Tests grün)

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Views/Sidebar/SmartFolderSidebarGrouping.swift FeedivoTests/SmartFolderSidebarGroupingTests.swift
git commit -m "Sidebar: SmartFolderSidebarGrouping-Helper für Standard/Eigene-Trennung"
```

---

### Task 4: SidebarView — Abschnitt aufteilen

**Files:**
- Modify: `Feedivo/Views/Sidebar/SidebarView.swift:34` (neue `@AppStorage`-Property)
- Modify: `Feedivo/Views/Sidebar/SidebarView.swift:54-57` (Aufruf-Stelle)
- Modify: `Feedivo/Views/Sidebar/SidebarView.swift:258-319` (Funktion
  `smartFoldersSection` wird durch zwei neue Funktionen ersetzt)

**Interfaces:**
- Consumes: `SmartFolderSidebarGrouping.defaultFolders(from:)` /
  `.customFolders(from:)` (Task 3), `SidebarSectionCollapseState.Section.customSmartFolders`
  (Task 1), `L10n.sidebarSmartFoldersCustomSection` / `.sidebarSmartFoldersCustomEmpty`
  (Task 2)
- Produces: keine neuen öffentlichen Symbole — reine View-interne Umstrukturierung

- [ ] **Step 1: Neue Collapse-Property ergänzen**

In `Feedivo/Views/Sidebar/SidebarView.swift` direkt nach Zeile 34
(`private var isSmartFoldersCollapsed = false`) einfügen:

```swift
    @AppStorage(SidebarSectionCollapseState.Section.customSmartFolders.storageKey)
    private var isCustomSmartFoldersCollapsed = false
```

- [ ] **Step 2: Aufruf-Stelle im `body` anpassen**

Den bestehenden Aufruf (aktuell Zeilen 54-57):

```swift
                    smartFoldersSection(
                        badgeSnapshot: sqliteSidebarState.smartFolderBadgeSnapshot,
                        mixedCountsByDefaultKey: sqliteSidebarState.mixedCountsByDefaultKey
                    )
```

ersetzen durch:

```swift
                    defaultSmartFoldersSection(
                        badgeSnapshot: sqliteSidebarState.smartFolderBadgeSnapshot,
                        mixedCountsByDefaultKey: sqliteSidebarState.mixedCountsByDefaultKey
                    )
                    customSmartFoldersSection(
                        badgeSnapshot: sqliteSidebarState.smartFolderBadgeSnapshot,
                        mixedCountsByDefaultKey: sqliteSidebarState.mixedCountsByDefaultKey
                    )
```

- [ ] **Step 3: `smartFoldersSection` durch zwei Funktionen ersetzen**

Die komplette bestehende Funktion `smartFoldersSection(badgeSnapshot:mixedCountsByDefaultKey:)`
(aktuell Zeilen 258-319, von `private func smartFoldersSection(` bis zur
schließenden `}` direkt vor `private func defaultSmartFolderSelection`) ersetzen durch:

```swift
    private func defaultSmartFoldersSection(
        badgeSnapshot: SmartFolderSidebarBadgeSnapshot,
        mixedCountsByDefaultKey: [String: SmartFolderMixedCounts]
    ) -> some View {
        CollapsibleSidebarSection(
            title: L10n.sidebarSmartFoldersSection,
            isCollapsed: $isSmartFoldersCollapsed
        ) content: {
            let folders = SmartFolderSidebarGrouping.defaultFolders(from: sqliteSidebarState.smartFolderSnapshots)

            if folders.isEmpty {
                Text(L10n.sidebarSmartFoldersEmpty)
                    .font(interfaceTextSize.font(size: 13))
                    .foregroundStyle(SidebarStyle.secondaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            } else {
                smartFolderRows(folders, badgeSnapshot: badgeSnapshot, mixedCountsByDefaultKey: mixedCountsByDefaultKey)
            }
        }
    }

    private func customSmartFoldersSection(
        badgeSnapshot: SmartFolderSidebarBadgeSnapshot,
        mixedCountsByDefaultKey: [String: SmartFolderMixedCounts]
    ) -> some View {
        CollapsibleSidebarSection(
            title: L10n.sidebarSmartFoldersCustomSection,
            isCollapsed: $isCustomSmartFoldersCollapsed,
            actionSystemImage: "plus",
            actionHelp: String(localized: "sidebar.smartFolder.create")
        ) {
            isCreatingSmartFolder = true
        } content: {
            let folders = SmartFolderSidebarGrouping.customFolders(from: sqliteSidebarState.smartFolderSnapshots)

            if folders.isEmpty {
                Text(L10n.sidebarSmartFoldersCustomEmpty)
                    .font(interfaceTextSize.font(size: 13))
                    .foregroundStyle(SidebarStyle.secondaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            } else {
                smartFolderRows(folders, badgeSnapshot: badgeSnapshot, mixedCountsByDefaultKey: mixedCountsByDefaultKey)
            }
        }
    }

    @ViewBuilder
    private func smartFolderRows(
        _ folders: [SQLiteSmartFolderSnapshot],
        badgeSnapshot: SmartFolderSidebarBadgeSnapshot,
        mixedCountsByDefaultKey: [String: SmartFolderMixedCounts]
    ) -> some View {
        ForEach(folders) { smartFolder in
            Button {
                selection = .smartFolder(smartFolder.id)
            } label: {
                SmartFolderSidebarRow(
                    smartFolder: smartFolder,
                    badgeSnapshot: badgeSnapshot,
                    mixedCounts: smartFolder.defaultKey.flatMap { mixedCountsByDefaultKey[$0] }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(
                SidebarRowButtonStyle(
                    isSelected: selection == .smartFolder(smartFolder.id)
                )
            )
            .contextMenu {
                Button {
                    smartFolderEditing = sqliteSmartFolderRecord(id: smartFolder.id)
                } label: {
                    Label(L10n.ruleEditButton, systemImage: "pencil")
                }

                Button {
                    duplicateSmartFolder(smartFolder)
                } label: {
                    Label(L10n.commonDuplicate, systemImage: "plus.square.on.square")
                }

                Divider()

                Button(role: .destructive) {
                    smartFolderPendingDeletion = smartFolder
                } label: {
                    Label(L10n.ruleDeleteButton, systemImage: "trash")
                }
            }
        }
    }

```

Wichtig: `CollapsibleSidebarSection` hat zwei Closure-Parameter (`action` vor
`content`, siehe `Feedivo/Views/Sidebar/SidebarView.swift:584-588`). Ein
unlabeled Trailing-Closure würde daher an `action` binden, nicht an `content`
(`content` ist nicht optional und hat keinen Default). Im Standard-Abschnitt
MUSS deshalb explizit die gelabelte Trailing-Closure-Syntax `) content: { ... }`
verwendet werden (wie oben geschrieben) — mit einem unlabeled `{ ... }` direkt
nach `isCollapsed:` würde der Compiler `content` als fehlendes Argument
melden. `actionSystemImage`/`actionHelp`/`action`/`isActionDisabled` behalten
dabei ihre Defaults (`nil`/`false`), wodurch kein "+"-Button gerendert wird.

- [ ] **Step 4: Build laufen lassen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo | tail -40`
Expected: `** BUILD SUCCEEDED **`. Falls SourceKit in der IDE weiterhin Fehler wie
"Cannot find type X in scope" anzeigt, ignorieren — nur der `xcodebuild`-Log zählt
(siehe CLAUDE.md Gotchas).

- [ ] **Step 5: Bestehende Sidebar-Tests laufen lassen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteSidebarStateTests -only-testing:FeedivoTests/SidebarSectionCollapseStateTests -only-testing:FeedivoTests/SidebarStyleTests -only-testing:FeedivoTests/SidebarUnreadCountTests -only-testing:FeedivoTests/SmartFolderSidebarGroupingTests`
Expected: PASS (alle Suiten grün — stellt sicher, dass die Umstrukturierung keine
bestehende Sidebar-Logik gebrochen hat)

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Views/Sidebar/SidebarView.swift
git commit -m "Sidebar: Intelligente Ordner in Standard- und Eigene-Abschnitt aufgeteilt"
```

---

### Task 5: Manuelle Verifikation in der laufenden App

**Files:** keine (nur Verifikation, keine Code-Änderung)

- [ ] **Step 1: App bauen und starten**

```bash
xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -configuration Debug build | tail -20
```
Expected: `** BUILD SUCCEEDED **`

Danach die gebaute App aus dem DerivedData-Pfad öffnen (siehe vorherige Sessions:
`open .../Build/Products/Debug/Feedivo.app`).

- [ ] **Step 2: Sidebar visuell prüfen**

Prüfen:
- Zwei getrennte Abschnitte "Intelligente Ordner" (8 Standard-Ordner: Alle,
  Ungelesen, Mit Stern, Heute, Ausgeblendet, Archiviert, Diese Woche, Gespeichert)
  und "Eigene Intelligente Ordner" sind sichtbar.
- "+"-Button erscheint NUR im Abschnitt "Eigene Intelligente Ordner".
- Beide Abschnitte lassen sich unabhängig voneinander ein-/ausklappen, der
  Zustand bleibt nach App-Neustart erhalten (AppStorage).
- Über den "+"-Button einen neuen Intelligenten Ordner anlegen → erscheint unter
  "Eigene Intelligente Ordner".
- Einen Standard-Ordner (z. B. "Alle") per Kontextmenü duplizieren → das Duplikat
  erscheint unter "Eigene Intelligente Ordner", nicht unter "Intelligente Ordner".
- Auswahl, Bearbeiten und Löschen funktionieren in beiden Abschnitten wie zuvor.

- [ ] **Step 3: Abschließender Commit-Check**

```bash
git log --oneline -6
git status --short
```
Expected: Alle 4 vorherigen Task-Commits sichtbar, Arbeitsverzeichnis sauber
(abgesehen von nicht-projektbezogenen, bereits vor diesem Plan bestehenden Änderungen).
