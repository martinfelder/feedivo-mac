# Ordner in der Sidebar umbenennen — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ordner in der linken Sidebar von Feedivo lassen sich per Doppelklick auf den Namen (oder über einen neuen Kontextmenü-Eintrag) inline umbenennen.

**Architecture:** Eine neue transaktionale Store-Methode `FeedFolderStore.renameFolder(from:to:)` aktualisiert sowohl den expliziten `feed_folders`-Datensatz als auch alle betroffenen `feeds.folderName`-Werte (Ordner sind in Feedivo rein namensbasiert, siehe `docs/superpowers/specs/2026-07-13-ordner-umbenennen-design.md`). Die UI-Komponente `SidebarFolderSection` bekommt einen Inline-Bearbeitungsmodus (TextField statt Text), ausgelöst per Doppelklick oder Kontextmenü, mit Enter/Escape/Fokusverlust-Handling und Fehleranzeige bei Leerstring/Namenskollision.

**Tech Stack:** Swift 5.9+, SwiftUI (macOS 14+), GRDB/SQLite, Swift Testing (`@Test`/`#expect`).

## Global Constraints

- Kommentare im Code auf Deutsch (Projektkonvention laut CLAUDE.md).
- Kein SwiftData — GRDB/SQLite ist die alleinige Persistenzschicht (ADR-007).
- Mindest-macOS 14.0 Sonoma — `@FocusState`, `onExitCommand`, zweiparametriges `.onChange(of:)` sind alle ab macOS 14 verfügbar, keine Kompatibilitätsprobleme.
- Nach jeder Store-Mutation muss `SQLiteDataInvalidation.bumpStatusVersion()` aufgerufen werden, sonst aktualisiert sich die UI nicht (kein automatisches `@Query`-Observation wie bei SwiftData).
- Datenbank-Migrationen werden nie nachträglich verändert, nur angehängt — für dieses Feature ist aber ohnehin keine neue Migration nötig (keine Schemaänderung).
- Nie ohne explizite Nutzerbestätigung nach `origin/main` pushen.
- `xcodebuild build` fügt bei einem neu referenzierten, noch nicht katalogisierten `L10n`-String automatisch einen leeren Stub-Eintrag in `Localizable.xcstrings` ein — dieser Plan legt den Eintrag stattdessen explizit und vollständig übersetzt an, um diesen Stub zu vermeiden.

---

### Task 1: `FeedFolderStore.renameFolder(from:to:)` inkl. Fehlertyp (TDD)

**Files:**
- Modify: `Feedivo/Stores/FeedFolderStore.swift`
- Create: `FeedivoTests/FeedFolderStoreTests.swift`

**Interfaces:**
- Consumes: `FeedFolderStore.init(database: FeedivoDatabase)` (bereits vorhanden), `FeedivoDatabase.inMemoryForTests()` (bereits vorhanden, siehe `SQLiteFeedStoreTests.swift`), `FeedRecord`/`FeedStore` (bereits vorhanden), `FeedFolderRecord` (bereits vorhanden).
- Produces: `func renameFolder(from oldName: String, to newName: String) throws` auf `FeedFolderStore`; `enum FeedFolderRenameError: LocalizedError, Equatable` mit Fällen `.emptyName`, `.duplicateName`, `.databaseUnavailable` — beide werden in Task 2 von `SidebarView.swift` konsumiert.

- [ ] **Step 1: Schreibe die fehlschlagenden Tests**

Erstelle `FeedivoTests/FeedFolderStoreTests.swift`:

```swift
import Foundation
import Testing
@testable import Feedivo

struct FeedFolderStoreTests {
    @Test func renameFolderUpdatesExplicitFolderRecord() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let folderStore = FeedFolderStore(database: database)
        try folderStore.save(FeedFolderRecord(id: "folder-1", name: "Tech"))

        try folderStore.renameFolder(from: "Tech", to: "Technology")

        let folders = try folderStore.folders()
        #expect(folders.map(\.name) == ["Technology"])
    }

    @Test func renameFolderUpdatesFeedsForImplicitFolder() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let folderStore = FeedFolderStore(database: database)

        try feedStore.save(
            FeedRecord(id: "feed-1", url: "https://a.example/feed.xml", title: "A", folderName: "News")
        )

        try folderStore.renameFolder(from: "News", to: "World News")

        let feed = try feedStore.feed(id: "feed-1")
        #expect(feed?.folderName == "World News")
    }

    @Test func renameFolderUpdatesAllFeedsInSameFolderButNotOthers() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let folderStore = FeedFolderStore(database: database)

        try feedStore.save(
            FeedRecord(id: "feed-1", url: "https://a.example/feed.xml", title: "A", folderName: "Tech")
        )
        try feedStore.save(
            FeedRecord(id: "feed-2", url: "https://b.example/feed.xml", title: "B", folderName: "Tech")
        )
        try feedStore.save(
            FeedRecord(id: "feed-3", url: "https://c.example/feed.xml", title: "C", folderName: "Other")
        )

        try folderStore.renameFolder(from: "Tech", to: "Technology")

        let feeds = try feedStore.feeds()
        let renamedFeedNames = feeds
            .filter { $0.id == "feed-1" || $0.id == "feed-2" }
            .map(\.folderName)
        let untouchedFeed = feeds.first { $0.id == "feed-3" }

        #expect(renamedFeedNames == ["Technology", "Technology"])
        #expect(untouchedFeed?.folderName == "Other")
    }

    @Test func renameFolderRejectsEmptyName() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let folderStore = FeedFolderStore(database: database)
        try folderStore.save(FeedFolderRecord(id: "folder-1", name: "Tech"))

        #expect(throws: FeedFolderRenameError.emptyName) {
            try folderStore.renameFolder(from: "Tech", to: "   ")
        }

        let folders = try folderStore.folders()
        #expect(folders.map(\.name) == ["Tech"])
    }

    @Test func renameFolderRejectsCollisionWithAnotherFolderCaseInsensitively() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let folderStore = FeedFolderStore(database: database)
        try folderStore.save(FeedFolderRecord(id: "folder-1", name: "Tech"))
        try folderStore.save(FeedFolderRecord(id: "folder-2", name: "News"))

        #expect(throws: FeedFolderRenameError.duplicateName) {
            try folderStore.renameFolder(from: "Tech", to: "news")
        }

        let folders = try folderStore.folders()
        #expect(Set(folders.map(\.name)) == ["Tech", "News"])
    }

    @Test func renameFolderAllowsCaseOnlyCorrectionOfOwnName() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let folderStore = FeedFolderStore(database: database)
        try folderStore.save(FeedFolderRecord(id: "folder-1", name: "tech"))

        try folderStore.renameFolder(from: "tech", to: "Tech")

        let folders = try folderStore.folders()
        #expect(folders.map(\.name) == ["Tech"])
    }
}
```

- [ ] **Step 2: Führe die Tests aus und bestätige, dass sie fehlschlagen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedFolderStoreTests`

Expected: FAIL (Compile-Fehler, da `renameFolder` und `FeedFolderRenameError` noch nicht existieren — "value of type 'FeedFolderStore' has no member 'renameFolder'" o. ä.)

- [ ] **Step 3: Implementiere `renameFolder(from:to:)` und `FeedFolderRenameError`**

Ersetze den kompletten Inhalt von `Feedivo/Stores/FeedFolderStore.swift`:

```swift
import Foundation
import GRDB

// Fehler, die beim Umbenennen eines Ordners auftreten können. `.databaseUnavailable`
// wird nicht von dieser Store-Methode selbst geworfen (die Datenbank ist hier
// bereits injiziert), sondern ausschließlich vom UI-seitigen Aufrufer
// (`SidebarView.renameFolder`), falls die `\.feedivoDatabase`-Environment fehlt.
enum FeedFolderRenameError: LocalizedError, Equatable {
    case emptyName
    case duplicateName
    case databaseUnavailable

    var errorDescription: String? {
        switch self {
        case .emptyName: L10n.feedRenameEmptyName
        case .duplicateName: L10n.sidebarAddFolderDuplicateError
        case .databaseUnavailable: L10n.feedRenameDatabaseUnavailable
        }
    }
}

struct FeedFolderStore {
    private let database: FeedivoDatabase

    init(database: FeedivoDatabase) {
        self.database = database
    }

    func save(_ folder: FeedFolderRecord) throws {
        try database.write { db in
            var folder = folder
            try folder.save(db)
        }
    }

    func folders() throws -> [FeedFolderRecord] {
        try database.read { db in
            try FeedFolderRecord.fetchAll(db, sql: """
                SELECT *
                FROM feed_folders
                ORDER BY name COLLATE NOCASE, id COLLATE NOCASE
                """)
        }
    }

    func delete(id: String) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    DELETE FROM feed_folders
                    WHERE id = ?
                    """,
                arguments: [id]
            )
        }
    }

    // Ordner sind in Feedivo namensbasiert (kein FK-Konzept, das Feeds referenzieren) —
    // ein Ordner kann als expliziter feed_folders-Datensatz UND/ODER implizit nur über
    // feeds.folderName existieren. Diese Methode aktualisiert daher beide Speicherorte
    // in einer einzigen Transaktion.
    func renameFolder(from oldName: String, to newName: String) throws {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            throw FeedFolderRenameError.emptyName
        }

        try database.write { db in
            // Kollision case-insensitiv über beide Tabellen prüfen, den umzubenennenden
            // Ordner selbst dabei ausschließen — eine reine Großschreibungskorrektur des
            // eigenen Namens ("tech" -> "Tech") zählt nicht als Kollision.
            let collisionCount = try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM (
                        SELECT name AS folderName FROM feed_folders
                        WHERE name = ? COLLATE NOCASE AND name != ? COLLATE NOCASE
                        UNION
                        SELECT folderName FROM feeds
                        WHERE folderName = ? COLLATE NOCASE AND folderName != ? COLLATE NOCASE
                    )
                    """,
                arguments: [trimmedName, oldName, trimmedName, oldName]
            ) ?? 0

            guard collisionCount == 0 else {
                throw FeedFolderRenameError.duplicateName
            }

            try db.execute(
                sql: """
                    UPDATE feeds
                    SET folderName = ?
                    WHERE folderName = ? COLLATE NOCASE
                    """,
                arguments: [trimmedName, oldName]
            )

            // Aktualisiert nur, falls ein expliziter Datensatz existiert — 0 betroffene
            // Zeilen ist hier kein Fehler und deckt rein implizite Ordner ab.
            try db.execute(
                sql: """
                    UPDATE feed_folders
                    SET name = ?, updatedAt = ?
                    WHERE name = ? COLLATE NOCASE
                    """,
                arguments: [trimmedName, Date(), oldName]
            )
        }
    }
}
```

- [ ] **Step 4: Führe die Tests aus und bestätige, dass sie bestehen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedFolderStoreTests`

Expected: PASS (alle 6 Tests grün)

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Stores/FeedFolderStore.swift FeedivoTests/FeedFolderStoreTests.swift
git commit -m "$(cat <<'EOF'
Feature: FeedFolderStore.renameFolder für Ordner-Umbenennen

Transaktionale Umbenennung über beide Speicherorte des namensbasierten
Ordner-Modells (feed_folders + feeds.folderName), mit case-insensitiver
Kollisionsprüfung. Vorbereitung für die Sidebar-UI (folgender Task).
EOF
)"
```

---

### Task 2: Inline-Umbenennen-UI in `SidebarFolderSection` + Wiring in `SidebarView`

**Files:**
- Modify: `Feedivo/Views/Sidebar/SidebarView.swift`
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `FeedFolderStore.renameFolder(from:to:) throws` und `FeedFolderRenameError` aus Task 1; `SQLiteDataInvalidation.bumpStatusVersion()` (bereits vorhanden); `L10n.commonDelete`, `SidebarStyle.secondaryText`/`.primaryText` (bereits vorhanden).
- Produces: Keine neuen Interfaces für weitere Tasks — dies ist der letzte Task des Plans.

- [ ] **Step 1: Neuen L10n-Key für den Kontextmenü-Eintrag ergänzen**

In `Feedivo/Resources/L10n.swift`, füge direkt nach der Zeile `static let sidebarAddFolderNamePlaceholder = LocalizedStringKey("sidebar.addFolder.name.placeholder")` (aktuell Zeile 19) diese neue Zeile ein:

```swift
    static let sidebarFolderRenameCommand = String(localized: "sidebar.folder.rename.command")
```

- [ ] **Step 2: Übersetzten Eintrag in `Localizable.xcstrings` ergänzen**

Füge in `Feedivo/Resources/Localizable.xcstrings` im `"strings"`-Objekt einen neuen Eintrag hinzu (alphabetisch nach `"sidebar.folders.section"` einsortieren, falls die Datei alphabetisch sortiert ist — sonst an beliebiger Stelle im `"strings"`-Objekt):

```json
"sidebar.folder.rename.command" : {
  "localizations" : {
    "de" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "Ordner umbenennen"
      }
    },
    "en" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "Rename Folder"
      }
    },
    "fr" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "Renommer le dossier"
      }
    },
    "it" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "Rinomina cartella"
      }
    }
  }
}
```

Prüfe danach, dass die Datei weiterhin valides JSON ist:

Run: `python3 -c "import json; json.load(open('Feedivo/Resources/Localizable.xcstrings'))" && echo "JSON OK"`

Expected: `JSON OK`

- [ ] **Step 3: `SidebarFolderSection` um Inline-Umbenennen erweitern**

Ersetze in `Feedivo/Views/Sidebar/SidebarView.swift` die komplette bestehende `SidebarFolderSection`-Struct-Definition (beginnend bei `private struct SidebarFolderSection<Content: View>: View {`, endend bei der schließenden `}` dieser Struct — aktuell Zeilen 686–735):

Alter Code (zu ersetzen):

```swift
private struct SidebarFolderSection<Content: View>: View {
    @Environment(\.interfaceTextSize) private var interfaceTextSize

    let title: String
    let isExpanded: Bool
    let deleteEmptyFolder: (() -> Void)?
    let toggle: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: toggle) {
                HStack(spacing: 9) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(interfaceTextSize.font(size: 10, weight: .bold))
                        .foregroundStyle(SidebarStyle.secondaryText)
                        .frame(width: interfaceTextSize.scaled(12))

                    Image(systemName: "folder")
                        .font(interfaceTextSize.font(size: 16, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: interfaceTextSize.scaled(20))

                    Text(title)
                        .font(interfaceTextSize.font(size: 13, weight: .medium))
                        .foregroundStyle(SidebarStyle.primaryText.opacity(0.82))
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
                .frame(height: interfaceTextSize.scaled(24))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .contextMenu {
                if let deleteEmptyFolder {
                    Button(role: .destructive) {
                        deleteEmptyFolder()
                    } label: {
                        Label(L10n.commonDelete, systemImage: "trash")
                    }
                }
            }

            content
        }
    }
}
```

Neuer Code:

```swift
private struct SidebarFolderSection<Content: View>: View {
    @Environment(\.interfaceTextSize) private var interfaceTextSize
    @FocusState private var isNameFieldFocused: Bool

    let title: String
    let isExpanded: Bool
    let deleteEmptyFolder: (() -> Void)?
    let renameFolder: (String) throws -> Void
    let toggle: () -> Void
    @ViewBuilder let content: Content

    @State private var isEditingName = false
    @State private var editedName = ""
    @State private var renameErrorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                Button(action: toggle) {
                    HStack(spacing: 9) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(interfaceTextSize.font(size: 10, weight: .bold))
                            .foregroundStyle(SidebarStyle.secondaryText)
                            .frame(width: interfaceTextSize.scaled(12))

                        Image(systemName: "folder")
                            .font(interfaceTextSize.font(size: 16, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: interfaceTextSize.scaled(20))
                    }
                }
                .buttonStyle(.plain)

                if isEditingName {
                    TextField(title, text: $editedName)
                        .textFieldStyle(.plain)
                        .font(interfaceTextSize.font(size: 13, weight: .medium))
                        .focused($isNameFieldFocused)
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
                    Text(title)
                        .font(interfaceTextSize.font(size: 13, weight: .medium))
                        .foregroundStyle(SidebarStyle.primaryText.opacity(0.82))
                        .lineLimit(1)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            beginEditing()
                        }
                        .onTapGesture(count: 1) {
                            toggle()
                        }
                }

                Spacer(minLength: 0)
            }
            .frame(height: interfaceTextSize.scaled(24))
            .contentShape(Rectangle())
            .onTapGesture {
                // Fängt Klicks auf den leeren Bereich rechts vom Namen ab, damit die
                // gesamte Zeile weiterhin wie vor dieser Änderung klickbar bleibt.
                // Klicks auf Chevron/Icon (eigener Button) und auf den Namen (eigene
                // Tap-Gesten oben) werden von SwiftUI vorrangig an die jeweils
                // spezifischere View vergeben und lösen diesen Handler nicht zusätzlich aus.
                toggle()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .contextMenu {
                Button {
                    beginEditing()
                } label: {
                    Label(L10n.sidebarFolderRenameCommand, systemImage: "pencil")
                }

                if let deleteEmptyFolder {
                    Button(role: .destructive) {
                        deleteEmptyFolder()
                    } label: {
                        Label(L10n.commonDelete, systemImage: "trash")
                    }
                }
            }

            if let renameErrorMessage {
                Text(renameErrorMessage)
                    .font(interfaceTextSize.font(size: 11))
                    .foregroundStyle(.red)
                    .padding(.leading, 16 + 12 + 9 + 20 + 9)
                    .padding(.trailing, 16)
            }

            content
        }
    }

    private func beginEditing() {
        editedName = title
        renameErrorMessage = nil
        isEditingName = true
        isNameFieldFocused = true
    }

    private func cancelEditing() {
        editedName = title
        renameErrorMessage = nil
        isEditingName = false
    }

    private func commitOrShowError() {
        let trimmedName = editedName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmedName != title else {
            isEditingName = false
            renameErrorMessage = nil
            return
        }

        do {
            try renameFolder(trimmedName)
            isEditingName = false
            renameErrorMessage = nil
        } catch {
            renameErrorMessage = error.localizedDescription
        }
    }
}
```

- [ ] **Step 4: `SidebarFolderSection`-Aufrufstelle um `renameFolder`-Closure erweitern**

Ersetze in `Feedivo/Views/Sidebar/SidebarView.swift` den bestehenden `ForEach`-Block (aktuell Zeilen 241–266):

Alter Code (zu ersetzen):

```swift
                ForEach(
                    FeedFolderOrganizer.feedsByFolderName(
                        in: visibleSnapshots,
                        folders: sqliteSidebarState.feedFolders
                    ),
                    id: \.folderName
                ) { entry in
                    let isExpanded = !collapsedFolderNames.contains(entry.folderName)
                    let explicitFolder = explicitFeedFolder(named: entry.folderName)
                    SidebarFolderSection(
                        title: entry.folderName,
                        isExpanded: isExpanded,
                        deleteEmptyFolder: entry.snapshots.isEmpty && explicitFolder != nil
                            ? { feedFolderPendingDeletion = explicitFolder }
                            : nil
                    ) {
                        toggleFolder(named: entry.folderName)
                    } content: {
                        if isExpanded {
                            feedRows(
                                entry.snapshots,
                                isIndented: true
                            )
                        }
                    }
                }
```

Neuer Code:

```swift
                ForEach(
                    FeedFolderOrganizer.feedsByFolderName(
                        in: visibleSnapshots,
                        folders: sqliteSidebarState.feedFolders
                    ),
                    id: \.folderName
                ) { entry in
                    let isExpanded = !collapsedFolderNames.contains(entry.folderName)
                    let explicitFolder = explicitFeedFolder(named: entry.folderName)
                    SidebarFolderSection(
                        title: entry.folderName,
                        isExpanded: isExpanded,
                        deleteEmptyFolder: entry.snapshots.isEmpty && explicitFolder != nil
                            ? { feedFolderPendingDeletion = explicitFolder }
                            : nil,
                        renameFolder: { newName in
                            try renameFolder(from: entry.folderName, to: newName)
                        }
                    ) {
                        toggleFolder(named: entry.folderName)
                    } content: {
                        if isExpanded {
                            feedRows(
                                entry.snapshots,
                                isIndented: true
                            )
                        }
                    }
                }
```

- [ ] **Step 5: Neue private Methode `renameFolder(from:to:)` in `SidebarView` ergänzen**

Füge in `Feedivo/Views/Sidebar/SidebarView.swift` direkt nach der bestehenden `deleteFeedFolder`-Methode (aktuell Zeilen 479–488) diese neue Methode ein:

```swift

    private func renameFolder(from oldName: String, to newName: String) throws {
        guard let database = feedivoDatabase else {
            throw FeedFolderRenameError.databaseUnavailable
        }

        try FeedFolderStore(database: database).renameFolder(from: oldName, to: newName)

        // Ein-/Ausklapp-Zustand ist über collapsedFolderNames am alten Namen
        // festgemacht — beim Umbenennen migrieren, damit ein zuvor eingeklappter
        // Ordner nach der Umbenennung nicht überraschend wieder aufklappt.
        if collapsedFolderNames.remove(oldName) != nil {
            collapsedFolderNames.insert(newName)
        }

        SQLiteDataInvalidation.bumpStatusVersion()
        sidebarDefinitionVersion += 1
    }
```

- [ ] **Step 6: Build ausführen und auf Erfolg prüfen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`

Expected: `BUILD SUCCEEDED`

Prüfe danach `git diff --stat Feedivo/Resources/Localizable.xcstrings`, um sicherzustellen, dass der Build keinen zusätzlichen leeren Stub-Eintrag für einen anderen, in diesem Task neu referenzierten String angelegt hat (sollte hier nicht der Fall sein, da `sidebar.folder.rename.command` bereits in Step 2 vollständig übersetzt eingetragen wurde).

- [ ] **Step 7: Manuelle Verifikation in der laufenden App**

Da SwiftUI-Gesten und Fokus-Verhalten in diesem Projekt nicht automatisiert getestet werden (siehe Design-Spec), die App starten und folgende Punkte von Hand prüfen:

1. Sidebar öffnen, einen Ordner mit mindestens einem Feed anlegen (falls noch keiner existiert).
2. Einzelklick auf den Ordnernamen → Ordner klappt weiterhin ein/aus wie vorher.
3. Doppelklick auf den Ordnernamen → Name wird zu einem editierbaren Textfeld.
4. Namen ändern, Enter drücken → neuer Name erscheint, Feeds im Ordner bleiben zugeordnet.
5. Erneut doppelklicken, Namen leeren, Enter drücken → roter Rahmen + Fehlertext "Der Name darf nicht leer sein.", Bearbeitungsmodus bleibt aktiv.
6. Namen auf den Namen eines anderen bestehenden Ordners ändern, Enter drücken → roter Rahmen + Fehlertext "Dieser Ordner existiert bereits.", Bearbeitungsmodus bleibt aktiv.
7. Escape drücken → Bearbeitung bricht ab, alter Name bleibt stehen.
8. Doppelklick, Namen ändern, dann irgendwo anders in der Sidebar klicken (Fokusverlust ohne Enter) → Änderung wird übernommen wie bei Enter.
9. Rechtsklick auf einen Ordner → neuer Eintrag "Ordner umbenennen" öffnet denselben Bearbeitungsmodus.
10. Ordner einklappen, dann umbenennen → Ordner bleibt nach der Umbenennung eingeklappt (nicht überraschend wieder aufgeklappt).

- [ ] **Step 8: Commit**

```bash
git add Feedivo/Views/Sidebar/SidebarView.swift Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings
git commit -m "$(cat <<'EOF'
Feature: Ordner in der Sidebar per Doppelklick umbenennbar

Inline-Textfeld-Bearbeitung (Enter/Escape/Fokusverlust) plus neuer
Kontextmenü-Eintrag "Ordner umbenennen". Nutzt FeedFolderStore.renameFolder
aus dem vorherigen Commit; Ein-/Ausklapp-Zustand wird beim Umbenennen
migriert.
EOF
)"
```
