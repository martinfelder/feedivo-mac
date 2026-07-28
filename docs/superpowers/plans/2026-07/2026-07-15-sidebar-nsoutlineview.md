# Sidebar-Migration auf AppKit NSOutlineView Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ersetzt die unzuverlässige SwiftUI-native `.draggable`/`.dropDestination`-Sidebar
durch eine einzige AppKit `NSOutlineView` (NetNewsWire-Vorbild), die zuverlässiges Drag & Drop
mit nativem visuellem Feedback für Feeds, Ordner, Tags und Smart Folders liefert.

**Architecture:** `NSViewRepresentable`-Bridge (`SidebarOutlineView`) hostet eine
`NSOutlineView`, deren Zeilen per `NSHostingView` die unveränderten bestehenden SwiftUI-
Row-Views rendern. Ein reines Swift-Baum-Modell (`SidebarOutlineNode`) bildet die
Sidebar-Struktur ab; ein Coordinator implementiert `NSOutlineViewDataSource` +
`NSOutlineViewDelegate` inkl. `NSPasteboardWriting`-basiertem Drag & Drop. Auswahl und
Ein-/Ausklappen bleiben rein SwiftUI-gesteuert (NSOutlineView verwaltet keine eigene
Selektion). Siehe Design-Spec:
`docs/superpowers/specs/2026-07-15-sidebar-nsoutlineview-design.md`.

**Tech Stack:** Swift, SwiftUI, AppKit (`NSOutlineView`, `NSViewRepresentable`,
`NSHostingView`, `NSPasteboardWriting`), GRDB/SQLite, Swift Testing (`@Test`/`#expect`).

## Global Constraints

- Kommentare im Code auf Deutsch (Projekt-Konvention, siehe CLAUDE.md).
- Migrationen werden immer als neuer `registerMigration`-Block angehängt, nie bestehende
  geändert.
- `UTType(exportedAs:)` braucht IMMER einen passenden `UTExportedTypeDeclarations`-Eintrag
  in `Feedivo/Info.plist`, auch bei rein appinterner Nutzung (bekannter Gotcha).
- Volle Testsuite (`xcodebuild test` ohne `-only-testing`) hängt reproduzierbar — immer
  gezielt mit `-only-testing:FeedivoTests/<SuiteName>` testen.
- SourceKit-Diagnosen in der IDE sind oft veraltet/falsch — nur ein echter
  `xcodebuild build`-Lauf zählt als Verifikation.
- Kein Placeholder-Verhalten: jede neue Migration/jeder neue Store-Call muss vollständig
  funktionsfähig sein, keine TODO-Stubs.

---

## Task 1: Tags sortIndex — Migration, TagRecord, TagStore.move

**Files:**
- Modify: `Feedivo/Database/FeedivoDatabaseMigrator.swift:373-385` (neue Migration nach v15
  einfügen)
- Modify: `Feedivo/Database/Records/TagRecord.swift`
- Modify: `Feedivo/Stores/TagStore.swift`
- Test: `FeedivoTests/SQLiteTagStoreTests.swift`

**Interfaces:**
- Produziert: `TagRecord.sortIndex: Int` (neues Feld), `TagStore.move(id: String,
  targetIndex: Int) throws`, `TagStore.tags()`/`TagStore.sidebarTags()` sortieren neu nach
  `sortIndex` statt `name`.
- Konsumiert: `FeedivoDatabase.inMemoryForTests()` (bestehende Test-Hilfsfunktion, siehe
  `FeedFolderStoreTests.swift:147`), `TagStore.save(_:)` (bestehend, wird in diesem Task
  angepasst).

- [ ] **Step 1: Prüfe den tatsächlich letzten Migrations-Stand**

Run: `grep -n "registerMigration" Feedivo/Database/FeedivoDatabaseMigrator.swift`
Expected: Letzter Eintrag ist `v15_add_feed_and_folder_sort_index` (Stand bei Plan-
Erstellung). Falls ein neuerer Eintrag existiert, die neue Migration in diesem Task als
`vN+1` statt `v16` benennen — NIE die Design-Spec/diesen Plan blind als Quelle der
Wahrheit für die Nummer nehmen (bekannter Gotcha, siehe CLAUDE.md).

- [ ] **Step 2: Schreibe den fehlschlagenden Test für `TagStore.move`**

In `FeedivoTests/SQLiteTagStoreTests.swift` ergänzen (Datei existiert bereits, neue Tests
ans Ende der Suite anhängen):

```swift
@Test func moveVerschiebtTagAnNeuePosition() throws {
    let database = try FeedivoDatabase.inMemoryForTests()
    let tagStore = TagStore(database: database)
    try tagStore.save(TagRecord(id: "tag-a", name: "Alpha", sortIndex: 0))
    try tagStore.save(TagRecord(id: "tag-b", name: "Bravo", sortIndex: 1))
    try tagStore.save(TagRecord(id: "tag-c", name: "Charlie", sortIndex: 2))

    try tagStore.move(id: "tag-c", targetIndex: 0)

    let orderedNames = try tagStore.tags()
        .sorted { $0.sortIndex < $1.sortIndex }
        .map(\.name)
    #expect(orderedNames == ["Charlie", "Alpha", "Bravo"])
}

@Test func moveKlemmtTargetIndexAufGueltigenBereich() throws {
    let database = try FeedivoDatabase.inMemoryForTests()
    let tagStore = TagStore(database: database)
    try tagStore.save(TagRecord(id: "tag-a", name: "Alpha", sortIndex: 0))
    try tagStore.save(TagRecord(id: "tag-b", name: "Bravo", sortIndex: 1))

    try tagStore.move(id: "tag-a", targetIndex: 999)

    let orderedNames = try tagStore.tags()
        .sorted { $0.sortIndex < $1.sortIndex }
        .map(\.name)
    #expect(orderedNames == ["Bravo", "Alpha"])
}

@Test func neuerTagWirdAmEndeEingefuegtNichtBeiIndexNull() throws {
    let database = try FeedivoDatabase.inMemoryForTests()
    let tagStore = TagStore(database: database)
    try tagStore.save(TagRecord(id: "tag-a", name: "Alpha", sortIndex: 0))
    try tagStore.save(TagRecord(id: "tag-b", name: "Bravo", sortIndex: 1))

    // Bewusst ohne explizit gesetzten sortIndex gespeichert (Default 0 aus dem
    // Initializer) — save() muss trotzdem ans Ende anhängen, nicht bei den
    // bestehenden Tags mit sortIndex 0 landen.
    try tagStore.save(TagRecord(id: "tag-c", name: "Charlie"))

    let orderedNames = try tagStore.tags()
        .sorted { $0.sortIndex < $1.sortIndex }
        .map(\.name)
    #expect(orderedNames == ["Alpha", "Bravo", "Charlie"])
}

@Test func tagsSortiertNachSortIndexNichtNachName() throws {
    let database = try FeedivoDatabase.inMemoryForTests()
    let tagStore = TagStore(database: database)
    try tagStore.save(TagRecord(id: "tag-z", name: "Zebra", sortIndex: 0))
    try tagStore.save(TagRecord(id: "tag-a", name: "Apfel", sortIndex: 1))

    let orderedNames = try tagStore.tags().map(\.name)
    #expect(orderedNames == ["Zebra", "Apfel"])
}
```

- [ ] **Step 3: Führe die Tests aus, um das erwartete Scheitern zu bestätigen**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteTagStoreTests 2>&1 | tail -60`
Expected: FAIL — `TagRecord` hat kein `sortIndex`-Argument im Initializer, `TagStore` hat
keine `move`-Methode. Compile-Fehler sind hier das erwartete "Fail" (Interfaces existieren
noch nicht).

- [ ] **Step 4: Migration `v16_add_tag_sort_index` ergänzen**

In `Feedivo/Database/FeedivoDatabaseMigrator.swift`, direkt nach dem bestehenden
`v15_add_feed_and_folder_sort_index`-Block (vor der `return migrator`-Zeile) einfügen:

```swift
        migrator.registerMigration("v16_add_tag_sort_index") { database in
            try database.alter(table: "tags") { table in
                table.add(column: "sortIndex", .integer).notNull().defaults(to: 0)
            }

            try backfillTagSortIndex(database)
        }
```

Und als neue private static Methode im selben Typ (analog zu
`backfillFeedAndFolderSortIndex`, direkt danach einfügen):

```swift
    /// Vergibt sortIndex-Werte für Tags passend zur AKTUELLEN alphabetischen
    /// Anzeige, damit Bestandsnutzer nach diesem Update keine sichtbare
    /// Umsortierung erleben — identisches Muster zu
    /// backfillFeedAndFolderSortIndex (v15).
    private static func backfillTagSortIndex(_ database: Database) throws {
        let orderedIDs = try String.fetchAll(
            database,
            sql: "SELECT id FROM tags ORDER BY name COLLATE NOCASE, id COLLATE NOCASE"
        )

        for (index, id) in orderedIDs.enumerated() {
            try database.execute(
                sql: "UPDATE tags SET sortIndex = ? WHERE id = ?",
                arguments: [index, id]
            )
        }
    }
```

- [ ] **Step 5: `TagRecord.sortIndex` ergänzen**

In `Feedivo/Database/Records/TagRecord.swift`:

```swift
import Foundation
import GRDB

struct TagRecord: Codable, FetchableRecord, Identifiable, MutablePersistableRecord, Equatable, Sendable {
    static let databaseTableName = "tags"

    var id: String
    var name: String
    var colorHex: String
    var sortIndex: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        colorHex: String = "#888888",
        sortIndex: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.sortIndex = sortIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
```

- [ ] **Step 6: `TagStore.move`, angepasstes `save`, `ORDER BY`-Umstellung**

In `Feedivo/Stores/TagStore.swift`:

`save(_:)` ersetzen (neuer Tag bekommt jetzt immer `maxSortIndex + 1` statt des ggf.
mitgelieferten Default-Werts 0 — sonst würden neu erstellte Tags zufällig zwischen die
bestehenden mit `sortIndex == 0` sortiert statt ans Ende angehängt zu werden):

```swift
    func save(_ tag: TagRecord) throws {
        try database.write { db in
            let existingID = try String.fetchOne(db, sql: """
                SELECT id
                FROM tags
                WHERE id = ? OR name = ?
                ORDER BY CASE WHEN id = ? THEN 0 ELSE 1 END
                LIMIT 1
                """, arguments: [tag.id, tag.name, tag.id])
            let now = Date()

            if let existingID {
                try db.execute(
                    sql: """
                        UPDATE tags
                        SET id = ?, name = ?, colorHex = ?, updatedAt = ?
                        WHERE id = ?
                        """,
                    arguments: [tag.id, tag.name, tag.colorHex, now, existingID]
                )
            } else {
                let maxSortIndex = (try Int.fetchOne(db, sql: "SELECT MAX(sortIndex) FROM tags") ?? -1) + 1
                var tag = tag
                tag.sortIndex = maxSortIndex
                try tag.insert(db)
            }
        }
    }

    /// Verschiebt den Tag mit `id` an Index `targetIndex` innerhalb der
    /// bestehenden Sortierreihenfolge (0-basiert, wird auf den gültigen
    /// Bereich geklemmt) und schreibt sortIndex für alle betroffenen Tags neu
    /// — analog zu FeedFolderStore.moveFolder.
    func move(id: String, targetIndex: Int) throws {
        try database.write { db in
            let otherIDs = try String.fetchAll(
                db,
                sql: "SELECT id FROM tags WHERE id != ? ORDER BY sortIndex",
                arguments: [id]
            )

            var orderedIDs = otherIDs
            let clampedIndex = min(max(targetIndex, 0), orderedIDs.count)
            orderedIDs.insert(id, at: clampedIndex)

            let now = Date()
            for (index, tagID) in orderedIDs.enumerated() {
                try db.execute(
                    sql: "UPDATE tags SET sortIndex = ?, updatedAt = ? WHERE id = ?",
                    arguments: [index, now, tagID]
                )
            }
        }
    }
```

`tags()` und `sidebarTags()` `ORDER BY`-Klauseln ändern (jeweils die bestehende Zeile
`ORDER BY name COLLATE NOCASE, id COLLATE NOCASE` bzw. `ORDER BY t.name COLLATE NOCASE,
t.id COLLATE NOCASE` — NUR in `tags()` und `sidebarTags()`, NICHT in `tags(articleID:)`
oder `tags(feedID:)`, die bleiben alphabetisch für ihre jeweiligen Anzeigekontexte):

```swift
    func tags() throws -> [TagRecord] {
        try database.read { db in
            try TagRecord.fetchAll(db, sql: """
                SELECT *
                FROM tags
                ORDER BY sortIndex, name COLLATE NOCASE, id COLLATE NOCASE
                """)
        }
    }
```

```swift
    func sidebarTags() throws -> [TagSidebarSnapshot] {
        try database.read { db in
            try TagSidebarSnapshot.fetchAll(db, sql: """
                SELECT
                    t.id,
                    t.name,
                    t.colorHex,
                    (
                        SELECT COUNT(DISTINCT a.id)
                        FROM articles a
                        WHERE EXISTS (
                            SELECT 1
                            FROM article_tags at
                            WHERE at.articleID = a.id
                                AND at.tagID = t.id
                        )
                        OR EXISTS (
                            SELECT 1
                            FROM feed_tags ft
                            WHERE ft.feedID = a.feedID
                                AND ft.tagID = t.id
                        )
                    ) AS articleCount
                FROM tags t
                ORDER BY t.sortIndex, t.name COLLATE NOCASE, t.id COLLATE NOCASE
                """)
        }
    }
```

- [ ] **Step 7: Tests erneut ausführen, PASS verifizieren**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteTagStoreTests 2>&1 | tail -60`
Expected: Alle Tests PASS, inklusive der bestehenden (nicht neuen) Tests in derselben
Suite — keine Regression.

- [ ] **Step 8: Vollen Build verifizieren**

Run: `xcodebuild build -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -40`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 9: Commit**

```bash
git add Feedivo/Database/FeedivoDatabaseMigrator.swift Feedivo/Database/Records/TagRecord.swift Feedivo/Stores/TagStore.swift FeedivoTests/SQLiteTagStoreTests.swift
git commit -m "Feature: Tags per sortIndex sortierbar (Migration v16 + TagStore.move)"
```

---

## Task 2: SidebarOutlineNode — Baum-Modell

**Files:**
- Create: `Feedivo/Views/Sidebar/SidebarOutlineNode.swift`
- Test: `FeedivoTests/SidebarOutlineNodeTests.swift`

**Interfaces:**
- Konsumiert: `FeedSidebarSnapshot` (`Feedivo/Snapshots/FeedSidebarSnapshot.swift` — `id,
  title, url, faviconURL, folderName, sortIndex, unreadCount, hasRecentError`),
  `TagSidebarSnapshot` (`id, name, colorHex, articleCount`), `SQLiteSmartFolderSnapshot`
  (`id, name, matchMode, conditions, iconName, colorHex, defaultKey`), `FeedFolderRecord`
  (`id, name, sortIndex, createdAt, updatedAt`), `FeedFolderOrganizer.feedsWithoutFolder
  (from:)`, `FeedFolderOrganizer.feedsByFolderName(in:folders:)` (bestehend,
  `Feedivo/Views/Sidebar/FeedFolderOrganizer.swift`), `SmartFolderSidebarGrouping.
  defaultFolders(from:)`/`.customFolders(from:)` (bestehend,
  `Feedivo/Views/Sidebar/SmartFolderSidebarGrouping.swift`).
- Produziert: `SidebarOutlineNode` (Klasse), `SidebarOutlineNode.Payload` (Enum),
  `SidebarOutlineNode.buildTree(feedSnapshots:feedFolders:tagSnapshots:
  smartFolderSnapshots:) -> [SidebarOutlineNode]`, `SidebarOutlineNode.find(id:in:) ->
  SidebarOutlineNode?` (rekursive Suche über den ganzen Baum — wird in Task 5 für die
  Drop-Auflösung gebraucht).

- [ ] **Step 1: Schreibe die fehlschlagenden Tests**

Neue Datei `FeedivoTests/SidebarOutlineNodeTests.swift`:

```swift
import Foundation
import Testing
@testable import Feedivo

struct SidebarOutlineNodeTests {
    private func makeFeed(id: String, title: String, folderName: String?, sortIndex: Int = 0) -> FeedSidebarSnapshot {
        FeedSidebarSnapshot(
            id: id,
            title: title,
            url: "https://example.com/\(id).xml",
            faviconURL: nil,
            folderName: folderName,
            sortIndex: sortIndex,
            unreadCount: 0,
            hasRecentError: false
        )
    }

    private func makeSmartFolder(id: String, name: String, defaultKey: String?) -> SQLiteSmartFolderSnapshot {
        SQLiteSmartFolderSnapshot(
            id: id,
            name: name,
            matchMode: .all,
            conditions: [],
            defaultKey: defaultKey
        )
    }

    @Test func buildTreeErzeugtGenauVierWurzelKnoten() {
        let nodes = SidebarOutlineNode.buildTree(
            feedSnapshots: [],
            feedFolders: [],
            tagSnapshots: [],
            smartFolderSnapshots: []
        )
        #expect(nodes.count == 4)
        #expect(nodes.map(\.id) == [
            "header.smartFolders.default",
            "header.smartFolders.custom",
            "header.tags",
            "header.folders"
        ])
    }

    @Test func buildTreeTrenntStandardUndEigeneSmartFolders() {
        let nodes = SidebarOutlineNode.buildTree(
            feedSnapshots: [],
            feedFolders: [],
            tagSnapshots: [],
            smartFolderSnapshots: [
                makeSmartFolder(id: "sf-default", name: "Alle", defaultKey: "all"),
                makeSmartFolder(id: "sf-custom", name: "Meine Auswahl", defaultKey: nil)
            ]
        )

        let defaultHeader = nodes.first { $0.id == "header.smartFolders.default" }
        let customHeader = nodes.first { $0.id == "header.smartFolders.custom" }
        #expect(defaultHeader?.children.map(\.id) == ["smartFolder:sf-default"])
        #expect(customHeader?.children.map(\.id) == ["smartFolder:sf-custom"])
    }

    @Test func buildTreeOrdnetFeedsOhneOrdnerVorDenOrdnernEin() {
        let nodes = SidebarOutlineNode.buildTree(
            feedSnapshots: [
                makeFeed(id: "feed-1", title: "Ohne Ordner", folderName: nil),
                makeFeed(id: "feed-2", title: "Mit Ordner", folderName: "News")
            ],
            feedFolders: [FeedFolderRecord(id: "folder-1", name: "News", sortIndex: 0)],
            tagSnapshots: [],
            smartFolderSnapshots: []
        )

        let foldersHeader = nodes.first { $0.id == "header.folders" }
        #expect(foldersHeader?.children.map(\.id) == ["feed:feed-1", "folder:News"])

        let folderNode = foldersHeader?.children.first { $0.id == "folder:News" }
        #expect(folderNode?.children.map(\.id) == ["feed:feed-2"])
    }

    @Test func buildTreeUebernimmtTagsInSortIndexReihenfolge() {
        let nodes = SidebarOutlineNode.buildTree(
            feedSnapshots: [],
            feedFolders: [],
            tagSnapshots: [
                TagSidebarSnapshot(id: "tag-a", name: "Alpha", colorHex: "#000000", articleCount: 0),
                TagSidebarSnapshot(id: "tag-b", name: "Bravo", colorHex: "#000000", articleCount: 0)
            ],
            smartFolderSnapshots: []
        )

        let tagsHeader = nodes.first { $0.id == "header.tags" }
        #expect(tagsHeader?.children.map(\.id) == ["tag:tag-a", "tag:tag-b"])
    }

    @Test func findDurchsuchtDenGesamtenBaumRekursiv() {
        let feed = makeFeed(id: "feed-1", title: "Verschachtelt", folderName: "News")
        let nodes = SidebarOutlineNode.buildTree(
            feedSnapshots: [feed],
            feedFolders: [FeedFolderRecord(id: "folder-1", name: "News", sortIndex: 0)],
            tagSnapshots: [],
            smartFolderSnapshots: []
        )

        let found = SidebarOutlineNode.find(id: "feed:feed-1", in: nodes)
        #expect(found != nil)

        let notFound = SidebarOutlineNode.find(id: "feed:missing", in: nodes)
        #expect(notFound == nil)
    }

    @Test func nodesMitGleicherIdSindGleich() {
        let a = SidebarOutlineNode(id: "x", payload: .tagsHeader)
        let b = SidebarOutlineNode(id: "x", payload: .foldersHeader)
        #expect(a.isEqual(b))
    }
}
```

- [ ] **Step 2: Tests ausführen, Scheitern verifizieren**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SidebarOutlineNodeTests 2>&1 | tail -60`
Expected: FAIL — `SidebarOutlineNode` existiert noch nicht (Compile-Fehler).

- [ ] **Step 3: `SidebarOutlineNode.swift` implementieren**

Neue Datei `Feedivo/Views/Sidebar/SidebarOutlineNode.swift`:

```swift
import AppKit

/// Ein Knoten im Sidebar-Baum, der von SidebarOutlineView (NSOutlineView-Bridge)
/// dargestellt wird. NSObject-Subklasse, weil NSOutlineViewDataSource für
/// Item-Identität Referenzsemantik voraussetzt. isEqual/hash sind auf `id`
/// überschrieben, damit ein bei jedem Reload komplett neu aufgebauter Baum
/// (siehe buildTree) trotzdem stabile Identität über reloadData()-Aufrufe
/// hinweg behält (nötig für expandItem/collapseItem-Wiederherstellung).
final class SidebarOutlineNode: NSObject {
    enum Payload {
        case smartFoldersHeader(isDefault: Bool)
        case smartFolder(SQLiteSmartFolderSnapshot)
        case tagsHeader
        case tag(TagSidebarSnapshot)
        case foldersHeader
        case folder(name: String)
        case feed(FeedSidebarSnapshot)
        /// Platzhalter-Zeile für einen leeren Abschnitt (z. B. "Keine
        /// Intelligenten Ordner vorhanden") — nicht selektierbar, nicht
        /// draggable.
        case emptyPlaceholder(text: String)
    }

    let id: String
    let payload: Payload
    private(set) var children: [SidebarOutlineNode]

    init(id: String, payload: Payload, children: [SidebarOutlineNode] = []) {
        self.id = id
        self.payload = payload
        self.children = children
    }

    var isDraggable: Bool {
        switch payload {
        case .feed, .folder, .tag, .smartFolder:
            true
        case .smartFoldersHeader, .tagsHeader, .foldersHeader, .emptyPlaceholder:
            false
        }
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? SidebarOutlineNode else { return false }
        return other.id == id
    }

    override var hash: Int {
        id.hashValue
    }
}

extension SidebarOutlineNode {
    static func buildTree(
        feedSnapshots: [FeedSidebarSnapshot],
        feedFolders: [FeedFolderRecord],
        tagSnapshots: [TagSidebarSnapshot],
        smartFolderSnapshots: [SQLiteSmartFolderSnapshot]
    ) -> [SidebarOutlineNode] {
        let defaultSmartFolders = SmartFolderSidebarGrouping.defaultFolders(from: smartFolderSnapshots)
        let customSmartFolders = SmartFolderSidebarGrouping.customFolders(from: smartFolderSnapshots)

        let defaultHeader = SidebarOutlineNode(
            id: "header.smartFolders.default",
            payload: .smartFoldersHeader(isDefault: true),
            children: defaultSmartFolders.map { folder in
                SidebarOutlineNode(id: "smartFolder:\(folder.id)", payload: .smartFolder(folder))
            }
        )

        let customHeader = SidebarOutlineNode(
            id: "header.smartFolders.custom",
            payload: .smartFoldersHeader(isDefault: false),
            children: customSmartFolders.map { folder in
                SidebarOutlineNode(id: "smartFolder:\(folder.id)", payload: .smartFolder(folder))
            }
        )

        let tagsHeader = SidebarOutlineNode(
            id: "header.tags",
            payload: .tagsHeader,
            children: tagSnapshots.map { tag in
                SidebarOutlineNode(id: "tag:\(tag.id)", payload: .tag(tag))
            }
        )

        let feedsWithoutFolder = FeedFolderOrganizer.feedsWithoutFolder(from: feedSnapshots)
        let folderEntries = FeedFolderOrganizer.feedsByFolderName(in: feedSnapshots, folders: feedFolders)

        var foldersChildren: [SidebarOutlineNode] = feedsWithoutFolder.map { snapshot in
            SidebarOutlineNode(id: "feed:\(snapshot.id)", payload: .feed(snapshot))
        }
        foldersChildren += folderEntries.map { entry in
            SidebarOutlineNode(
                id: "folder:\(entry.folderName)",
                payload: .folder(name: entry.folderName),
                children: entry.snapshots.map { snapshot in
                    SidebarOutlineNode(id: "feed:\(snapshot.id)", payload: .feed(snapshot))
                }
            )
        }

        let foldersHeader = SidebarOutlineNode(
            id: "header.folders",
            payload: .foldersHeader,
            children: foldersChildren
        )

        return [defaultHeader, customHeader, tagsHeader, foldersHeader]
    }

    /// Rekursive Suche über den gesamten Baum anhand der stabilen `id`.
    static func find(id: String, in nodes: [SidebarOutlineNode]) -> SidebarOutlineNode? {
        for node in nodes {
            if node.id == id {
                return node
            }
            if let found = find(id: id, in: node.children) {
                return found
            }
        }
        return nil
    }
}
```

- [ ] **Step 4: Tests erneut ausführen, PASS verifizieren**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SidebarOutlineNodeTests 2>&1 | tail -60`
Expected: Alle Tests PASS.

- [ ] **Step 5: Vollen Build verifizieren**

Run: `xcodebuild build -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -40`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Views/Sidebar/SidebarOutlineNode.swift FeedivoTests/SidebarOutlineNodeTests.swift
git commit -m "Feature: SidebarOutlineNode-Baum-Modell für NSOutlineView-Sidebar"
```

---

## Task 3: NSPasteboardWriting-Typen + Info.plist

**Files:**
- Create: `Feedivo/Views/Sidebar/SidebarOutlinePasteboard.swift`
- Modify: `Feedivo/Info.plist`
- Test: `FeedivoTests/SidebarOutlinePasteboardTests.swift`

**Interfaces:**
- Produziert: `UTType.feedivoTagDragItem`, `UTType.feedivoSmartFolderDragItem` (neu, analog
  zu bestehenden `.feedivoFeedDragItem`/`.feedivoFolderDragItem` in
  `SidebarDragAndDrop.swift:14-15`), `SidebarFeedPasteboardItem`,
  `SidebarFolderPasteboardItem`, `SidebarTagPasteboardItem`,
  `SidebarSmartFolderPasteboardItem` (je `NSObject`, `NSPasteboardWriting`, mit einem
  String-Payload = die jeweilige `id` bzw. der `folderName`).
- Konsumiert: keine (reine Pasteboard-Infrastruktur).

- [ ] **Step 1: Schreibe die fehlschlagenden Tests**

Neue Datei `FeedivoTests/SidebarOutlinePasteboardTests.swift`:

```swift
import AppKit
import Testing
@testable import Feedivo

struct SidebarOutlinePasteboardTests {
    @Test func feedPasteboardItemSchreibtUndLiestIDZurueck() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.clearContents() }

        let writer = SidebarFeedPasteboardItem(feedID: "feed-123")
        pasteboard.clearContents()
        pasteboard.writeObjects([writer])

        let readBack = pasteboard.string(forType: .feedivoFeedDragItem)
        #expect(readBack == "feed-123")
    }

    @Test func folderPasteboardItemSchreibtUndLiestNamenZurueck() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.clearContents() }

        let writer = SidebarFolderPasteboardItem(folderName: "News")
        pasteboard.clearContents()
        pasteboard.writeObjects([writer])

        let readBack = pasteboard.string(forType: .feedivoFolderDragItem)
        #expect(readBack == "News")
    }

    @Test func tagPasteboardItemSchreibtUndLiestIDZurueck() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.clearContents() }

        let writer = SidebarTagPasteboardItem(tagID: "tag-456")
        pasteboard.clearContents()
        pasteboard.writeObjects([writer])

        let readBack = pasteboard.string(forType: .feedivoTagDragItem)
        #expect(readBack == "tag-456")
    }

    @Test func smartFolderPasteboardItemSchreibtUndLiestIDZurueck() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.clearContents() }

        let writer = SidebarSmartFolderPasteboardItem(smartFolderID: "sf-789")
        pasteboard.clearContents()
        pasteboard.writeObjects([writer])

        let readBack = pasteboard.string(forType: .feedivoSmartFolderDragItem)
        #expect(readBack == "sf-789")
    }
}
```

- [ ] **Step 2: Tests ausführen, Scheitern verifizieren**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SidebarOutlinePasteboardTests 2>&1 | tail -60`
Expected: FAIL — Typen existieren noch nicht.

- [ ] **Step 3: `SidebarOutlinePasteboard.swift` implementieren**

Neue Datei `Feedivo/Views/Sidebar/SidebarOutlinePasteboard.swift`:

```swift
import AppKit
import UniformTypeIdentifiers

// UTType(exportedAs:) erzeugt zwar einen In-Prozess-UTType-Wert, aber macOS
// validiert beim tatsächlichen Drag-&-Drop-Betrieb trotzdem gegen die im
// Info.plist deklarierten UTExportedTypeDeclarations — auch bei rein
// appinterner Nutzung ohne Interoperabilität mit anderen Apps (bekannter
// Gotcha, siehe CLAUDE.md, gefunden 2026-07-14 bei den beiden Vorgänger-
// UTTypes .feedivoFeedDragItem/.feedivoFolderDragItem).
extension UTType {
    static let feedivoFeedDragItem = UTType(exportedAs: "ch.martin.Feedivo.feed-drag-item")
    static let feedivoFolderDragItem = UTType(exportedAs: "ch.martin.Feedivo.folder-drag-item")
    static let feedivoTagDragItem = UTType(exportedAs: "ch.martin.Feedivo.tag-drag-item")
    static let feedivoSmartFolderDragItem = UTType(exportedAs: "ch.martin.Feedivo.smart-folder-drag-item")
}

extension NSPasteboard.PasteboardType {
    static let feedivoFeedDragItem = NSPasteboard.PasteboardType(UTType.feedivoFeedDragItem.identifier)
    static let feedivoFolderDragItem = NSPasteboard.PasteboardType(UTType.feedivoFolderDragItem.identifier)
    static let feedivoTagDragItem = NSPasteboard.PasteboardType(UTType.feedivoTagDragItem.identifier)
    static let feedivoSmartFolderDragItem = NSPasteboard.PasteboardType(UTType.feedivoSmartFolderDragItem.identifier)
}

/// NSPasteboardWriting-Objekte für die vier ziehbaren Sidebar-Knotentypen.
/// Jeder Typ schreibt ausschließlich seine eigene ID (bzw. den Ordnernamen)
/// als reinen String unter seinem dedizierten internen UTType — kein
/// Cross-App-Interop nötig, siehe Design-Spec „Nicht-Ziele".
final class SidebarFeedPasteboardItem: NSObject, NSPasteboardWriting {
    let feedID: String

    init(feedID: String) {
        self.feedID = feedID
    }

    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        [.feedivoFeedDragItem]
    }

    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        type == .feedivoFeedDragItem ? feedID : nil
    }
}

final class SidebarFolderPasteboardItem: NSObject, NSPasteboardWriting {
    let folderName: String

    init(folderName: String) {
        self.folderName = folderName
    }

    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        [.feedivoFolderDragItem]
    }

    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        type == .feedivoFolderDragItem ? folderName : nil
    }
}

final class SidebarTagPasteboardItem: NSObject, NSPasteboardWriting {
    let tagID: String

    init(tagID: String) {
        self.tagID = tagID
    }

    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        [.feedivoTagDragItem]
    }

    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        type == .feedivoTagDragItem ? tagID : nil
    }
}

final class SidebarSmartFolderPasteboardItem: NSObject, NSPasteboardWriting {
    let smartFolderID: String

    init(smartFolderID: String) {
        self.smartFolderID = smartFolderID
    }

    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        [.feedivoSmartFolderDragItem]
    }

    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        type == .feedivoSmartFolderDragItem ? smartFolderID : nil
    }
}
```

- [ ] **Step 4: `Info.plist` um die zwei neuen UTExportedTypeDeclarations ergänzen**

In `Feedivo/Info.plist`, im bestehenden `UTExportedTypeDeclarations`-Array (nach dem
`ch.martin.Feedivo.folder-drag-item`-Eintrag, vor dem schließenden `</array>`) zwei neue
`<dict>`-Einträge ergänzen:

```xml
		<dict>
			<key>UTTypeIdentifier</key>
			<string>ch.martin.Feedivo.tag-drag-item</string>
			<key>UTTypeDescription</key>
			<string>Feedivo Tag Drag Item</string>
			<key>UTTypeConformsTo</key>
			<array>
				<string>public.data</string>
			</array>
		</dict>
		<dict>
			<key>UTTypeIdentifier</key>
			<string>ch.martin.Feedivo.smart-folder-drag-item</string>
			<key>UTTypeDescription</key>
			<string>Feedivo Smart Folder Drag Item</string>
			<key>UTTypeConformsTo</key>
			<array>
				<string>public.data</string>
			</array>
		</dict>
```

- [ ] **Step 5: Tests erneut ausführen, PASS verifizieren**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SidebarOutlinePasteboardTests 2>&1 | tail -60`
Expected: Alle Tests PASS.

- [ ] **Step 6: Vollen Build verifizieren + Info.plist-Eintrag im gebauten Bundle prüfen**

Run: `xcodebuild build -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -40`
Expected: `BUILD SUCCEEDED`

Run (Pfad ggf. anpassen, DerivedData-Ordner ist nutzerspezifisch):
```bash
plutil -p "$(find ~/Library/Developer/Xcode/DerivedData -name "Feedivo.app" -path "*Debug*" 2>/dev/null | head -1)/Contents/Info.plist" | grep -A2 "tag-drag-item\|smart-folder-drag-item"
```
Expected: Beide neuen UTTypeIdentifier-Strings tauchen im tatsächlich gebauten Bundle auf
(nicht nur `BUILD SUCCEEDED` — bekannter Gotcha, dass `INFOPLIST_KEY_*`-Build-Settings
manche Einträge stillschweigend verwerfen können; hier wird aber die physische
`Info.plist`-Datei verwendet, dieser Check verifiziert trotzdem den Ist-Zustand).

- [ ] **Step 7: Commit**

```bash
git add Feedivo/Views/Sidebar/SidebarOutlinePasteboard.swift Feedivo/Info.plist FeedivoTests/SidebarOutlinePasteboardTests.swift
git commit -m "Feature: NSPasteboardWriting-Typen für Feed/Ordner/Tag/Smart-Folder-Drag"
```

---

## Task 4: SidebarOutlineView — DataSource, Zeilen-Rendering, Auswahl/Expansion (ohne Drag)

**Files:**
- Create: `Feedivo/Views/Sidebar/SidebarOutlineView.swift`
- Modify: `Feedivo/Views/Sidebar/SidebarView.swift` (Zeilen-Views aus dem `ForEach`-Kontext
  lösen, siehe Step 1)

**Interfaces:**
- Konsumiert: `SidebarOutlineNode`/`.buildTree`/`.find` (Task 2), `FeedRowView` (bestehend,
  `Feedivo/Views/Sidebar/FeedRowView.swift`), `SidebarSelection` (bestehend), `SidebarStyle`
  (bestehend, `Feedivo/Views/Sidebar/SidebarStyle.swift`).
- Produziert: `SidebarOutlineView` (`NSViewRepresentable`), `SidebarOutlineView.Coordinator`
  (`NSObject`, `NSOutlineViewDataSource`, `NSOutlineViewDelegate`). Öffentliche Closures:
  `renameFeed: (String, String) throws -> Void`, `renameFolder: (String, String) throws ->
  Void`, `onFeedContextAction: (SidebarFeedContextAction, FeedSidebarSnapshot) -> Void`,
  `onFolderContextAction: (SidebarFolderContextAction, String) -> Void`,
  `onSmartFolderContextAction: (SidebarSmartFolderContextAction, SQLiteSmartFolderSnapshot)
  -> Void`, `onTagsManageRequested: () -> Void`, `onCreateSmartFolderRequested: () -> Void`,
  `onCreateFolderRequested: () -> Void`. Dieser Task lässt Drag & Drop noch AUS
  (`pasteboardWriterForItem` liefert `nil`) — das kommt in Task 5.

Dieser Task ist bewusst groß (AppKit-Bridge-Kern), aber in sich abgeschlossen testbar:
Ergebnis ist eine vollständig funktionale, browsbare Sidebar OHNE Drag & Drop — bestehende
Interaktionen (Auswahl, Ein-/Ausklappen, Inline-Rename, Kontextmenüs) müssen danach schon
funktionieren.

- [ ] **Step 1: Extrahiere `SmartFolderSidebarRow` und `TagSidebarRow` als eigenständig
  instanziierbare Views**

Diese beiden Views existieren bereits als `private struct` in `SidebarView.swift:651-761`
und sind bereits eigenständig instanziierbar (keine Abhängigkeit vom umschließenden
`ForEach`-Kontext) — sie benötigen nur `smartFolder`/`badgeSnapshot`/`mixedCounts` bzw.
`tag`/`badgeText` als Parameter. Ändere lediglich ihre Sichtbarkeit von `private struct` zu
`struct` (ohne `private`), damit `SidebarOutlineView.swift` (eine andere Datei) sie
instanziieren kann:

In `Feedivo/Views/Sidebar/SidebarView.swift:651` und `:728`:
```swift
struct SmartFolderSidebarRow: View {
```
```swift
struct TagSidebarRow: View {
```

(Nur das `private`-Schlüsselwort entfernen, sonst nichts an diesen beiden Structs ändern.)

- [ ] **Step 2: Baue, um sicherzustellen, dass die Sichtbarkeitsänderung nichts bricht**

Run: `xcodebuild build -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -40`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: `SidebarOutlineView.swift` implementieren**

Neue Datei `Feedivo/Views/Sidebar/SidebarOutlineView.swift`:

```swift
import AppKit
import SwiftUI

enum SidebarFeedContextAction {
    case rename
    case showProperties
    case delete
}

enum SidebarFolderContextAction {
    case rename
    case delete
}

enum SidebarSmartFolderContextAction {
    case edit
    case duplicate
    case delete
}

/// NSViewRepresentable-Bridge, die die komplette Sidebar (Smart Folders,
/// Tags, Ordner/Feeds) als einzelne NSOutlineView rendert. Zeilen werden per
/// NSHostingView aus den unveränderten bestehenden SwiftUI-Row-Views gebaut
/// (FeedRowView, SidebarFolderSection-Header, CollapsibleSidebarSection-
/// Header, SmartFolderSidebarRow, TagSidebarRow) — siehe Design-Spec
/// „Zeilen-Rendering & Interaktion".
struct SidebarOutlineView: NSViewRepresentable {
    let rootNodes: [SidebarOutlineNode]

    @Binding var selection: SidebarSelection?
    @Binding var collapsedFolderNames: Set<String>
    @Binding var isSmartFoldersCollapsed: Bool
    @Binding var isCustomSmartFoldersCollapsed: Bool
    @Binding var isTagsCollapsed: Bool
    @Binding var isFoldersCollapsed: Bool

    let badgeSnapshot: SmartFolderSidebarBadgeSnapshot
    let mixedCountsByDefaultKey: [String: SmartFolderMixedCounts]

    let renameFeed: (_ id: String, _ newTitle: String) throws -> Void
    let renameFolder: (_ oldName: String, _ newName: String) throws -> Void
    let onFeedContextAction: (SidebarFeedContextAction, FeedSidebarSnapshot) -> Void
    let onFolderContextAction: (SidebarFolderContextAction, String) -> Void
    let onSmartFolderContextAction: (SidebarSmartFolderContextAction, SQLiteSmartFolderSnapshot) -> Void
    let onTagsManageRequested: () -> Void
    let onCreateSmartFolderRequested: () -> Void
    let onCreateFolderRequested: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let outlineView = NSOutlineView()
        outlineView.headerView = nil
        outlineView.style = .plain
        // Eigenes SwiftUI-gesteuertes Auswahl-Highlighting (siehe FeedRowView/
        // SidebarRowButtonStyle) — NSOutlineView verwaltet bewusst KEINE eigene
        // Zeilenauswahl, siehe Design-Spec „Zeilen-Rendering & Interaktion".
        outlineView.selectionHighlightStyle = .none
        outlineView.indentationPerLevel = 0
        outlineView.rowSizeStyle = .custom
        outlineView.backgroundColor = .clear
        outlineView.dataSource = context.coordinator
        outlineView.delegate = context.coordinator

        let column = NSTableColumn(identifier: .init("SidebarColumn"))
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column

        let scrollView = NSScrollView()
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = true

        context.coordinator.outlineView = outlineView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.reload()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        var parent: SidebarOutlineView
        weak var outlineView: NSOutlineView?
        private var previousRootNodeIDs: [String] = []

        init(parent: SidebarOutlineView) {
            self.parent = parent
        }

        /// Baut die Outline neu auf und stellt danach den Expansion-Zustand
        /// aus den @AppStorage-gespiegelten Bindings wieder her. Selektion
        /// bleibt unberührt — sie wird ausschließlich von den select()-
        /// Closures innerhalb der gehosteten SwiftUI-Row-Views gesetzt, nie
        /// von NSOutlineView selbst.
        func reload() {
            guard let outlineView else { return }

            outlineView.reloadData()
            restoreExpansionState()
        }

        private func restoreExpansionState() {
            guard let outlineView else { return }

            for header in parent.rootNodes {
                let shouldExpand: Bool
                switch header.payload {
                case .smartFoldersHeader(isDefault: true):
                    shouldExpand = !parent.isSmartFoldersCollapsed
                case .smartFoldersHeader(isDefault: false):
                    shouldExpand = !parent.isCustomSmartFoldersCollapsed
                case .tagsHeader:
                    shouldExpand = !parent.isTagsCollapsed
                case .foldersHeader:
                    shouldExpand = !parent.isFoldersCollapsed
                default:
                    shouldExpand = true
                }

                if shouldExpand {
                    outlineView.expandItem(header)
                } else {
                    outlineView.collapseItem(header)
                }

                if case .foldersHeader = header.payload {
                    for child in header.children {
                        guard case .folder(let name) = child.payload else { continue }
                        if parent.collapsedFolderNames.contains(name) {
                            outlineView.collapseItem(child)
                        } else {
                            outlineView.expandItem(child)
                        }
                    }
                }
            }
        }

        // MARK: - NSOutlineViewDataSource

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            guard let item else { return parent.rootNodes.count }
            return (item as? SidebarOutlineNode)?.children.count ?? 0
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            guard let item else { return parent.rootNodes[index] }
            guard let node = item as? SidebarOutlineNode else {
                preconditionFailure("Unerwarteter Item-Typ in SidebarOutlineView")
            }
            return node.children[index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            guard let node = item as? SidebarOutlineNode else { return false }
            return !node.children.isEmpty
        }

        // MARK: - NSOutlineViewDelegate

        func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
            // NSOutlineView verwaltet bewusst keine eigene Auswahl — siehe
            // Design-Spec „Zeilen-Rendering & Interaktion".
            false
        }

        func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
            guard let node = item as? SidebarOutlineNode else { return 30 }
            switch node.payload {
            case .feed:
                return 30
            case .smartFoldersHeader, .tagsHeader, .foldersHeader:
                return 24
            case .folder:
                return 24
            case .smartFolder, .tag:
                return 30
            case .emptyPlaceholder:
                return 28
            }
        }

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let node = item as? SidebarOutlineNode else { return nil }

            let identifier = NSUserInterfaceItemIdentifier("SidebarOutlineCell")
            let cellView: NSTableCellView
            let hostingView: NSHostingView<AnyView>

            if let reused = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView,
               let reusedHosting = reused.subviews.first as? NSHostingView<AnyView> {
                cellView = reused
                hostingView = reusedHosting
            } else {
                cellView = NSTableCellView()
                cellView.identifier = identifier
                hostingView = NSHostingView(rootView: AnyView(EmptyView()))
                hostingView.translatesAutoresizingMaskIntoConstraints = false
                cellView.addSubview(hostingView)
                NSLayoutConstraint.activate([
                    hostingView.leadingAnchor.constraint(equalTo: cellView.leadingAnchor),
                    hostingView.trailingAnchor.constraint(equalTo: cellView.trailingAnchor),
                    hostingView.topAnchor.constraint(equalTo: cellView.topAnchor),
                    hostingView.bottomAnchor.constraint(equalTo: cellView.bottomAnchor)
                ])
            }

            hostingView.rootView = AnyView(rowContent(for: node))
            return cellView
        }

        @ViewBuilder
        private func rowContent(for node: SidebarOutlineNode) -> some View {
            switch node.payload {
            case .smartFoldersHeader(let isDefault):
                sectionHeaderRow(
                    title: isDefault ? L10n.sidebarSmartFoldersSection : L10n.sidebarSmartFoldersCustomSection,
                    isCollapsed: isDefault ? parent.isSmartFoldersCollapsed : parent.isCustomSmartFoldersCollapsed,
                    actionSystemImage: isDefault ? nil : "plus",
                    action: isDefault ? nil : parent.onCreateSmartFolderRequested,
                    toggle: {
                        if isDefault {
                            parent.isSmartFoldersCollapsed.toggle()
                        } else {
                            parent.isCustomSmartFoldersCollapsed.toggle()
                        }
                    }
                )
            case .smartFolder(let smartFolder):
                Button {
                    parent.selection = .smartFolder(smartFolder.id)
                } label: {
                    SmartFolderSidebarRow(
                        smartFolder: smartFolder,
                        badgeSnapshot: parent.badgeSnapshot,
                        mixedCounts: smartFolder.defaultKey.flatMap { parent.mixedCountsByDefaultKey[$0] }
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(
                    SidebarRowButtonStyle(
                        isSelected: parent.selection == .smartFolder(smartFolder.id),
                        leadingIndent: 6,
                        rowHeight: 30
                    )
                )
                .contextMenu {
                    Button {
                        parent.onSmartFolderContextAction(.edit, smartFolder)
                    } label: {
                        Label(L10n.ruleEditButton, systemImage: "pencil")
                    }
                    Button {
                        parent.onSmartFolderContextAction(.duplicate, smartFolder)
                    } label: {
                        Label(L10n.commonDuplicate, systemImage: "plus.square.on.square")
                    }
                    Divider()
                    Button(role: .destructive) {
                        parent.onSmartFolderContextAction(.delete, smartFolder)
                    } label: {
                        Label(L10n.ruleDeleteButton, systemImage: "trash")
                    }
                }
            case .tagsHeader:
                sectionHeaderRow(
                    title: L10n.sidebarTagsSection,
                    isCollapsed: parent.isTagsCollapsed,
                    actionSystemImage: "tag",
                    action: parent.onTagsManageRequested,
                    toggle: { parent.isTagsCollapsed.toggle() }
                )
            case .tag(let tag):
                Button {
                    parent.selection = .tag(tag.id)
                } label: {
                    TagSidebarRow(tag: tag, badgeText: SidebarUnreadCount.badgeText(for: tag.articleCount))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(
                    SidebarRowButtonStyle(
                        isSelected: parent.selection == .tag(tag.id),
                        leadingIndent: 6,
                        rowHeight: 30
                    )
                )
            case .foldersHeader:
                sectionHeaderRow(
                    title: L10n.sidebarFoldersSection,
                    isCollapsed: parent.isFoldersCollapsed,
                    actionSystemImage: nil,
                    action: nil,
                    toggle: { parent.isFoldersCollapsed.toggle() }
                )
            case .folder(let name):
                SidebarOutlineFolderRow(
                    name: name,
                    isCollapsed: parent.collapsedFolderNames.contains(name),
                    toggle: { parent.collapsedFolderNames.formSymmetricDifference([name]) },
                    renameFolder: { newName in try parent.renameFolder(name, newName) },
                    deleteFolder: { parent.onFolderContextAction(.delete, name) }
                )
            case .feed(let snapshot):
                feedRow(snapshot: snapshot, isIndented: snapshot.folderName != nil)
            case .emptyPlaceholder(let text):
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(SidebarStyle.secondaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
        }

        @ViewBuilder
        private func sectionHeaderRow(
            title: LocalizedStringKey,
            isCollapsed: Bool,
            actionSystemImage: String?,
            action: (() -> Void)?,
            toggle: @escaping () -> Void
        ) -> some View {
            HStack {
                Button(action: toggle) {
                    HStack(spacing: 7) {
                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 12)
                        Text(title)
                            .font(.system(size: 11, weight: .bold))
                            .textCase(.uppercase)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                if let actionSystemImage, let action {
                    Button(action: action) {
                        Image(systemName: actionSystemImage)
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                }
            }
            .foregroundStyle(SidebarStyle.sectionText)
            .padding(.horizontal, 10)
        }

        @ViewBuilder
        private func feedRow(snapshot: FeedSidebarSnapshot, isIndented: Bool) -> some View {
            FeedRowView(
                snapshot: snapshot,
                displayStyle: isIndented ? .folderChild : .regular,
                isSelected: parent.selection == .feed(snapshot.id),
                select: { parent.selection = .feed(snapshot.id) },
                renameFeed: { newName in
                    try parent.renameFeed(snapshot.id, newName)
                }
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .contextMenu {
                Button {
                    parent.onFeedContextAction(.rename, snapshot)
                } label: {
                    Label(L10n.feedRenameCommand, systemImage: "pencil")
                }
                Button {
                    parent.onFeedContextAction(.showProperties, snapshot)
                } label: {
                    Label(L10n.feedPropertiesCommand, systemImage: "info.circle")
                }
                Divider()
                Button(role: .destructive) {
                    parent.onFeedContextAction(.delete, snapshot)
                } label: {
                    Label(L10n.feedDeleteCommand, systemImage: "trash")
                }
            }
        }
    }
}

/// Eigenständige View statt reiner @ViewBuilder-Methode, da Inline-Rename
/// lokalen @State/@FocusState braucht — analog zu FeedRowView.
private struct SidebarOutlineFolderRow: View {
    let name: String
    let isCollapsed: Bool
    let toggle: () -> Void
    let renameFolder: (String) throws -> Void
    let deleteFolder: () -> Void

    @State private var isEditingName = false
    @State private var editedName = ""
    @State private var renameErrorMessage: String?
    @FocusState private var isNameFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 9) {
                Button(action: toggle) {
                    HStack(spacing: 9) {
                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(SidebarStyle.secondaryText)
                            .frame(width: 12)
                        Image(systemName: "folder")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 20)
                    }
                }
                .buttonStyle(.plain)

                if isEditingName {
                    TextField(name, text: $editedName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, weight: .medium))
                        .focused($isNameFieldFocused)
                        .overlay {
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(renameErrorMessage != nil ? Color.red : Color.clear, lineWidth: 1)
                        }
                        .onSubmit { commitOrShowError() }
                        .onExitCommand { cancelEditing() }
                        .onChange(of: isNameFieldFocused) { wasFocused, isFocused in
                            if wasFocused, !isFocused, isEditingName {
                                commitOrShowError()
                            }
                        }
                } else {
                    Text(name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(SidebarStyle.primaryText.opacity(0.82))
                        .lineLimit(1)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { beginEditing() }
                        .onTapGesture(count: 1) { toggle() }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .contextMenu {
                Button {
                    beginEditing()
                } label: {
                    Label(L10n.sidebarFolderRenameCommand, systemImage: "pencil")
                }
                Button(role: .destructive) {
                    deleteFolder()
                } label: {
                    Label(L10n.commonDelete, systemImage: "trash")
                }
            }

            if let renameErrorMessage {
                Text(renameErrorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .padding(.leading, 16 + 12 + 9 + 20 + 9)
                    .padding(.trailing, 16)
            }
        }
    }

    private func beginEditing() {
        editedName = name
        renameErrorMessage = nil
        isEditingName = true
        isNameFieldFocused = true
    }

    private func cancelEditing() {
        editedName = name
        renameErrorMessage = nil
        isEditingName = false
    }

    private func commitOrShowError() {
        let trimmedName = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName != name else {
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

Hinweis: `sidebarActionRow`, Sheets (`.sheet`, `.confirmationDialog`) und die Bau-Logik des
Baums (`SidebarOutlineNode.buildTree`) bleiben Aufgabe von `SidebarView.swift` — dieser Task
liefert nur die Bridge-Komponente selbst, die Integration folgt in Task 6.
`SidebarOutlineFolderRow` (mit vollem Inline-Rename) wird hier bereits direkt eingebaut,
nicht erst nachträglich in Task 6 — das erspart einen Zwischenschritt ohne Ordner-Rename.

- [ ] **Step 4: Build verifizieren**

Run: `xcodebuild build -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -60`
Expected: `BUILD SUCCEEDED`. Falls Fehler zu fehlenden `EmptyView`/`AnyView`-Typkonflikten
oder Signatur-Abweichungen auftreten (SourceKit-Diagnosen in der IDE ignorieren, siehe
Global Constraints): gezielt an der gemeldeten Zeile reparieren, kein Redesign.

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Views/Sidebar/SidebarOutlineView.swift Feedivo/Views/Sidebar/SidebarView.swift
git commit -m "Feature: SidebarOutlineView (NSOutlineView-Bridge, DataSource + Rendering ohne Drag)"
```

---

## Task 5: Drag & Drop-Wiring in SidebarOutlineView

**Files:**
- Modify: `Feedivo/Views/Sidebar/SidebarOutlineView.swift`
- Test: `FeedivoTests/SidebarOutlineDropPolicyTests.swift`

**Interfaces:**
- Konsumiert: `SidebarOutlineNode`/`.find` (Task 2), `SidebarFeedPasteboardItem` /
  `SidebarFolderPasteboardItem` / `SidebarTagPasteboardItem` /
  `SidebarSmartFolderPasteboardItem` (Task 3).
- Produziert: `SidebarOutlineDropTarget` (Enum), `SidebarOutlineDropPolicy.resolve(...)`
  (reine, testbare Entscheidungsfunktion ohne AppKit-Typen), zusätzliche Closures auf
  `SidebarOutlineView`: `moveFeed: (String, String?, Int) -> Void`, `moveFolder: (String,
  Int) -> Void`, `moveTag: (String, Int) -> Void`, `moveSmartFolder: (String, Int, Bool) ->
  Void` (letzter Parameter `isDefault`, um innerhalb der richtigen Gruppe zu bleiben).

- [ ] **Step 1: Schreibe die fehlschlagenden Tests für die reine Drop-Entscheidungslogik**

Neue Datei `FeedivoTests/SidebarOutlineDropPolicyTests.swift`:

```swift
import Foundation
import Testing
@testable import Feedivo

struct SidebarOutlineDropPolicyTests {
    private func makeFeed(id: String, folderName: String?) -> FeedSidebarSnapshot {
        FeedSidebarSnapshot(
            id: id, title: id, url: "https://example.com/\(id).xml",
            faviconURL: nil, folderName: folderName, sortIndex: 0,
            unreadCount: 0, hasRecentError: false
        )
    }

    @Test func feedAufOrdnerGezogenLiefertZielOrdnerUndEndeAlsIndex() {
        let nodes = SidebarOutlineNode.buildTree(
            feedSnapshots: [makeFeed(id: "feed-1", folderName: nil), makeFeed(id: "feed-2", folderName: "News")],
            feedFolders: [FeedFolderRecord(id: "f1", name: "News", sortIndex: 0)],
            tagSnapshots: [], smartFolderSnapshots: []
        )
        let foldersHeader = nodes.first { $0.id == "header.folders" }!
        let folderNode = foldersHeader.children.first { $0.id == "folder:News" }!

        let result = SidebarOutlineDropPolicy.resolve(
            draggedNodeID: "feed:feed-1",
            proposedParent: folderNode,
            proposedChildIndex: NSOutlineViewDropOnItemIndex,
            rootNodes: nodes
        )

        #expect(result == .feedDrop(folderName: "News", targetIndex: 1))
    }

    @Test func feedInnerhalbOrdnerlosemBereichUmsortierenBerechnetKorrektenIndex() {
        let nodes = SidebarOutlineNode.buildTree(
            feedSnapshots: [
                makeFeed(id: "feed-1", folderName: nil),
                makeFeed(id: "feed-2", folderName: nil),
                makeFeed(id: "feed-3", folderName: nil)
            ],
            feedFolders: [], tagSnapshots: [], smartFolderSnapshots: []
        )
        let foldersHeader = nodes.first { $0.id == "header.folders" }!

        // feed-3 wird an Position 0 gezogen (vor feed-1)
        let result = SidebarOutlineDropPolicy.resolve(
            draggedNodeID: "feed:feed-3",
            proposedParent: foldersHeader,
            proposedChildIndex: 0,
            rootNodes: nodes
        )

        #expect(result == .feedDrop(folderName: nil, targetIndex: 0))
    }

    @Test func ordnerKannNurUnterFoldersHeaderUmsortiertWerden() {
        let nodes = SidebarOutlineNode.buildTree(
            feedSnapshots: [],
            feedFolders: [
                FeedFolderRecord(id: "f1", name: "Alpha", sortIndex: 0),
                FeedFolderRecord(id: "f2", name: "Bravo", sortIndex: 1)
            ],
            tagSnapshots: [], smartFolderSnapshots: []
        )
        let foldersHeader = nodes.first { $0.id == "header.folders" }!

        let result = SidebarOutlineDropPolicy.resolve(
            draggedNodeID: "folder:Bravo",
            proposedParent: foldersHeader,
            proposedChildIndex: 0,
            rootNodes: nodes
        )

        #expect(result == .folderReorder(targetIndex: 0))
    }

    @Test func tagKannNurUnterTagsHeaderUmsortiertWerden() {
        let nodes = SidebarOutlineNode.buildTree(
            feedSnapshots: [], feedFolders: [],
            tagSnapshots: [
                TagSidebarSnapshot(id: "tag-a", name: "Alpha", colorHex: "#000", articleCount: 0),
                TagSidebarSnapshot(id: "tag-b", name: "Bravo", colorHex: "#000", articleCount: 0)
            ],
            smartFolderSnapshots: []
        )
        let tagsHeader = nodes.first { $0.id == "header.tags" }!

        let result = SidebarOutlineDropPolicy.resolve(
            draggedNodeID: "tag:tag-b",
            proposedParent: tagsHeader,
            proposedChildIndex: 0,
            rootNodes: nodes
        )

        #expect(result == .tagReorder(targetIndex: 0))
    }

    @Test func smartFolderKannNichtUeberGruppengrenzeGezogenWerden() {
        let defaultFolder = SQLiteSmartFolderSnapshot(id: "sf-default", name: "Alle", matchMode: .all, conditions: [], defaultKey: "all")
        let customFolder = SQLiteSmartFolderSnapshot(id: "sf-custom", name: "Meine", matchMode: .all, conditions: [], defaultKey: nil)
        let nodes = SidebarOutlineNode.buildTree(
            feedSnapshots: [], feedFolders: [], tagSnapshots: [],
            smartFolderSnapshots: [defaultFolder, customFolder]
        )
        let customHeader = nodes.first { $0.id == "header.smartFolders.custom" }!

        // Standard-Smart-Folder wird auf die "Eigene"-Gruppe fallen gelassen — muss abgelehnt werden.
        let result = SidebarOutlineDropPolicy.resolve(
            draggedNodeID: "smartFolder:sf-default",
            proposedParent: customHeader,
            proposedChildIndex: 0,
            rootNodes: nodes
        )

        #expect(result == nil)
    }

    @Test func smartFolderInnerhalbEigenerGruppeUmsortierenIstErlaubt() {
        let folderA = SQLiteSmartFolderSnapshot(id: "sf-a", name: "A", matchMode: .all, conditions: [], defaultKey: nil)
        let folderB = SQLiteSmartFolderSnapshot(id: "sf-b", name: "B", matchMode: .all, conditions: [], defaultKey: nil)
        let nodes = SidebarOutlineNode.buildTree(
            feedSnapshots: [], feedFolders: [], tagSnapshots: [],
            smartFolderSnapshots: [folderA, folderB]
        )
        let customHeader = nodes.first { $0.id == "header.smartFolders.custom" }!

        let result = SidebarOutlineDropPolicy.resolve(
            draggedNodeID: "smartFolder:sf-b",
            proposedParent: customHeader,
            proposedChildIndex: 0,
            rootNodes: nodes
        )

        #expect(result == .smartFolderReorder(isDefault: false, targetIndex: 0))
    }

    @Test func feedKannNichtInDieTagsHeaderGezogenWerden() {
        let nodes = SidebarOutlineNode.buildTree(
            feedSnapshots: [makeFeed(id: "feed-1", folderName: nil)],
            feedFolders: [], tagSnapshots: [], smartFolderSnapshots: []
        )
        let tagsHeader = nodes.first { $0.id == "header.tags" }!

        let result = SidebarOutlineDropPolicy.resolve(
            draggedNodeID: "feed:feed-1",
            proposedParent: tagsHeader,
            proposedChildIndex: 0,
            rootNodes: nodes
        )

        #expect(result == nil)
    }
}
```

- [ ] **Step 2: Tests ausführen, Scheitern verifizieren**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SidebarOutlineDropPolicyTests 2>&1 | tail -60`
Expected: FAIL — `SidebarOutlineDropPolicy`/`SidebarOutlineDropTarget` existieren noch
nicht.

- [ ] **Step 3: `SidebarOutlineDropTarget` + `SidebarOutlineDropPolicy` implementieren**

Am Ende von `Feedivo/Views/Sidebar/SidebarOutlineView.swift` ergänzen (als eigenständige
Top-Level-Deklarationen, nach `SidebarOutlineFolderRow`):

```swift
enum SidebarOutlineDropTarget: Equatable {
    case feedDrop(folderName: String?, targetIndex: Int)
    case folderReorder(targetIndex: Int)
    case tagReorder(targetIndex: Int)
    case smartFolderReorder(isDefault: Bool, targetIndex: Int)
}

/// Reine, AppKit-unabhängige Entscheidungslogik: übersetzt einen
/// vorgeschlagenen Drop (gezogener Knoten + Zielelternknoten + Zielindex)
/// in eine der vier erlaubten Aktionen — oder nil, falls der Drop laut den
/// Scoping-Regeln aus der Design-Spec nicht erlaubt ist. Die eigentlichen
/// NSOutlineViewDelegate-Methoden (validateDrop/acceptDrop) sind dünne
/// Wrapper darum, die nur zwischen NSOutlineView-Typen und diesen reinen
/// Swift-Werten übersetzen.
enum SidebarOutlineDropPolicy {
    static func resolve(
        draggedNodeID: String,
        proposedParent: SidebarOutlineNode?,
        proposedChildIndex: Int,
        rootNodes: [SidebarOutlineNode]
    ) -> SidebarOutlineDropTarget? {
        guard let draggedNode = SidebarOutlineNode.find(id: draggedNodeID, in: rootNodes) else {
            return nil
        }

        switch draggedNode.payload {
        case .feed:
            return resolveFeedDrop(
                draggedNode: draggedNode,
                proposedParent: proposedParent,
                proposedChildIndex: proposedChildIndex
            )
        case .folder:
            guard let foldersHeader = rootNodes.first(where: { $0.id == "header.folders" }),
                  proposedParent?.id == "header.folders"
            else {
                return nil
            }
            let index = clampedIndex(proposedChildIndex, siblingCount: foldersHeader.children.count, draggedID: draggedNode.id, siblings: foldersHeader.children)
            return .folderReorder(targetIndex: index)
        case .tag:
            guard let tagsHeader = rootNodes.first(where: { $0.id == "header.tags" }),
                  proposedParent?.id == "header.tags"
            else {
                return nil
            }
            let index = clampedIndex(proposedChildIndex, siblingCount: tagsHeader.children.count, draggedID: draggedNode.id, siblings: tagsHeader.children)
            return .tagReorder(targetIndex: index)
        case .smartFolder:
            guard let proposedParent,
                  proposedParent.id == "header.smartFolders.default" || proposedParent.id == "header.smartFolders.custom"
            else {
                return nil
            }
            // Ein Standard-Smart-Folder darf nur innerhalb der Standard-
            // Gruppe bleiben, ein eigener nur innerhalb der Eigene-Gruppe —
            // ermittelt über den Elternknoten, in dem der gezogene Knoten
            // tatsächlich aktuell steckt.
            guard let currentParent = parent(of: draggedNode, in: rootNodes),
                  currentParent.id == proposedParent.id
            else {
                return nil
            }
            let isDefault = proposedParent.id == "header.smartFolders.default"
            let index = clampedIndex(proposedChildIndex, siblingCount: proposedParent.children.count, draggedID: draggedNode.id, siblings: proposedParent.children)
            return .smartFolderReorder(isDefault: isDefault, targetIndex: index)
        default:
            return nil
        }
    }

    private static func resolveFeedDrop(
        draggedNode: SidebarOutlineNode,
        proposedParent: SidebarOutlineNode?,
        proposedChildIndex: Int
    ) -> SidebarOutlineDropTarget? {
        guard case .feed = draggedNode.payload else { return nil }
        guard let proposedParent else { return nil }

        // Drop "auf" einen Ordner-Knoten (NSOutlineViewDropOnItemIndex): ans
        // Ende des Ordners anhängen.
        if case .folder(let name) = proposedParent.payload, proposedChildIndex == NSOutlineViewDropOnItemIndex {
            return .feedDrop(folderName: name, targetIndex: proposedParent.children.count)
        }

        // Drop innerhalb des ordnerlosen Bereichs (proposedParent ==
        // foldersHeader) oder innerhalb eines Ordners (proposedParent ist
        // die Ordner-Zeile selbst) an einem konkreten Index.
        if proposedParent.id == "header.folders" {
            let index = clampedIndex(proposedChildIndex, siblingCount: proposedParent.children.count, draggedID: draggedNode.id, siblings: proposedParent.children)
            return .feedDrop(folderName: nil, targetIndex: index)
        }
        if case .folder(let name) = proposedParent.payload {
            let index = clampedIndex(proposedChildIndex, siblingCount: proposedParent.children.count, draggedID: draggedNode.id, siblings: proposedParent.children)
            return .feedDrop(folderName: name, targetIndex: index)
        }

        return nil
    }

    /// Findet den direkten Elternknoten von `target` im Baum (nil, falls
    /// `target` ein Wurzelknoten ist oder nicht gefunden wurde).
    private static func parent(of target: SidebarOutlineNode, in nodes: [SidebarOutlineNode]) -> SidebarOutlineNode? {
        for node in nodes {
            if node.children.contains(where: { $0.id == target.id }) {
                return node
            }
            if let found = parent(of: target, in: node.children) {
                return found
            }
        }
        return nil
    }

    /// Klemmt den vorgeschlagenen Index auf den gültigen Bereich und
    /// korrigiert ihn um eins, falls der gezogene Knoten selbst vor dem
    /// Zielindex in derselben Geschwisterliste steht (analog zur
    /// bestehenden Logik in SidebarView.swift vor dieser Migration).
    private static func clampedIndex(
        _ proposedIndex: Int,
        siblingCount: Int,
        draggedID: String,
        siblings: [SidebarOutlineNode]
    ) -> Int {
        var index = proposedIndex == NSOutlineViewDropOnItemIndex ? siblingCount : proposedIndex
        index = min(max(index, 0), siblingCount)
        if let draggedIndex = siblings.firstIndex(where: { $0.id == draggedID }), draggedIndex < index {
            index -= 1
        }
        return index
    }
}
```

- [ ] **Step 4: Tests erneut ausführen, PASS verifizieren**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SidebarOutlineDropPolicyTests 2>&1 | tail -80`
Expected: Alle Tests PASS. Bei Fehlschlägen: Logik in `resolve`/`resolveFeedDrop`/
`clampedIndex` gezielt an den fehlschlagenden Testfällen nachziehen — nicht die Tests
ans (falsche) Verhalten anpassen.

- [ ] **Step 5: NSOutlineViewDataSource/-Delegate um Drag-&-Drop-Methoden ergänzen**

In `SidebarOutlineView.Coordinator` (in `Feedivo/Views/Sidebar/SidebarOutlineView.swift`)
folgende Methoden ergänzen sowie in `makeNSView` die Registrierung der Drag-Typen.

In `makeNSView(context:)`, direkt nach `outlineView.delegate = context.coordinator`
einfügen:
```swift
        outlineView.registerForDraggedTypes([
            .feedivoFeedDragItem,
            .feedivoFolderDragItem,
            .feedivoTagDragItem,
            .feedivoSmartFolderDragItem
        ])
        outlineView.setDraggingSourceOperationMask(.move, forLocal: true)
```

Neue Closures auf `SidebarOutlineView` selbst ergänzen (bei den bereits bestehenden
`let renameFeed: ...` usw.):
```swift
    let moveFeed: (_ id: String, _ toFolderName: String?, _ targetIndex: Int) -> Void
    let moveFolder: (_ name: String, _ targetIndex: Int) -> Void
    let moveTag: (_ id: String, _ targetIndex: Int) -> Void
    let moveSmartFolder: (_ id: String, _ targetIndex: Int, _ isDefault: Bool) -> Void
```

Im `Coordinator` folgende Methoden ergänzen (nach den bestehenden
`NSOutlineViewDelegate`-Methoden):

```swift
        // MARK: - Drag & Drop

        func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
            guard let node = item as? SidebarOutlineNode, node.isDraggable else { return nil }

            switch node.payload {
            case .feed(let snapshot):
                return SidebarFeedPasteboardItem(feedID: snapshot.id)
            case .folder(let name):
                return SidebarFolderPasteboardItem(folderName: name)
            case .tag(let tag):
                return SidebarTagPasteboardItem(tagID: tag.id)
            case .smartFolder(let folder):
                return SidebarSmartFolderPasteboardItem(smartFolderID: folder.id)
            default:
                return nil
            }
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            validateDrop info: NSDraggingInfo,
            proposedItem item: Any?,
            proposedChildIndex index: Int
        ) -> NSDragOperation {
            resolveDropTarget(info: info, proposedItem: item, proposedChildIndex: index) == nil ? [] : .move
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            acceptDrop info: NSDraggingInfo,
            item: Any?,
            childIndex index: Int
        ) -> Bool {
            guard let target = resolveDropTarget(info: info, proposedItem: item, proposedChildIndex: index) else {
                return false
            }

            switch target {
            case .feedDrop(let folderName, let targetIndex):
                guard let feedID = draggedID(from: info, type: .feedivoFeedDragItem) else { return false }
                parent.moveFeed(feedID, folderName, targetIndex)
            case .folderReorder(let targetIndex):
                guard let folderName = draggedID(from: info, type: .feedivoFolderDragItem) else { return false }
                parent.moveFolder(folderName, targetIndex)
            case .tagReorder(let targetIndex):
                guard let tagID = draggedID(from: info, type: .feedivoTagDragItem) else { return false }
                parent.moveTag(tagID, targetIndex)
            case .smartFolderReorder(let isDefault, let targetIndex):
                guard let smartFolderID = draggedID(from: info, type: .feedivoSmartFolderDragItem) else { return false }
                parent.moveSmartFolder(smartFolderID, targetIndex, isDefault)
            }
            return true
        }

        private func draggedID(from info: NSDraggingInfo, type: NSPasteboard.PasteboardType) -> String? {
            info.draggingPasteboard.string(forType: type)
        }

        private func resolveDropTarget(
            info: NSDraggingInfo,
            proposedItem item: Any?,
            proposedChildIndex index: Int
        ) -> SidebarOutlineDropTarget? {
            let proposedParent = item as? SidebarOutlineNode

            let draggedNodeID: String?
            if let feedID = draggedID(from: info, type: .feedivoFeedDragItem) {
                draggedNodeID = "feed:\(feedID)"
            } else if let folderName = draggedID(from: info, type: .feedivoFolderDragItem) {
                draggedNodeID = "folder:\(folderName)"
            } else if let tagID = draggedID(from: info, type: .feedivoTagDragItem) {
                draggedNodeID = "tag:\(tagID)"
            } else if let smartFolderID = draggedID(from: info, type: .feedivoSmartFolderDragItem) {
                draggedNodeID = "smartFolder:\(smartFolderID)"
            } else {
                draggedNodeID = nil
            }

            guard let draggedNodeID else { return nil }

            return SidebarOutlineDropPolicy.resolve(
                draggedNodeID: draggedNodeID,
                proposedParent: proposedParent,
                proposedChildIndex: index,
                rootNodes: parent.rootNodes
            )
        }
```

- [ ] **Step 6: Build verifizieren**

Run: `xcodebuild build -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -60`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 7: Commit**

```bash
git add Feedivo/Views/Sidebar/SidebarOutlineView.swift FeedivoTests/SidebarOutlineDropPolicyTests.swift
git commit -m "Feature: Drag & Drop-Wiring für SidebarOutlineView (validateDrop/acceptDrop)"
```

---

## Task 6: Integration in SidebarView.swift + Aufräumen + Verifikation

**Files:**
- Modify: `Feedivo/Views/Sidebar/SidebarView.swift`
- Delete: `Feedivo/Views/Sidebar/SidebarDragAndDrop.swift`
- Delete: `FeedivoTests/SidebarDragAndDropTests.swift`

**Interfaces:**
- Konsumiert: `SidebarOutlineView` (Task 4+5), `SidebarOutlineNode.buildTree` (Task 2),
  `TagStore.move` (Task 1), `SQLiteSmartFolderStore.move(id:toPositionOf:)` (bestehend,
  `Feedivo/Stores/SQLiteSmartFolderStore.swift:110`).
- Produziert: Kein neues öffentliches Interface — reine Integration.

- [ ] **Step 1: `SidebarView.body` auf `SidebarOutlineView` umstellen**

In `Feedivo/Views/Sidebar/SidebarView.swift`, den Block von `defaultSmartFoldersSection(...)`
bis `foldersSection` (aktuell Zeilen 64–73) ersetzen durch einen einzelnen
`SidebarOutlineView`-Aufruf. Vorher (zu entfernen):

```swift
                    defaultSmartFoldersSection(
                        badgeSnapshot: sqliteSidebarState.smartFolderBadgeSnapshot,
                        mixedCountsByDefaultKey: sqliteSidebarState.mixedCountsByDefaultKey
                    )
                    customSmartFoldersSection(
                        badgeSnapshot: sqliteSidebarState.smartFolderBadgeSnapshot,
                        mixedCountsByDefaultKey: sqliteSidebarState.mixedCountsByDefaultKey
                    )
                    tagsSection
                    foldersSection
```

Nachher:

```swift
                    SidebarOutlineView(
                        rootNodes: SidebarOutlineNode.buildTree(
                            feedSnapshots: sqliteSidebarState.snapshots,
                            feedFolders: sqliteSidebarState.feedFolders,
                            tagSnapshots: sqliteSidebarState.tagSnapshots,
                            smartFolderSnapshots: sqliteSidebarState.smartFolderSnapshots
                        ),
                        selection: $selection,
                        collapsedFolderNames: $collapsedFolderNames,
                        isSmartFoldersCollapsed: $isSmartFoldersCollapsed,
                        isCustomSmartFoldersCollapsed: $isCustomSmartFoldersCollapsed,
                        isTagsCollapsed: $isTagsCollapsed,
                        isFoldersCollapsed: $isFoldersCollapsed,
                        badgeSnapshot: sqliteSidebarState.smartFolderBadgeSnapshot,
                        mixedCountsByDefaultKey: sqliteSidebarState.mixedCountsByDefaultKey,
                        renameFeed: { id, newName in try renameFeed(id: id, to: newName) },
                        renameFolder: { oldName, newName in try renameFolder(from: oldName, to: newName) },
                        onFeedContextAction: { action, snapshot in
                            switch action {
                            case .rename: feedRenaming = snapshot
                            case .showProperties: feedShowingProperties = snapshot
                            case .delete: onRequestDeleteFeed(snapshot.id)
                            }
                        },
                        onFolderContextAction: { action, name in
                            switch action {
                            case .rename:
                                break // Inline-Rename läuft direkt in SidebarOutlineFolderRow; kein Dialog nötig.
                            case .delete:
                                if let folder = explicitFeedFolder(named: name) {
                                    feedFolderPendingDeletion = folder
                                }
                            }
                        },
                        onSmartFolderContextAction: { action, smartFolder in
                            switch action {
                            case .edit: smartFolderEditing = sqliteSmartFolderRecord(id: smartFolder.id)
                            case .duplicate: duplicateSmartFolder(smartFolder)
                            case .delete: smartFolderPendingDeletion = smartFolder
                            }
                        },
                        onTagsManageRequested: { isShowingTagManager = true },
                        onCreateSmartFolderRequested: { isCreatingSmartFolder = true },
                        onCreateFolderRequested: { isShowingAddFolderSheet = true },
                        moveFeed: { id, folderName, targetIndex in moveFeed(id: id, toFolderName: folderName, targetIndex: targetIndex) },
                        moveFolder: { name, targetIndex in moveFolder(name: name, targetIndex: targetIndex) },
                        moveTag: { id, targetIndex in moveTag(id: id, targetIndex: targetIndex) },
                        moveSmartFolder: { id, targetIndex, isDefault in moveSmartFolder(id: id, targetIndex: targetIndex, isDefault: isDefault) }
                    )
                    .frame(minHeight: 200)
```

- [ ] **Step 2: Ergänze `moveTag`/`moveSmartFolder` als private Methoden in SidebarView**

In `Feedivo/Views/Sidebar/SidebarView.swift`, direkt nach der bestehenden `moveFolder(name:
targetIndex:)`-Methode (Zeile ~624) einfügen. Zuerst prüfen, ob eine `subscript(safe:)`-
Extension existiert:

Run: `grep -rn "subscript(safe" Feedivo/Extensions/`

Falls sie NICHT existiert (erwarteter Fall), folgenden Code mit manuellem Bounds-Check
einfügen:

```swift
    private func moveTag(id: String, targetIndex: Int) {
        guard let database = feedivoDatabase else { return }
        try? TagStore(database: database).move(id: id, targetIndex: targetIndex)
        SQLiteDataInvalidation.bumpStatusVersion()
    }

    private func moveSmartFolder(id: String, targetIndex: Int, isDefault: Bool) {
        guard let database = feedivoDatabase else { return }

        do {
            let folders = isDefault
                ? SmartFolderSidebarGrouping.defaultFolders(from: sqliteSidebarState.smartFolderSnapshots)
                : SmartFolderSidebarGrouping.customFolders(from: sqliteSidebarState.smartFolderSnapshots)
            let clampedIndex = min(max(targetIndex, 0), max(folders.count - 1, 0))
            guard clampedIndex >= 0, clampedIndex < folders.count else { return }
            let targetFolder = folders[clampedIndex]
            guard targetFolder.id != id else { return }
            try SQLiteSmartFolderStore(database: database).move(id: id, toPositionOf: targetFolder.id)
        } catch {
            AppLogger.dataAccess.error("moveSmartFolder fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
        }
        SQLiteDataInvalidation.bumpStatusVersion()
        sidebarDefinitionVersion += 1
    }
```

(`SQLiteSmartFolderStore.move(id:toPositionOf:)` erwartet eine Ziel-ID, nicht einen Index —
siehe `Feedivo/Stores/SQLiteSmartFolderStore.swift:110` — deshalb hier die Umrechnung von
Index auf die ID des aktuell an dieser Position stehenden Ordners.)

- [ ] **Step 3: Alte Sektions-Funktionen und `SidebarDragAndDrop.swift` entfernen**

In `Feedivo/Views/Sidebar/SidebarView.swift` folgende jetzt unbenutzte private
Funktionen/Structs entfernen: `tagsSection` (Zeile ~205-218), `foldersSection` (Zeile
~220-312), `unassignedFeedsHeader` (Zeile ~314-330), `defaultSmartFoldersSection` (Zeile
~332-352), `customSmartFoldersSection` (Zeile ~354-378), `smartFolderRows` (Zeile
~380-426), `feedRows` (Zeile ~438-496), `tagRows` (Zeile ~498-517), `toggleFolder` (Zeile
~519-527), `SidebarFolderSection` (Zeile ~822-971, jetzt durch `SidebarOutlineFolderRow`
aus Task 4 ersetzt). Vor dem Löschen jeweils mit `grep -n "<Funktionsname>"
Feedivo/Views/Sidebar/*.swift FeedivoTests/*.swift` verifizieren, dass keine andere Stelle
sie noch referenziert.

Datei löschen: `Feedivo/Views/Sidebar/SidebarDragAndDrop.swift` (Inhalt vollständig durch
`SidebarOutlinePasteboard.swift` aus Task 3 ersetzt).

Datei löschen: `FeedivoTests/SidebarDragAndDropTests.swift` (testete ausschließlich
`DropInsertionSide`, das mit `SidebarDragAndDrop.swift` entfällt — die Nachfolgelogik ist
bereits in `SidebarOutlineDropPolicyTests.swift` aus Task 5 abgedeckt).

```bash
git rm Feedivo/Views/Sidebar/SidebarDragAndDrop.swift FeedivoTests/SidebarDragAndDropTests.swift
```

- [ ] **Step 4: Build verifizieren**

Run: `xcodebuild build -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -80`
Expected: `BUILD SUCCEEDED`. Verbleibende Compile-Fehler sind an dieser Stelle erwartbar
(z. B. übersehene Referenz auf eine gelöschte Funktion) — gezielt an der gemeldeten Zeile
beheben, nicht großflächig umbauen.

- [ ] **Step 5: Relevante Test-Suiten laufen lassen**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SidebarOutlineNodeTests -only-testing:FeedivoTests/SidebarOutlinePasteboardTests -only-testing:FeedivoTests/SidebarOutlineDropPolicyTests -only-testing:FeedivoTests/SQLiteTagStoreTests -only-testing:FeedivoTests/FeedFolderStoreTests -only-testing:FeedivoTests/SQLiteSidebarStateTests -only-testing:FeedivoTests/SmartFolderSidebarGroupingTests 2>&1 | tail -100`
Expected: Alle PASS. (Nicht die volle Suite ohne `-only-testing` — hängt reproduzierbar,
siehe Global Constraints.)

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Refactor: Sidebar vollständig auf NSOutlineView umgestellt, alte SwiftUI-Drag-Implementierung entfernt"
```

- [ ] **Step 7: Manuelles Live-Verifikationsprotokoll (NICHT automatisierbar — vom Nutzer
  auszuführen)**

Die App bauen und im Debug-Modus starten, dann **jeden** der folgenden Fälle **mehrfach
wiederholt** live testen (aus dem Design-Spec-Verifikationsplan übernommen):

1. Feed auf einen Ordner ziehen
2. Feed auf den ordnerlosen Bereich ziehen
3. Feed innerhalb eines Ordners umsortieren
4. Feed innerhalb des ordnerlosen Bereichs umsortieren
5. Feed **zurück in seinen ursprünglichen Ordner** ziehen (der ursprüngliche Bug-Fall)
6. Ordner umsortieren
7. Tag umsortieren
8. Smart Folder umsortieren (Standard-Gruppe und Eigene-Gruppe je einzeln), inkl.
   Verifikation, dass ein Drop über die Gruppengrenze hinweg abgelehnt wird (kein Drop-
   Indikator erscheint)
9. Inline-Umbenennen: Feed per Doppelklick, Ordner per Doppelklick/Kontextmenü
10. Kontextmenüs: Feed-Eigenschaften, Feed löschen, Ordner löschen, Smart-Folder
    bearbeiten/duplizieren/löschen
11. Klick-Auswahl für alle vier Bereiche (Feed, Ordner selbst nicht selektierbar korrekt
    ignoriert, Tag, Smart Folder)
12. Ein-/Ausklappen aller vier Abschnitte sowie einzelner Ordner (Zustand bleibt nach
    Neustart der App erhalten, da über `@AppStorage` gespeichert)
13. Tag-Manager-Button, Smart-Folder-Erstellen-Button, „+"-Menü in der Aktionszeile öffnen
    weiterhin die richtigen Sheets

Erst nach bestätigtem Durchlauf ALLER 13 Punkte gilt die Migration als abgeschlossen —
`xcodebuild build`/`BUILD SUCCEEDED` allein zählt laut Design-Spec ausdrücklich NICHT als
Verifikation.

---

## Self-Review-Notizen (bereits durchgeführt)

- **Spec-Abdeckung:** Alle Abschnitte der Design-Spec (Architektur, Zeilen-Rendering,
  Drag&Drop-Mechanik, Datenschicht, Reload-Strategie, Verifikationsplan) sind auf Tasks
  1–6 gemappt. Die Datei-Zusammenfassung der Spec (neu/geändert/gelöscht) deckt sich mit
  den `Files:`-Blöcken der Tasks.
- **Typkonsistenz geprüft:** `SidebarOutlineDropTarget`/`SidebarOutlineDropPolicy` (Task 5)
  verwenden dieselben Feld-/Payload-Namen wie `SidebarOutlineNode` (Task 2).
  `moveTag`/`moveSmartFolder`-Closures (Task 6) haben dieselbe Signatur wie in Task 5 an
  `SidebarOutlineView` deklariert. `TagStore.move(id:targetIndex:)` (Task 1) wird in Task 6
  mit exakt dieser Signatur aufgerufen. `SidebarOutlineFolderRow` wurde von Task 6 nach
  Task 4 vorgezogen (dort bereits vollständig mit Inline-Rename implementiert), damit Task 4
  schon eine vollständig interaktive Sidebar liefert statt eines Zwischenstands ohne
  Ordner-Rename.
- **Bekannter Nachtrag:** `SidebarFolderContextAction.rename` bleibt nach Task 6 ein
  ungenutzter Enum-Fall am Call-Site (`break`) — Inline-Rename läuft direkt in
  `SidebarOutlineFolderRow`, der Kontextmenü-Eintrag „Ordner umbenennen" ruft dort
  `beginEditing()` lokal auf, nicht über den Closure. Bewusst nicht entfernt, falls ein
  zukünftiger externer Rename-Trigger (z. B. Menüleisten-Shortcut) ihn braucht.
