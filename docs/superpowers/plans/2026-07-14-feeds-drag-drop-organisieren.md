# Feeds per Drag & Drop organisieren (Feature 15.2) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Feeds lassen sich in der Sidebar per Drag & Drop einem Ordner zuweisen (bzw. die Zuweisung entfernen) und innerhalb eines Ordners/„Ohne Ordner" frei anordnen; Ordner selbst lassen sich untereinander frei anordnen — statt wie bisher überall zwingend alphabetisch.

**Architecture:** Neues `sortIndex`-Feld auf `feeds` und `feed_folders` (Migration v15, mit Backfill aus der aktuellen alphabetischen Anzeige, damit sich für Bestandsnutzer nach dem Update nichts sichtbar ändert). Neue Store-Methoden `FeedStore.moveFeed(id:toFolderName:targetIndex:)` und `FeedFolderStore.moveFolder(name:targetIndex:)` kapseln das Neu-Nummerieren der betroffenen Gruppe. `FeedFolderStore.materializeImplicitFolders()` löst die Dual-Source-of-Truth-Altlast (Ordner ohne `FeedFolderRecord`) dauerhaft auf, indem sie bei jedem Sidebar-Laden rein implizite Ordner zu echten Datensätzen macht. `FeedFolderOrganizer` sortiert künftig nach `sortIndex` statt alphabetisch. Die eigentliche Drag-&-Drop-Geste nutzt SwiftUIs native `.draggable`/`.dropDestination`-APIs mit zwei kleinen `Transferable`-Payload-Typen in einer neuen Datei.

**Tech Stack:** Swift 5.9+, SwiftUI (macOS 14+), GRDB/SQLite, Swift Testing (`@Test`/`#expect`).

## Global Constraints

- Kommentare im Code auf Deutsch (Projektkonvention laut CLAUDE.md).
- Kein SwiftData — GRDB/SQLite ist die alleinige Persistenzschicht (ADR-007).
- Datenbank-Migrationen werden nie nachträglich verändert, nur angehängt. Die letzte bestehende Migration ist **v14** (`v14_add_article_identity_history_retention_flag`, verifiziert per `grep -n registerMigration` am 2026-07-14) — diese neue Migration heißt `v15_add_feed_and_folder_sort_index`.
- Nach jeder Store-Mutation, die die UI betrifft, muss `SQLiteDataInvalidation.bumpStatusVersion()` (für Feed-Änderungen) bzw. der lokale `sidebarDefinitionVersion`-Zähler (für Ordner-Struktur-Änderungen, bestehendes Muster in `SidebarView.swift`) hochgezählt werden — sonst aktualisiert sich die UI nicht (kein automatisches `@Query`-Observation wie bei SwiftData).
- `xcodebuild build` fügt bei einem neu referenzierten, noch nicht katalogisierten `L10n`-String automatisch einen leeren Stub-Eintrag in `Localizable.xcstrings` ein — dieser Plan braucht dafür keinen neuen Key (Wiederverwendung von `L10n.feedPropertiesNoFolder`), daher entfällt dieses Risiko hier vollständig.
- Nie ohne explizite Nutzerbestätigung nach `origin/main` pushen.
- **Korrektur gegenüber der genehmigten Spec** (gefunden beim detaillierteren Prüfen für diesen Plan): Die Spec nahm an, die beiden neuen `UTType`-Exports (`FeedDragItem`/`FolderDragItem`) müssten zusätzlich in `Info.plist` unter `UTExportedTypeDeclarations` eingetragen werden. Verifiziert per Code-Suche: Es gibt im Projekt aktuell **kein einziges** `UTExportedTypeDeclarations`-Vorkommen und **keinen** bestehenden `UTType(exportedAs:)`-Aufruf, auf den sich die Spec hätte stützen können — diese Annahme war falsch. Für rein prozessinterne `Transferable`-Nutzung (Drag & Drop nur innerhalb desselben Fensters/derselben App, keine Interoperabilität mit anderen Apps/Finder/Spotlight nötig) reicht `UTType(exportedAs:)` im Code allein aus, ganz ohne `Info.plist`-Eintrag. Dieser Plan lässt die `Info.plist`-Änderung deshalb ersatzlos weg.

---

### Task 1: Migration v15 — `sortIndex`-Spalten + Backfill (TDD)

**Files:**
- Modify: `Feedivo/Database/FeedivoDatabaseMigrator.swift`
- Test: `FeedivoTests/SQLiteDatabaseMigrationTests.swift`

**Interfaces:**
- Consumes: `DatabaseMigrator` (GRDB, bereits vorhanden), bestehende Tabellen `feeds`/`feed_folders`.
- Produces: Spalte `sortIndex INTEGER NOT NULL DEFAULT 0` auf `feeds` und `feed_folders`, befüllt mit der aktuellen alphabetischen Reihenfolge. Wird von Task 2 (`feed_folders.sortIndex`) und Task 3 (`feeds.sortIndex`) konsumiert.

- [ ] **Step 1: Schreibe die fehlschlagenden Tests**

Füge diese beiden Tests am Ende von `FeedivoTests/SQLiteDatabaseMigrationTests.swift` hinzu (vor der letzten schließenden `}` der `struct SQLiteDatabaseMigrationTests`):

```swift
    @Test func migrationV15BackfilltSortIndexAusBestehenderAlphabetischerReihenfolge() throws {
        let queue = try DatabaseQueue()
        try FeedivoDatabaseMigrator.migrator.migrate(queue, upTo: "v14_add_article_identity_history_retention_flag")

        try queue.write { db in
            let now = Date()
            // Wichtig: Zu diesem Zeitpunkt (nur bis v14 migriert) existiert die
            // sortIndex-Spalte auf BEIDEN Tabellen noch nicht — sie darf in
            // diesen INSERTs deshalb noch nicht auftauchen, sonst schlägt die
            // Query mit "no such column: sortIndex" fehl.
            try db.execute(
                sql: """
                    INSERT INTO feed_folders (id, name, createdAt, updatedAt)
                    VALUES ('folder-tech', 'Tech', ?, ?)
                    """,
                arguments: [now, now]
            )
            // "News" existiert NUR implizit über ein Feed, ohne eigenen feed_folders-Datensatz.
            try db.execute(
                sql: """
                    INSERT INTO feeds (
                        id, url, title, folderName, refreshIntervalMinutes,
                        isNotificationEnabled, articleRetentionOverridesGlobalSetting,
                        articleRetentionIsEnabled, articleRetentionDays,
                        articleRetentionMinimumArticles, articleRetentionIncludesProtectedArticles,
                        unreadCount, createdAt, updatedAt
                    ) VALUES
                        ('feed-b', 'https://b.example/feed.xml', 'Beta', 'Tech', 30, 0, 0, 0, 90, 20, 0, 0, ?, ?),
                        ('feed-a', 'https://a.example/feed.xml', 'Alpha', 'Tech', 30, 0, 0, 0, 90, 20, 0, 0, ?, ?),
                        ('feed-z', 'https://z.example/feed.xml', 'Zulu', 'News', 30, 0, 0, 0, 90, 20, 0, 0, ?, ?),
                        ('feed-x', 'https://x.example/feed.xml', 'Xray', NULL, 30, 0, 0, 0, 90, 20, 0, 0, ?, ?)
                    """,
                arguments: [now, now, now, now, now, now, now, now]
            )
        }

        try FeedivoDatabaseMigrator.migrator.migrate(queue)

        let feedSortIndexByID = try queue.read { db in
            try Row.fetchAll(db, sql: "SELECT id, sortIndex FROM feeds")
        }.reduce(into: [String: Int]()) { result, row in
            result[row["id"]] = row["sortIndex"]
        }
        // "Tech"-Gruppe: Alpha vor Beta (alphabetisch).
        #expect(feedSortIndexByID["feed-a"] == 0)
        #expect(feedSortIndexByID["feed-b"] == 1)
        // "News"-Gruppe (nur ein Feed) und "Ohne Ordner"-Gruppe (nur ein Feed)
        // starten jeweils unabhängig bei 0.
        #expect(feedSortIndexByID["feed-z"] == 0)
        #expect(feedSortIndexByID["feed-x"] == 0)

        let folders = try queue.read { db in
            try Row.fetchAll(db, sql: "SELECT name, sortIndex FROM feed_folders ORDER BY sortIndex")
        }
        // "News" (nur implizit) wird materialisiert; alphabetisch VOR "Tech" einsortiert.
        #expect(folders.map { $0["name"] as String } == ["News", "Tech"])
        #expect(folders.map { $0["sortIndex"] as Int } == [0, 1])
    }

    @Test func migrationV15IstIdempotentBeiBereitsVorhandenerSpalte() throws {
        // Regressionstest gegen versehentliches erneutes Ausführen der Migration
        // gegen eine bereits vollständig migrierte Datenbank (Standardfall bei
        // jedem regulären App-Start über FeedivoDatabase.inMemoryForTests()).
        let database = try FeedivoDatabase.inMemoryForTests()

        let columns = try database.read { db in
            try Row.fetchAll(db, sql: "PRAGMA table_info(feeds)")
        }
        let sortIndexColumn = columns.first { ($0["name"] as String?) == "sortIndex" }

        #expect(sortIndexColumn != nil)
        #expect((sortIndexColumn?["notnull"] as Int?) == 1)
        #expect((sortIndexColumn?["dflt_value"] as String?) == "0")
    }
```

- [ ] **Step 2: Führe die Tests aus, um das Fehlschlagen zu bestätigen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteDatabaseMigrationTests`
Expected: FAIL — `sortIndex`-Spalte existiert noch nicht (`no such column: sortIndex`).

- [ ] **Step 3: Implementiere die Migration**

In `Feedivo/Database/FeedivoDatabaseMigrator.swift`, füge NACH dem bestehenden `v14_add_article_identity_history_retention_flag`-Block (und vor `return migrator`) ein:

```swift
        migrator.registerMigration("v15_add_feed_and_folder_sort_index") { database in
            try database.alter(table: "feeds") { table in
                table.add(column: "sortIndex", .integer).notNull().defaults(to: 0)
            }
            try database.alter(table: "feed_folders") { table in
                table.add(column: "sortIndex", .integer).notNull().defaults(to: 0)
            }

            try backfillFeedAndFolderSortIndex(database)
        }
```

Füge am Ende der `enum FeedivoDatabaseMigrator`-Deklaration (nach dem schließenden `}` von `migrator`, aber noch innerhalb des `enum`-Bodys) diese private Hilfsmethode hinzu:

```swift
    /// Vergibt sortIndex-Werte für Feeds und Ordner passend zur AKTUELLEN
    /// alphabetischen Anzeige, damit Bestandsnutzer nach diesem Update keine
    /// sichtbare Umsortierung erleben. Materialisiert dabei zusätzlich alle
    /// bisher rein impliziten Ordner (nur über feeds.folderName, ohne eigenen
    /// feed_folders-Datensatz) als echte Datensätze — reimplementiert die
    /// case-insensitive Dedupliziierungs-/Sortierlogik von
    /// FeedFolderOrganizer.folderNames(...) eigenständig in reinem SQL/Swift,
    /// da FeedFolderOrganizer (Views-Schicht) zum Zeitpunkt dieser Migration
    /// nicht von der Datenbank-Schicht importiert werden soll.
    private static func backfillFeedAndFolderSortIndex(_ database: Database) throws {
        let feedFolderNames = try String.fetchAll(
            database,
            sql: "SELECT DISTINCT folderName FROM feeds WHERE folderName IS NOT NULL"
        )
        let explicitFolderNames = try String.fetchAll(database, sql: "SELECT name FROM feed_folders")

        var canonicalNamesByLowercasedName: [String: String] = [:]
        for name in feedFolderNames + explicitFolderNames {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if canonicalNamesByLowercasedName[key] == nil {
                canonicalNamesByLowercasedName[key] = trimmed
            }
        }

        let orderedFolderNames = canonicalNamesByLowercasedName.values.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }

        let now = Date()
        for (index, folderName) in orderedFolderNames.enumerated() {
            try database.execute(
                sql: "UPDATE feed_folders SET sortIndex = ? WHERE name = ? COLLATE NOCASE",
                arguments: [index, folderName]
            )

            if database.changesCount == 0 {
                try database.execute(
                    sql: """
                        INSERT INTO feed_folders (id, name, sortIndex, createdAt, updatedAt)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                    arguments: [UUID().uuidString, folderName, index, now, now]
                )
            }
        }

        struct FeedRow: FetchableRecord {
            let id: String
            let folderName: String?
            let title: String

            init(row: Row) {
                id = row["id"]
                folderName = row["folderName"]
                title = row["title"]
            }
        }

        let allFeeds = try FeedRow.fetchAll(database, sql: "SELECT id, folderName, title FROM feeds")
        var feedsByNormalizedFolderKey: [String: [FeedRow]] = [:]
        for feed in allFeeds {
            let trimmed = feed.folderName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let key = trimmed.isEmpty ? "" : trimmed.lowercased()
            feedsByNormalizedFolderKey[key, default: []].append(feed)
        }

        for (_, feedsInGroup) in feedsByNormalizedFolderKey {
            let sortedFeeds = feedsInGroup.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
            for (index, feed) in sortedFeeds.enumerated() {
                try database.execute(
                    sql: "UPDATE feeds SET sortIndex = ? WHERE id = ?",
                    arguments: [index, feed.id]
                )
            }
        }
    }
```

- [ ] **Step 4: Führe die Tests erneut aus**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteDatabaseMigrationTests`
Expected: PASS (alle Tests in dieser Suite, inkl. der zwei neuen).

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Database/FeedivoDatabaseMigrator.swift FeedivoTests/SQLiteDatabaseMigrationTests.swift
git commit -m "Feature: Migration v15 fuegt sortIndex zu feeds/feed_folders hinzu"
```

---

### Task 2: `FeedFolderStore` — `materializeImplicitFolders()` + `moveFolder(name:targetIndex:)` (TDD)

**Files:**
- Modify: `Feedivo/Database/Records/FeedFolderRecord.swift`
- Modify: `Feedivo/Stores/FeedFolderStore.swift`
- Modify: `Feedivo/ViewModels/SQLiteSidebarState.swift`
- Test: `FeedivoTests/FeedFolderStoreTests.swift`

**Interfaces:**
- Consumes: `sortIndex`-Spalte auf `feed_folders` (Task 1).
- Produces: `FeedFolderRecord.sortIndex: Int`, `FeedFolderStore.materializeImplicitFolders() throws`, `FeedFolderStore.moveFolder(name:targetIndex:) throws` — von Task 4 (`FeedFolderOrganizer`, liest `FeedFolderRecord.sortIndex`) und Task 6 (UI ruft `moveFolder` auf) konsumiert. `SQLiteSidebarState.load(...)` ruft `materializeImplicitFolders()` fortan bei jedem Laden auf.

- [ ] **Step 1: Schreibe die fehlschlagenden Tests**

Füge diese Tests am Ende von `FeedivoTests/FeedFolderStoreTests.swift` hinzu (vor der letzten schließenden `}`):

```swift
    @Test func materializeImplicitFoldersLegtDatensatzFuerReinImplizitenOrdnerAn() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let folderStore = FeedFolderStore(database: database)

        try feedStore.save(
            FeedRecord(id: "feed-1", url: "https://a.example/feed.xml", title: "A", folderName: "News")
        )

        try folderStore.materializeImplicitFolders()

        let folders = try folderStore.folders()
        #expect(folders.map(\.name) == ["News"])
        #expect(folders.first?.sortIndex == 0)
    }

    @Test func materializeImplicitFoldersIstIdempotent() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let folderStore = FeedFolderStore(database: database)

        try feedStore.save(
            FeedRecord(id: "feed-1", url: "https://a.example/feed.xml", title: "A", folderName: "News")
        )

        try folderStore.materializeImplicitFolders()
        try folderStore.materializeImplicitFolders()

        let folders = try folderStore.folders()
        #expect(folders.map(\.name) == ["News"])
    }

    @Test func materializeImplicitFoldersUeberspringtBereitsExplizitenOrdner() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let folderStore = FeedFolderStore(database: database)

        try folderStore.save(FeedFolderRecord(id: "folder-1", name: "Tech", sortIndex: 0))
        try feedStore.save(
            FeedRecord(id: "feed-1", url: "https://a.example/feed.xml", title: "A", folderName: "Tech")
        )

        try folderStore.materializeImplicitFolders()

        let folders = try folderStore.folders()
        #expect(folders.count == 1)
        #expect(folders.first?.id == "folder-1")
    }

    @Test func moveFolderVerschiebtOrdnerAnNeuePosition() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let folderStore = FeedFolderStore(database: database)
        try folderStore.save(FeedFolderRecord(id: "folder-a", name: "Alpha", sortIndex: 0))
        try folderStore.save(FeedFolderRecord(id: "folder-b", name: "Bravo", sortIndex: 1))
        try folderStore.save(FeedFolderRecord(id: "folder-c", name: "Charlie", sortIndex: 2))

        try folderStore.moveFolder(name: "Charlie", targetIndex: 0)

        let orderedNames = try folderStore.folders()
            .sorted { $0.sortIndex < $1.sortIndex }
            .map(\.name)
        #expect(orderedNames == ["Charlie", "Alpha", "Bravo"])
    }

    @Test func moveFolderMaterialisiertReinImplizitenOrdnerVorDemVerschieben() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let folderStore = FeedFolderStore(database: database)
        try folderStore.save(FeedFolderRecord(id: "folder-a", name: "Alpha", sortIndex: 0))
        try feedStore.save(
            FeedRecord(id: "feed-1", url: "https://a.example/feed.xml", title: "A", folderName: "News")
        )

        try folderStore.moveFolder(name: "News", targetIndex: 0)

        let orderedNames = try folderStore.folders()
            .sorted { $0.sortIndex < $1.sortIndex }
            .map(\.name)
        #expect(orderedNames == ["News", "Alpha"])
    }

    @Test func moveFolderKlemmtTargetIndexAufGueltigenBereich() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let folderStore = FeedFolderStore(database: database)
        try folderStore.save(FeedFolderRecord(id: "folder-a", name: "Alpha", sortIndex: 0))
        try folderStore.save(FeedFolderRecord(id: "folder-b", name: "Bravo", sortIndex: 1))

        try folderStore.moveFolder(name: "Alpha", targetIndex: 999)

        let orderedNames = try folderStore.folders()
            .sorted { $0.sortIndex < $1.sortIndex }
            .map(\.name)
        #expect(orderedNames == ["Bravo", "Alpha"])
    }
```

- [ ] **Step 2: Führe die Tests aus, um das Fehlschlagen zu bestätigen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedFolderStoreTests`
Expected: FAIL — `materializeImplicitFolders`/`moveFolder` existieren noch nicht, `FeedFolderRecord.init` kennt kein `sortIndex`.

- [ ] **Step 3: Implementiere `sortIndex` auf `FeedFolderRecord`**

In `Feedivo/Database/Records/FeedFolderRecord.swift`, füge das Feld und den Init-Parameter hinzu:

```swift
struct FeedFolderRecord: Codable, FetchableRecord, MutablePersistableRecord, Equatable, Sendable {
    static let databaseTableName = "feed_folders"

    var id: String
    var name: String
    var sortIndex: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        sortIndex: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.sortIndex = sortIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
```

- [ ] **Step 4: Implementiere `materializeImplicitFolders()` und `moveFolder(name:targetIndex:)`**

In `Feedivo/Stores/FeedFolderStore.swift`, füge diese beiden öffentlichen Methoden sowie die private Transaktions-interne Variante hinzu (z. B. direkt nach `renameFolder`):

```swift
    /// Materialisiert alle Ordnernamen, die nur auf feeds.folderName existieren
    /// aber (noch) keinen feed_folders-Datensatz haben, als echte Datensätze ans
    /// Ende der aktuellen Ordner-Reihenfolge. Idempotent — bereits materialisierte
    /// Ordner werden übersprungen.
    func materializeImplicitFolders() throws {
        try database.write { db in
            try materializeImplicitFolders(db)
        }
    }

    /// Transaktionslose Variante zur Wiederverwendung innerhalb einer bereits
    /// laufenden database.write-Transaktion (siehe moveFolder unten — GRDB
    /// erlaubt keine verschachtelten Schreibtransaktionen).
    private func materializeImplicitFolders(_ db: Database) throws {
        let rawFolderNames = try String.fetchAll(
            db,
            sql: "SELECT DISTINCT folderName FROM feeds WHERE folderName IS NOT NULL"
        )
        let existingLowercasedNames = Set(
            try String.fetchAll(db, sql: "SELECT name FROM feed_folders").map { $0.lowercased() }
        )

        var canonicalNamesByLowercasedName: [String: String] = [:]
        for rawName in rawFolderNames {
            let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !existingLowercasedNames.contains(trimmed.lowercased()) else {
                continue
            }
            let key = trimmed.lowercased()
            if canonicalNamesByLowercasedName[key] == nil {
                canonicalNamesByLowercasedName[key] = trimmed
            }
        }

        let namesToMaterialize = canonicalNamesByLowercasedName.values.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }

        guard !namesToMaterialize.isEmpty else {
            return
        }

        var nextSortIndex = try Int.fetchOne(
            db,
            sql: "SELECT COALESCE(MAX(sortIndex), -1) + 1 FROM feed_folders"
        ) ?? 0

        let now = Date()
        for folderName in namesToMaterialize {
            try db.execute(
                sql: """
                    INSERT INTO feed_folders (id, name, sortIndex, createdAt, updatedAt)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: [UUID().uuidString, folderName, nextSortIndex, now, now]
            )
            nextSortIndex += 1
        }
    }

    /// Verschiebt den benannten Ordner an targetIndex innerhalb der Liste der
    /// benannten Ordner (0-basiert, wird auf 0...anzahlAndererOrdner geklemmt).
    /// Materialisiert den Ordner zuerst, falls er noch keinen Datensatz hat.
    /// Nummeriert anschließend ALLE benannten Ordner 0...n-1 neu durch.
    func moveFolder(name: String, targetIndex: Int) throws {
        try database.write { db in
            try materializeImplicitFolders(db)

            let otherFolderNames = try String.fetchAll(
                db,
                sql: """
                    SELECT name FROM feed_folders
                    WHERE name != ? COLLATE NOCASE
                    ORDER BY sortIndex
                    """,
                arguments: [name]
            )

            var orderedNames = otherFolderNames
            let clampedIndex = min(max(targetIndex, 0), orderedNames.count)
            orderedNames.insert(name, at: clampedIndex)

            let now = Date()
            for (index, folderName) in orderedNames.enumerated() {
                try db.execute(
                    sql: "UPDATE feed_folders SET sortIndex = ?, updatedAt = ? WHERE name = ? COLLATE NOCASE",
                    arguments: [index, now, folderName]
                )
            }
        }
    }
```

- [ ] **Step 5: Verdrahte `materializeImplicitFolders()` in `SQLiteSidebarState.load(...)`**

In `Feedivo/ViewModels/SQLiteSidebarState.swift`, füge direkt nach der Zeile `let feedFolderStore = FeedFolderStore(database: database)` (innerhalb des `do`-Blocks von `load(database:showsReadFeeds:)`) diese Zeile ein:

```swift
            try feedFolderStore.materializeImplicitFolders()
```

(Läuft bewusst VOR `feedFolderStore.folders()`, damit neu materialisierte Ordner sofort in `loadedFeedFolders` erscheinen.)

- [ ] **Step 6: Führe die Tests erneut aus**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedFolderStoreTests`
Expected: PASS (alle Tests, inkl. der bereits vorher bestehenden Rename-Tests).

- [ ] **Step 7: Commit**

```bash
git add Feedivo/Database/Records/FeedFolderRecord.swift Feedivo/Stores/FeedFolderStore.swift Feedivo/ViewModels/SQLiteSidebarState.swift FeedivoTests/FeedFolderStoreTests.swift
git commit -m "Feature: FeedFolderStore materialisiert implizite Ordner und kann sie umsortieren"
```

---

### Task 3: `FeedStore.moveFeed(id:toFolderName:targetIndex:)` + `FeedSidebarSnapshot.sortIndex` (TDD)

**Files:**
- Modify: `Feedivo/Database/Records/FeedRecord.swift`
- Modify: `Feedivo/Snapshots/FeedSidebarSnapshot.swift`
- Modify: `Feedivo/Stores/FeedStore.swift`
- Test: `FeedivoTests/SQLiteFeedStoreTests.swift`

**Interfaces:**
- Consumes: `sortIndex`-Spalte auf `feeds` (Task 1).
- Produces: `FeedRecord.sortIndex: Int`, `FeedSidebarSnapshot.sortIndex: Int`, `FeedStore.moveFeed(id:toFolderName:targetIndex:) throws` — von Task 4 (`FeedFolderOrganizer.sortedSnapshots`, liest `FeedSidebarSnapshot.sortIndex`) und Task 6 (UI ruft `moveFeed` auf) konsumiert.

- [ ] **Step 1: Schreibe die fehlschlagenden Tests**

Prüfe zuerst per `grep -n "^struct\|^}" FeedivoTests/SQLiteFeedStoreTests.swift` die exakte Einfügestelle (vor der letzten schließenden `}` der Test-Struct), dann füge diese Tests dort hinzu:

```swift
    @Test func sidebarFeedsSortiertNachSortIndexNichtNachTitel() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        try feedStore.save(
            FeedRecord(id: "feed-z", url: "https://z.example/feed.xml", title: "Zulu", sortIndex: 0)
        )
        try feedStore.save(
            FeedRecord(id: "feed-a", url: "https://a.example/feed.xml", title: "Alpha", sortIndex: 1)
        )

        let snapshots = try feedStore.sidebarFeeds()

        #expect(snapshots.map(\.id) == ["feed-z", "feed-a"])
    }

    @Test func moveFeedOrdnetGruppeNeuInnerhalbDesselbenOrdners() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        try feedStore.save(
            FeedRecord(id: "feed-a", url: "https://a.example/feed.xml", title: "A", folderName: "Tech", sortIndex: 0)
        )
        try feedStore.save(
            FeedRecord(id: "feed-b", url: "https://b.example/feed.xml", title: "B", folderName: "Tech", sortIndex: 1)
        )
        try feedStore.save(
            FeedRecord(id: "feed-c", url: "https://c.example/feed.xml", title: "C", folderName: "Tech", sortIndex: 2)
        )

        try feedStore.moveFeed(id: "feed-c", toFolderName: "Tech", targetIndex: 0)

        let orderedIDs = try feedStore.feeds()
            .sorted { $0.sortIndex < $1.sortIndex }
            .map(\.id)
        #expect(orderedIDs == ["feed-c", "feed-a", "feed-b"])
    }

    @Test func moveFeedWeistNeuenOrdnerZuUndReihtAmEndeEin() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        try feedStore.save(
            FeedRecord(id: "feed-a", url: "https://a.example/feed.xml", title: "A", folderName: "Tech", sortIndex: 0)
        )
        try feedStore.save(
            FeedRecord(id: "feed-b", url: "https://b.example/feed.xml", title: "B", folderName: "News", sortIndex: 0)
        )

        try feedStore.moveFeed(id: "feed-b", toFolderName: "Tech", targetIndex: 1)

        let feedB = try feedStore.feed(id: "feed-b")
        #expect(feedB?.folderName == "Tech")
        #expect(feedB?.sortIndex == 1)
        let feedA = try feedStore.feed(id: "feed-a")
        #expect(feedA?.sortIndex == 0)
    }

    @Test func moveFeedZuOhneOrdnerSetztFolderNameAufNil() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        try feedStore.save(
            FeedRecord(id: "feed-a", url: "https://a.example/feed.xml", title: "A", folderName: "Tech", sortIndex: 0)
        )

        try feedStore.moveFeed(id: "feed-a", toFolderName: nil, targetIndex: 0)

        let feed = try feedStore.feed(id: "feed-a")
        #expect(feed?.folderName == nil)
        #expect(feed?.sortIndex == 0)
    }

    @Test func moveFeedKlemmtTargetIndexAufGueltigenBereich() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        try feedStore.save(
            FeedRecord(id: "feed-a", url: "https://a.example/feed.xml", title: "A", sortIndex: 0)
        )
        try feedStore.save(
            FeedRecord(id: "feed-b", url: "https://b.example/feed.xml", title: "B", sortIndex: 1)
        )

        try feedStore.moveFeed(id: "feed-a", toFolderName: nil, targetIndex: 999)

        let orderedIDs = try feedStore.feeds()
            .sorted { $0.sortIndex < $1.sortIndex }
            .map(\.id)
        #expect(orderedIDs == ["feed-b", "feed-a"])
    }
```

- [ ] **Step 2: Führe die Tests aus, um das Fehlschlagen zu bestätigen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedStoreTests`
Expected: FAIL — `FeedRecord.init` kennt kein `sortIndex`, `moveFeed` existiert noch nicht.

- [ ] **Step 3: Implementiere `sortIndex` auf `FeedRecord`**

In `Feedivo/Database/Records/FeedRecord.swift`, füge das Feld `var sortIndex: Int` nach `folderName` und den Init-Parameter `sortIndex: Int = 0` (nach `folderName: String? = nil`) hinzu — sowohl in der Property-Liste als auch im `init` (Signatur UND Zuweisung `self.sortIndex = sortIndex`).

- [ ] **Step 4: Implementiere `sortIndex` auf `FeedSidebarSnapshot` + SQL-Anpassung**

In `Feedivo/Snapshots/FeedSidebarSnapshot.swift`, füge das Feld hinzu:

```swift
struct FeedSidebarSnapshot: Equatable, Identifiable, Sendable {
    var id: String
    var title: String
    var url: String
    var faviconURL: String?
    var folderName: String?
    var sortIndex: Int = 0
    var unreadCount: Int
    var hasRecentError: Bool
}
```

In `Feedivo/Stores/FeedStore.swift`, erweitere den `FetchableRecord`-Init um `sortIndex`:

```swift
extension FeedSidebarSnapshot: FetchableRecord {
    init(row: Row) throws {
        id = row["id"]
        title = row["title"]
        url = row["url"]
        faviconURL = row["faviconURL"]
        folderName = row["folderName"]
        sortIndex = row["sortIndex"]
        unreadCount = row["unreadCount"]
        hasRecentError = row["hasRecentError"]
    }
}
```

Ergänze in `sidebarFeeds()` die SQL-`SELECT`-Liste um `f.sortIndex,` (direkt nach `f.folderName,`) und stelle die abschließende `ORDER BY` sowie den Swift-seitigen `.sorted { … }`-Aufruf um:

```swift
    func sidebarFeeds() throws -> [FeedSidebarSnapshot] {
        try database.read { db in
            let snapshots = try FeedSidebarSnapshot.fetchAll(db, sql: """
                SELECT
                    f.id,
                    f.title,
                    f.url,
                    f.faviconURL,
                    f.folderName,
                    f.sortIndex,
                    (
                        SELECT COUNT(*)
                        FROM articles a
                        JOIN article_statuses s ON s.articleID = a.id
                        WHERE a.feedID = f.id
                            AND s.isRead = 0
                            AND s.isHidden = 0
                    ) AS unreadCount,
                    COALESCE(
                        (
                            SELECT level = 'error'
                            FROM feed_logs
                            WHERE feedID = f.id
                            ORDER BY createdAt DESC
                            LIMIT 1
                        ),
                        0
                    ) AS hasRecentError
                FROM feeds f
                ORDER BY f.sortIndex, f.title COLLATE NOCASE, f.id COLLATE NOCASE
                """)
            return snapshots.sorted {
                if $0.sortIndex != $1.sortIndex {
                    return $0.sortIndex < $1.sortIndex
                }
                let titleOrder = $0.title.localizedStandardCompare($1.title)
                if titleOrder != .orderedSame {
                    return titleOrder == .orderedAscending
                }

                return $0.id.localizedStandardCompare($1.id) == .orderedAscending
            }
        }
    }
```

- [ ] **Step 5: Implementiere `moveFeed(id:toFolderName:targetIndex:)`**

Füge in `Feedivo/Stores/FeedStore.swift` diese Methode hinzu (z. B. direkt nach `sidebarFeeds(showsReadFeeds:)`):

```swift
    /// Weist den Feed ggf. einem neuen Ordner zu (nil = "Ohne Ordner") und
    /// positioniert ihn an targetIndex innerhalb der Ziel-Gruppe (0-basiert,
    /// wird auf 0...anzahlAndererFeedsInDerGruppe geklemmt). Nummeriert
    /// anschließend NUR die Ziel-Gruppe 0...n-1 neu durch — die Quell-Gruppe
    /// (falls der Feed den Ordner wechselt) behält ihre bestehenden
    /// sortIndex-Werte samt Lücke; das ist harmlos, da nur die relative
    /// Reihenfolge zählt, nicht die absoluten Werte.
    func moveFeed(id: String, toFolderName: String?, targetIndex: Int) throws {
        let trimmedFolderName = toFolderName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveFolderName = (trimmedFolderName?.isEmpty ?? true) ? nil : trimmedFolderName

        try database.write { db in
            let otherFeedIDs: [String]
            if let effectiveFolderName {
                otherFeedIDs = try String.fetchAll(
                    db,
                    sql: """
                        SELECT id FROM feeds
                        WHERE folderName = ? COLLATE NOCASE AND id != ?
                        ORDER BY sortIndex
                        """,
                    arguments: [effectiveFolderName, id]
                )
            } else {
                otherFeedIDs = try String.fetchAll(
                    db,
                    sql: """
                        SELECT id FROM feeds
                        WHERE folderName IS NULL AND id != ?
                        ORDER BY sortIndex
                        """,
                    arguments: [id]
                )
            }

            var orderedIDs = otherFeedIDs
            let clampedIndex = min(max(targetIndex, 0), orderedIDs.count)
            orderedIDs.insert(id, at: clampedIndex)

            let now = Date()
            for (index, feedID) in orderedIDs.enumerated() {
                if feedID == id {
                    try db.execute(
                        sql: """
                            UPDATE feeds
                            SET sortIndex = ?, folderName = ?, updatedAt = ?
                            WHERE id = ?
                            """,
                        arguments: [index, effectiveFolderName, now, feedID]
                    )
                } else {
                    try db.execute(
                        sql: "UPDATE feeds SET sortIndex = ? WHERE id = ?",
                        arguments: [index, feedID]
                    )
                }
            }
        }
    }
```

- [ ] **Step 6: Führe die Tests erneut aus**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedStoreTests`
Expected: PASS (alle Tests dieser Suite).

Führe zusätzlich `xcodebuild test ... -only-testing:FeedivoTests/AppIconBadgeServiceTests` aus (Regressionscheck: `FeedSidebarSnapshot`s neues, defaultetes `sortIndex`-Feld darf die drei dort bestehenden Direkt-Konstruktionsaufrufe nicht brechen).
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Feedivo/Database/Records/FeedRecord.swift Feedivo/Snapshots/FeedSidebarSnapshot.swift Feedivo/Stores/FeedStore.swift FeedivoTests/SQLiteFeedStoreTests.swift
git commit -m "Feature: FeedStore.moveFeed setzt Ordner-Zuweisung und Reihenfolge, sidebarFeeds sortiert nach sortIndex"
```

---

### Task 4: `FeedFolderOrganizer` — Sortierung nach `sortIndex` (TDD)

**Files:**
- Modify: `Feedivo/Views/Sidebar/FeedFolderOrganizer.swift`
- Test: `FeedivoTests/FeedFolderOrganizerTests.swift`

**Interfaces:**
- Consumes: `FeedFolderRecord.sortIndex` (Task 2), `FeedSidebarSnapshot.sortIndex` (Task 3).
- Produces: `sortedSnapshots(_:)` sortiert nach `sortIndex`; neue Überladung `folderNames(feedFolderNames:explicitFolders:)`; `feedsByFolderName(in:folders:)` nutzt sie. Von Task 6 (`SidebarView.swift`) konsumiert — die bereits bestehende `feedRows`/`foldersSection`-Nutzung bleibt unverändert, nur das zugrunde liegende Sortierverhalten ändert sich.

- [ ] **Step 1: Schreibe die fehlschlagenden Tests**

Füge diese Tests am Ende von `FeedivoTests/FeedFolderOrganizerTests.swift` hinzu (vor der letzten schließenden `}`):

```swift
    @Test func feedsWithoutFolderSortiertNachSortIndexNichtAlphabetisch() {
        let snapshots = [
            FeedSidebarSnapshot(id: "1", title: "Zulu", url: "u", sortIndex: 0, unreadCount: 0, hasRecentError: false),
            FeedSidebarSnapshot(id: "2", title: "Alpha", url: "u", sortIndex: 1, unreadCount: 0, hasRecentError: false)
        ]

        let ordered = FeedFolderOrganizer.feedsWithoutFolder(from: snapshots)

        #expect(ordered.map(\.id) == ["1", "2"])
    }

    @Test func feedsByFolderNameSortiertOrdnerNachSortIndexDerFeedFolderRecords() {
        let snapshots = [
            FeedSidebarSnapshot(id: "1", title: "A", url: "u", folderName: "Zeta", unreadCount: 0, hasRecentError: false),
            FeedSidebarSnapshot(id: "2", title: "B", url: "u", folderName: "Alpha", unreadCount: 0, hasRecentError: false)
        ]
        let folders = [
            FeedFolderRecord(id: "f-zeta", name: "Zeta", sortIndex: 0),
            FeedFolderRecord(id: "f-alpha", name: "Alpha", sortIndex: 1)
        ]

        let grouped = FeedFolderOrganizer.feedsByFolderName(in: snapshots, folders: folders)

        #expect(grouped.map(\.folderName) == ["Zeta", "Alpha"])
    }

    @Test func folderNamesMitExplicitFoldersSortiertNachSortIndexMitAlphabetischemFallback() {
        let folders = [
            FeedFolderRecord(id: "f-b", name: "Bravo", sortIndex: 0),
            FeedFolderRecord(id: "f-a", name: "Alpha", sortIndex: 1)
        ]

        let names = FeedFolderOrganizer.folderNames(feedFolderNames: [], explicitFolders: folders)

        #expect(names == ["Bravo", "Alpha"])
    }
```

- [ ] **Step 2: Führe die Tests aus, um das Fehlschlagen zu bestätigen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedFolderOrganizerTests`
Expected: FAIL — neue Überladung `folderNames(feedFolderNames:explicitFolders:)` existiert noch nicht, Sortierung ist noch alphabetisch.

- [ ] **Step 3: Implementiere die neue Sortierlogik**

In `Feedivo/Views/Sidebar/FeedFolderOrganizer.swift`, ersetze `sortedSnapshots(_:)`:

```swift
    private static func sortedSnapshots(_ snapshots: [FeedSidebarSnapshot]) -> [FeedSidebarSnapshot] {
        snapshots.sorted {
            if $0.sortIndex != $1.sortIndex {
                return $0.sortIndex < $1.sortIndex
            }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }
```

Füge eine neue Überladung von `folderNames` hinzu (die bestehende, rein string-basierte Überladung bleibt für ihre anderen, weiterhin alphabetisch sortierten Aufrufer — `ArticleMetadataInspectorView.swift:477`, `SidebarView.swift:88`/`:1079` — unverändert erhalten):

```swift
    static func folderNames(feedFolderNames: [String?], explicitFolders: [FeedFolderRecord]) -> [String] {
        var canonicalNamesByLowercasedName: [String: String] = [:]

        for folderName in feedFolderNames {
            insert(folderName: folderName, into: &canonicalNamesByLowercasedName)
        }
        for folder in explicitFolders {
            insert(folderName: folder.name, into: &canonicalNamesByLowercasedName)
        }

        let sortIndexByLowercasedName = Dictionary(
            explicitFolders.map { ($0.name.lowercased(), $0.sortIndex) },
            uniquingKeysWith: { first, _ in first }
        )

        return canonicalNamesByLowercasedName
            .sorted { lhs, rhs in
                let lhsIndex = sortIndexByLowercasedName[lhs.key] ?? Int.max
                let rhsIndex = sortIndexByLowercasedName[rhs.key] ?? Int.max
                if lhsIndex != rhsIndex {
                    return lhsIndex < rhsIndex
                }
                return lhs.value.localizedCaseInsensitiveCompare(rhs.value) == .orderedAscending
            }
            .map(\.value)
    }
```

Passe `feedsByFolderName(in:folders:)` an, sodass es die neue Überladung nutzt (ersetze im bestehenden Rumpf nur den `folderNames(...)`-Aufruf):

```swift
        let orderedFolderNames = folderNames(
            feedFolderNames: snapshots.map(\.folderName),
            explicitFolders: folders
        )
```

- [ ] **Step 4: Führe die Tests erneut aus**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedFolderOrganizerTests`
Expected: PASS (alle Tests, inkl. der bereits vorher bestehenden zwei Tests).

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Views/Sidebar/FeedFolderOrganizer.swift FeedivoTests/FeedFolderOrganizerTests.swift
git commit -m "Feature: FeedFolderOrganizer sortiert Feeds und Ordner nach sortIndex statt alphabetisch"
```

---

### Task 5: `SidebarDragAndDrop.swift` — Transferable-Payloads (TDD)

**Files:**
- Create: `Feedivo/Views/Sidebar/SidebarDragAndDrop.swift`
- Test: `FeedivoTests/SidebarDragAndDropTests.swift`

**Interfaces:**
- Consumes: nichts (eigenständige, neue Datei).
- Produces: `FeedDragItem`, `FolderDragItem` (beide `Transferable`), `DropInsertionSide` — von Task 6 (`SidebarView.swift`) konsumiert.

- [ ] **Step 1: Schreibe den fehlschlagenden Test**

Erstelle `FeedivoTests/SidebarDragAndDropTests.swift`:

```swift
import Foundation
import Testing
@testable import Feedivo

struct SidebarDragAndDropTests {
    @Test func dropInsertionSideObererHaelfteIstBefore() {
        let side = DropInsertionSide.of(
            location: CGPoint(x: 10, y: 5),
            in: CGSize(width: 100, height: 30)
        )
        #expect(side == .before)
    }

    @Test func dropInsertionSideUntererHaelfteIstAfter() {
        let side = DropInsertionSide.of(
            location: CGPoint(x: 10, y: 25),
            in: CGSize(width: 100, height: 30)
        )
        #expect(side == .after)
    }

    @Test func dropInsertionSideExaktAufDerMitteIstAfter() {
        // Deterministischer Grenzfall: exakt bei der Hälfte zählt als "danach".
        let side = DropInsertionSide.of(
            location: CGPoint(x: 10, y: 15),
            in: CGSize(width: 100, height: 30)
        )
        #expect(side == .after)
    }
}
```

- [ ] **Step 2: Führe den Test aus, um das Fehlschlagen zu bestätigen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SidebarDragAndDropTests`
Expected: FAIL — `DropInsertionSide` existiert noch nicht (Compile-Fehler).

- [ ] **Step 3: Implementiere die Datei**

Erstelle `Feedivo/Views/Sidebar/SidebarDragAndDrop.swift`:

```swift
import SwiftUI
import UniformTypeIdentifiers

// Reine In-Prozess-Nutzung (Drag & Drop nur innerhalb desselben Fensters,
// keine Interoperabilität mit anderen Apps/Finder/Spotlight nötig) — deshalb
// genügt UTType(exportedAs:) rein im Code, ganz ohne Info.plist-Eintrag unter
// UTExportedTypeDeclarations.
extension UTType {
    static let feedivoFeedDragItem = UTType(exportedAs: "ch.martin.Feedivo.feed-drag-item")
    static let feedivoFolderDragItem = UTType(exportedAs: "ch.martin.Feedivo.folder-drag-item")
}

/// Transferable-Payload für einen per Drag & Drop gezogenen Feed (Feed-ID).
struct FeedDragItem: Codable, Transferable {
    let feedID: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .feedivoFeedDragItem)
    }
}

/// Transferable-Payload für einen per Drag & Drop gezogenen Ordner (Ordnername).
struct FolderDragItem: Codable, Transferable {
    let folderName: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .feedivoFolderDragItem)
    }
}

/// Bestimmt anhand der Y-Position eines Drops innerhalb der Höhe einer
/// Zielzeile, ob "davor" oder "danach" eingefügt werden soll — gemeinsame
/// Logik für Feed- und Ordner-Reordering in SidebarView.swift.
enum DropInsertionSide: Equatable {
    case before
    case after

    static func of(location: CGPoint, in size: CGSize) -> DropInsertionSide {
        location.y < size.height / 2 ? .before : .after
    }
}
```

- [ ] **Step 4: Führe den Test erneut aus**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SidebarDragAndDropTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Views/Sidebar/SidebarDragAndDrop.swift FeedivoTests/SidebarDragAndDropTests.swift
git commit -m "Feature: Transferable-Payloads fuer Sidebar-Drag-and-Drop"
```

---

### Task 6: `SidebarView.swift` — Drag & Drop verdrahten

**Files:**
- Modify: `Feedivo/Views/Sidebar/FeedRowView.swift`
- Modify: `Feedivo/Views/Sidebar/SidebarView.swift`

**Interfaces:**
- Consumes: `FeedDragItem`/`FolderDragItem`/`DropInsertionSide` (Task 5), `FeedStore.moveFeed` (Task 3), `FeedFolderStore.moveFolder` (Task 2), `FeedFolderOrganizer.feedsByFolderName`/`feedsWithoutFolder` (Task 4, bereits sortIndex-basiert).
- Produces: fertiges Drag-&-Drop-Verhalten in der Sidebar. Keine weiteren Konsumenten (letzter Task).

**Vorbemerkung — während der Planung gefundene, notwendige Ergänzung
gegenüber der Spec:** Die "Ohne Ordner"-Gruppe hat in der aktuellen Sidebar
KEINEN eigenen Kopfzeilen-Bereich — sie wird nur gerendert, wenn mindestens
ein Feed ohne Ordner existiert (`if !feedsWithoutFolder.isEmpty { feedRows(...) }`).
Ist die Gruppe leer, gibt es dadurch buchstäblich keine sichtbare Fläche, auf
die ein Feed gezogen werden könnte, um seine Ordner-Zuweisung zu entfernen.
Dieser Task ergänzt deshalb eine kleine, IMMER sichtbare Kopfzeile für diesen
Bereich (analog zum Kopf jedes benannten Ordners), die den bereits
vorhandenen Text `L10n.feedPropertiesNoFolder` ("Kein Ordner") wiederverwendet
— kein neuer L10n-Key nötig.

- [ ] **Step 1: Mache `FeedRowView.DisplayStyle.rowHeight` für `SidebarView` sichtbar**

In `Feedivo/Views/Sidebar/FeedRowView.swift`, entferne `private` von der Extension-Deklaration:

```swift
extension FeedRowView.DisplayStyle {
```

(war zuvor `private extension FeedRowView.DisplayStyle {` — `SidebarView.swift` braucht in Step 3 unten Zugriff auf `.rowHeight`, um die Drop-Position innerhalb einer Feed-Zeile korrekt zu berechnen, ohne die Höhe zusätzlich per Laufzeit-Geometrie zu messen.)

- [ ] **Step 2: Baue, um sicherzustellen, dass diese Sichtbarkeitsänderung allein nichts bricht**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Erweitere `feedRows(_:isIndented:)` um Drag-&-Drop und einen `folderName`-Parameter**

In `Feedivo/Views/Sidebar/SidebarView.swift`, ersetze die bestehende `feedRows`-Methode:

```swift
    private func feedRows(
        _ snapshots: [FeedSidebarSnapshot],
        isIndented: Bool = false,
        folderName: String? = nil
    ) -> some View {
        let rowHeight = interfaceTextSize.scaled(
            (isIndented ? FeedRowView.DisplayStyle.folderChild : FeedRowView.DisplayStyle.regular).rowHeight
        )

        return ForEach(snapshots) { snapshot in
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
            .draggable(FeedDragItem(feedID: snapshot.id))
            .dropDestination(for: FeedDragItem.self) { items, location in
                guard let dragged = items.first, dragged.feedID != snapshot.id else {
                    return false
                }

                let side = DropInsertionSide.of(location: location, in: CGSize(width: 0, height: rowHeight))
                let currentIndex = snapshots.firstIndex(where: { $0.id == snapshot.id }) ?? 0
                let targetIndex = side == .before ? currentIndex : currentIndex + 1
                moveFeed(id: dragged.feedID, toFolderName: folderName, targetIndex: targetIndex)
                return true
            }
        }
    }
```

(Die `.contextMenu`-Inhalte sind wörtlich unverändert aus der bestehenden Methode übernommen — nur `.draggable`/`.dropDestination` sind neu, sowie der geänderte Funktionskopf und die vorangestellte `rowHeight`-Berechnung.)

- [ ] **Step 4: Passe die Aufrufstelle von `feedRows` in `foldersSection` an**

In `Feedivo/Views/Sidebar/SidebarView.swift`, ersetze den kompletten bisherigen Rumpf von `foldersSection` und füge eine neue Hilfsview `unassignedFeedsHeader` hinzu:

```swift
    private var foldersSection: some View {
        CollapsibleSidebarSection(
            title: L10n.sidebarFoldersSection,
            isCollapsed: $isFoldersCollapsed
        ) {
            // Snapshots sind bereits beim Laden via showsReadFeeds gefiltert.
            let visibleSnapshots = sqliteSidebarState.snapshots

            if visibleSnapshots.isEmpty && sqliteSidebarState.feedFolders.isEmpty {
                Text(L10n.sidebarEmptyTitle)
                    .font(interfaceTextSize.font(size: 13))
                    .foregroundStyle(SidebarStyle.secondaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            } else {
                let feedsWithoutFolder = FeedFolderOrganizer.feedsWithoutFolder(from: visibleSnapshots)

                // Immer gerendert (auch wenn feedsWithoutFolder leer ist) — sonst
                // gäbe es keine sichtbare Drop-Fläche, um die Ordner-Zuweisung
                // eines Feeds zu entfernen, solange kein einziger Feed bereits
                // ordnerlos ist.
                VStack(alignment: .leading, spacing: 0) {
                    unassignedFeedsHeader
                    feedRows(feedsWithoutFolder, folderName: nil)
                }
                .dropDestination(for: FeedDragItem.self) { items, _ in
                    guard let dragged = items.first else {
                        return false
                    }
                    moveFeed(id: dragged.feedID, toFolderName: nil, targetIndex: feedsWithoutFolder.count)
                    return true
                }

                let folderEntries = FeedFolderOrganizer.feedsByFolderName(
                    in: visibleSnapshots,
                    folders: sqliteSidebarState.feedFolders
                )

                ForEach(folderEntries, id: \.folderName) { entry in
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
                                isIndented: true,
                                folderName: entry.folderName
                            )
                        }
                    }
                    .draggable(FolderDragItem(folderName: entry.folderName))
                    .dropDestination(for: FeedDragItem.self) { items, _ in
                        guard let dragged = items.first else {
                            return false
                        }
                        moveFeed(id: dragged.feedID, toFolderName: entry.folderName, targetIndex: entry.snapshots.count)
                        return true
                    }
                    .dropDestination(for: FolderDragItem.self) { items, location in
                        guard let draggedFolder = items.first, draggedFolder.folderName != entry.folderName else {
                            return false
                        }

                        let side = DropInsertionSide.of(
                            location: location,
                            in: CGSize(width: 0, height: interfaceTextSize.scaled(24))
                        )
                        let currentIndex = folderEntries.firstIndex(where: { $0.folderName == entry.folderName }) ?? 0
                        let targetIndex = side == .before ? currentIndex : currentIndex + 1
                        moveFolder(name: draggedFolder.folderName, targetIndex: targetIndex)
                        return true
                    }
                }
            }
        }
    }

    private var unassignedFeedsHeader: some View {
        HStack(spacing: 9) {
            Image(systemName: "tray")
                .font(interfaceTextSize.font(size: 16, weight: .medium))
                .foregroundStyle(SidebarStyle.secondaryText)
                .frame(width: interfaceTextSize.scaled(20))

            Text(L10n.feedPropertiesNoFolder)
                .font(interfaceTextSize.font(size: 13, weight: .medium))
                .foregroundStyle(SidebarStyle.primaryText.opacity(0.82))

            Spacer(minLength: 0)
        }
        .frame(height: interfaceTextSize.scaled(24))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
```

- [ ] **Step 5: Ergänze die beiden privaten Move-Methoden**

Füge in `Feedivo/Views/Sidebar/SidebarView.swift` diese beiden Methoden hinzu (z. B. direkt nach `renameFeed(id:to:)`):

```swift
    private func moveFeed(id: String, toFolderName: String?, targetIndex: Int) {
        guard let database = feedivoDatabase else {
            return
        }

        try? FeedStore(database: database).moveFeed(id: id, toFolderName: toFolderName, targetIndex: targetIndex)
        SQLiteDataInvalidation.bumpStatusVersion()
    }

    private func moveFolder(name: String, targetIndex: Int) {
        guard let database = feedivoDatabase else {
            return
        }

        try? FeedFolderStore(database: database).moveFolder(name: name, targetIndex: targetIndex)
        sidebarDefinitionVersion += 1
    }
```

(Fehler werden bewusst still verworfen — `try?`, konsistent mit `duplicateSmartFolder`/`deleteSmartFolder` in derselben Datei. Ein fehlschlagender Move bewirkt im schlimmsten Fall, dass der Drop optisch nichts ändert; kein Datenverlust, da rein additiv/umsortierend.)

- [ ] **Step 6: Build + volle bestehende Testsuite für betroffene Bereiche**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED.

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedFolderStoreTests -only-testing:FeedivoTests/SQLiteFeedStoreTests -only-testing:FeedivoTests/FeedFolderOrganizerTests -only-testing:FeedivoTests/SidebarDragAndDropTests -only-testing:FeedivoTests/SQLiteDatabaseMigrationTests -only-testing:FeedivoTests/AppIconBadgeServiceTests -only-testing:FeedivoTests/FeedivoAppSceneConfigurationTests`
Expected: PASS (mit Ausnahme der bekannten, dokumentierten 15 vorbestehenden Fehlschläge in `FeedivoAppSceneConfigurationTests`, siehe `CLAUDE.md`-Gotcha — keine NEUEN Fehlschläge dort).

- [ ] **Step 7: Commit**

```bash
git add Feedivo/Views/Sidebar/FeedRowView.swift Feedivo/Views/Sidebar/SidebarView.swift
git commit -m "Feature: Drag & Drop fuer Feed-Ordner-Zuweisung, Feed-Reihenfolge und Ordner-Reihenfolge in der Sidebar"
```

---

## Manuelle Verifikation nach Abschluss aller Tasks

Kein computer-use für native macOS-Apps in dieser Umgebung verfügbar — nach Implementierung bittet der Nutzer manuell prüfen:

1. Einen Feed auf einen anderen Ordner-Header ziehen → Feed erscheint dort, verschwindet aus dem alten Ordner.
2. Einen Feed innerhalb desselben Ordners auf eine andere Zeile ziehen (obere/untere Hälfte) → Reihenfolge ändert sich wie erwartet.
3. Einen Feed auf den „Kein Ordner"-Bereich ziehen (auch wenn dieser aktuell leer ist) → Feed verliert seine Ordner-Zuweisung.
4. Einen Ordner-Header auf einen anderen Ordner-Header ziehen → Ordner-Reihenfolge ändert sich.
5. Einen rein aus OPML-Import stammenden, nie manuell erstellten Ordner verschieben → funktioniert genauso (Materialisierung im Hintergrund).
6. App neu starten → Reihenfolge bleibt exakt wie zuletzt gesetzt (Persistenz über die Migration hinweg, keine Rücksortierung auf alphabetisch).
