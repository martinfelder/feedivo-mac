# SQLite Feed Refresh Wiring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ensure normal feed add and refresh operations populate the SQLite/GRDB store used by the new feed reader path.

**Status 2026-07-02:** Implemented. Feed add, selected-feed refresh and all-feeds refresh now receive the SwiftUI `FeedivoDatabase` environment value and populate SQLite for the new feed reader path. Focused tests and app build are part of the final verification for this slice.

**Architecture:** Keep the existing SwiftData feed workflows intact during the transition, but mirror feed/article data into SQLite whenever a feed is added or refreshed. The UI passes the already-open `FeedivoDatabase` environment value into `FeedViewModel`; if SQLite is unavailable, the old SwiftData path still works.

**Tech Stack:** Swift, SwiftData, GRDB, Swift Testing, `xcodebuild`.

---

## File Structure

- Modify: `Feedivo/ViewModels/FeedViewModel.swift`
  - Add optional `sqliteDatabase` parameters to add and refresh methods.
  - Add helper methods for saving a SwiftData feed snapshot to SQLite and refreshing SQLite by feed URL.

- Modify: `Feedivo/Views/ContentView.swift`
  - Read `feedivoDatabase` from the environment.
  - Pass it into selected-feed refresh and all-feeds refresh.

- Modify: `Feedivo/Views/Sidebar/SidebarView.swift`
  - Read `feedivoDatabase` in `AddFeedSheet`.
  - Pass it into `FeedViewModel.addFeed`.

- Modify: `FeedivoTests/FeedViewModelTests.swift`
  - Add coverage that adding a feed mirrors feed/articles into SQLite.
  - Add coverage that refreshing a feed updates SQLite articles.

- Modify: `FeedivoTests/FeedivoAppSceneConfigurationTests.swift`
  - Add source checks that `ContentView` and `AddFeedSheet` pass the SQLite database into feed operations.

- Modify docs:
  - `AGENTS.md`
  - `FEATURES.md`
  - This plan file.

## Task 1: FeedViewModel SQLite Mirror

**Files:**
- Modify: `Feedivo/ViewModels/FeedViewModel.swift`
- Modify: `FeedivoTests/FeedViewModelTests.swift`

- [x] **Step 1: Write failing tests**

Add tests:

```swift
@Test func addFeedSpiegeltFeedUndArtikelNachSQLite() async throws
@Test func refreshFeedSchreibtAktualisierteArtikelNachSQLite() async throws
```

The first test creates an in-memory SwiftData context and `FeedivoDatabase.inMemoryForTests()`, calls:

```swift
await viewModel.addFeed(
    urlString: "https://example.com/feed.xml",
    context: context,
    sqliteDatabase: sqliteDatabase
)
```

Then assert:

```swift
let sqliteFeed = try FeedStore(database: sqliteDatabase).feed(url: "https://example.com/feed.xml")
#expect(sqliteFeed?.title == "Example")
let rows = try TimelineStore(database: sqliteDatabase).articles(
    scope: .feed(sqliteFeed!.id),
    includeRead: true,
    includeHidden: false,
    limit: 20
)
#expect(rows.map(\.title) == ["First"])
```

The second test inserts a SwiftData feed and matching SQLite feed first, calls:

```swift
await viewModel.refreshFeed(feed, context: context, sqliteDatabase: sqliteDatabase)
```

Then assert the SQLite timeline contains the refreshed article title.

- [x] **Step 2: Run tests to verify red**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedViewModelTests
```

Expected: fail because `sqliteDatabase` parameters and mirror helpers do not exist.

- [x] **Step 3: Implement minimal code**

In `FeedViewModel`:

```swift
func addFeed(urlString: String, context: ModelContext, sqliteDatabase: FeedivoDatabase? = nil) async
func refreshFeed(_ feed: Feed?, context: ModelContext, sqliteDatabase: FeedivoDatabase? = nil) async
func refreshAllFeeds(_ feeds: [Feed], context: ModelContext, sqliteDatabase: FeedivoDatabase? = nil) async
func refreshAllFeeds(_ feeds: [Feed], modelContainer: ModelContainer, sqliteDatabase: FeedivoDatabase? = nil) async
```

Add helpers:

```swift
private func mirrorFeedToSQLite(_ feed: Feed, database: FeedivoDatabase) throws
private func refreshSQLiteFeed(_ feed: Feed, database: FeedivoDatabase) async throws -> SQLiteFeedRefreshResult
```

`mirrorFeedToSQLite` saves a `FeedRecord` using `feed.id.uuidString` as the SQLite ID and upserts current `feed.articles` with `ArticleStore`.

`refreshSQLiteFeed` ensures the feed record exists and calls `SQLiteFeedRefreshService.refresh(feedID:)`.

- [x] **Step 4: Run tests to verify green**

Run the same test command. Expected: `TEST SUCCEEDED`.

- [x] **Step 5: Commit**

```bash
git add Feedivo/ViewModels/FeedViewModel.swift FeedivoTests/FeedViewModelTests.swift
git commit -m "feat: mirror feed refreshes to sqlite"
```

## Task 2: UI Wiring

**Files:**
- Modify: `Feedivo/Views/ContentView.swift`
- Modify: `Feedivo/Views/Sidebar/SidebarView.swift`
- Modify: `FeedivoTests/FeedivoAppSceneConfigurationTests.swift`

- [x] **Step 1: Write failing source tests**

Add tests:

```swift
@Test func contentViewPassesSQLiteDatabaseToFeedRefreshes() throws
@Test func addFeedSheetPassesSQLiteDatabaseToFeedViewModel() throws
```

Assert `ContentView.swift` contains `@Environment(\\.feedivoDatabase)` and passes `sqliteDatabase: feedivoDatabase` to `refreshFeed` and `refreshAllFeeds`.

Assert `SidebarView.swift` contains `@Environment(\\.feedivoDatabase)` in `AddFeedSheet` and passes `sqliteDatabase: feedivoDatabase` to `addFeed`.

- [x] **Step 2: Run tests to verify red**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoAppSceneConfigurationTests
```

Expected: fail because UI wiring is missing.

- [x] **Step 3: Implement minimal code**

In `ContentView`, add:

```swift
@Environment(\.feedivoDatabase) private var feedivoDatabase
```

Pass `sqliteDatabase: feedivoDatabase` to:

```swift
feedViewModel.refreshFeed(selectedFeed, context: modelContext, sqliteDatabase: feedivoDatabase)
feedViewModel.refreshAllFeeds(feeds, modelContainer: modelContainer, sqliteDatabase: feedivoDatabase)
feedViewModel.refreshAllFeeds(feeds, context: modelContext, sqliteDatabase: feedivoDatabase)
```

In `AddFeedSheet`, add the same environment property and call:

```swift
await viewModel.addFeed(urlString: urlString, context: modelContext, sqliteDatabase: feedivoDatabase)
```

- [x] **Step 4: Run tests to verify green**

Run the same source-test command. Expected: `TEST SUCCEEDED`.

- [x] **Step 5: Commit**

```bash
git add Feedivo/Views/ContentView.swift Feedivo/Views/Sidebar/SidebarView.swift FeedivoTests/FeedivoAppSceneConfigurationTests.swift
git commit -m "feat: pass sqlite database to feed operations"
```

## Task 3: Documentation and Verification

**Files:**
- Modify: `AGENTS.md`
- Modify: `FEATURES.md`
- Modify: `docs/superpowers/plans/2026-07-02-sqlite-feed-refresh-wiring.md`

- [x] **Step 1: Update docs**

Document that add-feed and refresh operations now mirror data into SQLite for the new feed reader path.

- [x] **Step 2: Run focused verification**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedViewModelTests -only-testing:FeedivoTests/FeedivoAppSceneConfigurationTests -only-testing:FeedivoTests/SQLiteFeedRefreshServiceTests -only-testing:FeedivoTests/SQLiteFeedArticleListStateTests
```

Expected: `TEST SUCCEEDED`.

- [x] **Step 3: Run app build**

Run:

```bash
xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'
```

Expected: `BUILD SUCCEEDED`.

- [x] **Step 4: Commit**

```bash
git add AGENTS.md FEATURES.md docs/superpowers/plans/2026-07-02-sqlite-feed-refresh-wiring.md
git commit -m "docs: update sqlite refresh wiring"
```

## Self-Review

- Spec coverage: This plan connects the newly wired SQLite feed reader path to real feed add/refresh writes, while preserving SwiftData fallback behavior.
- Placeholder scan: No TBD/TODO placeholders remain.
- Type consistency: All method signatures use optional `FeedivoDatabase?` with default `nil`, preserving existing call sites and tests.
