# SQLite Refresh Snapshot Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first NetNewsWire-like SQLite refresh path for Feedivo.

**Architecture:** `FeedService` remains responsible for fetching and parsing feeds. New SQLite stores and a `SQLiteFeedRefreshService` write parsed feed data into GRDB in small, direct operations: articles in `articles`, read/star/archive/hidden state in `article_statuses`, feed metadata in `feeds`, and refresh diagnostics in `feed_logs`.

**Tech Stack:** Swift, GRDB, Swift Testing, macOS XCTest runner via `xcodebuild`.

---

## File Structure

- Modify: `Feedivo/Stores/ArticleStore.swift`
  - Add `ArticleUpsertResult`.
  - Add batch upsert that runs inside one SQLite write transaction.
  - Keep single-item `upsert` as a wrapper for existing callers.

- Modify: `Feedivo/Stores/ArticleStatusStore.swift`
  - Add unread counting and bulk status ensure helpers.

- Modify: `Feedivo/Stores/FeedStore.swift`
  - Add lookup by URL.
  - Add refresh metadata and unread-count update helpers.

- Create: `Feedivo/Stores/FeedLogStore.swift`
  - Append and read feed refresh logs.

- Create: `Feedivo/Services/SQLiteFeedRefreshService.swift`
  - Coordinate conditional fetch, parsed article mapping, article upsert, count refresh, and logging.

- Modify/Create tests:
  - `FeedivoTests/SQLiteArticleStoreTests.swift`
  - `FeedivoTests/SQLiteArticleStatusStoreTests.swift`
  - `FeedivoTests/SQLiteFeedStoreTests.swift`
  - `FeedivoTests/SQLiteFeedLogStoreTests.swift`
  - `FeedivoTests/SQLiteFeedRefreshServiceTests.swift`

- Modify docs:
  - `AGENTS.md`
  - `FEATURES.md`

---

### Task 1: Batch Article Upsert

**Files:**
- Modify: `Feedivo/Stores/ArticleStore.swift`
- Modify: `FeedivoTests/SQLiteArticleStoreTests.swift`

- [ ] **Step 1: Write the failing test**

Add tests named:

```swift
@Test func batchUpsertReturnsInsertedAndUpdatedIDs() throws
@Test func batchUpsertRunsInOneTransactionAndPreservesStatus() throws
```

The first test inserts two articles, then upserts one existing and one new article.
It expects `insertedArticleIDs.count == 1`, `updatedArticleIDs.count == 1`, and no
duplicate for the existing `sourceID`.

The second test marks an existing article read, batch-upserts the same article,
and expects the status to remain read and `dateArrived` unchanged.

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteArticleStoreTests
```

Expected: fail because `upsert(_ inputs:)` and `ArticleUpsertResult` do not exist.

- [ ] **Step 3: Implement minimal code**

Add:

```swift
struct ArticleUpsertResult: Equatable, Sendable {
    var insertedArticleIDs: [String]
    var updatedArticleIDs: [String]
    var articleIDs: [String]
}
```

Refactor `ArticleStore` so `upsert(_ input:)` calls `upsert([input])`. The batch
method must use one `database.write` block, reuse the existing identity lookup,
insert `ArticleStatusRecord` only for new articles, and return inserted/updated IDs.

- [ ] **Step 4: Run test to verify it passes**

Run the same `xcodebuild test` command. Expected: `TEST SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Stores/ArticleStore.swift FeedivoTests/SQLiteArticleStoreTests.swift
git commit -m "feat: add sqlite article batch upsert"
```

### Task 2: Feed Counts, Metadata, and Logs

**Files:**
- Modify: `Feedivo/Stores/ArticleStatusStore.swift`
- Modify: `Feedivo/Stores/FeedStore.swift`
- Create: `Feedivo/Stores/FeedLogStore.swift`
- Modify/Create tests:
  - `FeedivoTests/SQLiteArticleStatusStoreTests.swift`
  - `FeedivoTests/SQLiteFeedStoreTests.swift`
  - `FeedivoTests/SQLiteFeedLogStoreTests.swift`

- [ ] **Step 1: Write failing tests**

Add tests named:

```swift
@Test func unreadCountForFeedIgnoresReadAndHiddenArticles() throws
@Test func feedByURLFindsExistingRecord() throws
@Test func updateAfterRefreshStoresValidatorsAndUnreadCount() throws
@Test func appendLogPersistsNewestFirst() throws
```

Expected APIs:

```swift
try statusStore.unreadCount(feedID: "feed-1")
try feedStore.feed(url: "https://example.com/feed.xml")
try feedStore.updateAfterRefresh(...)
try logStore.append(...)
try logStore.logs(feedID: "feed-1", limit: 10)
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteArticleStatusStoreTests -only-testing:FeedivoTests/SQLiteFeedStoreTests -only-testing:FeedivoTests/SQLiteFeedLogStoreTests
```

Expected: fail because the new store methods and `FeedLogStore` do not exist.

- [ ] **Step 3: Implement minimal code**

Implement:

```swift
func unreadCount(feedID: String) throws -> Int
func feed(url: String) throws -> FeedRecord?
func updateAfterRefresh(feedID: String, title: String?, websiteURL: String?, validators: FeedHTTPValidators, unreadCount: Int, refreshedAt: Date) throws
func setUnreadCount(_ unreadCount: Int, feedID: String) throws
struct FeedLogStore { func append(_ log: FeedLogRecord) throws; func logs(feedID: String, limit: Int) throws -> [FeedLogRecord] }
```

Keep title updates conservative: use a non-empty parsed title, but leave folder,
favicon and user-controlled fields untouched.

- [ ] **Step 4: Run tests to verify pass**

Run the same command. Expected: `TEST SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Stores/ArticleStatusStore.swift Feedivo/Stores/FeedStore.swift Feedivo/Stores/FeedLogStore.swift FeedivoTests/SQLiteArticleStatusStoreTests.swift FeedivoTests/SQLiteFeedStoreTests.swift FeedivoTests/SQLiteFeedLogStoreTests.swift
git commit -m "feat: add sqlite feed refresh stores"
```

### Task 3: SQLite Feed Refresh Service

**Files:**
- Create: `Feedivo/Services/SQLiteFeedRefreshService.swift`
- Create: `FeedivoTests/SQLiteFeedRefreshServiceTests.swift`

- [ ] **Step 1: Write failing tests**

Add tests named:

```swift
@Test func refreshInsertsParsedArticlesAndUpdatesUnreadCount() async throws
@Test func refreshNotModifiedUpdatesValidatorsAndLeavesArticlesUntouched() async throws
@Test func refreshFailureWritesErrorLogAndKeepsExistingArticles() async throws
@Test func refreshPreservesReadStatusWhenArticleUpdates() async throws
```

Use an injected fetch closure returning:

```swift
enum SQLiteFeedFetchResult {
    case updated(ParsedFeed, FeedHTTPValidators)
    case notModified(FeedHTTPValidators)
}
```

The tests should avoid the network.

- [ ] **Step 2: Run test to verify failure**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedRefreshServiceTests
```

Expected: fail because `SQLiteFeedRefreshService` does not exist.

- [ ] **Step 3: Implement minimal code**

Create:

```swift
struct SQLiteFeedRefreshResult: Equatable, Sendable {
    var feedID: String
    var insertedArticleIDs: [String]
    var updatedArticleIDs: [String]
    var unreadCount: Int
    var isNotModified: Bool
}

struct SQLiteFeedRefreshService {
    typealias Fetcher = @Sendable (String, FeedHTTPValidators) async throws -> SQLiteFeedFetchResult

    func refresh(feedID: String) async throws -> SQLiteFeedRefreshResult
}
```

The service loads the feed, builds validators from `FeedRecord`, fetches
conditionally, maps articles to `ArticleUpsertInput`, batch-upserts them, updates
the feed unread count, writes a success/not-modified/error log, and returns the
result.

- [ ] **Step 4: Run test to verify pass**

Run the same command. Expected: `TEST SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Services/SQLiteFeedRefreshService.swift FeedivoTests/SQLiteFeedRefreshServiceTests.swift
git commit -m "feat: add sqlite feed refresh service"
```

### Task 4: Documentation and Verification

**Files:**
- Modify: `AGENTS.md`
- Modify: `FEATURES.md`

- [ ] **Step 1: Update docs**

Document that the SQLite refresh core exists, but the visible app still uses the
old SwiftData UI path until the next UI-integration slice.

- [ ] **Step 2: Run focused tests**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteArticleStoreTests -only-testing:FeedivoTests/SQLiteArticleStatusStoreTests -only-testing:FeedivoTests/SQLiteFeedStoreTests -only-testing:FeedivoTests/SQLiteFeedLogStoreTests -only-testing:FeedivoTests/SQLiteFeedRefreshServiceTests -only-testing:FeedivoTests/SQLiteTimelineStoreTests
```

Expected: `TEST SUCCEEDED`.

- [ ] **Step 3: Run build**

Run:

```bash
xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add AGENTS.md FEATURES.md docs/superpowers/plans/2026-07-02-sqlite-refresh-snapshot-integration.md
git commit -m "docs: update sqlite refresh progress"
```

## Self-Review

- Spec coverage: The plan covers refresh service, store extensions, feed logs,
  status preservation, unread count updates, and snapshot-read preparation. Full UI
  switching remains intentionally out of scope.
- Placeholder scan: No `TBD` or unspecified implementation steps remain.
- Type consistency: `SQLiteFeedRefreshResult`, `SQLiteFeedFetchResult`,
  `ArticleUpsertResult`, `FeedLogStore`, and store method names are introduced
  before later tasks reference them.
