# SQLite/GRDB Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first SQLite/GRDB foundation slice for Feedivo: package dependency, database bootstrap, migrations, records, stores, snapshot reads, and focused tests.

**Architecture:** Keep the existing SwiftData app path running while adding a separate SQLite-first persistence layer. The new layer is isolated under `Feedivo/Database`, `Feedivo/Stores`, and `Feedivo/Snapshots`; Views do not talk to GRDB directly.

**Tech Stack:** Swift 5.9+, macOS 14+, Xcode 26, Swift Testing, GRDB Swift package, SQLite via `DatabaseQueue`.

---

## Scope

This plan implements only the first foundation slice. It does not move the UI,
refresh service, reader, tags, rules, smart folders, OPML, export, iCloud Sync,
or search to SQLite. The output is working, tested infrastructure that later
tasks can connect to the app.

## File Structure

Create:

- `Feedivo/Database/FeedivoDatabase.swift`
  Owns `DatabaseQueue` creation, migration execution, test in-memory DBs, and
  debug schema inspection helpers.

- `Feedivo/Database/FeedivoDatabaseMigrator.swift`
  Defines schema version `v1` with `feeds`, `articles`, `article_statuses`, and
  `feed_logs`.

- `Feedivo/Database/Records/FeedRecord.swift`
  GRDB record for the `feeds` table.

- `Feedivo/Database/Records/ArticleRecord.swift`
  GRDB record for the `articles` table.

- `Feedivo/Database/Records/ArticleStatusRecord.swift`
  GRDB record for the `article_statuses` table.

- `Feedivo/Database/Records/FeedLogRecord.swift`
  GRDB record for the `feed_logs` table.

- `Feedivo/Snapshots/FeedSidebarSnapshot.swift`
  Lightweight sidebar value type.

- `Feedivo/Snapshots/ArticleListSnapshot.swift`
  Lightweight article-list row value type.

- `Feedivo/Snapshots/ArticleReaderSnapshot.swift`
  Full reader value type for a selected article.

- `Feedivo/Stores/FeedStore.swift`
  Feed create/update/read/count APIs.

- `Feedivo/Stores/ArticleStatusStore.swift`
  Status ensure/update/count APIs.

- `Feedivo/Stores/ArticleStore.swift`
  Article upsert and reader-detail APIs.

- `Feedivo/Stores/TimelineStore.swift`
  Snapshot timeline reads with limit and status joins.

- `FeedivoTests/SQLiteDatabaseMigrationTests.swift`
  Schema and index coverage.

- `FeedivoTests/SQLiteFeedStoreTests.swift`
  Feed persistence and sidebar snapshots.

- `FeedivoTests/SQLiteArticleStoreTests.swift`
  Article upsert, status preservation, and reader snapshot tests.

- `FeedivoTests/SQLiteArticleStatusStoreTests.swift`
  Status ensure and mutation tests.

- `FeedivoTests/SQLiteTimelineStoreTests.swift`
  Timeline snapshots, sorting, filtering, and unread counts.

- `FeedivoTests/SQLitePerformanceSmokeTests.swift`
  Synthetic data smoke test.

Modify:

- `Feedivo.xcodeproj/project.pbxproj`
  Add GRDB Swift package product to the app target. Add it through Xcode's
  package UI so Xcode creates stable object IDs.

- `Feedivo.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
  Let Xcode update this file after package resolution.

- `AGENTS.md`
  Add a short "Letzte Änderungen" note after the slice is implemented.

- `FEATURES.md`
  Add a short completed bullet under Feature 26.2 after the slice is implemented.

---

### Task 1: Add GRDB Package Dependency

**Files:**
- Modify: `Feedivo.xcodeproj/project.pbxproj`
- Modify: `Feedivo.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`

- [ ] **Step 1: Add the package through Xcode**

Open the project in Xcode and add this Swift Package:

```text
https://github.com/groue/GRDB.swift
```

Use this dependency rule:

```text
Up to Next Major Version: 7.0.0
```

Add the `GRDB` product to the `Feedivo` app target. The unit tests use
`@testable import Feedivo`, so the test files do not need to import GRDB
directly.

- [ ] **Step 2: Resolve packages from the command line**

Run:

```bash
xcodebuild -resolvePackageDependencies -project Feedivo.xcodeproj -scheme Feedivo
```

Expected: command exits successfully and `Package.resolved` contains a `grdb.swift`
pin.

- [ ] **Step 3: Verify the project references**

Run:

```bash
rg -n "GRDB|grdb.swift|XCRemoteSwiftPackageReference" Feedivo.xcodeproj/project.pbxproj Feedivo.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
```

Expected: output includes `https://github.com/groue/GRDB.swift`, a `GRDB in Frameworks`
entry, and the existing FeedKit references remain.

- [ ] **Step 4: Commit dependency change**

```bash
git add Feedivo.xcodeproj/project.pbxproj Feedivo.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
git commit -m "build: add grdb package"
```

---

### Task 2: Database Bootstrap and Migration Tests

**Files:**
- Create: `Feedivo/Database/FeedivoDatabase.swift`
- Create: `Feedivo/Database/FeedivoDatabaseMigrator.swift`
- Create: `FeedivoTests/SQLiteDatabaseMigrationTests.swift`

- [ ] **Step 1: Write failing migration tests**

Create `FeedivoTests/SQLiteDatabaseMigrationTests.swift`:

```swift
import Testing
@testable import Feedivo

struct SQLiteDatabaseMigrationTests {
    @Test func migrationCreatesCoreTables() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        let tableNames = try database.debugTableNames()

        #expect(tableNames.contains("feeds"))
        #expect(tableNames.contains("articles"))
        #expect(tableNames.contains("article_statuses"))
        #expect(tableNames.contains("feed_logs"))
    }

    @Test func migrationCreatesPerformanceIndexes() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        let indexNames = try database.debugIndexNames()

        #expect(indexNames.contains("idx_feeds_url_unique"))
        #expect(indexNames.contains("idx_articles_feed_published"))
        #expect(indexNames.contains("idx_articles_feed_source_unique"))
        #expect(indexNames.contains("idx_articles_feed_link_unique"))
        #expect(indexNames.contains("idx_article_statuses_is_read"))
        #expect(indexNames.contains("idx_article_statuses_is_starred"))
        #expect(indexNames.contains("idx_article_statuses_is_archived"))
        #expect(indexNames.contains("idx_article_statuses_is_hidden"))
    }

    @Test func articleStatusesHaveNoForeignKeyCascadeToArticles() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        let foreignKeys = try database.debugForeignKeys(for: "article_statuses")

        #expect(foreignKeys.isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteDatabaseMigrationTests
```

Expected: compile fails because `FeedivoDatabase` does not exist.

- [ ] **Step 3: Create database bootstrap**

Create `Feedivo/Database/FeedivoDatabase.swift`:

```swift
import Foundation
import GRDB

struct FeedivoDatabase {
    private let writer: any DatabaseWriter

    init(writer: any DatabaseWriter) {
        self.writer = writer
    }

    static func open(at fileURL: URL) throws -> FeedivoDatabase {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var configuration = Configuration()
        configuration.prepareDatabase { database in
            try database.execute(sql: "PRAGMA foreign_keys = ON")
        }

        let queue = try DatabaseQueue(path: fileURL.path, configuration: configuration)
        try FeedivoDatabaseMigrator.migrator.migrate(queue)
        return FeedivoDatabase(writer: queue)
    }

    static func inMemoryForTests() throws -> FeedivoDatabase {
        var configuration = Configuration()
        configuration.prepareDatabase { database in
            try database.execute(sql: "PRAGMA foreign_keys = ON")
        }

        let queue = try DatabaseQueue(configuration: configuration)
        try FeedivoDatabaseMigrator.migrator.migrate(queue)
        return FeedivoDatabase(writer: queue)
    }

    func read<Value>(_ block: (Database) throws -> Value) throws -> Value {
        try writer.read(block)
    }

    func write<Value>(_ block: (Database) throws -> Value) throws -> Value {
        try writer.write(block)
    }

    func debugTableNames() throws -> Set<String> {
        try read { database in
            let rows = try Row.fetchAll(database, sql: """
                SELECT name FROM sqlite_master
                WHERE type = 'table'
                """)
            return Set(rows.compactMap { row in row["name"] as String? })
        }
    }

    func debugIndexNames() throws -> Set<String> {
        try read { database in
            let rows = try Row.fetchAll(database, sql: """
                SELECT name FROM sqlite_master
                WHERE type = 'index'
                """)
            return Set(rows.compactMap { row in row["name"] as String? })
        }
    }

    func debugForeignKeys(for tableName: String) throws -> [String] {
        try read { database in
            let rows = try Row.fetchAll(database, sql: "PRAGMA foreign_key_list(\(tableName))")
            return rows.compactMap { row in row["table"] as String? }
        }
    }
}
```

- [ ] **Step 4: Create migration**

Create `Feedivo/Database/FeedivoDatabaseMigrator.swift`:

```swift
import Foundation
import GRDB

enum FeedivoDatabaseMigrator {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_create_core_tables") { database in
            try database.create(table: "feeds") { table in
                table.column("id", .text).primaryKey()
                table.column("url", .text).notNull()
                table.column("title", .text).notNull()
                table.column("websiteURL", .text)
                table.column("faviconURL", .text)
                table.column("folderName", .text)
                table.column("refreshIntervalMinutes", .integer).notNull().defaults(to: 30)
                table.column("lastRefreshedAt", .datetime)
                table.column("lastETag", .text)
                table.column("lastModified", .text)
                table.column("lastBodyHash", .text)
                table.column("lastHTTPStatusCode", .integer)
                table.column("unreadCount", .integer).notNull().defaults(to: 0)
                table.column("createdAt", .datetime).notNull()
                table.column("updatedAt", .datetime).notNull()
            }

            try database.create(table: "articles") { table in
                table.column("id", .text).primaryKey()
                table.column("feedID", .text).notNull()
                    .references("feeds", column: "id", onDelete: .cascade)
                table.column("sourceID", .text)
                table.column("link", .text)
                table.column("title", .text).notNull()
                table.column("summary", .text)
                table.column("content", .text)
                table.column("imageURL", .text)
                table.column("author", .text)
                table.column("publishedAt", .datetime)
                table.column("arrivedAt", .datetime).notNull()
                table.column("updatedAt", .datetime).notNull()
                table.column("estimatedReadingMinutes", .integer)
            }

            try database.create(table: "article_statuses") { table in
                table.column("articleID", .text).primaryKey()
                table.column("isRead", .boolean).notNull().defaults(to: false)
                table.column("isStarred", .boolean).notNull().defaults(to: false)
                table.column("isArchived", .boolean).notNull().defaults(to: false)
                table.column("isHidden", .boolean).notNull().defaults(to: false)
                table.column("readAt", .datetime)
                table.column("starredAt", .datetime)
                table.column("archivedAt", .datetime)
                table.column("hiddenAt", .datetime)
                table.column("dateArrived", .datetime).notNull()
            }

            try database.create(table: "feed_logs") { table in
                table.column("id", .text).primaryKey()
                table.column("feedID", .text).notNull()
                    .references("feeds", column: "id", onDelete: .cascade)
                table.column("createdAt", .datetime).notNull()
                table.column("level", .text).notNull()
                table.column("message", .text).notNull()
                table.column("httpStatusCode", .integer)
                table.column("newArticleCount", .integer).notNull().defaults(to: 0)
            }

            try database.create(index: "idx_feeds_url_unique", on: "feeds", columns: ["url"], unique: true)
            try database.create(index: "idx_feeds_title", on: "feeds", columns: ["title"])
            try database.create(index: "idx_articles_feed_published", on: "articles", columns: ["feedID", "publishedAt"])
            try database.create(index: "idx_articles_published", on: "articles", columns: ["publishedAt"])
            try database.execute(sql: """
                CREATE UNIQUE INDEX idx_articles_feed_source_unique
                ON articles(feedID, sourceID)
                WHERE sourceID IS NOT NULL AND sourceID <> ''
                """)
            try database.execute(sql: """
                CREATE UNIQUE INDEX idx_articles_feed_link_unique
                ON articles(feedID, link)
                WHERE link IS NOT NULL AND link <> ''
                """)
            try database.create(index: "idx_article_statuses_is_read", on: "article_statuses", columns: ["isRead"])
            try database.create(index: "idx_article_statuses_is_starred", on: "article_statuses", columns: ["isStarred"])
            try database.create(index: "idx_article_statuses_is_archived", on: "article_statuses", columns: ["isArchived"])
            try database.create(index: "idx_article_statuses_is_hidden", on: "article_statuses", columns: ["isHidden"])
            try database.create(index: "idx_feed_logs_feed_created", on: "feed_logs", columns: ["feedID", "createdAt"])
        }

        return migrator
    }
}
```

- [ ] **Step 5: Run migration tests**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteDatabaseMigrationTests
```

Expected: `SQLiteDatabaseMigrationTests` passes.

- [ ] **Step 6: Commit database bootstrap**

```bash
git add Feedivo/Database FeedivoTests/SQLiteDatabaseMigrationTests.swift
git commit -m "feat: add sqlite database bootstrap"
```

---

### Task 3: Add GRDB Records

**Files:**
- Create: `Feedivo/Database/Records/FeedRecord.swift`
- Create: `Feedivo/Database/Records/ArticleRecord.swift`
- Create: `Feedivo/Database/Records/ArticleStatusRecord.swift`
- Create: `Feedivo/Database/Records/FeedLogRecord.swift`

- [ ] **Step 1: Create `FeedRecord`**

Create `Feedivo/Database/Records/FeedRecord.swift`:

```swift
import Foundation
import GRDB

struct FeedRecord: Codable, FetchableRecord, MutablePersistableRecord, Equatable, Sendable {
    static let databaseTableName = "feeds"

    var id: String
    var url: String
    var title: String
    var websiteURL: String?
    var faviconURL: String?
    var folderName: String?
    var refreshIntervalMinutes: Int
    var lastRefreshedAt: Date?
    var lastETag: String?
    var lastModified: String?
    var lastBodyHash: String?
    var lastHTTPStatusCode: Int?
    var unreadCount: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        url: String,
        title: String,
        websiteURL: String? = nil,
        faviconURL: String? = nil,
        folderName: String? = nil,
        refreshIntervalMinutes: Int = 30,
        lastRefreshedAt: Date? = nil,
        lastETag: String? = nil,
        lastModified: String? = nil,
        lastBodyHash: String? = nil,
        lastHTTPStatusCode: Int? = nil,
        unreadCount: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.websiteURL = websiteURL
        self.faviconURL = faviconURL
        self.folderName = folderName
        self.refreshIntervalMinutes = refreshIntervalMinutes
        self.lastRefreshedAt = lastRefreshedAt
        self.lastETag = lastETag
        self.lastModified = lastModified
        self.lastBodyHash = lastBodyHash
        self.lastHTTPStatusCode = lastHTTPStatusCode
        self.unreadCount = unreadCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
```

- [ ] **Step 2: Create `ArticleRecord`**

Create `Feedivo/Database/Records/ArticleRecord.swift`:

```swift
import Foundation
import GRDB

struct ArticleRecord: Codable, FetchableRecord, MutablePersistableRecord, Equatable, Sendable {
    static let databaseTableName = "articles"

    var id: String
    var feedID: String
    var sourceID: String?
    var link: String?
    var title: String
    var summary: String?
    var content: String?
    var imageURL: String?
    var author: String?
    var publishedAt: Date?
    var arrivedAt: Date
    var updatedAt: Date
    var estimatedReadingMinutes: Int?
}
```

- [ ] **Step 3: Create `ArticleStatusRecord`**

Create `Feedivo/Database/Records/ArticleStatusRecord.swift`:

```swift
import Foundation
import GRDB

struct ArticleStatusRecord: Codable, FetchableRecord, MutablePersistableRecord, Equatable, Sendable {
    static let databaseTableName = "article_statuses"

    var articleID: String
    var isRead: Bool
    var isStarred: Bool
    var isArchived: Bool
    var isHidden: Bool
    var readAt: Date?
    var starredAt: Date?
    var archivedAt: Date?
    var hiddenAt: Date?
    var dateArrived: Date

    init(
        articleID: String,
        isRead: Bool = false,
        isStarred: Bool = false,
        isArchived: Bool = false,
        isHidden: Bool = false,
        readAt: Date? = nil,
        starredAt: Date? = nil,
        archivedAt: Date? = nil,
        hiddenAt: Date? = nil,
        dateArrived: Date = Date()
    ) {
        self.articleID = articleID
        self.isRead = isRead
        self.isStarred = isStarred
        self.isArchived = isArchived
        self.isHidden = isHidden
        self.readAt = readAt
        self.starredAt = starredAt
        self.archivedAt = archivedAt
        self.hiddenAt = hiddenAt
        self.dateArrived = dateArrived
    }
}
```

- [ ] **Step 4: Create `FeedLogRecord`**

Create `Feedivo/Database/Records/FeedLogRecord.swift`:

```swift
import Foundation
import GRDB

struct FeedLogRecord: Codable, FetchableRecord, MutablePersistableRecord, Equatable, Sendable {
    static let databaseTableName = "feed_logs"

    var id: String
    var feedID: String
    var createdAt: Date
    var level: String
    var message: String
    var httpStatusCode: Int?
    var newArticleCount: Int

    init(
        id: String = UUID().uuidString,
        feedID: String,
        createdAt: Date = Date(),
        level: String,
        message: String,
        httpStatusCode: Int? = nil,
        newArticleCount: Int = 0
    ) {
        self.id = id
        self.feedID = feedID
        self.createdAt = createdAt
        self.level = level
        self.message = message
        self.httpStatusCode = httpStatusCode
        self.newArticleCount = newArticleCount
    }
}
```

- [ ] **Step 5: Run a compile check**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteDatabaseMigrationTests
```

Expected: migration tests still pass.

- [ ] **Step 6: Commit records**

```bash
git add Feedivo/Database/Records
git commit -m "feat: add sqlite records"
```

---

### Task 4: Feed Store and Sidebar Snapshots

**Files:**
- Create: `Feedivo/Snapshots/FeedSidebarSnapshot.swift`
- Create: `Feedivo/Stores/FeedStore.swift`
- Create: `FeedivoTests/SQLiteFeedStoreTests.swift`

- [ ] **Step 1: Write failing feed-store tests**

Create `FeedivoTests/SQLiteFeedStoreTests.swift`:

```swift
import Foundation
import Testing
@testable import Feedivo

struct SQLiteFeedStoreTests {
    @Test func saveFeedPersistsAndUpdatesByID() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = FeedStore(database: database)
        let now = Date(timeIntervalSince1970: 1_000)

        var feed = FeedRecord(
            id: "feed-1",
            url: "https://example.com/feed.xml",
            title: "Example",
            createdAt: now,
            updatedAt: now
        )
        try store.save(feed)

        feed.title = "Updated"
        feed.unreadCount = 7
        feed.updatedAt = Date(timeIntervalSince1970: 2_000)
        try store.save(feed)

        let loaded = try store.feed(id: "feed-1")

        #expect(loaded?.title == "Updated")
        #expect(loaded?.unreadCount == 7)
    }

    @Test func duplicateURLIsRejectedByUniqueIndex() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = FeedStore(database: database)

        try store.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "One"))

        #expect(throws: Error.self) {
            try store.save(FeedRecord(id: "feed-2", url: "https://example.com/feed.xml", title: "Two"))
        }
    }

    @Test func sidebarSnapshotsAreSortedByTitle() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = FeedStore(database: database)

        try store.save(FeedRecord(id: "b", url: "https://b.example/feed.xml", title: "Beta", unreadCount: 2))
        try store.save(FeedRecord(id: "a", url: "https://a.example/feed.xml", title: "Alpha", unreadCount: 1))

        let snapshots = try store.sidebarFeeds()

        #expect(snapshots.map(\.id) == ["a", "b"])
        #expect(snapshots.first?.unreadCount == 1)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedStoreTests
```

Expected: compile fails because `FeedStore` and `FeedSidebarSnapshot` do not exist.

- [ ] **Step 3: Create sidebar snapshot**

Create `Feedivo/Snapshots/FeedSidebarSnapshot.swift`:

```swift
import Foundation

struct FeedSidebarSnapshot: Equatable, Identifiable, Sendable {
    var id: String
    var title: String
    var url: String
    var faviconURL: String?
    var folderName: String?
    var unreadCount: Int
}
```

- [ ] **Step 4: Create feed store**

Create `Feedivo/Stores/FeedStore.swift`:

```swift
import Foundation
import GRDB

struct FeedStore {
    private let database: FeedivoDatabase

    init(database: FeedivoDatabase) {
        self.database = database
    }

    func save(_ feed: FeedRecord) throws {
        try database.write { db in
            try feed.save(db)
        }
    }

    func feed(id: String) throws -> FeedRecord? {
        try database.read { db in
            try FeedRecord.fetchOne(db, key: id)
        }
    }

    func sidebarFeeds() throws -> [FeedSidebarSnapshot] {
        try database.read { db in
            let snapshots = try FeedSidebarSnapshot.fetchAll(db, sql: """
                SELECT id, title, url, faviconURL, folderName, unreadCount
                FROM feeds
                ORDER BY title COLLATE NOCASE
                """)
            return snapshots.sorted {
                $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        }
    }
}

extension FeedSidebarSnapshot: FetchableRecord {
    init(row: Row) throws {
        id = row["id"]
        title = row["title"]
        url = row["url"]
        faviconURL = row["faviconURL"]
        folderName = row["folderName"]
        unreadCount = row["unreadCount"]
    }
}
```

- [ ] **Step 5: Run feed-store tests**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedStoreTests
```

Expected: `SQLiteFeedStoreTests` passes.

- [ ] **Step 6: Commit feed store**

```bash
git add Feedivo/Snapshots/FeedSidebarSnapshot.swift Feedivo/Stores/FeedStore.swift FeedivoTests/SQLiteFeedStoreTests.swift
git commit -m "feat: add sqlite feed store"
```

---

### Task 5: Article Status Store

**Files:**
- Create: `Feedivo/Stores/ArticleStatusStore.swift`
- Create: `FeedivoTests/SQLiteArticleStatusStoreTests.swift`

- [ ] **Step 1: Write failing status-store tests**

Create `FeedivoTests/SQLiteArticleStatusStoreTests.swift`:

```swift
import Foundation
import Testing
@testable import Feedivo

struct SQLiteArticleStatusStoreTests {
    @Test func ensureStatusCreatesDefaultUnreadStatus() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = ArticleStatusStore(database: database)
        let arrivedAt = Date(timeIntervalSince1970: 100)

        try store.ensureStatus(articleID: "article-1", dateArrived: arrivedAt)

        let status = try store.status(articleID: "article-1")

        #expect(status?.articleID == "article-1")
        #expect(status?.isRead == false)
        #expect(status?.isStarred == false)
        #expect(status?.dateArrived == arrivedAt)
    }

    @Test func ensureStatusDoesNotOverwriteExistingStatus() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = ArticleStatusStore(database: database)

        try store.ensureStatus(articleID: "article-1", dateArrived: Date(timeIntervalSince1970: 100))
        try store.setRead(true, articleID: "article-1", at: Date(timeIntervalSince1970: 200))
        try store.ensureStatus(articleID: "article-1", dateArrived: Date(timeIntervalSince1970: 300))

        let status = try store.status(articleID: "article-1")

        #expect(status?.isRead == true)
        #expect(status?.readAt == Date(timeIntervalSince1970: 200))
        #expect(status?.dateArrived == Date(timeIntervalSince1970: 100))
    }

    @Test func statusMutationsUpdateOnlyStatusTable() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let statusStore = ArticleStatusStore(database: database)

        try statusStore.ensureStatus(articleID: "article-1", dateArrived: Date(timeIntervalSince1970: 100))
        try statusStore.setStarred(true, articleID: "article-1", at: Date(timeIntervalSince1970: 400))
        try statusStore.setArchived(true, articleID: "article-1", at: Date(timeIntervalSince1970: 500))
        try statusStore.setHidden(true, articleID: "article-1", at: Date(timeIntervalSince1970: 600))

        let status = try statusStore.status(articleID: "article-1")

        #expect(status?.isStarred == true)
        #expect(status?.starredAt == Date(timeIntervalSince1970: 400))
        #expect(status?.isArchived == true)
        #expect(status?.archivedAt == Date(timeIntervalSince1970: 500))
        #expect(status?.isHidden == true)
        #expect(status?.hiddenAt == Date(timeIntervalSince1970: 600))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteArticleStatusStoreTests
```

Expected: compile fails because `ArticleStatusStore` does not exist.

- [ ] **Step 3: Create status store**

Create `Feedivo/Stores/ArticleStatusStore.swift`:

```swift
import Foundation
import GRDB

struct ArticleStatusStore {
    private let database: FeedivoDatabase

    init(database: FeedivoDatabase) {
        self.database = database
    }

    func ensureStatus(articleID: String, dateArrived: Date) throws {
        try database.write { db in
            if try ArticleStatusRecord.fetchOne(db, key: articleID) == nil {
                try ArticleStatusRecord(articleID: articleID, dateArrived: dateArrived).insert(db)
            }
        }
    }

    func status(articleID: String) throws -> ArticleStatusRecord? {
        try database.read { db in
            try ArticleStatusRecord.fetchOne(db, key: articleID)
        }
    }

    func setRead(_ isRead: Bool, articleID: String, at date: Date?) throws {
        try updateBooleanStatus(
            column: "isRead",
            dateColumn: "readAt",
            value: isRead,
            articleID: articleID,
            date: date
        )
    }

    func setStarred(_ isStarred: Bool, articleID: String, at date: Date?) throws {
        try updateBooleanStatus(
            column: "isStarred",
            dateColumn: "starredAt",
            value: isStarred,
            articleID: articleID,
            date: date
        )
    }

    func setArchived(_ isArchived: Bool, articleID: String, at date: Date?) throws {
        try updateBooleanStatus(
            column: "isArchived",
            dateColumn: "archivedAt",
            value: isArchived,
            articleID: articleID,
            date: date
        )
    }

    func setHidden(_ isHidden: Bool, articleID: String, at date: Date?) throws {
        try updateBooleanStatus(
            column: "isHidden",
            dateColumn: "hiddenAt",
            value: isHidden,
            articleID: articleID,
            date: date
        )
    }

    private func updateBooleanStatus(
        column: String,
        dateColumn: String,
        value: Bool,
        articleID: String,
        date: Date?
    ) throws {
        let timestamp = value ? date : nil
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE article_statuses
                    SET \(column) = ?, \(dateColumn) = ?
                    WHERE articleID = ?
                    """,
                arguments: [value, timestamp, articleID]
            )
        }
    }
}
```

- [ ] **Step 4: Run status-store tests**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteArticleStatusStoreTests
```

Expected: `SQLiteArticleStatusStoreTests` passes.

- [ ] **Step 5: Commit status store**

```bash
git add Feedivo/Stores/ArticleStatusStore.swift FeedivoTests/SQLiteArticleStatusStoreTests.swift
git commit -m "feat: add sqlite article status store"
```

---

### Task 6: Article Store and Reader Snapshot

**Files:**
- Create: `Feedivo/Snapshots/ArticleReaderSnapshot.swift`
- Create: `Feedivo/Stores/ArticleStore.swift`
- Create: `FeedivoTests/SQLiteArticleStoreTests.swift`

- [ ] **Step 1: Write failing article-store tests**

Create `FeedivoTests/SQLiteArticleStoreTests.swift`:

```swift
import Foundation
import Testing
@testable import Feedivo

struct SQLiteArticleStoreTests {
    @Test func upsertInsertsArticleAndCreatesStatus() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))

        let articleID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "source-1",
                link: "https://example.com/a",
                title: "Title",
                summary: "Summary",
                content: "Content",
                imageURL: "https://example.com/image.jpg",
                author: "Author",
                publishedAt: Date(timeIntervalSince1970: 1_000),
                arrivedAt: Date(timeIntervalSince1970: 2_000),
                estimatedReadingMinutes: 3
            )
        )

        let reader = try articleStore.readerArticle(id: articleID)
        let status = try statusStore.status(articleID: articleID)

        #expect(reader?.title == "Title")
        #expect(reader?.feedTitle == "Example")
        #expect(reader?.content == "Content")
        #expect(status?.isRead == false)
    }

    @Test func upsertUpdatesExistingArticleBySourceIDWithoutOverwritingStatus() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))

        let firstID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "source-1",
                link: "https://example.com/a",
                title: "Old",
                summary: nil,
                content: nil,
                imageURL: nil,
                author: nil,
                publishedAt: Date(timeIntervalSince1970: 1_000),
                arrivedAt: Date(timeIntervalSince1970: 2_000),
                estimatedReadingMinutes: nil
            )
        )
        try statusStore.setRead(true, articleID: firstID, at: Date(timeIntervalSince1970: 3_000))

        let secondID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "source-1",
                link: "https://example.com/changed",
                title: "New",
                summary: "New summary",
                content: "New content",
                imageURL: nil,
                author: nil,
                publishedAt: Date(timeIntervalSince1970: 1_500),
                arrivedAt: Date(timeIntervalSince1970: 9_000),
                estimatedReadingMinutes: 4
            )
        )

        let reader = try articleStore.readerArticle(id: secondID)
        let status = try statusStore.status(articleID: secondID)

        #expect(secondID == firstID)
        #expect(reader?.title == "New")
        #expect(status?.isRead == true)
        #expect(status?.dateArrived == Date(timeIntervalSince1970: 2_000))
    }

    @Test func upsertFallsBackToLinkWhenSourceIDIsMissing() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))

        let firstID = try articleStore.upsert(
            ArticleUpsertInput(feedID: "feed-1", sourceID: nil, link: "https://example.com/a", title: "Old")
        )
        let secondID = try articleStore.upsert(
            ArticleUpsertInput(feedID: "feed-1", sourceID: nil, link: "https://example.com/a", title: "New")
        )

        #expect(firstID == secondID)
        #expect(try articleStore.readerArticle(id: firstID)?.title == "New")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteArticleStoreTests
```

Expected: compile fails because `ArticleStore`, `ArticleUpsertInput`, and
`ArticleReaderSnapshot` do not exist.

- [ ] **Step 3: Create reader snapshot**

Create `Feedivo/Snapshots/ArticleReaderSnapshot.swift`:

```swift
import Foundation

struct ArticleReaderSnapshot: Equatable, Identifiable, Sendable {
    var id: String
    var feedID: String
    var feedTitle: String
    var title: String
    var link: String?
    var summary: String?
    var content: String?
    var imageURL: String?
    var author: String?
    var publishedAt: Date?
    var arrivedAt: Date
    var estimatedReadingMinutes: Int?
    var isRead: Bool
    var isStarred: Bool
    var isArchived: Bool
    var isHidden: Bool
}
```

- [ ] **Step 4: Create article store**

Create `Feedivo/Stores/ArticleStore.swift`:

```swift
import Foundation
import GRDB

struct ArticleUpsertInput: Equatable, Sendable {
    var feedID: String
    var sourceID: String?
    var link: String?
    var title: String
    var summary: String?
    var content: String?
    var imageURL: String?
    var author: String?
    var publishedAt: Date?
    var arrivedAt: Date
    var estimatedReadingMinutes: Int?

    init(
        feedID: String,
        sourceID: String?,
        link: String?,
        title: String,
        summary: String? = nil,
        content: String? = nil,
        imageURL: String? = nil,
        author: String? = nil,
        publishedAt: Date? = nil,
        arrivedAt: Date = Date(),
        estimatedReadingMinutes: Int? = nil
    ) {
        self.feedID = feedID
        self.sourceID = sourceID
        self.link = link
        self.title = title
        self.summary = summary
        self.content = content
        self.imageURL = imageURL
        self.author = author
        self.publishedAt = publishedAt
        self.arrivedAt = arrivedAt
        self.estimatedReadingMinutes = estimatedReadingMinutes
    }
}

struct ArticleStore {
    private let database: FeedivoDatabase

    init(database: FeedivoDatabase) {
        self.database = database
    }

    func upsert(_ input: ArticleUpsertInput) throws -> String {
        try database.write { db in
            let existingID = try findExistingArticleID(input: input, db: db)
            let now = Date()

            if let existingID {
                try db.execute(
                    sql: """
                        UPDATE articles
                        SET link = ?, title = ?, summary = ?, content = ?, imageURL = ?,
                            author = ?, publishedAt = ?, updatedAt = ?,
                            estimatedReadingMinutes = ?
                        WHERE id = ?
                        """,
                    arguments: [
                        input.link,
                        input.title,
                        input.summary,
                        input.content,
                        input.imageURL,
                        input.author,
                        input.publishedAt,
                        now,
                        input.estimatedReadingMinutes,
                        existingID
                    ]
                )
                return existingID
            }

            let articleID = UUID().uuidString
            let record = ArticleRecord(
                id: articleID,
                feedID: input.feedID,
                sourceID: input.sourceID,
                link: input.link,
                title: input.title,
                summary: input.summary,
                content: input.content,
                imageURL: input.imageURL,
                author: input.author,
                publishedAt: input.publishedAt,
                arrivedAt: input.arrivedAt,
                updatedAt: now,
                estimatedReadingMinutes: input.estimatedReadingMinutes
            )
            try record.insert(db)
            try ArticleStatusRecord(articleID: articleID, dateArrived: input.arrivedAt).insert(db)
            return articleID
        }
    }

    func readerArticle(id: String) throws -> ArticleReaderSnapshot? {
        try database.read { db in
            try ArticleReaderSnapshot.fetchOne(db, sql: """
                SELECT
                    a.id,
                    a.feedID,
                    f.title AS feedTitle,
                    a.title,
                    a.link,
                    a.summary,
                    a.content,
                    a.imageURL,
                    a.author,
                    a.publishedAt,
                    a.arrivedAt,
                    a.estimatedReadingMinutes,
                    s.isRead,
                    s.isStarred,
                    s.isArchived,
                    s.isHidden
                FROM articles a
                JOIN feeds f ON f.id = a.feedID
                JOIN article_statuses s ON s.articleID = a.id
                WHERE a.id = ?
                """, arguments: [id])
        }
    }

    private func findExistingArticleID(input: ArticleUpsertInput, db: Database) throws -> String? {
        if let sourceID = input.sourceID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !sourceID.isEmpty {
            let row = try Row.fetchOne(db, sql: """
                SELECT id FROM articles
                WHERE feedID = ? AND sourceID = ?
                LIMIT 1
                """, arguments: [input.feedID, sourceID])
            if let id = row?["id"] as String? {
                return id
            }
        }

        if let link = input.link?.trimmingCharacters(in: .whitespacesAndNewlines),
           !link.isEmpty {
            let row = try Row.fetchOne(db, sql: """
                SELECT id FROM articles
                WHERE feedID = ? AND link = ?
                LIMIT 1
                """, arguments: [input.feedID, link])
            return row?["id"] as String?
        }

        return nil
    }
}

extension ArticleReaderSnapshot: FetchableRecord {
    init(row: Row) throws {
        id = row["id"]
        feedID = row["feedID"]
        feedTitle = row["feedTitle"]
        title = row["title"]
        link = row["link"]
        summary = row["summary"]
        content = row["content"]
        imageURL = row["imageURL"]
        author = row["author"]
        publishedAt = row["publishedAt"]
        arrivedAt = row["arrivedAt"]
        estimatedReadingMinutes = row["estimatedReadingMinutes"]
        isRead = row["isRead"]
        isStarred = row["isStarred"]
        isArchived = row["isArchived"]
        isHidden = row["isHidden"]
    }
}
```

- [ ] **Step 5: Run article-store tests**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteArticleStoreTests
```

Expected: `SQLiteArticleStoreTests` passes.

- [ ] **Step 6: Commit article store**

```bash
git add Feedivo/Snapshots/ArticleReaderSnapshot.swift Feedivo/Stores/ArticleStore.swift FeedivoTests/SQLiteArticleStoreTests.swift
git commit -m "feat: add sqlite article store"
```

---

### Task 7: Timeline Store and List Snapshots

**Files:**
- Create: `Feedivo/Snapshots/ArticleListSnapshot.swift`
- Create: `Feedivo/Stores/TimelineStore.swift`
- Create: `FeedivoTests/SQLiteTimelineStoreTests.swift`

- [ ] **Step 1: Write failing timeline tests**

Create `FeedivoTests/SQLiteTimelineStoreTests.swift`:

```swift
import Foundation
import Testing
@testable import Feedivo

struct SQLiteTimelineStoreTests {
    @Test func timelineFetchesNewestUnreadVisibleSnapshotsForFeed() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)
        let timelineStore = TimelineStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))
        let oldID = try articleStore.upsert(ArticleUpsertInput(feedID: "feed-1", sourceID: "old", link: "https://example.com/old", title: "Old", publishedAt: Date(timeIntervalSince1970: 100)))
        let newID = try articleStore.upsert(ArticleUpsertInput(feedID: "feed-1", sourceID: "new", link: "https://example.com/new", title: "New", publishedAt: Date(timeIntervalSince1970: 200)))
        try statusStore.setRead(true, articleID: oldID, at: Date(timeIntervalSince1970: 300))

        let snapshots = try timelineStore.articles(
            scope: .feed("feed-1"),
            includeRead: false,
            includeHidden: false,
            limit: 20
        )

        #expect(snapshots.map(\.id) == [newID])
        #expect(snapshots.first?.feedTitle == "Example")
    }

    @Test func timelineHonorsLimitAndSortsByPublishedThenArrivedDate() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let timelineStore = TimelineStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))
        _ = try articleStore.upsert(ArticleUpsertInput(feedID: "feed-1", sourceID: "one", link: "https://example.com/1", title: "One", publishedAt: Date(timeIntervalSince1970: 100)))
        let twoID = try articleStore.upsert(ArticleUpsertInput(feedID: "feed-1", sourceID: "two", link: "https://example.com/2", title: "Two", publishedAt: Date(timeIntervalSince1970: 200)))
        let threeID = try articleStore.upsert(ArticleUpsertInput(feedID: "feed-1", sourceID: "three", link: "https://example.com/3", title: "Three", publishedAt: nil, arrivedAt: Date(timeIntervalSince1970: 300)))

        let snapshots = try timelineStore.articles(scope: .all, includeRead: true, includeHidden: false, limit: 2)

        #expect(snapshots.map(\.id) == [threeID, twoID])
    }

    @Test func unreadCountIgnoresReadAndHiddenArticles() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)
        let timelineStore = TimelineStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))
        let unreadID = try articleStore.upsert(ArticleUpsertInput(feedID: "feed-1", sourceID: "unread", link: "https://example.com/unread", title: "Unread"))
        let readID = try articleStore.upsert(ArticleUpsertInput(feedID: "feed-1", sourceID: "read", link: "https://example.com/read", title: "Read"))
        let hiddenID = try articleStore.upsert(ArticleUpsertInput(feedID: "feed-1", sourceID: "hidden", link: "https://example.com/hidden", title: "Hidden"))

        try statusStore.setRead(true, articleID: readID, at: Date())
        try statusStore.setHidden(true, articleID: hiddenID, at: Date())

        #expect(unreadID.isEmpty == false)
        #expect(try timelineStore.unreadCount(feedID: "feed-1") == 1)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteTimelineStoreTests
```

Expected: compile fails because `TimelineStore`, `TimelineScope`, and
`ArticleListSnapshot` do not exist.

- [ ] **Step 3: Create list snapshot**

Create `Feedivo/Snapshots/ArticleListSnapshot.swift`:

```swift
import Foundation

struct ArticleListSnapshot: Equatable, Identifiable, Sendable {
    var id: String
    var feedID: String
    var feedTitle: String
    var title: String
    var summary: String?
    var link: String?
    var imageURL: String?
    var publishedAt: Date?
    var arrivedAt: Date
    var estimatedReadingMinutes: Int?
    var isRead: Bool
    var isStarred: Bool
    var isArchived: Bool
    var isHidden: Bool
}
```

- [ ] **Step 4: Create timeline store**

Create `Feedivo/Stores/TimelineStore.swift`:

```swift
import Foundation
import GRDB

enum TimelineScope: Equatable, Sendable {
    case all
    case feed(String)
}

struct TimelineStore {
    private let database: FeedivoDatabase

    init(database: FeedivoDatabase) {
        self.database = database
    }

    func articles(
        scope: TimelineScope,
        includeRead: Bool,
        includeHidden: Bool,
        limit: Int
    ) throws -> [ArticleListSnapshot] {
        let safeLimit = max(1, limit)
        var whereClauses: [String] = []
        var arguments = StatementArguments()

        switch scope {
        case .all:
            break
        case .feed(let feedID):
            whereClauses.append("a.feedID = ?")
            arguments.append(contentsOf: [feedID])
        }

        if !includeRead {
            whereClauses.append("s.isRead = 0")
        }

        if !includeHidden {
            whereClauses.append("s.isHidden = 0")
        }

        let whereSQL = whereClauses.isEmpty ? "" : "WHERE " + whereClauses.joined(separator: " AND ")
        arguments.append(contentsOf: [safeLimit])

        return try database.read { db in
            try ArticleListSnapshot.fetchAll(db, sql: """
                SELECT
                    a.id,
                    a.feedID,
                    f.title AS feedTitle,
                    a.title,
                    a.summary,
                    a.link,
                    a.imageURL,
                    a.publishedAt,
                    a.arrivedAt,
                    a.estimatedReadingMinutes,
                    s.isRead,
                    s.isStarred,
                    s.isArchived,
                    s.isHidden
                FROM articles a
                JOIN feeds f ON f.id = a.feedID
                JOIN article_statuses s ON s.articleID = a.id
                \(whereSQL)
                ORDER BY COALESCE(a.publishedAt, a.arrivedAt) DESC, a.arrivedAt DESC
                LIMIT ?
                """, arguments: arguments)
        }
    }

    func unreadCount(feedID: String) throws -> Int {
        try database.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*)
                FROM articles a
                JOIN article_statuses s ON s.articleID = a.id
                WHERE a.feedID = ? AND s.isRead = 0 AND s.isHidden = 0
                """, arguments: [feedID]) ?? 0
        }
    }
}

extension ArticleListSnapshot: FetchableRecord {
    init(row: Row) throws {
        id = row["id"]
        feedID = row["feedID"]
        feedTitle = row["feedTitle"]
        title = row["title"]
        summary = row["summary"]
        link = row["link"]
        imageURL = row["imageURL"]
        publishedAt = row["publishedAt"]
        arrivedAt = row["arrivedAt"]
        estimatedReadingMinutes = row["estimatedReadingMinutes"]
        isRead = row["isRead"]
        isStarred = row["isStarred"]
        isArchived = row["isArchived"]
        isHidden = row["isHidden"]
    }
}
```

- [ ] **Step 5: Run timeline tests**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteTimelineStoreTests
```

Expected: `SQLiteTimelineStoreTests` passes.

- [ ] **Step 6: Commit timeline store**

```bash
git add Feedivo/Snapshots/ArticleListSnapshot.swift Feedivo/Stores/TimelineStore.swift FeedivoTests/SQLiteTimelineStoreTests.swift
git commit -m "feat: add sqlite timeline store"
```

---

### Task 8: Performance Smoke Test

**Files:**
- Create: `FeedivoTests/SQLitePerformanceSmokeTests.swift`

- [ ] **Step 1: Write performance smoke test**

Create `FeedivoTests/SQLitePerformanceSmokeTests.swift`:

```swift
import Foundation
import Testing
@testable import Feedivo

struct SQLitePerformanceSmokeTests {
    @Test func timelineAndUnreadCountsStayUsableWithLargeSyntheticDataset() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)
        let timelineStore = TimelineStore(database: database)

        for feedIndex in 0..<100 {
            let feedID = "feed-\(feedIndex)"
            try feedStore.save(
                FeedRecord(
                    id: feedID,
                    url: "https://example.com/\(feedIndex)/feed.xml",
                    title: "Feed \(feedIndex)"
                )
            )

            for articleIndex in 0..<500 {
                let articleID = try articleStore.upsert(
                    ArticleUpsertInput(
                        feedID: feedID,
                        sourceID: "source-\(feedIndex)-\(articleIndex)",
                        link: "https://example.com/\(feedIndex)/\(articleIndex)",
                        title: "Article \(articleIndex)",
                        summary: "Summary \(articleIndex)",
                        publishedAt: Date(timeIntervalSince1970: TimeInterval(articleIndex)),
                        arrivedAt: Date(timeIntervalSince1970: TimeInterval(articleIndex))
                    )
                )

                if articleIndex % 2 == 0 {
                    try statusStore.setRead(true, articleID: articleID, at: Date())
                }
            }
        }

        let start = Date()
        let snapshots = try timelineStore.articles(scope: .all, includeRead: false, includeHidden: false, limit: 50)
        let count = try timelineStore.unreadCount(feedID: "feed-42")
        let elapsed = Date().timeIntervalSince(start)

        #expect(snapshots.count == 50)
        #expect(count == 250)
        #expect(elapsed < 1.0)
    }
}
```

- [ ] **Step 2: Run smoke test**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLitePerformanceSmokeTests
```

Expected: smoke test passes. If the machine is under heavy load and only the
`elapsed < 1.0` assertion fails, rerun once before changing code. If it fails
twice, inspect the query plan with SQLite indexes before relaxing the threshold.

- [ ] **Step 3: Commit smoke test**

```bash
git add FeedivoTests/SQLitePerformanceSmokeTests.swift
git commit -m "test: add sqlite performance smoke test"
```

---

### Task 9: Documentation and Full Verification

**Files:**
- Modify: `AGENTS.md`
- Modify: `FEATURES.md`

- [ ] **Step 1: Update `FEATURES.md`**

Under Feature 26.2, append this bullet to `Umgesetzt`:

```markdown
  - SQLite/GRDB-Fundament angelegt: GRDB Package, `FeedivoDatabase`, v1-
    Migrationen für `feeds`, `articles`, `article_statuses` und `feed_logs`,
    Record-Typen, erste Stores für Feeds/Artikel/Status/Timeline und Tests gegen
    temporäre In-Memory-Datenbanken.
```

- [ ] **Step 2: Update `AGENTS.md`**

Under `Letzte Änderungen`, add this entry:

```markdown
- 2026-07-02: Erster SQLite/GRDB-Fundament-Slice umgesetzt. Feedivo hat nun eine
  separate GRDB-basierte SQLite-Schicht mit v1-Migrationen, Record-Typen,
  testbaren Stores für Feeds, Artikel, Artikelstatus und Timeline-Snapshots
  sowie In-Memory-Tests. Der bestehende SwiftData-App-Pfad bleibt unverändert;
  UI- und Refresh-Umbau folgen in späteren Slices.
```

- [ ] **Step 3: Run focused SQLite tests**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteDatabaseMigrationTests -only-testing:FeedivoTests/SQLiteFeedStoreTests -only-testing:FeedivoTests/SQLiteArticleStatusStoreTests -only-testing:FeedivoTests/SQLiteArticleStoreTests -only-testing:FeedivoTests/SQLiteTimelineStoreTests -only-testing:FeedivoTests/SQLitePerformanceSmokeTests
```

Expected: all SQLite tests pass.

- [ ] **Step 4: Run full test suite**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'
```

Expected: full test suite passes.

- [ ] **Step 5: Review git status**

Run:

```bash
git status --short --branch
```

Expected: changed files are only SQLite implementation, SQLite tests, package
resolution/project files, and documentation. Do not stage
`Feedivo.xcodeproj/project.xcworkspace/xcuserdata/martinfelder.xcuserdatad/UserInterfaceState.xcuserstate`.

- [ ] **Step 6: Commit documentation and any remaining verified implementation**

```bash
git add AGENTS.md FEATURES.md Feedivo FeedivoTests Feedivo.xcodeproj/project.pbxproj Feedivo.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
git commit -m "feat: add sqlite grdb foundation"
```

Expected: commit succeeds and the Xcode UI state remains unstaged if it changed.

---

## Review Checklist

- Migration covers `feeds`, `articles`, `article_statuses`, and `feed_logs`.
- `article_statuses` has no cascade foreign key to `articles`.
- `articles(feedID, sourceID)` and `articles(feedID, link)` are unique only for
  non-empty values.
- Status updates write only `article_statuses`.
- Timeline queries return value snapshots, not SwiftData models.
- Tests use in-memory SQLite and do not require existing app data.
- Existing SwiftData app path still builds and tests.
