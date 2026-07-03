# SQLite Migration Closure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the remaining SQLite/GRDB migration gaps in Feedivo's user-facing data paths.

**Architecture:** Keep SwiftData only for transition data and configuration models where it is still intentionally the owner. Move article-heavy reads and writes to GRDB stores: rule previews/backfills, offline state/content, retention cleanup, OPML export/import mirroring, and article export snapshots.

**Tech Stack:** SwiftUI, SwiftData transition models, GRDB, Swift Testing, xcodebuild.

---

## Scope

- [x] Rule preview counts and "apply to existing articles" use SQLite article snapshots instead of `@Query` materialized `Article` values.
- [x] SQLite articles store offline state/content so Reader, archive/offline actions, storage summary, and cleanup can operate without SwiftData article blobs.
- [x] Article retention cleanup deletes expired SQLite articles and recalculates SQLite unread counts.
- [x] OPML export can be sourced from SQLite feed/tag snapshots, and OPML import/refresh continues to populate SQLite.
- [x] Article export can prepare snapshots from SQLite reader articles.
- [x] Documentation records what remains intentionally SwiftData-owned.
- [x] Focused tests, full build, and diff checks verify the closure.

## Execution Notes

- Worktree: `/Users/martinfelder/Developer/FeedivoMac/.worktrees/sqlite-grdb-foundation`
- Branch: `codex/sqlite-grdb-foundation`
- Use TDD for each behavior change: add focused failing test, verify red, implement, verify green.
- Do not remove SwiftData models wholesale in this pass; feeds, rules, smart-folder definitions and settings still use them as transition/configuration objects.
