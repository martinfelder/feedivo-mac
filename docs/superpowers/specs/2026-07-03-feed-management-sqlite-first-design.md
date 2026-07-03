# Feed Management SQLite-First Design

## Goal

Move Feedivo's feed-management surfaces toward SQLite-first behavior while keeping SwiftData available only for transition paths that still need `Feed` model objects.

## Scope

This slice covers feed administration, not the full removal of SwiftData. The primary targets are:

- Feed rename and original-title restore.
- Feed properties for refresh interval, folder assignment, notification flag, retention settings, feed tags, logs, and metrics.
- Feed management settings rows where feed metadata is displayed or mutated.
- Sidebar feed-management entry points where they can pass a SQLite feed ID or record instead of relying on a live SwiftData `Feed`.

Out of scope for this slice:

- Rewriting FirstRun/OPML import away from `FeedViewModel`.
- Removing the SwiftData `ModelContainer`.
- Removing legacy `ArticleListView`/`ReaderView`.
- Replacing every old SwiftData helper in one sweep.

## Architecture

`FeedStore` becomes the central GRDB surface for feed administration. It will expose focused methods for mutation: display title, original-title restore, refresh interval, folder name, notification flag, retention settings, deletion, and feed tags. Views should use `FeedRecord`, `FeedSidebarSnapshot`, or a dedicated lightweight management snapshot instead of binding directly to SwiftData `Feed` whenever the UI is an administration surface.

SwiftData `Feed` can remain at boundaries that still need it, especially OPML/first-run/import paths and any existing delete/refresh path not yet converted. Those remaining boundaries should be explicit and documented as transition paths.

## Data Flow

Feed management UI loads a feed by SQLite ID through `FeedStore.feed(id:)`. Changes are saved through focused `FeedStore` methods and then reload the local record/snapshots. If a view still receives a SwiftData `Feed` from the sidebar or settings, it should immediately resolve the matching SQLite record and use that for displayed state and mutations.

Feed tags should use `TagStore` and `feed_tags`. Existing SwiftData feed tags should continue to be backfilled by `FeedTagBackfillService`, but user edits in the properties UI should write to SQLite-first.

Logs and metrics already come from SQLite and should stay that way.

## Error Handling

If the SQLite database is unavailable, management views should show the existing unavailable fallback text and avoid silently mutating SwiftData as a hidden fallback. Mutation errors should keep the sheet open and show a concise error message near the relevant control.

## Testing

Use source-guard tests to prevent regressions back to SwiftData for feed-management views, plus store tests for each new `FeedStore` mutation. Verification should include:

- `FeedStore` mutation tests in `SQLiteAdminStoreTests` or a nearby SQLite store test file.
- Source tests in `FeedivoAppSceneConfigurationTests` proving `FeedRenameView` and feed-management portions of `FeedPropertiesView` use `FeedStore`.
- Focused `xcodebuild test` for the source/store tests.
- Full app build.

## Acceptance Criteria

- Feed rename writes to SQLite through `FeedStore`, not `FeedViewModel.renameFeed`.
- Feed properties write refresh interval, folder assignment, notification flag, retention settings, and feed tags through SQLite stores.
- Feed properties continue reading logs and article metrics from SQLite.
- Project memory documents feed management as SQLite-first with SwiftData kept as transition/backfill.
- Existing visible reader/list SQLite path remains unchanged.
