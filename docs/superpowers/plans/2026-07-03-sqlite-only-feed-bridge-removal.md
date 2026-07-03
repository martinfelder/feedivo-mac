# SQLite-only Feed-Bridge Removal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Die verbleibende SwiftData-`Feed`-Brücke entfernen. `ContentView` kommt ohne `@Query [Feed]` aus; OPML-/Wizard-/Badge-/Refresh-/Delete-Pfade arbeiten direkt auf SQLite (`FeedRecord`/`FeedSidebarSnapshot`/`FeedStore`). SwiftData `Feed` wird entweder entfernt oder hart isoliert, falls noch andere SwiftData-Modelle (`Article`, `Tag`, `Rule`) daran hängen.

**Architecture:** Vorheriger Slice (`2026-07-03-sqlite-sidebar-contentview-identity.md`, Commit `34cccaf0e`) hat die Navigationsidentität auf SQLite-Feed-ID umgestellt. SwiftData `Feed` ist seitdem nur noch Aktionsbackend, per ID aufgelöst. Dieser Slice ersetzt diese Aktionsbackends durch SQLite-Pfade und entfernt dann die Brücke.

**Tech Stack:** SwiftUI, SwiftData (Übergang), GRDB, Swift Testing, xcodebuild.

---

## Scope

- [ ] `ContentView` ohne `@Query [Feed]`: First-Run-Entscheidung, OPML-Übergabe, Refresh-All, Delete, Feed-Menü `hasFeeds`, Dock-Badge aus SQLite.
- [ ] OPML-Export/Import-Sheets und FirstRunWizard: `feeds: [Feed]` → SQLite-Quelle.
- [ ] `AppIconBadgeService.unreadCount` SQLite-basiert.
- [ ] `FeedViewModel` SQLite-First: `refreshFeed(feedID:)`, `refreshAllFeeds` aus `FeedStore.feeds()`, `deleteFeed(feedID:)` via `FeedStore.delete`, `renameFeed`/`restoreOriginalFeedTitle` delegieren an `FeedStore`.
- [ ] SwiftData `Feed`-Brücke (`mirrorFeedToSQLite`, `saveSwiftDataBridge`) entfernen oder hart isolieren.
- [ ] `ArticleSearchWindowView @Query [Feed]` → SQLite.
- [ ] Fokussierte Tests, Build, Diff-Check.

## Out of scope

- SwiftData-`Article`/`Tag`/`Rule`-Modelle entfernen (nur soweit nötig, um `Feed` zu isolieren).
- iCloud/CloudKit-Aktivierung (separater Milestone).
- `NSTableView`-Artikelliste, Retention-Seen-Tabelle (siehe Vergleichs-Doku).

## Execution Notes

- Worktree: `/Users/martinfelder/Developer/FeedivoMac/.worktrees/sqlite-grdb-foundation`
- Branch: `codex/sqlite-grdb-foundation`
- TDD pro Verhaltensänderung: fokussierten Test ergänzen, rot sehen, implementieren, grün sehen.
- Vor jeder Aufgabe prüfen, ob SwiftData `Feed` noch von anderen Modellen referenziert wird (`Article.feedID` ist String, `Article.feed` Relationship prüfen). Nur entfernen, wenn keine lebenden SwiftData-Beziehungen mehr bestehen — sonst hart isolieren und klar kommentieren.
- Kommentare auf Deutsch, wie in CLAUDE.md vorgegeben.

## Tasks

- [ ] T1 — `ContentView`: `@Query [Feed]` entfernen. Ersatz: `@State private var feedSnapshots: [FeedSidebarSnapshot] = []` (geladen via `FeedStore.sidebarFeeds()` im `.task`/`onChange(sqliteStatusVersion)`). `feeds.count` (First-Run, `hasFeeds`) → `feedSnapshots.count`. `selectedFeed` (Resolve für Refresh/Delete) → `FeedStore.feed(id:)` bzw. `FeedRefreshSnapshot` aus Snapshots.
- [ ] T2 — Dock-Badge: `AppIconBadgeService.unreadCount(in: [Feed])` ersetzen durch SQLite-Variante `unreadCount(in snapshots: [FeedSidebarSnapshot])` (Summe `unreadCount`) oder `FeedStore`-Count. ContentView `unreadArticleCount` aus `feedSnapshots`.
- [ ] T3 — `OPMLExportSheet`: `feeds: [Feed]` → `opmlFeeds: [OPMLFeed]` (FeedStore.opmlFeedsForExport bereits vorhanden und Sheet hat bereits SQLite-Load-Pfad). Aufrufstelle ContentView anpassen.
- [ ] T4 — `OPMLImportReviewView`/`OPMLImportPreviewController`: `feeds: [Feed]`/`existingFeeds: [Feed]` → SQLite-Quelle (`FeedStore.feeds()` für Duplikat-/Folder-Check). `FeedViewModel.opmlImportPreviewRows` nutzt bereits SQLite — Konsolidieren.
- [ ] T5 — `FirstRunWizardView`: `feeds: [Feed]` → SQLite (`FeedStore.feeds()` bzw. `feedSnapshots.count` für First-Run-Entscheidung).
- [ ] T6 — `FeedViewModel`: `refreshFeed(_ feed: Feed?, …)` durch `refreshFeed(feedID: String, …)` ersetzen, delegiert an `SQLiteFeedRefreshService.refresh(feedID:)`. `refreshAllFeeds` nimmt `[FeedRefreshSnapshot]` aus `FeedStore.feeds()` statt `[Feed]`. `deleteFeed(_ feed: Feed?, …)` → `deleteFeed(feedID: String, …)` via `FeedStore.delete(id:)` (+ SwiftData-Bridge-Feed-Löschung, falls Brücke noch besteht). `renameFeed`/`restoreOriginalFeedTitle` an `FeedStore` delegieren.
- [ ] T7 — `ArticleSearchWindowView`: `@Query [Feed]` → `FeedStore.feeds()` für Filter-Dropdown.
- [ ] T8 — SwiftData `Feed`-Brücke entfernen: `mirrorFeedToSQLite`, `SQLiteFeedSubscriptionService.saveSwiftDataBridge` und `@Model Feed`-Schreibzugriffe prüfen. Wenn `Article.feed`/`Tag.feeds` Relationships noch leben: `Feed` hart isolieren (nur noch lesbar aus alter DB, keine neuen Writes) und klar kommentieren. Sonst `@Model Feed` entfernen + ModelContainer-Registrierung bereinigen.
- [ ] T9 — Fokussierte Tests (Badge aus Snapshots, refreshFeed(feedID:), OPML-Export aus SQLite, ContentView ohne @Query), Build, Diff-Check.

## Reihenfolge-Hinweis

T1/T2/T3/T4/T5/T7 können weitgehend parallel/unabhängig umgestellt werden (jeweils lokale Consumer). T6 (FeedViewModel) ist Voraussetzung, dass Refresh-/Delete-Aktionen nicht mehr ein SwiftData-`Feed`-Objekt brauchen. T8 (Brücke entfernen) als letztes, sobald kein produktiver Pfad mehr nach `Feed` schreibt — sonst Breakage.