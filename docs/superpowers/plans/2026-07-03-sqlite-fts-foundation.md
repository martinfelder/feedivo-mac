# SQLite FTS Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a tested SQLite FTS5 article search index for future SQLite-first search UI.

**Architecture:** Add a `v4_create_article_search_index` migration with an external-content FTS5 table and triggers on `articles`. Add `ArticleStore.searchArticles(matching:includeHidden:limit:)` returning `ArticleListSnapshot`s through the existing lightweight row model.

**Tech Stack:** Swift, GRDB, SQLite FTS5, Swift Testing.

---

### Task 1: Migration

**Files:**
- Modify: `Feedivo/Database/FeedivoDatabaseMigrator.swift`
- Modify: `Feedivo/Database/FeedivoDatabase.swift`
- Test: `FeedivoTests/SQLiteDatabaseMigrationTests.swift`

- [ ] Add failing tests that `article_search` exists and that triggers
  `articles_ai`, `articles_au`, and `articles_ad` exist.
- [ ] Run `xcodebuild test -quiet -parallel-testing-enabled NO -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteDatabaseMigrationTests` and confirm the tests fail.
- [ ] Add migration `v4_create_article_search_index` with FTS5 table, triggers,
  and rebuild.
- [ ] Re-run the migration tests and confirm they pass.

### Task 2: Search Store

**Files:**
- Modify: `Feedivo/Stores/ArticleStore.swift`
- Test: `FeedivoTests/SQLiteArticleStoreTests.swift`

- [ ] Add failing tests for searching title, summary, content, author, update,
  delete, hidden exclusion, and limit.
- [ ] Run `xcodebuild test -quiet -parallel-testing-enabled NO -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteArticleStoreTests` and confirm the tests fail.
- [ ] Implement `ArticleStore.searchArticles(matching:includeHidden:limit:)`
  using `article_search MATCH ?`, joining `articles`, `feeds`, and
  `article_statuses`.
- [ ] Re-run article store tests and confirm they pass.

### Task 3: Docs And Verification

**Files:**
- Modify: `AGENTS.md`
- Modify: `FEATURES.md`

- [ ] Document the FTS foundation as implemented, while keeping UI hookup open.
- [ ] Run targeted database/article store tests.
- [ ] Run `xcodebuild build -quiet -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`.
- [ ] Run `git diff --check`.
- [ ] Commit with `feat: add sqlite article search index`.
