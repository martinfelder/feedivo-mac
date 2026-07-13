# Tags direkt im Reader-Header hinzufügen — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ein "+"-Button neben Ordner-/Tag-Chips im Reader-Header öffnet ein Popover, in dem
Tags per Klick zugewiesen/entfernt oder neu erstellt werden können — mit denselben Optionen
wie im bestehenden Metadaten-Inspector.

**Architecture:** Die Tag-Zuweisungs-/Erstellungslogik aus `ArticleMetadataInspectorView`
wird in einen neuen, eigenständigen View-Baustein `ArticleTagAssignmentView` extrahiert. Der
Inspector nutzt ihn künftig selbst (reiner Refactor), und `SQLiteReaderView` bettet ihn
zusätzlich in ein neues Popover ein, das über einen "+"-Button am Ende der Chip-Zeile
erreichbar ist. Beide Aufrufer synchronisieren sich automatisch über den bereits bestehenden
`SidebarBadgeInvalidation.directTagVersionKey`-Zähler.

**Tech Stack:** SwiftUI (macOS 14+), GRDB/SQLite (`TagStore`), `@State`/`@AppStorage`-basiertes
State-Handling (Projekt-Konvention).

## Global Constraints

- Kommentare im Code auf Deutsch (Projekt-Konvention laut CLAUDE.md).
- Kein SwiftData — GRDB/SQLite ist die alleinige Persistenz (ADR-007).
- Verlässliche Verifikation ausschließlich über einen echten `xcodebuild build`-Lauf, NICHT
  über SourceKit/IDE-Diagnosen (bekannter Gotcha: diese sind oft veraltet/falsch-positiv).
- Für `ArticleMetadataInspectorView`/`SQLiteReaderView` existieren projektweit keine
  dedizierten View-Unit-Tests (SwiftUI-Views werden hier konventionell nicht per
  ViewInspector o. Ä. getestet) — Verifikation je Task erfolgt daher über Build-Erfolg plus
  eine präzise beschriebene manuelle Prüfung, nicht über automatisierte Tests. Die
  zugrunde liegende `TagStore`-Datenschicht bleibt unverändert und ist bereits über
  `SQLiteTagStoreTests.swift` abgedeckt.
- Neuer Tooltip-Text nutzt den bereits vorhandenen, vollständig übersetzten L10n-Key
  `L10n.articleAssignTagCommand` ("Tag zuweisen" / "Assign tag") statt eines neuen Keys —
  spart eine unnötige Dopplung eines fast identischen Strings.
- Build-Befehl für alle Verifikations-Schritte:
  `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo build`

---

### Task 1: Neuer Baustein `ArticleTagAssignmentView`

**Files:**
- Create: `Feedivo/Views/Reader/ArticleTagAssignmentView.swift`
- Modify: `Feedivo/Views/Reader/ArticleMetadataInspectorView.swift:754` (Sichtbarkeit der
  `sqliteInspectorControl()`/`sqliteInspectorPanel()`-Modifier von file-private auf
  modul-intern anheben, damit die neue Datei sie mitnutzen kann)

**Interfaces:**
- Produces: `struct ArticleTagAssignmentView: View` mit
  `init(articleID: String, snapshotTags: [ReaderArticleTagMetadata])` — wird von Task 2
  (`ArticleMetadataInspectorView`) und Task 3 (`SQLiteReaderView`) instanziiert.
- Consumes: `TagStore` (`Feedivo/Stores/TagStore.swift`, unverändert), `TagRecord`
  (`Feedivo/Database/Records/TagRecord.swift`, unverändert), `ReaderArticleTagMetadata`
  (`Feedivo/Snapshots/ArticleReaderSnapshot.swift`, unverändert), `TagColorPalette`,
  `ColorSwatchPicker`, `FlowLayout`, `SidebarStyle`, `ArticleInspectorTypography`,
  `SidebarBadgeInvalidation` (alle unverändert), sowie
  `.sqliteInspectorControl()`/`.sqliteInspectorPanel()` aus
  `ArticleMetadataInspectorView.swift` (Sichtbarkeit wird in diesem Task angehoben).

- [ ] **Step 1: Sichtbarkeit der Inspector-Style-Modifier anheben**

In `Feedivo/Views/Reader/ArticleMetadataInspectorView.swift:754` steht aktuell:

```swift
private extension View {
    func sqliteInspectorControl(cornerRadius: CGFloat = 8) -> some View {
```

Ändere die Zeile zu (nur das `private`-Schlüsselwort entfernen, Rest der Datei unverändert):

```swift
extension View {
    func sqliteInspectorControl(cornerRadius: CGFloat = 8) -> some View {
```

- [ ] **Step 2: Neue Datei `ArticleTagAssignmentView.swift` anlegen**

Erstelle `Feedivo/Views/Reader/ArticleTagAssignmentView.swift` mit exakt folgendem Inhalt
(1:1 verschobene Logik aus `ArticleMetadataInspectorView.swift`, `currentSnapshot.id` →
`articleID`-Parameter, `currentSnapshot.tags` → `snapshotTags`-Parameter,
`reloadInspectorData()`-Aufrufe entfallen, da inspector-spezifisch — stattdessen
`.onChange(of: directTagVersion)` als Ersatz-Synchronisation, da diese View jetzt
eigenständig auch außerhalb des Inspectors lebt):

```swift
import SwiftUI

/// Wiederverwendbarer Tag-Zuweisungs-/Erstellungs-Baustein für einen einzelnen Artikel.
/// Kapselt die TagStore-Zugriffslogik, die zuvor nur in ArticleMetadataInspectorView lag.
/// Genutzt sowohl vom Metadaten-Inspector (eingebettete Sektion) als auch vom
/// "+"-Button-Popover im Reader-Header (SQLiteReaderView) — beide Aufrufer synchronisieren
/// sich automatisch über SidebarBadgeInvalidation.directTagVersionKey.
struct ArticleTagAssignmentView: View {
    @Environment(\.feedivoDatabase) private var database
    @Environment(\.interfaceTextSize) private var interfaceTextSize

    let articleID: String
    let snapshotTags: [ReaderArticleTagMetadata]

    @State private var assignedTags: [TagRecord] = []
    @State private var availableTags: [TagRecord] = []
    @State private var newTagName = ""
    @State private var newTagColorHex = TagColorPalette.defaultColorHex

    @AppStorage(SidebarBadgeInvalidation.directTagVersionKey)
    private var directTagVersion = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if assignedTags.isEmpty && availableTags.isEmpty {
                Text(L10n.readerInspectorNoTags)
                    .font(interfaceTextSize.font(size: ArticleInspectorTypography.primaryValueFontSize))
                    .foregroundStyle(SidebarStyle.secondaryText)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(assignedTags) { tag in
                        tagTogglePill(tag, isActive: true)
                    }

                    ForEach(availableTags) { tag in
                        tagTogglePill(tag, isActive: false)
                    }
                }
            }

            tagCreator
        }
        .task(id: articleID) {
            loadTags()
        }
        .onChange(of: directTagVersion) { _, _ in
            loadTags()
        }
    }

    private var tagCreator: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(L10n.readerInspectorNewTag)

            HStack(spacing: 6) {
                TextField(L10n.readerInspectorAddTagPlaceholder, text: $newTagName)
                    .textFieldStyle(.plain)
                    .font(interfaceTextSize.font(size: ArticleInspectorTypography.controlFontSize))
                    .padding(.horizontal, 9)
                    .frame(height: interfaceTextSize.scaled(30))
                    .sqliteInspectorControl()
                    .onSubmit(addTag)

                Button {
                    addTag()
                } label: {
                    Image(systemName: "plus")
                        .font(interfaceTextSize.font(size: ArticleInspectorTypography.iconFontSize, weight: .semibold))
                }
                .disabled(normalizedTagName(newTagName) == nil)
                .buttonStyle(.plain)
                .frame(width: interfaceTextSize.scaled(32), height: interfaceTextSize.scaled(30))
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(SidebarStyle.separator, lineWidth: 1)
                }
                .foregroundStyle(
                    normalizedTagName(newTagName) == nil
                    ? SidebarStyle.secondaryText
                    : SidebarStyle.primaryText
                )
            }

            ColorSwatchPicker(selection: $newTagColorHex)
        }
        .padding(.top, 10)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(SidebarStyle.separator)
                .frame(height: 1)
        }
        .padding(.top, 4)
    }

    private func sectionLabel(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(interfaceTextSize.font(size: ArticleInspectorTypography.labelFontSize, weight: .bold))
            .foregroundStyle(SidebarStyle.sectionText)
    }

    private func tagTogglePill(_ tag: TagRecord, isActive: Bool) -> some View {
        let tagColor = TagColorPalette.color(for: tag.colorHex)

        return Button {
            toggleTag(tag, isActive: isActive)
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(tagColor)
                    .frame(width: 7, height: 7)

                Text(tag.name)
                    .lineLimit(1)
            }
            .font(interfaceTextSize.font(size: ArticleInspectorTypography.chipFontSize, weight: .semibold))
            .foregroundStyle(isActive ? SidebarStyle.primaryText : SidebarStyle.secondaryText)
            .padding(.horizontal, 8)
            .frame(minHeight: interfaceTextSize.scaled(26))
            .background(isActive ? tagColor.opacity(0.12) : Color(nsColor: .textBackgroundColor), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(isActive ? tagColor.opacity(0.42) : SidebarStyle.separator, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func loadTags() {
        guard let database else {
            assignedTags = snapshotTags.map { TagRecord(id: $0.id, name: $0.name, colorHex: $0.colorHex) }
            availableTags = []
            return
        }

        do {
            let allTags = try TagStore(database: database).tags()
            let directlyAssignedTags = try TagStore(database: database).tags(articleID: articleID)
            assignedTags = mergedAssignedTags(directTags: directlyAssignedTags)
            availableTags = allTags.filter { tag in
                !assignedTags.contains { $0.id == tag.id }
            }
        } catch {
            assignedTags = snapshotTags.map { TagRecord(id: $0.id, name: $0.name, colorHex: $0.colorHex) }
            availableTags = []
        }
    }

    private func mergedAssignedTags(directTags: [TagRecord]) -> [TagRecord] {
        var recordsByID: [String: TagRecord] = [:]
        for tag in snapshotTags {
            recordsByID[tag.id] = TagRecord(id: tag.id, name: tag.name, colorHex: tag.colorHex)
        }
        for tag in directTags {
            recordsByID[tag.id] = tag
        }

        return recordsByID.values.sorted {
            let nameOrder = $0.name.localizedCaseInsensitiveCompare($1.name)
            if nameOrder != .orderedSame {
                return nameOrder == .orderedAscending
            }

            return $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending
        }
    }

    private func toggleTag(_ tag: TagRecord, isActive: Bool) {
        guard let database else {
            return
        }

        do {
            if isActive {
                try TagStore(database: database).removeTag(tagID: tag.id, fromArticleID: articleID)
            } else {
                try TagStore(database: database).assignTag(tagID: tag.id, toArticleID: articleID, at: Date())
            }
            SidebarBadgeInvalidation.bumpDirectTagVersion()
            loadTags()
        } catch {
            return
        }
    }

    private func addTag() {
        guard let database,
              let normalizedName = normalizedTagName(newTagName) else {
            return
        }

        do {
            let existingTag = try TagStore(database: database).tags().first {
                $0.name.caseInsensitiveCompare(normalizedName) == .orderedSame
            }
            let tag = existingTag ?? TagRecord(name: normalizedName, colorHex: newTagColorHex)
            if existingTag == nil {
                try TagStore(database: database).save(tag)
            }
            try TagStore(database: database).assignTag(tagID: tag.id, toArticleID: articleID, at: Date())
            SidebarBadgeInvalidation.bumpDirectTagVersion()
            newTagName = ""
            loadTags()
        } catch {
            return
        }
    }

    private func normalizedTagName(_ name: String?) -> String? {
        guard let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmedName.isEmpty else {
            return nil
        }

        return trimmedName
    }
}
```

- [ ] **Step 3: Build verifizieren**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo build`
Expected: `** BUILD SUCCEEDED **`. `ArticleTagAssignmentView` wird an dieser Stelle noch von
niemandem aufgerufen — das ist erwartet und kein Fehler (Zwischenzustand, wird in Task 2 und
Task 3 verdrahtet).

- [ ] **Step 4: Commit**

```bash
git add Feedivo/Views/Reader/ArticleTagAssignmentView.swift Feedivo/Views/Reader/ArticleMetadataInspectorView.swift
git commit -m "Refactor: ArticleTagAssignmentView als wiederverwendbaren Tag-Baustein extrahieren"
```

---

### Task 2: `ArticleMetadataInspectorView` auf den neuen Baustein umstellen

**Files:**
- Modify: `Feedivo/Views/Reader/ArticleMetadataInspectorView.swift`

**Interfaces:**
- Consumes: `ArticleTagAssignmentView(articleID: String, snapshotTags: [ReaderArticleTagMetadata])`
  aus Task 1.
- Produces: keine neuen Interfaces — reiner interner Refactor, Verhalten für den Nutzer
  bleibt identisch.

- [ ] **Step 1: Tote `@State`-Properties entfernen**

In `Feedivo/Views/Reader/ArticleMetadataInspectorView.swift:22-28` steht aktuell:

```swift
    @State private var currentSnapshot: ArticleReaderSnapshot
    @State private var assignedTags: [TagRecord] = []
    @State private var availableTags: [TagRecord] = []
    @State private var folderNames: [String] = []
    @State private var newTagName = ""
    @State private var newTagColorHex = TagColorPalette.defaultColorHex
    @State private var newFolderName = ""
```

Ändere zu:

```swift
    @State private var currentSnapshot: ArticleReaderSnapshot
    @State private var folderNames: [String] = []
    @State private var newFolderName = ""
```

- [ ] **Step 2: `loadTags()`-Aufrufe aus `body` entfernen**

Aktuell (Zeilen 58–66):

```swift
        .task {
            reloadInspectorData()
            loadTags()
        }
        .onChange(of: snapshot) { _, newSnapshot in
            currentSnapshot = newSnapshot
            reloadInspectorData()
            loadTags()
        }
```

Ändere zu:

```swift
        .task {
            reloadInspectorData()
        }
        .onChange(of: snapshot) { _, newSnapshot in
            currentSnapshot = newSnapshot
            reloadInspectorData()
        }
```

- [ ] **Step 3: `tagSection` auf den neuen Baustein umstellen**

Aktuell (Zeilen 270–338, `tagSection` und `tagCreator`):

```swift
    private var tagSection: some View {
        inspectorSection(
            L10n.readerInspectorTags,
            isExpanded: $isTagSectionExpanded
        ) {
            if assignedTags.isEmpty && availableTags.isEmpty {
                Text(L10n.readerInspectorNoTags)
                    .font(interfaceTextSize.font(size: ArticleInspectorTypography.primaryValueFontSize))
                    .foregroundStyle(SidebarStyle.secondaryText)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(assignedTags) { tag in
                        tagTogglePill(tag, isActive: true)
                    }

                    ForEach(availableTags) { tag in
                        tagTogglePill(tag, isActive: false)
                    }
                }
            }

            tagCreator
        }
    }

    private var tagCreator: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(L10n.readerInspectorNewTag)

            HStack(spacing: 6) {
                TextField(L10n.readerInspectorAddTagPlaceholder, text: $newTagName)
                    .textFieldStyle(.plain)
                    .font(interfaceTextSize.font(size: ArticleInspectorTypography.controlFontSize))
                    .padding(.horizontal, 9)
                    .frame(height: interfaceTextSize.scaled(30))
                    .sqliteInspectorControl()
                    .onSubmit(addTag)

                Button {
                    addTag()
                } label: {
                    Image(systemName: "plus")
                        .font(interfaceTextSize.font(size: ArticleInspectorTypography.iconFontSize, weight: .semibold))
                }
                .disabled(normalizedTagName(newTagName) == nil)
                .buttonStyle(.plain)
                .frame(width: interfaceTextSize.scaled(32), height: interfaceTextSize.scaled(30))
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(SidebarStyle.separator, lineWidth: 1)
                }
                .foregroundStyle(
                    normalizedTagName(newTagName) == nil
                    ? SidebarStyle.secondaryText
                    : SidebarStyle.primaryText
                )
            }

            ColorSwatchPicker(selection: $newTagColorHex)
        }
        .padding(.top, 10)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(SidebarStyle.separator)
                .frame(height: 1)
        }
        .padding(.top, 4)
    }
```

Ersetze BEIDE (den kompletten Block von `private var tagSection` bis zum Ende von
`tagCreator`) durch:

```swift
    private var tagSection: some View {
        inspectorSection(
            L10n.readerInspectorTags,
            isExpanded: $isTagSectionExpanded
        ) {
            ArticleTagAssignmentView(articleID: currentSnapshot.id, snapshotTags: currentSnapshot.tags)
        }
    }
```

- [ ] **Step 4: Tote Tag-Methoden entfernen**

Entferne aus `Feedivo/Views/Reader/ArticleMetadataInspectorView.swift` die folgenden, jetzt
ungenutzten Methoden vollständig (Inhalt ist 1:1 nach `ArticleTagAssignmentView.swift`
umgezogen):

- `tagTogglePill(_:isActive:)` (aktuell Zeilen 530–555)
- `loadTags()` (aktuell Zeilen 585–603)
- `mergedAssignedTags(directTags:)` (aktuell Zeilen 605–622)
- `toggleTag(_:isActive:)` (aktuell Zeilen 683–700)
- `addTag()` (aktuell Zeilen 702–724)
- `normalizedTagName(_:)` (aktuell Zeilen 744–751)

- [ ] **Step 5: `reloadInspectorData()` von Tag-Logik befreien**

Aktuell:

```swift
    private func reloadInspectorData() {
        guard let database else {
            assignedTags = currentSnapshot.tags.map { TagRecord(id: $0.id, name: $0.name, colorHex: $0.colorHex) }
            availableTags = []
            folderNames = []
            return
        }

        do {
            if let reloadedSnapshot = try ArticleStore(database: database).readerArticle(id: currentSnapshot.id) {
                currentSnapshot = reloadedSnapshot
            }

            loadTags()

            let feedFolderStore = FeedFolderStore(database: database)
            let feeds = try FeedStore(database: database).feeds()
            let explicitFolders = try feedFolderStore.folders()
            folderNames = FeedFolderOrganizer.folderNames(
                feedFolderNames: feeds.map(\.folderName),
                explicitFolderNames: explicitFolders.map(\.name)
            )
        } catch {
            assignedTags = currentSnapshot.tags.map { TagRecord(id: $0.id, name: $0.name, colorHex: $0.colorHex) }
            availableTags = []
        }
    }
```

Ändere zu:

```swift
    private func reloadInspectorData() {
        guard let database else {
            folderNames = []
            return
        }

        do {
            if let reloadedSnapshot = try ArticleStore(database: database).readerArticle(id: currentSnapshot.id) {
                currentSnapshot = reloadedSnapshot
            }

            let feedFolderStore = FeedFolderStore(database: database)
            let feeds = try FeedStore(database: database).feeds()
            let explicitFolders = try feedFolderStore.folders()
            folderNames = FeedFolderOrganizer.folderNames(
                feedFolderNames: feeds.map(\.folderName),
                explicitFolderNames: explicitFolders.map(\.name)
            )
        } catch {
            return
        }
    }
```

- [ ] **Step 6: Build verifizieren**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Manuell prüfen (Metadaten-Inspector)**

App starten, einen Artikel öffnen, Metadaten-Inspector öffnen (Toolbar-Icon), Tags-Sektion
aufklappen. Erwartung: identisches Verhalten wie vor dem Refactor — bestehende Tags per Klick
togglebar, neuer Tag per Namensfeld + Farbe + "+"-Button erstellbar und sofort zugewiesen.

- [ ] **Step 8: Commit**

```bash
git add Feedivo/Views/Reader/ArticleMetadataInspectorView.swift
git commit -m "Refactor: ArticleMetadataInspectorView nutzt ArticleTagAssignmentView"
```

---

### Task 3: "+"-Button und Popover im Reader-Header

**Files:**
- Modify: `Feedivo/Views/Reader/SQLiteReaderView.swift`

**Interfaces:**
- Consumes: `ArticleTagAssignmentView(articleID: String, snapshotTags: [ReaderArticleTagMetadata])`
  aus Task 1, `L10n.articleAssignTagCommand: String` (bereits vorhanden in
  `Feedivo/Resources/L10n.swift:506`).
- Produces: keine neuen Interfaces — UI-Endpunkt dieses Features.

- [ ] **Step 1: Neuen Popover-State hinzufügen**

In `Feedivo/Views/Reader/SQLiteReaderView.swift:17-19` steht aktuell:

```swift
    @State private var state = SQLiteReaderState()
    @State private var isAppearancePopoverPresented = false
    @State private var isMetadataInspectorPresented = false
```

Ändere zu:

```swift
    @State private var state = SQLiteReaderState()
    @State private var isAppearancePopoverPresented = false
    @State private var isMetadataInspectorPresented = false
    @State private var isTagAssignmentPopoverPresented = false
```

- [ ] **Step 2: Chip-Zeile immer rendern und "+"-Button ergänzen**

Aktuell (Zeilen 471–525, `readerArticleMetadata`, `readerMetadataChipHeight`,
`readerFolderChip`, `readerTagChip`):

```swift
    @ViewBuilder
    private func readerArticleMetadata(_ snapshot: ArticleReaderSnapshot) -> some View {
        let folderName = FeedFolderOrganizer.normalizedFolderName(snapshot.folderName)
        if folderName != nil || !snapshot.tags.isEmpty {
            FlowLayout(spacing: 8) {
                if let folderName {
                    readerFolderChip(folderName)
                }

                ForEach(snapshot.tags) { tag in
                    readerTagChip(tag)
                }
            }
            .padding(.top, 2)
        }
    }

    private var readerMetadataChipHeight: CGFloat {
        interfaceTextSize.scaled(26)
    }

    private func readerFolderChip(_ folderName: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .font(.caption2)

            Text(folderName)
                .lineLimit(1)
        }
        .font(interfaceTextSize.font(size: 12, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: readerMetadataChipHeight)
        .background(.secondary.opacity(0.08), in: Capsule())
        .overlay {
            Capsule()
                .stroke(.secondary.opacity(0.16), lineWidth: 1)
        }
    }

    private func readerTagChip(_ tag: ReaderArticleTagMetadata) -> some View {
        let tagColor = TagColorPalette.color(for: tag.colorHex)

        return Text("#\(tag.name)")
            .lineLimit(1)
            .font(interfaceTextSize.font(size: 12, weight: .semibold))
            .foregroundStyle(tagColor)
            .padding(.horizontal, 10)
            .frame(height: readerMetadataChipHeight)
            .background(tagColor.opacity(0.1), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(tagColor.opacity(0.24), lineWidth: 1)
            }
    }
```

Ändere zu (die `if folderName != nil || !snapshot.tags.isEmpty`-Bedingung entfällt bewusst —
die Zeile enthält künftig immer mindestens den "+"-Button, damit auch der erste Tag eines
Artikels ohne bisherige Chips direkt im Header angelegt werden kann; neue Funktion
`readerAddTagButton` am Ende ergänzt):

```swift
    private func readerArticleMetadata(_ snapshot: ArticleReaderSnapshot) -> some View {
        let folderName = FeedFolderOrganizer.normalizedFolderName(snapshot.folderName)
        return FlowLayout(spacing: 8) {
            if let folderName {
                readerFolderChip(folderName)
            }

            ForEach(snapshot.tags) { tag in
                readerTagChip(tag)
            }

            readerAddTagButton(snapshot)
        }
        .padding(.top, 2)
    }

    private var readerMetadataChipHeight: CGFloat {
        interfaceTextSize.scaled(26)
    }

    private func readerFolderChip(_ folderName: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .font(.caption2)

            Text(folderName)
                .lineLimit(1)
        }
        .font(interfaceTextSize.font(size: 12, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: readerMetadataChipHeight)
        .background(.secondary.opacity(0.08), in: Capsule())
        .overlay {
            Capsule()
                .stroke(.secondary.opacity(0.16), lineWidth: 1)
        }
    }

    private func readerTagChip(_ tag: ReaderArticleTagMetadata) -> some View {
        let tagColor = TagColorPalette.color(for: tag.colorHex)

        return Text("#\(tag.name)")
            .lineLimit(1)
            .font(interfaceTextSize.font(size: 12, weight: .semibold))
            .foregroundStyle(tagColor)
            .padding(.horizontal, 10)
            .frame(height: readerMetadataChipHeight)
            .background(tagColor.opacity(0.1), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(tagColor.opacity(0.24), lineWidth: 1)
            }
    }

    private func readerAddTagButton(_ snapshot: ArticleReaderSnapshot) -> some View {
        Button {
            isTagAssignmentPopoverPresented.toggle()
        } label: {
            Image(systemName: "plus")
                .font(interfaceTextSize.font(size: 12, weight: .semibold))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .frame(width: readerMetadataChipHeight, height: readerMetadataChipHeight)
        .background(.secondary.opacity(0.08), in: Circle())
        .overlay {
            Circle()
                .stroke(.secondary.opacity(0.16), lineWidth: 1)
        }
        .help(L10n.articleAssignTagCommand)
        .popover(isPresented: $isTagAssignmentPopoverPresented) {
            ArticleTagAssignmentView(articleID: snapshot.id, snapshotTags: snapshot.tags)
                .padding(12)
                .frame(minWidth: 260, idealWidth: 280, maxWidth: 320)
        }
    }
```

Hinweis: `readerArticleMetadata` war zuvor mit `@ViewBuilder` annotiert (nötig für die
bedingte `if`-Verzweigung). Da die Funktion jetzt immer genau einen `FlowLayout`-Wert
zurückgibt, wird `@ViewBuilder` entfernt und stattdessen ein normales `return` verwendet —
beides sind gültige, äquivalente Schreibweisen für eine Funktion mit `some View`-Rückgabetyp
ohne Verzweigung.

- [ ] **Step 3: Build verifizieren**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Manuell prüfen (Reader-Header)**

App starten, einen Artikel **ohne** bisherige Tags/Ordner öffnen. Erwartung: Unter dem Titel
erscheint jetzt eine schmale Zeile mit nur dem "+"-Button (vorher: keine Zeile). Klick auf
"+" öffnet ein Popover mit "Keine Tags vorhanden" (falls global noch keine Tags existieren)
sowie dem Namens-/Farb-Formular. Neuen Tag erstellen → Popover bleibt offen, der neue Tag
erscheint sofort als Chip in der Header-Zeile. Bei einem Artikel mit bereits vorhandenen
Tags: "+" erscheint als letztes Element nach den Tag-Chips, bestehende Tags lassen sich per
Klick im Popover togglen (an/aus), ohne dass sich das Popover schließt. Zusätzlich: bei
gleichzeitig geöffnetem Metadaten-Inspector bleiben beide Ansichten synchron. Im
Artikel-Popout-Fenster (Doppelklick/Kontextmenü "In neuem Fenster öffnen") erscheint derselbe
"+"-Button, da `ArticleWindowView` `SQLiteReaderView` intern wiederverwendet.

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Views/Reader/SQLiteReaderView.swift
git commit -m "Feature: Tags direkt im Reader-Header hinzufügen (+ Button, Popover)"
```
