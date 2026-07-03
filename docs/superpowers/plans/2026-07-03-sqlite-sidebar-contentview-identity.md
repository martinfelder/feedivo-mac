# SQLite-only Sidebar/ContentView Feed-Identität Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sidebar und ContentView nutzen die SQLite-Feed-ID (String) als Navigationsidentität statt SwiftData `Feed`/`PersistentIdentifier`. Die Sidebar-Reihen, die Feed-Auswahl, die Artikellisten-Zuordnung und die Properties/Rename-Sheets arbeiten auf `FeedSidebarSnapshot`/`FeedRecord`.

**Architecture:** `SidebarSelection.feed` trägt künftig die SQLite-Feed-ID. `SQLiteSidebarState.snapshots` wird die einzige Quelle für die Sidebar-Feed-Liste. SwiftData `Feed` bleibt *übergangsweise* als Aktions-Backend (Refresh/Delete/Badge/OPML/Wizard) erhalten und wird aus ContentView bei Bedarf per Feed-ID aufgelöst — es ist keine Navigationsidentität mehr. Das vollständige Entfernen der SwiftData-Feed-Brücke ist ein Folge-Slice (`sqlite-only-feed-bridge-removal`).

**Tech Stack:** SwiftUI, SwiftData (Übergang), GRDB, Swift Testing, xcodebuild.

---

## Scope

- [ ] `SidebarSelection.feed` nutzt SQLite-Feed-ID (`String`) statt `PersistentIdentifier`.
- [ ] `SQLiteSidebarState` ist die Sidebar-Quelle; Bridge-Helfer `snapshot(for: Feed)`/`visibleFeeds(from:)` entfallen durch feedID-basierte/snapshot-basierte Helfer.
- [ ] `FeedRowView` rendert aus `FeedSidebarSnapshot` (kein SwiftData `Feed` mehr).
- [ ] `SidebarView` kommt ohne `@Query [Feed]` aus; Ordnung/Filter/Reload-Token laufen über Snapshots.
- [ ] `FeedPropertiesView`/`FeedRenameView` nehmen `feedID: String` und laden `FeedRecord` via `FeedStore`.
- [ ] `SQLiteFeedArticleListView` erhält `init(feedID:)`; `Scope.feed` trägt `String`.
- [ ] `ContentView` löst die Auswahl als `selectedFeedID: String?` auf; `SQLiteFeedArticleListView(feedID:)`; Lösch-/Refresh-Aktionen resolven den Übergangs-`Feed` per ID.
- [ ] Fokussierte Tests, Build und Diff-Check verifizieren den Slice.

## Out of scope (Folge-Slice `sqlite-only-feed-bridge-removal`)

- OPML-Import/Export-Sheets und FirstRunWizard: `feeds: [Feed]` → SQLite-Quelle.
- `AppIconBadgeService.unreadCount(in: [Feed])` → SQLite.
- `FeedViewModel.refreshFeed/refreshAllFeeds/deleteFeed`: Feed-ID-basierte SQLite-First-Pfade, Verschslankung.
- SwiftData `Feed`-Modell entfernen oder hart isolieren.

## Execution Notes

- Worktree: `/Users/martinfelder/Developer/FeedivoMac/.worktrees/sqlite-grdb-foundation`
- Branch: `codex/sqlite-grdb-foundation`
- TDD pro Verhaltensänderung: fokussierten Test ergänzen, rot sehen, implementieren, grün sehen.
- SwiftData `Feed` wird in diesem Slice *nicht* entfernt; er bleibt als Übergangs-Aktions-Backend erhalten.
- Kommentare auf Deutsch, wie in CLAUDE.md vorgegeben.

## Tasks

- [ ] T1 — `SidebarSelection`: `.feed(PersistentIdentifier)` → `.feed(String)` (SQLite-Feed-ID). Alle Konstruktions- und Match-Stellen aktualisieren (SidebarView, ContentView; legacy `ArticleListView` ist tot und wird nicht angefasst).
- [ ] T2 — `SQLiteSidebarState`: Snapshots als Quelle; `snapshot(for: Feed)`/`visibleFeeds(from:)` entfernen und durch `snapshot(forFeedID: String)` bzw. direkte Nutzung von `snapshots` ersetzen. `showsReadFeeds`-Filterung bleibt im `FeedStore.sidebarFeeds(showsReadFeeds:)`.
- [ ] T3 — `FeedRowView`: `feed: Feed` → `snapshot: FeedSidebarSnapshot`; SwiftData-Fallbacks (`SidebarUnreadCount.unreadArticleCount(for:)`, `feed.title`, `feed.faviconURL`) entfallen.
- [ ] T4 — `SidebarView`: `@Query [Feed]` entfernen. `feedRows(_ snapshots:)`, `feedsByFolderName(in: [FeedSidebarSnapshot])` auf Snapshots. Kontextmenü (Rename/Properties/Delete) reicht `feedID` weiter. `sqliteSidebarReloadToken` nutzt Snapshot-IDs + Version statt SwiftData-Feed-IDs. `feeds.isEmpty`-Checks (Toolbar, Empty-State) werden über `sqliteSidebarState.snapshots.isEmpty` aufgelöst.
- [ ] T5 — `FeedPropertiesView`: `feed: Feed` → `feedID: String`; `FeedRecord` via `FeedStore.feed(id:)` laden (bereits vorhandenes `feedRecord`-Laden konsolidieren). Alle `feed.*`-Leser durch `FeedRecord`-Felder ersetzen.
- [ ] T6 — `FeedRenameView`: `feed: Feed` → `feedID: String`; `FeedRecord` laden; `FeedStore.renameFeed`/`restoreOriginalTitle` nutzen (bereits vorhanden).
- [ ] T7 — `SQLiteFeedArticleListView`: `init(feedID: String, ...)` ergänzen; `Scope.feed(Feed)` → `Scope.feed(String)`; `reload()` nutzt `feedID` direkt statt `feed.id.uuidString`.
- [ ] T8 — `ContentView`: `selectedFeed` → `selectedFeedID: String?` (aus `.feed(String)`); `SQLiteFeedArticleListView(feedID: selectedFeedID)`. `feedPendingDeletion: FeedSidebarSnapshot?` (Titel für Bestätigungsdialog). `deleteFeed`/`refreshSelectedFeed` resolven den Übergangs-`Feed` per ID aus `feeds` und rufen bestehende `FeedViewModel`-Pfade. `FeedCommandActions.selectedFeed` wird aus `selectedFeedID` + `feeds` resolven.
- [ ] T9 — Fokussierte Tests (Sidebar-Auswahl via feedID, FeedProperties/FeedRename via feedID), Build, Diff-Check.