# Reader-Toolbar Status-Gruppe Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fasst Stern, Archivieren und Als-ungelesen-markieren als eine Button-Gruppe in der Reader-Toolbar von `SQLiteReaderView` zusammen, statt Archivieren allein und Stern/Ungelesen nur per Tastaturkürzel erreichbar zu haben.

**Architecture:** Reine SwiftUI-View-Änderung in einer bestehenden `ToolbarItemGroup`. Keine neue Business-Logik — die drei Toggle-Methoden (`toggleStarred`, `toggleArchived`, `toggleRead`) existieren bereits auf `SQLiteReaderState` und sind über bestehende Tests abgedeckt.

**Tech Stack:** SwiftUI (macOS), bestehende `SQLiteReaderState`-Klasse, bestehende L10n-Keys.

## Global Constraints

- Kommentare im Code auf Deutsch (Projektkonvention, siehe CLAUDE.md).
- Bestehende L10n-Keys wiederverwenden, keine neuen Strings anlegen.
- Icons folgen dem bestehenden gefüllt/leer-Muster (`archivebox`/`archivebox.fill`, `star`/`star.fill`).

---

### Task 1: Status-Gruppe in der Reader-Toolbar

**Files:**
- Modify: `Feedivo/Views/Reader/SQLiteReaderView.swift:117-141` (Toolbar-Block von "Original öffnen" bis zum bisherigen Archivieren-Button)

**Interfaces:**
- Consumes: `state.toggleStarred(database:)`, `state.toggleArchived(database:)`, `state.toggleRead(database:)` (bereits vorhanden auf `SQLiteReaderState`, `Feedivo/ViewModels/SQLiteReaderState.swift`), `state.snapshot` (Typ `ArticleReaderSnapshot?`, Felder `isStarred: Bool`, `isArchived: Bool`, `isRead: Bool`), `database` (Typ `FeedivoDatabase?`, aus `@Environment(\.feedivoDatabase)`)
- Produces: nichts, terminale UI-Änderung

- [ ] **Step 1: Neue Gruppe zwischen "Original öffnen" und "Exportieren" einfügen, alten Archivieren-Button entfernen**

In `Feedivo/Views/Reader/SQLiteReaderView.swift` den gesamten Block von "Original öffnen"-Button bis
zum bisherigen Archivieren-Button ersetzen (aktuell Zeilen 117–141):

```swift
                Button {
                    openOriginal()
                } label: {
                    Image(systemName: "safari")
                }
                .help(L10n.articleOpenOriginalCommand)
                .disabled(originalURL == nil)

                Button {
                    requestExportArticle()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .help(L10n.articleExportCommand)
                .disabled(state.snapshot == nil)

                Button {
                    if let database {
                        state.toggleArchived(database: database)
                    }
                } label: {
                    Image(systemName: state.snapshot?.isArchived == true ? "archivebox.fill" : "archivebox")
                }
                .help(L10n.articleArchiveCommand)
                .disabled(state.snapshot == nil)
```

durch:

```swift
                Button {
                    openOriginal()
                } label: {
                    Image(systemName: "safari")
                }
                .help(L10n.articleOpenOriginalCommand)
                .disabled(originalURL == nil)

                Divider()

                Button {
                    if let database {
                        state.toggleStarred(database: database)
                    }
                } label: {
                    Image(systemName: state.snapshot?.isStarred == true ? "star.fill" : "star")
                }
                .help(state.snapshot?.isStarred == true ? L10n.articleRowStarRemove : L10n.articleRowStarAdd)
                .disabled(state.snapshot == nil)

                Button {
                    if let database {
                        state.toggleArchived(database: database)
                    }
                } label: {
                    Image(systemName: state.snapshot?.isArchived == true ? "archivebox.fill" : "archivebox")
                }
                .help(state.snapshot?.isArchived == true ? L10n.articleUnarchiveCommand : L10n.articleArchiveCommand)
                .disabled(state.snapshot == nil)

                Button {
                    if let database {
                        state.toggleRead(database: database)
                    }
                } label: {
                    Image(systemName: state.snapshot?.isRead == true ? "circle" : "circle.fill")
                }
                .help(state.snapshot?.isRead == true ? L10n.articleRowMarkUnread : L10n.articleRowMarkRead)
                .disabled(state.snapshot == nil)

                Divider()

                Button {
                    requestExportArticle()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .help(L10n.articleExportCommand)
                .disabled(state.snapshot == nil)
```

Hinweis zum Ungelesen-Icon: `circle.fill` zeigt den Zustand "ungelesen" an (gefüllter Punkt, wie der
Sidebar-Badge), `circle` den Zustand "gelesen" — also invers zu Stern/Archiv, wo "gefüllt" = "aktiv"
bedeutet. Das ist beabsichtigt, weil der gefüllte Punkt in der gesamten App bereits "ungelesen"
bedeutet (vgl. `ArticleFilterOption`).

- [ ] **Step 2: Bauen**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -configuration Debug -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Manuell im Reader verifizieren**

App starten, einen Artikel öffnen und prüfen:
- Die drei Buttons (Stern, Archivieren, Ungelesen) erscheinen zwischen "Original öffnen" und
  "Exportieren", mit Trennstrichen davor/danach.
- Klick auf Stern togglet `star`/`star.fill` und der Artikel erscheint/verschwindet im
  Stern-Smart-Filter.
- Klick auf Archivieren togglet `archivebox`/`archivebox.fill` wie zuvor.
- Klick auf Ungelesen togglet `circle.fill`/`circle` und der Ungelesen-Zähler in der Sidebar
  ändert sich entsprechend.
- Alle drei sind deaktiviert, wenn kein Artikel geladen ist (z. B. direkt nach Datenbank-Fehler).

- [ ] **Step 4: Commit**

```bash
git add Feedivo/Views/Reader/SQLiteReaderView.swift
git commit -m "Reader-Toolbar: Stern/Archivieren/Ungelesen als Gruppe zusammenfassen"
```

---

## Self-Review

**Spec coverage:** Die Spec fordert genau eine zusammenhängende Gruppe aus Stern, Archivieren,
Ungelesen anstelle des einzelnen Archivieren-Buttons, mit Trennstrich, an der Position nach
"Original öffnen"/vor "Exportieren", unter Wiederverwendung bestehender Methoden und L10n-Keys.
Task 1 deckt das vollständig ab — es gibt keine weiteren Anforderungen in der Spec.

**Placeholder-Scan:** Keine TBD/TODO, vollständiger Code in jedem Schritt.

**Typ-Konsistenz:** `state.toggleStarred(database:)`, `state.toggleArchived(database:)`,
`state.toggleRead(database:)` entsprechen den tatsächlichen Signaturen in
`Feedivo/ViewModels/SQLiteReaderState.swift`. `ArticleReaderSnapshot.isStarred/isArchived/isRead`
sind `Bool`-Felder, passend zur Verwendung.
