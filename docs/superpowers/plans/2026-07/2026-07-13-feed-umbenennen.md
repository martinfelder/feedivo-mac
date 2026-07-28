# Feeds in der Sidebar umbenennen — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Feeds in der linken Sidebar von Feedivo lassen sich per Doppelklick auf den Namen inline umbenennen, genau wie zuvor bei Ordnern.

**Architecture:** `FeedStoreError` bekommt `LocalizedError`-Konformität, damit Fehler beim Umbenennen (leerer Name, DB nicht verfügbar) freundliche deutsche Texte liefern — das behebt nebenbei denselben Bug im bereits bestehenden `FeedRenameView`-Dialog. `FeedRowView` verliert den umschließenden `Button` (der sonst Klicks ins Inline-Textfeld während der Bearbeitung abfangen würde) und übernimmt Auswahl (Einzelklick) sowie Bearbeitungsstart (Doppelklick) selbst — strukturell identisch zum bereits umgesetzten `SidebarFolderSection`-Muster.

**Tech Stack:** Swift 5.9+, SwiftUI (macOS 14+), GRDB/SQLite, Swift Testing (`@Test`/`#expect`).

## Global Constraints

- Kommentare im Code auf Deutsch (Projektkonvention laut CLAUDE.md).
- Kein SwiftData — GRDB/SQLite ist die alleinige Persistenzschicht (ADR-007).
- Mindest-macOS 14.0 Sonoma — `@FocusState`, `onExitCommand`, zweiparametriges `.onChange(of:)` sind alle ab macOS 14 verfügbar.
- Nach jeder Store-Mutation muss `SQLiteDataInvalidation.bumpStatusVersion()` aufgerufen werden.
- Kein zusätzlicher Kontextmenü-Eintrag für die Inline-Bearbeitung — der bestehende „Feed umbenennen…"-Eintrag bleibt unverändert und öffnet weiterhin `FeedRenameView`.
- Keine Namens-Kollisionsprüfung für Feeds (anders als bei Ordnern) — nur Leer-Namen-Validierung.
- Nie ohne explizite Nutzerbestätigung nach `origin/main` pushen.

---

### Task 1: `FeedStoreError` bekommt `LocalizedError`-Konformität (TDD)

**Files:**
- Modify: `Feedivo/Stores/FeedStore.swift`
- Modify: `FeedivoTests/SQLiteAdminStoreTests.swift`

**Interfaces:**
- Consumes: `FeedStore.renameFeed(id:displayTitle:) throws` (bereits vorhanden, `Feedivo/Stores/FeedStore.swift:46`), `L10n.feedRenameEmptyName`/`L10n.feedRenameDatabaseUnavailable` (bereits vorhanden), `FeedivoDatabase.inMemoryForTests()` (bereits vorhanden).
- Produces: `enum FeedStoreError: Error, Equatable, LocalizedError` mit Fällen `.emptyTitle`, `.missingFeed`, `.databaseUnavailable` — `.databaseUnavailable` wird in Task 2 von `SidebarView.swift` konsumiert.

- [ ] **Step 1: Schreibe die fehlschlagenden Tests**

Öffne `FeedivoTests/SQLiteAdminStoreTests.swift` und füge am Ende der bestehenden `struct SQLiteAdminStoreTests { ... }` (vor der letzten schließenden `}` der Struct) diese zwei Tests ein:

```swift
    @Test func renameFeedRejectsEmptyTitle() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = FeedStore(database: database)
        try store.save(
            FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example")
        )

        #expect(throws: FeedStoreError.emptyTitle) {
            try store.renameFeed(id: "feed-1", displayTitle: "   ")
        }

        #expect(try store.feed(id: "feed-1")?.title == "Example")
    }

    @Test func feedStoreErrorEmptyTitleHatFreundlicheFehlermeldung() throws {
        #expect(FeedStoreError.emptyTitle.errorDescription == L10n.feedRenameEmptyName)
    }
```

- [ ] **Step 2: Führe die Tests aus und bestätige, dass sie fehlschlagen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteAdminStoreTests`

Expected: FAIL — `feedStoreErrorEmptyTitleHatFreundlicheFehlermeldung` schlägt fehl, weil `FeedStoreError.emptyTitle.errorDescription` aktuell `nil` liefert (keine `LocalizedError`-Konformität). `renameFeedRejectsEmptyTitle` sollte bereits bestehen (der Store wirft `.emptyTitle` schon heute), stelle aber sicher, dass beide Tests kompilieren und laufen.

- [ ] **Step 3: Ergänze `LocalizedError`-Konformität in `FeedStore.swift`**

Öffne `Feedivo/Stores/FeedStore.swift`, finde die bestehende Definition (Zeile 352):

Alter Code (zu ersetzen):

```swift
enum FeedStoreError: Error, Equatable {
    case emptyTitle
    case missingFeed
}
```

Neuer Code:

```swift
// Fehler beim Umbenennen eines Feeds. `.databaseUnavailable` wird nicht von
// dieser Store-Methode selbst geworfen (die Datenbank ist hier bereits
// injiziert), sondern ausschließlich vom UI-seitigen Aufrufer
// (`SidebarView.renameFeed`), falls die `\.feedivoDatabase`-Environment fehlt.
// `.missingFeed` bleibt ohne eigenen Text — über die aktuellen Aufrufpfade
// nicht erreichbar und bislang nirgends speziell behandelt.
enum FeedStoreError: Error, Equatable, LocalizedError {
    case emptyTitle
    case missingFeed
    case databaseUnavailable

    var errorDescription: String? {
        switch self {
        case .emptyTitle: L10n.feedRenameEmptyName
        case .missingFeed: nil
        case .databaseUnavailable: L10n.feedRenameDatabaseUnavailable
        }
    }
}
```

- [ ] **Step 4: Führe die Tests aus und bestätige, dass sie bestehen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteAdminStoreTests`

Expected: PASS (alle Tests in `SQLiteAdminStoreTests`, inklusive der 2 neuen, grün)

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Stores/FeedStore.swift FeedivoTests/SQLiteAdminStoreTests.swift
git commit -m "$(cat <<'EOF'
Fix: FeedStoreError liefert freundliche deutsche Fehlermeldungen

LocalizedError-Konformität ergänzt (.emptyTitle -> vorhandener
feedRenameEmptyName-Key). Behebt nebenbei, dass der bestehende
FeedRenameView-Dialog bei leerem Namen bisher eine generische
Systemfehlermeldung zeigte. Neuer .databaseUnavailable-Fall als
Vorbereitung für Inline-Umbenennen in der Sidebar (folgender Task).
EOF
)"
```

---

### Task 2: `FeedRowView` Inline-Umbenennen + Wiring in `SidebarView`

**Files:**
- Modify: `Feedivo/Views/Sidebar/FeedRowView.swift`
- Modify: `Feedivo/Views/Sidebar/SidebarView.swift`

**Interfaces:**
- Consumes: `FeedStoreError.databaseUnavailable`/`.emptyTitle` aus Task 1; `FeedStore.renameFeed(id:displayTitle:) throws` (bereits vorhanden); `SQLiteDataInvalidation.bumpStatusVersion()` (bereits vorhanden); `SidebarStyle.activeSelection`/`.activeBorder`/`.primaryText`/`.secondaryText` (bereits vorhanden, siehe `SidebarRowButtonStyle` in `SidebarView.swift`); `L10n.feedErrorBadgeTooltip`, `SidebarUnreadCount.badgeText(for:)`, `CachedRemoteImageView` (alle bereits vorhanden).
- Produces: Keine neuen Interfaces für weitere Tasks — dies ist der letzte Task des Plans.

- [ ] **Step 1: `FeedRowView` um Inline-Umbenennen erweitern und den Button-Wrapper-Ersatz vorbereiten**

Ersetze den kompletten Inhalt von `Feedivo/Views/Sidebar/FeedRowView.swift`:

```swift
import SwiftUI

struct FeedRowView: View {
    @Environment(\.interfaceTextSize) private var interfaceTextSize
    @FocusState private var isNameFieldFocused: Bool

    @AppStorage(SidebarFeedVisibilitySettings.showsUnreadCountKey)
    private var showsUnreadCount = SidebarFeedVisibilitySettings.defaultShowsUnreadCount

    @AppStorage(SidebarFeedVisibilitySettings.showsFaviconsKey)
    private var showsFavicons = SidebarFeedVisibilitySettings.defaultShowsFavicons

    enum DisplayStyle {
        case regular
        case folderChild
    }

    let snapshot: FeedSidebarSnapshot
    var displayStyle: DisplayStyle = .regular
    let isSelected: Bool
    let select: () -> Void
    let renameFeed: (String) throws -> Void

    @State private var isEditingName = false
    @State private var editedName = ""
    @State private var renameErrorMessage: String?

    init(
        snapshot: FeedSidebarSnapshot,
        displayStyle: DisplayStyle = .regular,
        isSelected: Bool,
        select: @escaping () -> Void,
        renameFeed: @escaping (String) throws -> Void
    ) {
        self.snapshot = snapshot
        self.displayStyle = displayStyle
        self.isSelected = isSelected
        self.select = select
        self.renameFeed = renameFeed
    }

    // Die Zeile rendert ausschließlich aus dem SQLite-Snapshot. Ein
    // Als-gelesen-markieren invalidiert nur die Snapshot-Quelle
    // (SQLiteSidebarState) und wertet die Zeile neu aus.
    private var unreadCount: Int {
        snapshot.unreadCount
    }

    private var displayTitle: String {
        snapshot.title
    }

    private var displayFaviconURL: String? {
        snapshot.faviconURL
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: displayStyle.horizontalSpacing) {
                faviconView
                    .frame(
                        width: interfaceTextSize.scaled(displayStyle.iconSize),
                        height: interfaceTextSize.scaled(displayStyle.iconSize)
                    )

                if snapshot.hasRecentError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(interfaceTextSize.font(size: 11, weight: .semibold))
                        .foregroundStyle(.orange)
                        .help(L10n.feedErrorBadgeTooltip)
                        .accessibilityLabel(Text(L10n.feedErrorBadgeTooltip))
                }

                if isEditingName {
                    TextField(displayTitle, text: $editedName)
                        .textFieldStyle(.roundedBorder)
                        .font(interfaceTextSize.font(
                            size: displayStyle.titleSize,
                            weight: displayStyle.titleWeight
                        ))
                        .focused($isNameFieldFocused)
                        .overlay {
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(renameErrorMessage != nil ? Color.red : Color.clear, lineWidth: 1)
                        }
                        .onSubmit {
                            commitOrShowError()
                        }
                        .onExitCommand {
                            cancelEditing()
                        }
                        .onChange(of: isNameFieldFocused) { wasFocused, isFocused in
                            // Fokusverlust (z. B. Klick woanders hin) verhält sich wie
                            // Enter. Die Guard-Bedingung verhindert ein doppeltes
                            // Auslösen, wenn commitOrShowError()/cancelEditing() den
                            // Bearbeitungsmodus bereits beendet haben, bevor der Fokus
                            // tatsächlich wechselt.
                            if wasFocused, !isFocused, isEditingName {
                                commitOrShowError()
                            }
                        }
                } else {
                    Text(displayTitle)
                        .font(interfaceTextSize.font(
                            size: displayStyle.titleSize,
                            weight: displayStyle.titleWeight
                        ))
                        .foregroundStyle(isSelected ? SidebarStyle.primaryText : SidebarStyle.primaryText.opacity(0.82))
                        .lineLimit(1)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            beginEditing()
                        }
                        .onTapGesture(count: 1) {
                            select()
                        }
                }

                Spacer(minLength: 8)

                if showsUnreadCount, let badgeText = SidebarUnreadCount.badgeText(for: unreadCount) {
                    HStack(spacing: 3) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 8, weight: .semibold))
                        Text(badgeText)
                            .font(interfaceTextSize.font(size: 11, weight: .semibold))
                            .monospacedDigit()
                    }
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(SidebarStyle.activeSelection, in: Capsule())
                }
            }
            .padding(.horizontal, 10)
            .frame(height: interfaceTextSize.scaled(displayStyle.rowHeight))
            .padding(.leading, displayStyle.leadingIndent)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? SidebarStyle.activeSelection : Color.clear)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? SidebarStyle.activeBorder : Color.clear, lineWidth: 1)
                    }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .onTapGesture {
                // Fängt Klicks auf Favicon/Fehler-Icon/Badge/Leerraum ab, damit die
                // gesamte Zeile weiterhin wie zuvor klickbar bleibt. Während der
                // Bearbeitung (isEditingName) ist dieser Handler bewusst ein No-op,
                // damit ein Klick ins TextField (Fokussieren/Cursor positionieren)
                // nicht stattdessen die Auswahl auslöst.
                if !isEditingName {
                    select()
                }
            }

            if let renameErrorMessage {
                Text(renameErrorMessage)
                    .font(interfaceTextSize.font(size: 11))
                    .foregroundStyle(.red)
                    .padding(.leading, displayStyle.leadingIndent + 10)
            }
        }
    }

    private func beginEditing() {
        editedName = displayTitle
        renameErrorMessage = nil
        isEditingName = true
        isNameFieldFocused = true
    }

    private func cancelEditing() {
        editedName = displayTitle
        renameErrorMessage = nil
        isEditingName = false
    }

    private func commitOrShowError() {
        let trimmedName = editedName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmedName != displayTitle else {
            isEditingName = false
            renameErrorMessage = nil
            return
        }

        do {
            try renameFeed(trimmedName)
            isEditingName = false
            renameErrorMessage = nil
        } catch {
            renameErrorMessage = error.localizedDescription
        }
    }

    @ViewBuilder
    private var faviconView: some View {
        if showsFavicons,
           let faviconURL = displayFaviconURL,
           let url = URL(string: faviconURL) {
            CachedRemoteImageView(url: url) { image in
                image
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: displayStyle.iconCornerRadius))
            } placeholder: {
                fallbackIcon
            }
        } else {
            fallbackIcon
        }
    }

    private var fallbackIcon: some View {
        Image(systemName: "dot.radiowaves.left.and.right")
            .font(interfaceTextSize.font(size: displayStyle.fallbackIconSize))
            .foregroundStyle(.secondary)
    }
}

private extension FeedRowView.DisplayStyle {
    var horizontalSpacing: CGFloat {
        switch self {
        case .regular:
            8
        case .folderChild:
            8
        }
    }

    var iconSize: CGFloat {
        switch self {
        case .regular:
            16
        case .folderChild:
            16
        }
    }

    var fallbackIconSize: CGFloat {
        switch self {
        case .regular:
            13
        case .folderChild:
            13
        }
    }

    var iconCornerRadius: CGFloat {
        switch self {
        case .regular:
            3
        case .folderChild:
            3
        }
    }

    var titleSize: CGFloat {
        switch self {
        case .regular:
            12
        case .folderChild:
            12
        }
    }

    var titleWeight: Font.Weight {
        switch self {
        case .regular:
            .semibold
        case .folderChild:
            .medium
        }
    }

    var leadingIndent: CGFloat {
        switch self {
        case .regular:
            0
        case .folderChild:
            46
        }
    }

    var rowHeight: CGFloat {
        switch self {
        case .regular:
            30
        case .folderChild:
            28
        }
    }
}
```

Das ist eine vollständige Ersetzung der Datei — sie enthält alle bisherigen Werte aus `DisplayStyle` unverändert (`horizontalSpacing`, `iconSize`, `fallbackIconSize`, `iconCornerRadius`, `titleSize`, `titleWeight`) plus die zwei neuen (`leadingIndent`, `rowHeight`, mit denselben Werten, die bisher direkt am Aufrufort in `SidebarRowButtonStyle(leadingIndent:rowHeight:)` standen: `isIndented ? 46 : 0` und `isIndented ? 28 : 30`).

- [ ] **Step 2: Aufrufstelle in `SidebarView.feedRows(_:)` anpassen**

Ersetze in `Feedivo/Views/Sidebar/SidebarView.swift` die bestehende `feedRows(_:)`-Methode (aktuell Zeilen 380–420):

Alter Code (zu ersetzen):

```swift
    private func feedRows(_ snapshots: [FeedSidebarSnapshot], isIndented: Bool = false) -> some View {
        ForEach(snapshots) { snapshot in
            Button {
                selection = .feed(snapshot.id)
            } label: {
                FeedRowView(
                    snapshot: snapshot,
                    displayStyle: isIndented ? .folderChild : .regular
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(
                SidebarRowButtonStyle(
                    isSelected: selection == .feed(snapshot.id),
                    leadingIndent: isIndented ? 46 : 0,
                    rowHeight: isIndented ? 28 : 30
                )
            )
            .contextMenu {
                Button {
                    feedRenaming = snapshot
                } label: {
                    Label(L10n.feedRenameCommand, systemImage: "pencil")
                }

                Button {
                    feedShowingProperties = snapshot
                } label: {
                    Label(L10n.feedPropertiesCommand, systemImage: "info.circle")
                }

                Divider()

                Button(role: .destructive) {
                    onRequestDeleteFeed(snapshot.id)
                } label: {
                    Label(L10n.feedDeleteCommand, systemImage: "trash")
                }
            }
        }
    }
```

Neuer Code:

```swift
    private func feedRows(_ snapshots: [FeedSidebarSnapshot], isIndented: Bool = false) -> some View {
        ForEach(snapshots) { snapshot in
            FeedRowView(
                snapshot: snapshot,
                displayStyle: isIndented ? .folderChild : .regular,
                isSelected: selection == .feed(snapshot.id),
                select: { selection = .feed(snapshot.id) },
                renameFeed: { newName in
                    try renameFeed(id: snapshot.id, to: newName)
                }
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .contextMenu {
                Button {
                    feedRenaming = snapshot
                } label: {
                    Label(L10n.feedRenameCommand, systemImage: "pencil")
                }

                Button {
                    feedShowingProperties = snapshot
                } label: {
                    Label(L10n.feedPropertiesCommand, systemImage: "info.circle")
                }

                Divider()

                Button(role: .destructive) {
                    onRequestDeleteFeed(snapshot.id)
                } label: {
                    Label(L10n.feedDeleteCommand, systemImage: "trash")
                }
            }
        }
    }
```

Der `contextMenu`-Block bleibt inhaltlich unverändert (gleiche drei Einträge, gleiche Reihenfolge) — er hängt jetzt direkt an `FeedRowView(...)` statt an der entfernten `Button`-Hülle.

- [ ] **Step 3: Neue private Methode `renameFeed(id:to:)` in `SidebarView` ergänzen**

Füge in `Feedivo/Views/Sidebar/SidebarView.swift` direkt nach der bestehenden `renameFolder(from:to:)`-Methode (die im vorherigen Feature ergänzt wurde, direkt nach `deleteFeedFolder`) diese neue Methode ein:

```swift

    private func renameFeed(id: String, to newTitle: String) throws {
        guard let database = feedivoDatabase else {
            throw FeedStoreError.databaseUnavailable
        }

        try FeedStore(database: database).renameFeed(id: id, displayTitle: newTitle)
        SQLiteDataInvalidation.bumpStatusVersion()
    }
```

- [ ] **Step 4: Build ausführen und auf Erfolg prüfen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`

Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Manuelle Verifikation in der laufenden App**

Wie beim Ordner-Feature ist SwiftUI-Gesten-/Fokus-Verhalten in diesem Projekt nicht automatisiert getestet. Die App starten und folgende Punkte von Hand prüfen:

1. Einzelklick auf einen Feed-Namen (oberste Ebene, außerhalb eines Ordners) → Feed wird ausgewählt wie bisher, Artikelliste lädt.
2. Doppelklick auf denselben Feed-Namen → Name wird zu einem editierbaren, nativ aussehenden Textfeld (abgerundeter Rahmen).
3. Namen ändern, Enter drücken → neuer Name erscheint sofort in der Sidebar.
4. Erneut doppelklicken, Namen leeren, Enter drücken → roter Rahmen + Fehlertext "Der Name darf nicht leer sein.", Bearbeitungsmodus bleibt aktiv.
5. Escape drücken → Bearbeitung bricht ab, alter Name bleibt stehen.
6. Doppelklick, Namen ändern, dann irgendwo anders in der Sidebar klicken (Fokusverlust ohne Enter) → Änderung wird übernommen wie bei Enter.
7. Rechtsklick auf einen Feed → Kontextmenü zeigt weiterhin "Feed umbenennen…", "Feed-Eigenschaften", "Löschen" wie bisher; Klick auf "Feed umbenennen…" öffnet weiterhin den vollen Dialog mit Original-Titel-Anzeige und "Ursprung wiederherstellen"-Button (unverändert).
8. Denselben Ablauf (1–6) für einen Feed **innerhalb eines Ordners** wiederholen (eingerückte Darstellung, `displayStyle: .folderChild`) — Einrückung und Zeilenhöhe müssen optisch identisch zum Zustand vor dieser Änderung bleiben.
9. Einen Feed auswählen (Klick), dann einen anderen Feed anklicken → Auswahl-Hervorhebung (Hintergrund/Rahmen) wechselt sichtbar zum neu ausgewählten Feed, exakt wie vor dieser Änderung.

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Views/Sidebar/FeedRowView.swift Feedivo/Views/Sidebar/SidebarView.swift
git commit -m "$(cat <<'EOF'
Feature: Feeds in der Sidebar per Doppelklick umbenennbar

FeedRowView verliert den umschließenden Button (gleiches
Kollisionsproblem mit dem Inline-TextField wie zuvor bei Ordnern) und
übernimmt Auswahl + Bearbeitungsstart selbst. Auswahl-Optik von
SidebarRowButtonStyle manuell nachgebaut (Press-Flash-Mikroanimation
entfällt bewusst). Bestehender Feed-umbenennen-Dialog (Original-Titel
+ Wiederherstellen) bleibt über das Kontextmenü unverändert erreichbar.
EOF
)"
```
