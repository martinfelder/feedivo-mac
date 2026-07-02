# SQLite Sidebar Feed Snapshots Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render normal feed rows and unread feed visibility from SQLite snapshots while keeping SwiftData feed objects for selection, rename, properties and deletion during the transition.

**Status 2026-07-02:** Implemented. Sidebar feed rows now prefer SQLite snapshots for title, favicon and unread count, while existing SwiftData feed objects remain responsible for selection, context menus and feed management actions.

**Architecture:** Add a small `SQLiteSidebarState` that loads `FeedSidebarSnapshot` rows from `FeedStore`. `SidebarView` keeps its existing SwiftData `@Query` for feed identity and actions, but overlays SQLite display data by matching `Feed.id.uuidString` to `FeedSidebarSnapshot.id`. `FeedRowView` accepts an optional SQLite snapshot and reads title, favicon and unread badge from it when available.

**Tech Stack:** Swift, SwiftUI, SwiftData, GRDB, Swift Testing, `xcodebuild`.

---

## File Structure

- Modify: `Feedivo/Stores/FeedStore.swift`
  - Add a `sidebarFeeds(showsReadFeeds:)` overload so SQLite can filter read feeds before the Sidebar renders.

- Create: `Feedivo/ViewModels/SQLiteSidebarState.swift`
  - Load SQLite feed sidebar snapshots.
  - Expose snapshots by feed ID and visible SwiftData feeds.

- Modify: `Feedivo/Views/Sidebar/FeedRowView.swift`
  - Add optional `FeedSidebarSnapshot`.
  - Prefer snapshot title, favicon and unread count when present.

- Modify: `Feedivo/Views/Sidebar/SidebarView.swift`
  - Read `feedivoDatabase` from the environment.
  - Load `SQLiteSidebarState`.
  - Use SQLite snapshots for feed visibility and feed rows.

- Modify tests:
  - `FeedivoTests/SQLiteFeedStoreTests.swift`
  - Create `FeedivoTests/SQLiteSidebarStateTests.swift`
  - `FeedivoTests/FeedivoAppSceneConfigurationTests.swift`

## Task 1: FeedStore Sidebar Filtering

**Files:**
- Modify: `Feedivo/Stores/FeedStore.swift`
- Modify: `FeedivoTests/SQLiteFeedStoreTests.swift`

- [x] **Step 1: Write failing test**

Add a test:

```swift
@Test func sidebarSnapshotsCanHideReadFeeds() throws {
    let database = try FeedivoDatabase.inMemoryForTests()
    let store = FeedStore(database: database)

    try store.save(FeedRecord(id: "read", url: "https://read.example/feed.xml", title: "Read", unreadCount: 0))
    try store.save(FeedRecord(id: "unread", url: "https://unread.example/feed.xml", title: "Unread", unreadCount: 3))

    let visible = try store.sidebarFeeds(showsReadFeeds: false)

    #expect(visible.map(\.id) == ["unread"])
}
```

- [x] **Step 2: Run red**

Run:

```bash
xcodebuild test -quiet -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedStoreTests
```

Expected: fail because `sidebarFeeds(showsReadFeeds:)` does not exist.

- [x] **Step 3: Implement**

Add:

```swift
func sidebarFeeds(showsReadFeeds: Bool) throws -> [FeedSidebarSnapshot] {
    let snapshots = try sidebarFeeds()
    guard !showsReadFeeds else {
        return snapshots
    }
    return snapshots.filter { $0.unreadCount > 0 }
}
```

- [x] **Step 4: Run green**

Run the same test command. Expected: `TEST SUCCEEDED`.

- [x] **Step 5: Commit**

```bash
git add Feedivo/Stores/FeedStore.swift FeedivoTests/SQLiteFeedStoreTests.swift docs/superpowers/plans/2026-07-02-sqlite-sidebar-feed-snapshots.md
git commit -m "feat: filter sqlite sidebar feeds"
```

## Task 2: SQLiteSidebarState

**Files:**
- Create: `Feedivo/ViewModels/SQLiteSidebarState.swift`
- Create: `FeedivoTests/SQLiteSidebarStateTests.swift`

- [x] **Step 1: Write failing tests**

Add tests that load snapshots from an in-memory SQLite DB and verify:

```swift
@MainActor
@Test func loadReadsSnapshotsAndTotalUnreadCount() throws
```

and:

```swift
@MainActor
@Test func visibleSwiftDataFeedsFollowSQLiteVisibility() throws
```

The second test creates two SwiftData `Feed` objects with UUIDs matching SQLite feed IDs and asserts that `visibleFeeds(from:)` only returns the unread SQLite feed when `showsReadFeeds` is false.

- [x] **Step 2: Run red**

Run:

```bash
xcodebuild test -quiet -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteSidebarStateTests
```

Expected: fail because `SQLiteSidebarState` does not exist.

- [x] **Step 3: Implement**

Create `@Observable @MainActor final class SQLiteSidebarState` with:

```swift
private(set) var snapshots: [FeedSidebarSnapshot] = []
private(set) var totalUnreadCount = 0
private(set) var errorMessage: String?

func load(database: FeedivoDatabase?, showsReadFeeds: Bool)
func snapshot(for feed: Feed) -> FeedSidebarSnapshot?
func visibleFeeds(from feeds: [Feed], showsReadFeeds: Bool) -> [Feed]
```

- [x] **Step 4: Run green**

Run the same test command. Expected: `TEST SUCCEEDED`.

- [x] **Step 5: Commit**

```bash
git add Feedivo/ViewModels/SQLiteSidebarState.swift FeedivoTests/SQLiteSidebarStateTests.swift
git commit -m "feat: add sqlite sidebar state"
```

## Task 3: Sidebar UI Wiring

**Files:**
- Modify: `Feedivo/Views/Sidebar/FeedRowView.swift`
- Modify: `Feedivo/Views/Sidebar/SidebarView.swift`
- Modify: `FeedivoTests/FeedivoAppSceneConfigurationTests.swift`

- [x] **Step 1: Write failing source tests**

Add tests asserting:

```swift
@Test func sidebarViewLoadsSQLiteSidebarState() throws
@Test func feedRowViewPrefersSQLiteSnapshotValues() throws
```

Expected source markers:
- `@Environment(\\.feedivoDatabase) private var feedivoDatabase`
- `@State private var sqliteSidebarState = SQLiteSidebarState()`
- `sqliteSidebarState.load(database: feedivoDatabase, showsReadFeeds: showsReadFeedsInSidebar)`
- `sqliteSnapshot: sqliteSidebarState.snapshot(for: feed)`
- `let sqliteSnapshot: FeedSidebarSnapshot?`
- `sqliteSnapshot?.unreadCount`
- `sqliteSnapshot?.title`
- `sqliteSnapshot?.faviconURL`

- [x] **Step 2: Run red**

Run:

```bash
xcodebuild test -quiet -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoAppSceneConfigurationTests
```

Expected: fail because Sidebar UI wiring is missing.

- [x] **Step 3: Implement**

In `FeedRowView`, add `let sqliteSnapshot: FeedSidebarSnapshot? = nil` and use helper properties:

```swift
private var displayTitle: String { sqliteSnapshot?.title ?? feed.title }
private var displayFaviconURL: String? { sqliteSnapshot?.faviconURL ?? feed.faviconURL }
private var unreadCount: Int { sqliteSnapshot?.unreadCount ?? SidebarUnreadCount.unreadArticleCount(for: feed) }
```

In `SidebarView`, load `SQLiteSidebarState` and use it for:

```swift
let visibleFeeds = sqliteSidebarState.visibleFeeds(from: feeds, showsReadFeeds: showsReadFeedsInSidebar)
FeedRowView(feed: feed, sqliteSnapshot: sqliteSidebarState.snapshot(for: feed), ...)
```

- [x] **Step 4: Run green**

Run the same source-test command. Expected: `TEST SUCCEEDED`.

- [x] **Step 5: Commit**

```bash
git add Feedivo/Views/Sidebar/FeedRowView.swift Feedivo/Views/Sidebar/SidebarView.swift FeedivoTests/FeedivoAppSceneConfigurationTests.swift
git commit -m "feat: render sidebar feed rows from sqlite snapshots"
```

## Task 4: Documentation and Verification

**Files:**
- Modify: `AGENTS.md`
- Modify: `FEATURES.md`
- Modify this plan file.

- [x] **Step 1: Update docs**

Document that normal feed rows now prefer SQLite snapshots for title, favicon and unread counts.

- [x] **Step 2: Run focused verification**

```bash
xcodebuild test -quiet -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedStoreTests -only-testing:FeedivoTests/SQLiteSidebarStateTests -only-testing:FeedivoTests/FeedivoAppSceneConfigurationTests
```

Expected: `TEST SUCCEEDED`.

- [x] **Step 3: Run build**

```bash
xcodebuild build -quiet -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'
```

Expected: `BUILD SUCCEEDED`.

- [x] **Step 4: Commit**

```bash
git add AGENTS.md FEATURES.md docs/superpowers/plans/2026-07-02-sqlite-sidebar-feed-snapshots.md
git commit -m "docs: update sqlite sidebar progress"
```

## Self-Review

- Spec coverage: This covers the next small NetNewsWire-like step: sidebar feed display/counts move to SQLite snapshots without breaking legacy feed actions.
- Placeholder scan: No placeholders remain.
- Type consistency: `FeedSidebarSnapshot.id` remains the SwiftData feed UUID string, so `SQLiteSidebarState` can match snapshots to existing `Feed` objects.
