# SQLite Feed Reader Path Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Switch the normal feed reading path toward SQLite: feed article list snapshots, SQLite article ID selection, reader snapshots, and direct status writes.

**Status 2026-07-02:** Implemented. The normal feed path now opens the GRDB database from Application Support, renders selected feeds through `SQLiteFeedArticleListView`, tracks `selectedSQLiteArticleID`, shows `SQLiteReaderView`, and writes read/star/archive mutations through `ArticleStatusStore`. Smart folders, tags, global filters, rules, export, offline download, and remaining sidebar/feed refresh UI wiring stay on follow-up slices.

**Architecture:** The legacy SwiftData path stays in place for smart folders, tags, filters, export, rules, and offline features. The new feed-only path resolves a SwiftData `Feed.url` to a SQLite `FeedRecord`, renders `TimelineStore` snapshots, selects SQLite article IDs, loads `ArticleReaderSnapshot`, and mutates `ArticleStatusStore`.

**Tech Stack:** SwiftUI, Swift, GRDB, Swift Testing, `xcodebuild`.

---

## File Structure

- Create: `Feedivo/Database/FeedivoDatabaseLocation.swift`
  - Computes the app SQLite URL under Application Support.

- Create: `Feedivo/Database/FeedivoDatabaseEnvironment.swift`
  - Adds `EnvironmentValues.feedivoDatabase`.

- Modify: `Feedivo/App/FeedivoApp.swift`
  - Opens `FeedivoDatabase` and injects it into windows.

- Modify: `Feedivo/Views/ArticleList/ArticleListItemSnapshot.swift`
  - Adds an initializer from `ArticleListSnapshot`.

- Create: `Feedivo/ViewModels/SQLiteArticleNavigationState.swift`
  - Tracks previous/next SQLite article IDs.

- Modify: `Feedivo/Views/Reader/ReaderPreparedArticle.swift`
  - Adds `ReaderArticleInput.make(from snapshot: ArticleReaderSnapshot)`.

- Create: `Feedivo/Views/Reader/SQLiteReaderView.swift`
  - Loads and renders `ArticleReaderSnapshot`.
  - Offers read/star/archive status actions via `ArticleStatusStore`.

- Create: `Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift`
  - Resolves a SwiftData `Feed` to SQLite by URL.
  - Loads `ArticleListSnapshot` rows via `TimelineStore`.
  - Uses SQLite IDs for selection and navigation.

- Modify: `Feedivo/Views/ContentView.swift`
  - Adds `selectedSQLiteArticleID`.
  - Clears legacy selection when feed path is active.
  - Shows `SQLiteReaderView` for selected SQLite article IDs.

- Modify docs:
  - `AGENTS.md`
  - `FEATURES.md`

## Task 1: SQLite Database Environment

**Files:**
- Create: `Feedivo/Database/FeedivoDatabaseLocation.swift`
- Create: `Feedivo/Database/FeedivoDatabaseEnvironment.swift`
- Modify: `Feedivo/App/FeedivoApp.swift`
- Test: `FeedivoTests/FeedivoAppSceneConfigurationTests.swift`

- [ ] **Step 1: Write failing tests**

Add tests that assert:

```swift
@Test func appOpensAndInjectsSQLiteDatabase() throws
@Test func sqliteDatabaseLocationUsesApplicationSupport() throws
```

The first test scans `FeedivoApp.swift` for `private let feedivoDatabase`,
`FeedivoDatabase.open`, and `.environment(\\.feedivoDatabase, feedivoDatabase)`.
The second test calls `FeedivoDatabaseLocation.databaseURL(applicationSupportDirectory:bundleIdentifier:)`
and expects the last path components `Feedivo/feedivo.sqlite`.

- [ ] **Step 2: Run tests to verify red**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoAppSceneConfigurationTests
```

Expected: fail because the location/environment files and app injection do not exist.

- [ ] **Step 3: Implement minimal code**

Create `FeedivoDatabaseLocation` with:

```swift
enum FeedivoDatabaseLocation {
    static func databaseURL(
        applicationSupportDirectory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0],
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "Feedivo"
    ) -> URL
}
```

The result should be:
`<Application Support>/<bundleIdentifier>/Feedivo/feedivo.sqlite`.

Create `FeedivoDatabaseEnvironmentKey` with optional `FeedivoDatabase?`.

In `FeedivoApp`, add `private let feedivoDatabase: FeedivoDatabase` and open it in
`init()`. If open fails, use `FeedivoDatabase.inMemoryForTests()` as a last-resort
fallback so the app still launches.

Inject into the main window, article search window, article window group, and settings.

- [ ] **Step 4: Run tests to verify green**

Run the same test command. Expected: `TEST SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Database/FeedivoDatabaseLocation.swift Feedivo/Database/FeedivoDatabaseEnvironment.swift Feedivo/App/FeedivoApp.swift FeedivoTests/FeedivoAppSceneConfigurationTests.swift
git commit -m "feat: inject sqlite database environment"
```

## Task 2: Snapshot Mapping and SQLite Navigation

**Files:**
- Modify: `Feedivo/Views/ArticleList/ArticleListItemSnapshot.swift`
- Create: `Feedivo/ViewModels/SQLiteArticleNavigationState.swift`
- Modify: `Feedivo/Views/Reader/ReaderPreparedArticle.swift`
- Test:
  - `FeedivoTests/ArticleListItemSnapshotTests.swift`
  - `FeedivoTests/SQLiteArticleNavigationStateTests.swift`
  - `FeedivoTests/ReaderPreparedArticleTests.swift`

- [ ] **Step 1: Write failing tests**

Add tests:

```swift
@Test func articleListItemSnapshotCanBeBuiltFromSQLiteSnapshot() throws
@Test func sqliteNavigationFindsPreviousAndNextIDs() throws
@Test func readerInputCanBeBuiltFromSQLiteReaderSnapshot() throws
```

The snapshot initializer must map title, summary, feed title, published date,
status booleans, image URL and link availability. Offline state must be `.none`.

- [ ] **Step 2: Run tests to verify red**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ArticleListItemSnapshotTests -only-testing:FeedivoTests/SQLiteArticleNavigationStateTests -only-testing:FeedivoTests/ReaderPreparedArticleTests
```

Expected: fail because the new initializer/navigation/input builder do not exist.

- [ ] **Step 3: Implement minimal code**

Add:

```swift
init(sqlite snapshot: ArticleListSnapshot)
```

Use `PersistentIdentifier?` no longer possible for SQLite IDs, so change
`ArticleListItemSnapshot.id` from `PersistentIdentifier` to `String`, and set the
SwiftData initializer to `article.persistentModelID.id.description`.

Add:

```swift
struct SQLiteArticleNavigationState: Equatable {
    static let empty = SQLiteArticleNavigationState()
    let previousArticleID: String?
    let nextArticleID: String?
    init(articleIDs: [String], selectedArticleID: String?)
}
```

Add `ReaderArticleInput.make(from snapshot: ArticleReaderSnapshot)` with offline
state `.none` and feed title/date/link/content from the snapshot.

- [ ] **Step 4: Run tests to verify green**

Run the same command. Expected: `TEST SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Views/ArticleList/ArticleListItemSnapshot.swift Feedivo/ViewModels/SQLiteArticleNavigationState.swift Feedivo/Views/Reader/ReaderPreparedArticle.swift FeedivoTests/ArticleListItemSnapshotTests.swift FeedivoTests/SQLiteArticleNavigationStateTests.swift FeedivoTests/ReaderPreparedArticleTests.swift
git commit -m "feat: add sqlite article snapshots"
```

## Task 3: SQLite Reader State and View

**Files:**
- Create: `Feedivo/ViewModels/SQLiteReaderState.swift`
- Create: `Feedivo/Views/Reader/SQLiteReaderView.swift`
- Test: `FeedivoTests/SQLiteReaderStateTests.swift`

- [ ] **Step 1: Write failing tests**

Add tests:

```swift
@Test func readerStateLoadsSnapshotAndPreparedArticle() throws
@Test func readerStateTogglesReadAndReloadsSnapshot() throws
@Test func readerStateTogglesStarredAndReloadsSnapshot() throws
```

Use `FeedivoDatabase.inMemoryForTests()`, `FeedStore`, `ArticleStore`, and
`ArticleStatusStore`.

- [ ] **Step 2: Run test to verify red**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteReaderStateTests
```

Expected: fail because `SQLiteReaderState` does not exist.

- [ ] **Step 3: Implement minimal code**

Add `@Observable final class SQLiteReaderState` with:

```swift
var snapshot: ArticleReaderSnapshot?
var preparedArticle: ReaderPreparedArticle
func load(articleID: String, database: FeedivoDatabase)
func toggleRead(database: FeedivoDatabase)
func toggleStarred(database: FeedivoDatabase)
func toggleArchived(database: FeedivoDatabase)
```

`SQLiteReaderView` reads the database from environment, calls state load on
`.task(id: articleID)`, renders title/metadata/content blocks, and provides simple
toolbar/status buttons.

- [ ] **Step 4: Run test to verify green**

Run same command. Expected: `TEST SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add Feedivo/ViewModels/SQLiteReaderState.swift Feedivo/Views/Reader/SQLiteReaderView.swift FeedivoTests/SQLiteReaderStateTests.swift
git commit -m "feat: add sqlite reader view"
```

## Task 4: SQLite Feed Article List

**Files:**
- Create: `Feedivo/ViewModels/SQLiteFeedArticleListState.swift`
- Create: `Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift`
- Test: `FeedivoTests/SQLiteFeedArticleListStateTests.swift`

- [ ] **Step 1: Write failing tests**

Add tests:

```swift
@Test func listStateResolvesFeedByURLAndLoadsSnapshots() throws
@Test func listStateTogglesReadAndRefreshesRows() throws
@Test func listStateReportsMissingSQLiteFeed() throws
```

- [ ] **Step 2: Run test to verify red**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedArticleListStateTests
```

Expected: fail because state/view do not exist.

- [ ] **Step 3: Implement minimal code**

Add `@Observable final class SQLiteFeedArticleListState` with:

```swift
enum LoadState: Equatable { case idle, missingSQLiteDatabase, missingFeed, loaded }
var rows: [ArticleListSnapshot]
var navigationState: SQLiteArticleNavigationState
func load(swiftDataFeedURL: String, database: FeedivoDatabase?, selectedArticleID: String?)
func toggleRead(articleID: String, database: FeedivoDatabase)
func toggleStarred(articleID: String, database: FeedivoDatabase)
func toggleArchived(articleID: String, database: FeedivoDatabase)
```

The view renders rows through `ArticleRowView(snapshot: ArticleListItemSnapshot(sqlite: row), ...)`.
Disable tag/rule/export/offline menu actions for SQLite rows by passing no-op closures and
`hasAvailableTags: false`.

- [ ] **Step 4: Run test to verify green**

Run same command. Expected: `TEST SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add Feedivo/ViewModels/SQLiteFeedArticleListState.swift Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift FeedivoTests/SQLiteFeedArticleListStateTests.swift
git commit -m "feat: add sqlite feed article list"
```

## Task 5: ContentView Feed Path Wiring

**Files:**
- Modify: `Feedivo/Views/ContentView.swift`
- Test: `FeedivoTests/FeedivoAppSceneConfigurationTests.swift`

- [ ] **Step 1: Write failing tests**

Add source-scanning tests:

```swift
@Test func contentViewKeepsSeparateSQLiteArticleSelection() throws
@Test func contentViewUsesSQLiteFeedArticleListForSelectedFeed() throws
@Test func contentViewUsesSQLiteReaderForSQLiteSelection() throws
```

- [ ] **Step 2: Run test to verify red**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoAppSceneConfigurationTests
```

Expected: fail because `ContentView` still uses only `ArticleListView(feed:)` and `ReaderView(article:)`.

- [ ] **Step 3: Implement minimal code**

Add:

```swift
@State private var selectedSQLiteArticleID: String?
@State private var sqliteArticleNavigationState = SQLiteArticleNavigationState.empty
```

For `selectedFeed`, render `SQLiteFeedArticleListView(feed:selectedArticleID:navigationState:)`.
For detail, if `selectedSQLiteArticleID != nil`, render `SQLiteReaderView`.
Clear `selectedArticle` when SQLite selection changes and clear `selectedSQLiteArticleID`
when legacy sidebar paths are selected.

- [ ] **Step 4: Run test to verify green**

Run same command. Expected: `TEST SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Views/ContentView.swift FeedivoTests/FeedivoAppSceneConfigurationTests.swift
git commit -m "feat: wire sqlite feed reader path"
```

## Task 6: Documentation and Verification

**Files:**
- Modify: `AGENTS.md`
- Modify: `FEATURES.md`

- [ ] **Step 1: Update docs**

Document that normal feed selection has a SQLite UI path for list/reader/status,
while smart folders/tags/global filters remain legacy.

- [ ] **Step 2: Run focused tests**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoAppSceneConfigurationTests -only-testing:FeedivoTests/ArticleListItemSnapshotTests -only-testing:FeedivoTests/SQLiteArticleNavigationStateTests -only-testing:FeedivoTests/ReaderPreparedArticleTests -only-testing:FeedivoTests/SQLiteReaderStateTests -only-testing:FeedivoTests/SQLiteFeedArticleListStateTests -only-testing:FeedivoTests/SQLiteArticleStoreTests -only-testing:FeedivoTests/SQLiteArticleStatusStoreTests -only-testing:FeedivoTests/SQLiteFeedStoreTests -only-testing:FeedivoTests/SQLiteTimelineStoreTests
```

Expected: `TEST SUCCEEDED`.

- [ ] **Step 3: Run app build**

Run:

```bash
xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add AGENTS.md FEATURES.md docs/superpowers/plans/2026-07-02-sqlite-feed-reader-path.md
git commit -m "docs: update sqlite feed reader progress"
```

## Self-Review

- Spec coverage: The plan covers environment injection, feed URL resolution,
  SQLite list snapshots, SQLite reader snapshots, status-only mutations, selection
  separation, and documentation. Smart folders, tags, export, rules and offline
  remain out of scope as specified.
- Placeholder scan: No `TBD`/`TODO` placeholders remain.
- Type consistency: `selectedSQLiteArticleID`, `SQLiteArticleNavigationState`,
  `SQLiteReaderState`, and `SQLiteFeedArticleListState` are introduced before use.
