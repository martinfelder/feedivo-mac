# Performance-Hardening Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sieben verifizierte, unabhängig testbare Performance- und Best-Practice-Fixes aus dem Code-Review vom 2026-07-11 umsetzen, auf einem eigenen Branch (nicht `main`), damit der Ansatz vor einem Merge getestet werden kann.

**Architecture:** Jede Task ist in sich abgeschlossen und unabhängig von den anderen (keine gemeinsamen Zwischenzustände) — sie können in beliebiger Reihenfolge gemerged werden, falls einzelne Fixes verworfen werden sollen. Datenbank-Migrationen (Task 1–3) laufen zuerst, vom sichersten (reiner Index) zum riskantesten (Tabellen-Neuaufbau für Fremdschlüssel). View-/Service-Fixes (Task 4–7) sind rein additive Refactorings ohne Schema-Änderung.

**Tech Stack:** Swift 6 / SwiftUI (macOS 14+), GRDB 7.11.1 / SQLite, Swift Testing (kein XCTest).

## Global Constraints

- Jede neue Datenbank-Migration wird als neuer `migrator.registerMigration("vN_…")`-Block angehängt — bestehende Migrationen (v1–v10) werden NIE verändert (bricht sonst Bestands-Datenbanken).
- Tests laufen ausschließlich gezielt: `xcodebuild -scheme Feedivo -destination 'platform=macOS' test -only-testing:FeedivoTests/<SuiteName> -parallel-testing-enabled NO`. Ein unscoped `xcodebuild test` über alle Testdateien hängt reproduzierbar (bekanntes Infrastrukturproblem, siehe CLAUDE.md).
- Nach jedem Code-Edit gilt: SourceKit-Diagnosen in der IDE sind unzuverlässig (zeigen oft falsche "Cannot find type"-Fehler). Verlässlich ist ausschließlich ein echter `xcodebuild build`-Lauf.
- Bekannte, dauerhaft vorbestehende Testfehlschläge (nicht neu einführen, aber auch nicht als eigenen Bug behandeln): 9 Tests in `FeedivoAppSceneConfigurationTests.swift`, 2 flaky-unter-Last Tests in `FeedViewModelTests.swift`.
- Kommentare im Code auf Deutsch (Projektkonvention).

---

## Vorbereitung (vor Task 1, kein TDD-Task)

```bash
git status
git checkout -b perf/hardening-phase-1
```

Falls `git status` uncommittete Änderungen zeigt, die nicht zu diesem Plan gehören (z. B. `UserInterfaceState.xcuserstate`), diese vorher klären statt zu überschreiben.

---

### Task 1: Composite-Index `article_statuses(isHidden, isRead)`

**Files:**
- Modify: `Feedivo/Database/FeedivoDatabaseMigrator.swift` (neue Migration `v11_add_article_statuses_hidden_read_index`, ans Ende vor `return migrator` anhängen)
- Test: `FeedivoTests/SQLiteDatabaseMigrationTests.swift`

**Interfaces:**
- Produziert: Index `idx_article_statuses_hidden_read` auf `article_statuses(isHidden, isRead)` — wird von Task 3 (Tabellen-Neuaufbau) erneut mit angelegt, da SQLite Indizes beim Löschen der Tabelle automatisch verwirft.

- [ ] **Step 1: Fehlschlagenden Test schreiben**

In `FeedivoTests/SQLiteDatabaseMigrationTests.swift`, direkt nach `migrationCreatesPerformanceIndexes()` (nach Zeile 61) einfügen:

```swift
    @Test func migrationCreatesArticleStatusesHiddenReadCompositeIndex() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        let indexNames = try database.debugIndexNames()

        #expect(indexNames.contains("idx_article_statuses_hidden_read"))
    }
```

- [ ] **Step 2: Test ausführen, Fehlschlag verifizieren**

Run: `xcodebuild -scheme Feedivo -destination 'platform=macOS' test -only-testing:FeedivoTests/SQLiteDatabaseMigrationTests/migrationCreatesArticleStatusesHiddenReadCompositeIndex -parallel-testing-enabled NO`
Expected: FAIL — Index existiert noch nicht.

- [ ] **Step 3: Migration ergänzen**

In `Feedivo/Database/FeedivoDatabaseMigrator.swift`, zwischen der `v10_add_feed_retention_minimum_articles`-Migration (endet bei Zeile 308) und `return migrator` (Zeile 310) einfügen:

```swift
        migrator.registerMigration("v11_add_article_statuses_hidden_read_index") { database in
            try database.create(
                index: "idx_article_statuses_hidden_read",
                on: "article_statuses",
                columns: ["isHidden", "isRead"]
            )
        }
```

- [ ] **Step 4: Test ausführen, Erfolg verifizieren**

Run: `xcodebuild -scheme Feedivo -destination 'platform=macOS' test -only-testing:FeedivoTests/SQLiteDatabaseMigrationTests -parallel-testing-enabled NO`
Expected: PASS — alle Tests der Suite grün, inkl. der bestehenden `migrationCreatesPerformanceIndexes()`.

- [ ] **Step 5: Build verifizieren und committen**

Run: `xcodebuild -scheme Feedivo -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED

```bash
git add Feedivo/Database/FeedivoDatabaseMigrator.swift FeedivoTests/SQLiteDatabaseMigrationTests.swift
git commit -m "Perf: Composite-Index (isHidden, isRead) für heißeste Artikel-Query"
```

---

### Task 2: Expression-Index für `ORDER BY COALESCE(publishedAt, arrivedAt)`

**Files:**
- Modify: `Feedivo/Database/FeedivoDatabaseMigrator.swift` (neue Migration `v12_add_articles_published_coalesce_index`)
- Test: `FeedivoTests/SQLiteDatabaseMigrationTests.swift`

**Interfaces:**
- Produziert: Index `idx_articles_published_coalesce` auf `articles(COALESCE(publishedAt, arrivedAt) DESC, arrivedAt DESC)` — deckt exakt das `ORDER BY`-Muster ab, das `TimelineStore.swift:111` und `ArticleDatabase.swift:302` bereits verwenden.

- [ ] **Step 1: Fehlschlagenden Test schreiben**

In `FeedivoTests/SQLiteDatabaseMigrationTests.swift`, nach dem in Task 1 ergänzten Test einfügen:

```swift
    @Test func migrationCreatesArticlesPublishedCoalesceExpressionIndex() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        let indexNames = try database.debugIndexNames()

        #expect(indexNames.contains("idx_articles_published_coalesce"))
    }

    @Test func queryPlanForTimelineOrderByNutztCoalesceIndex() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        let plan = try database.read { db in
            try Row.fetchAll(db, sql: """
                EXPLAIN QUERY PLAN
                SELECT a.id
                FROM articles a
                JOIN feeds f ON f.id = a.feedID
                JOIN article_statuses s ON s.articleID = a.id
                ORDER BY COALESCE(a.publishedAt, a.arrivedAt) DESC, a.arrivedAt DESC
                LIMIT 10
                """)
        }

        let planDetails = plan.compactMap { row in row["detail"] as String? }.joined(separator: " | ")
        #expect(planDetails.contains("idx_articles_published_coalesce"))
    }
```

- [ ] **Step 2: Tests ausführen, Fehlschlag verifizieren**

Run: `xcodebuild -scheme Feedivo -destination 'platform=macOS' test -only-testing:FeedivoTests/SQLiteDatabaseMigrationTests/migrationCreatesArticlesPublishedCoalesceExpressionIndex -only-testing:FeedivoTests/SQLiteDatabaseMigrationTests/queryPlanForTimelineOrderByNutztCoalesceIndex -parallel-testing-enabled NO`
Expected: FAIL — Index existiert noch nicht, Query-Plan zeigt einen separaten SORT-Schritt statt Index-Nutzung.

- [ ] **Step 3: Migration ergänzen**

In `Feedivo/Database/FeedivoDatabaseMigrator.swift`, nach der in Task 1 ergänzten `v11`-Migration einfügen:

```swift
        migrator.registerMigration("v12_add_articles_published_coalesce_index") { database in
            try database.execute(sql: """
                CREATE INDEX idx_articles_published_coalesce
                ON articles(COALESCE(publishedAt, arrivedAt) DESC, arrivedAt DESC)
                """)
        }
```

- [ ] **Step 4: Tests ausführen, Erfolg verifizieren**

Run: `xcodebuild -scheme Feedivo -destination 'platform=macOS' test -only-testing:FeedivoTests/SQLiteDatabaseMigrationTests -parallel-testing-enabled NO`
Expected: PASS. Falls `queryPlanForTimelineOrderByNutztCoalesceIndex` weiterhin fehlschlägt (SQLite entscheidet sich trotz Index für einen Full-Scan, z. B. bei sehr kleinen Testdatenmengen), den Test stattdessen mit vorherigem `ANALYZE`-Aufruf ergänzen:

```swift
        try database.write { db in
            try db.execute(sql: "ANALYZE")
        }
```

direkt vor dem `EXPLAIN QUERY PLAN`-Aufruf, und erneut ausführen.

- [ ] **Step 5: Build verifizieren und committen**

Run: `xcodebuild -scheme Feedivo -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED

```bash
git add Feedivo/Database/FeedivoDatabaseMigrator.swift FeedivoTests/SQLiteDatabaseMigrationTests.swift
git commit -m "Perf: Expression-Index für ORDER BY COALESCE(publishedAt, arrivedAt)"
```

---

### Task 3: Fremdschlüssel-Kaskade `article_statuses` → `articles`

**Files:**
- Modify: `Feedivo/Database/FeedivoDatabaseMigrator.swift` (neue Migration `v13_add_article_statuses_foreign_key`)
- Modify: `FeedivoTests/SQLiteDatabaseMigrationTests.swift` (2 bestehende Tests aktualisieren, die aktuell den Bug als Sollverhalten fixieren + 1 neuer Test)

**Interfaces:**
- Produziert: `article_statuses.articleID` referenziert `articles(id)` mit `ON DELETE CASCADE`. Ab dieser Migration löscht jedes `DELETE FROM articles WHERE id = ?` (egal an welcher Stelle im Code, inkl. dem rohen SQL in `SQLiteFeedArticleListView.swift:794`) automatisch die zugehörige `article_statuses`-Zeile mit — **kein Produktionscode außerhalb der Migration muss geändert werden**, GRDB/SQLite erzwingt das über `PRAGMA foreign_keys = ON` (bereits in `FeedivoDatabase.open`/`inMemoryForTests` gesetzt).

**Wichtig:** Diese Migration baut die Tabelle `article_statuses` komplett neu auf (SQLite kann Fremdschlüssel nicht per `ALTER TABLE` nachträglich hinzufügen). Dabei werden bereits **verwaiste** `article_statuses`-Zeilen (Status-Zeilen ohne zugehörigen Artikel — genau der Bug, den dieser Fix behebt) bewusst NICHT mitkopiert, da die neue Fremdschlüssel-Spalte sie ablehnen würde.

- [ ] **Step 1: Bestehende Tests lesen und verstehen, warum sie brechen werden**

`FeedivoTests/SQLiteDatabaseMigrationTests.swift` enthält aktuell zwei Tests, die das **bisherige, fehlerhafte** Verhalten fixieren:
- `articleStatusesHaveNoForeignKeyCascadeToArticles()` (Zeile 73–79) erwartet `foreignKeys.isEmpty == true`.
- `deletingFeedCascadesToArticlesAndFeedLogsButNotArticleStatuses()` (Zeile 174–198) erwartet nach dem Löschen eines Feeds `rowCount(table: "article_statuses") == 1` (die verwaiste Zeile bleibt liegen).

Beide müssen in diesem Task auf das neue, korrekte Verhalten umgestellt werden — das ist kein Nebeneffekt, sondern der Zweck dieses Tasks.

- [ ] **Step 2: Bestehende Tests auf neues Verhalten umstellen (das sind die "failing tests" dieses Tasks)**

In `FeedivoTests/SQLiteDatabaseMigrationTests.swift`, den Test `articleStatusesHaveNoForeignKeyCascadeToArticles()` (Zeile 73–79) ersetzen durch:

```swift
    @Test func articleStatusesCascadeWhenArticleIsDeleted() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        let foreignKeys = try database.debugForeignKeys(for: "article_statuses")

        #expect(foreignKeys == ["articles"])
    }
```

Den Test `deletingFeedCascadesToArticlesAndFeedLogsButNotArticleStatuses()` (Zeile 174–198) umbenennen und die letzte Assertion ändern:

```swift
    @Test func deletingFeedCascadesToArticlesFeedLogsAndArticleStatuses() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        try insertFeed(into: database, id: "feed-1")
        try insertArticle(
            into: database,
            id: "article-1",
            feedID: "feed-1",
            sourceID: "source-1",
            link: "https://example.com/articles/1"
        )
        try insertFeedLog(into: database, id: "log-1", feedID: "feed-1")
        try insertArticleStatus(into: database, articleID: "article-1")

        try database.write { database in
            try database.execute(
                sql: "DELETE FROM feeds WHERE id = ?",
                arguments: ["feed-1"]
            )
        }

        #expect(try rowCount(in: database, table: "articles") == 0)
        #expect(try rowCount(in: database, table: "feed_logs") == 0)
        #expect(try rowCount(in: database, table: "article_statuses") == 0)
    }
```

Zusätzlich einen neuen Test für den konkreten Bug-Fall (Einzelartikel-Löschen ohne Feed-Löschen) direkt danach einfügen:

```swift
    @Test func deletingSingleArticleCascadesToArticleStatuses() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        try insertFeed(into: database, id: "feed-1")
        try insertArticle(
            into: database,
            id: "article-1",
            feedID: "feed-1",
            sourceID: "source-1",
            link: "https://example.com/articles/1"
        )
        try insertArticleStatus(into: database, articleID: "article-1")

        try database.write { database in
            try database.execute(sql: "DELETE FROM articles WHERE id = ?", arguments: ["article-1"])
        }

        #expect(try rowCount(in: database, table: "article_statuses") == 0)
    }
```

- [ ] **Step 3: Tests ausführen, Fehlschlag verifizieren**

Run: `xcodebuild -scheme Feedivo -destination 'platform=macOS' test -only-testing:FeedivoTests/SQLiteDatabaseMigrationTests -parallel-testing-enabled NO`
Expected: FAIL bei genau den 3 oben genannten Tests (`articleStatusesCascadeWhenArticleIsDeleted`, `deletingFeedCascadesToArticlesFeedLogsAndArticleStatuses`, `deletingSingleArticleCascadesToArticleStatuses`) — alle anderen Tests der Suite bleiben grün.

- [ ] **Step 4: Migration ergänzen**

In `Feedivo/Database/FeedivoDatabaseMigrator.swift`, nach der in Task 2 ergänzten `v12`-Migration einfügen:

```swift
        migrator.registerMigration("v13_add_article_statuses_foreign_key") { database in
            try database.create(table: "article_statuses_new") { table in
                table.column("articleID", .text).primaryKey()
                    .references("articles", column: "id", onDelete: .cascade)
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

            // Verwaiste Zeilen (aus dem Bug vor diesem Fix) werden bewusst NICHT
            // mitkopiert — die neue Fremdschluessel-Spalte wuerde sie ablehnen.
            try database.execute(sql: """
                INSERT INTO article_statuses_new
                SELECT
                    s.articleID, s.isRead, s.isStarred, s.isArchived, s.isHidden,
                    s.readAt, s.starredAt, s.archivedAt, s.hiddenAt, s.dateArrived
                FROM article_statuses s
                WHERE EXISTS (SELECT 1 FROM articles a WHERE a.id = s.articleID)
                """)

            try database.drop(table: "article_statuses")
            try database.rename(table: "article_statuses_new", to: "article_statuses")

            try database.create(index: "idx_article_statuses_is_read", on: "article_statuses", columns: ["isRead"])
            try database.create(index: "idx_article_statuses_is_starred", on: "article_statuses", columns: ["isStarred"])
            try database.create(index: "idx_article_statuses_is_archived", on: "article_statuses", columns: ["isArchived"])
            try database.create(index: "idx_article_statuses_is_hidden", on: "article_statuses", columns: ["isHidden"])
            try database.create(
                index: "idx_article_statuses_hidden_read",
                on: "article_statuses",
                columns: ["isHidden", "isRead"]
            )
        }
```

- [ ] **Step 5: Tests ausführen, Erfolg verifizieren**

Run: `xcodebuild -scheme Feedivo -destination 'platform=macOS' test -only-testing:FeedivoTests/SQLiteDatabaseMigrationTests -parallel-testing-enabled NO`
Expected: PASS — alle Tests der Suite grün, inkl. der 3 aus Step 2/3.

- [ ] **Step 6: Gezielte Regressionstests für angrenzende Bereiche laufen lassen**

Diese Migration ändert eine Kern-Tabelle — zusätzlich prüfen, dass Store-Tests, die `article_statuses` lesen/schreiben, nicht brechen:

Run: `xcodebuild -scheme Feedivo -destination 'platform=macOS' test -only-testing:FeedivoTests/SQLiteArticleStoreTests -only-testing:FeedivoTests/SQLiteFeedArticleListStateTests -parallel-testing-enabled NO`
Expected: PASS

- [ ] **Step 7: Build verifizieren und committen**

Run: `xcodebuild -scheme Feedivo -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED

```bash
git add Feedivo/Database/FeedivoDatabaseMigrator.swift FeedivoTests/SQLiteDatabaseMigrationTests.swift
git commit -m "Fix: Fremdschlüssel-Kaskade article_statuses->articles, keine verwaisten Status-Zeilen mehr"
```

---

### Task 4: Artikel-Navigation ohne DB-Reload bei Auswahlwechsel

**Files:**
- Create: `Feedivo/ViewModels/SQLiteFeedArticleListLoadToken.swift`
- Create: `FeedivoTests/SQLiteFeedArticleListLoadTokenTests.swift`
- Modify: `Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift:132-137, 375-377`

**Interfaces:**
- Produziert: `SQLiteFeedArticleListLoadToken.make(scopeToken:directTagVersion:sqliteStatusVersion:debouncedSearchText:) -> String` — reine, pure Funktion ohne `selectedArticleID`-Parameter.
- Konsumiert (bestehend): `SQLiteArticleNavigationState.init(articleIDs:selectedArticleID:)` (`Feedivo/ViewModels/SQLiteArticleNavigationState.swift:17`) — bereits vorhanden, wird jetzt zusätzlich lokal (ohne DB-Reload) aufgerufen.

- [ ] **Step 1: Fehlschlagenden Test für die extrahierte Token-Funktion schreiben**

Neue Datei `FeedivoTests/SQLiteFeedArticleListLoadTokenTests.swift`:

```swift
import Testing
@testable import Feedivo

struct SQLiteFeedArticleListLoadTokenTests {
    @Test func gleicheParameterErgebenGleichenToken() {
        let first = SQLiteFeedArticleListLoadToken.make(
            scopeToken: "feed:1",
            directTagVersion: 0,
            sqliteStatusVersion: 3,
            debouncedSearchText: ""
        )
        let second = SQLiteFeedArticleListLoadToken.make(
            scopeToken: "feed:1",
            directTagVersion: 0,
            sqliteStatusVersion: 3,
            debouncedSearchText: ""
        )

        #expect(first == second)
    }

    @Test func unterschiedlicheScopesErgebenUnterschiedlichenToken() {
        let first = SQLiteFeedArticleListLoadToken.make(
            scopeToken: "feed:1",
            directTagVersion: 0,
            sqliteStatusVersion: 3,
            debouncedSearchText: ""
        )
        let second = SQLiteFeedArticleListLoadToken.make(
            scopeToken: "feed:2",
            directTagVersion: 0,
            sqliteStatusVersion: 3,
            debouncedSearchText: ""
        )

        #expect(first != second)
    }

    @Test func unterschiedlicheSuchtexteErgebenUnterschiedlichenToken() {
        let first = SQLiteFeedArticleListLoadToken.make(
            scopeToken: "feed:1",
            directTagVersion: 0,
            sqliteStatusVersion: 3,
            debouncedSearchText: "Swift"
        )
        let second = SQLiteFeedArticleListLoadToken.make(
            scopeToken: "feed:1",
            directTagVersion: 0,
            sqliteStatusVersion: 3,
            debouncedSearchText: ""
        )

        #expect(first != second)
    }
}
```

- [ ] **Step 2: Test ausführen, Fehlschlag verifizieren**

Run: `xcodebuild -scheme Feedivo -destination 'platform=macOS' test -only-testing:FeedivoTests/SQLiteFeedArticleListLoadTokenTests -parallel-testing-enabled NO`
Expected: FAIL — `SQLiteFeedArticleListLoadToken` existiert noch nicht (Compile-Fehler).

- [ ] **Step 3: Token-Funktion implementieren**

Neue Datei `Feedivo/ViewModels/SQLiteFeedArticleListLoadToken.swift`:

```swift
import Foundation

/// Baut den `.task(id:)`-Trigger-String fuer `SQLiteFeedArticleListView` aus reinen
/// Werten zusammen — bewusst OHNE `selectedArticleID`. Ein Artikel-Klick soll die
/// Vor-/Zurueck-Navigation lokal aus den bereits geladenen Zeilen ableiten
/// (`SQLiteArticleNavigationState.init(articleIDs:selectedArticleID:)`) statt einen
/// kompletten SQL-Reload der Liste auszuloesen.
enum SQLiteFeedArticleListLoadToken {
    static func make(
        scopeToken: String,
        directTagVersion: Int,
        sqliteStatusVersion: Int,
        debouncedSearchText: String
    ) -> String {
        "\(scopeToken)#\(directTagVersion)#\(sqliteStatusVersion)#\(debouncedSearchText)"
    }
}
```

- [ ] **Step 4: Test ausführen, Erfolg verifizieren**

Run: `xcodebuild -scheme Feedivo -destination 'platform=macOS' test -only-testing:FeedivoTests/SQLiteFeedArticleListLoadTokenTests -parallel-testing-enabled NO`
Expected: PASS

- [ ] **Step 5: View auf die neue Token-Funktion umstellen und Navigation lokal berechnen**

In `Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift`, den bestehenden `loadToken` (Zeile 375–377) ersetzen durch:

```swift
    private var loadToken: String {
        SQLiteFeedArticleListLoadToken.make(
            scopeToken: scopeToken,
            directTagVersion: directTagVersion,
            sqliteStatusVersion: sqliteStatusVersion,
            debouncedSearchText: debouncedSearchText
        )
    }
```

Den bestehenden `.onChange(of: selectedArticleID) { markSelectedArticleReadIfNeeded() }` (Zeile 132–134) erweitern, damit die Navigation bei reinem Auswahlwechsel lokal nachgezogen wird:

```swift
        .onChange(of: selectedArticleID) {
            markSelectedArticleReadIfNeeded()
            navigationState = SQLiteArticleNavigationState(
                articleIDs: state.rows.map(\.id),
                selectedArticleID: selectedArticleID
            )
        }
```

- [ ] **Step 6: Build verifizieren**

Run: `xcodebuild -scheme Feedivo -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Angrenzende Tests laufen lassen**

Run: `xcodebuild -scheme Feedivo -destination 'platform=macOS' test -only-testing:FeedivoTests/SQLiteFeedArticleListStateTests -only-testing:FeedivoTests/SQLiteArticleNavigationStateTests -parallel-testing-enabled NO`
Expected: PASS

- [ ] **Step 8: Committen**

```bash
git add Feedivo/ViewModels/SQLiteFeedArticleListLoadToken.swift FeedivoTests/SQLiteFeedArticleListLoadTokenTests.swift Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift
git commit -m "Perf: Artikel-Auswahl loest keinen kompletten Listen-Reload mehr aus"
```

---

### Task 5: `displayState` einmal statt bis zu 3× pro Render berechnen

**Files:**
- Modify: `Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift:244-292`

**Interfaces:**
- Keine neuen öffentlichen Interfaces — reines internes Refactoring der View, verifiziert über Build + bestehende Regressionstests (SwiftUI-Render-Häufigkeit ist mit der Swift-Testing-Suite dieses Projekts nicht direkt messbar; dieser Task hat deshalb bewusst keinen neuen Test, siehe Step 1).

- [ ] **Step 1: Ausgangslage bestätigen (kein neuer Test — Begründung)**

`filteredRows` (Zeile 261–263), `visibleRows` (Zeile 265–267) und `hiddenReadRowCount` (Zeile 269–271) sind aktuell drei unabhängige computed properties, die alle bei jedem Zugriff `displayState` (Zeile 284–292) neu instanziieren — inklusive vollem Sortierdurchlauf über `effectiveRows.sorted(by: sortRows)`. `articleList` (Zeile 244–259) greift auf alle drei zu, macht also bis zu 3 volle Neuberechnungen pro Render. Da SwiftUI-Render-Aufrufhäufigkeit mit Swift Testing nicht sinnvoll direkt messbar ist (kein ViewInspector im Tech-Stack), wird dieser Task ausschließlich über Build-Erfolg und die bestehende Test-Suite verifiziert (Step 4), nicht über einen neuen fehlschlagenden Test.

- [ ] **Step 2: `displayState` einmalig pro `articleList`-Aufruf berechnen**

In `Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift`, `articleList` (Zeile 244–259) ersetzen durch:

```swift
    private var articleList: some View {
        let currentDisplayState = displayState

        return List(selection: $selectedArticleID) {
            if currentDisplayState.filteredRows.isEmpty {
                articleListEmptyState(isSearching: isSearching)
            } else {
                ForEach(currentDisplayState.visibleRows) { row in
                    articleRow(row, visibleRows: currentDisplayState.visibleRows)
                        .tag(row.id)
                }

                if !showsReadArticles, currentDisplayState.hiddenReadRowCount > 0 {
                    showReadArticlesButton(count: currentDisplayState.hiddenReadRowCount)
                }
            }
        }
    }
```

Die jetzt ungenutzten Wrapper-Properties `filteredRows` (Zeile 261–263), `visibleRows` (Zeile 265–267), `hiddenReadRowCount` (Zeile 269–271) und `shouldShowReadArticlesButton` (Zeile 273–275) entfernen — nach diesem Schritt prüfen, ob `shouldShowReadArticlesButton`/`visibleRows` noch anderswo in derselben Datei referenziert werden (z. B. im `.toolbar`-Block bei `markReadMenu(visibleRows: visibleRows)`, Zeile 151); falls ja, dort ebenfalls auf `displayState.visibleRows` umstellen statt die Wrapper-Property zu behalten.

- [ ] **Step 3: Build verifizieren**

Run: `xcodebuild -scheme Feedivo -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED. Bei Compile-Fehlern wegen entfernter Wrapper-Properties: alle verbleibenden Referenzen in derselben Datei per Grep suchen (`grep -n "visibleRows\|filteredRows\|hiddenReadRowCount\|shouldShowReadArticlesButton" Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift`) und auf `displayState.<property>` bzw. eine lokale `let currentDisplayState = displayState` am jeweiligen Ort umstellen.

- [ ] **Step 4: Regressionstests laufen lassen**

Run: `xcodebuild -scheme Feedivo -destination 'platform=macOS' test -only-testing:FeedivoTests/SQLiteFeedArticleListStateTests -parallel-testing-enabled NO`
Expected: PASS

- [ ] **Step 5: Committen**

```bash
git add Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift
git commit -m "Perf: displayState einmal statt bis zu 3x pro Render berechnen"
```

---

### Task 6: `ImageCacheService` — Trim-Throttling + Hintergrund-Ausführung

**Files:**
- Modify: `Feedivo/Services/ImageCacheService.swift:23-56, 319-325`
- Test: `FeedivoTests/ImageCacheServiceTests.swift`

**Interfaces:**
- Produziert: `ImageCacheService.init(..., trimEveryNWrites: Int = 20)` — neuer, defaulteter Konstruktor-Parameter für Testbarkeit.
- Verhalten: `trimCacheAfterWriteIfNeeded()` scannt das Cache-Verzeichnis nicht mehr bei jedem einzelnen Bild-Schreibvorgang, sondern nur noch alle `trimEveryNWrites` Schreibvorgänge, und tut das auf einem Hintergrund-Thread statt inline.

- [ ] **Step 1: Fehlschlagenden Test schreiben**

In `FeedivoTests/ImageCacheServiceTests.swift`, nach `imageLaedtEinmalAusDemNetzUndDanachAusMemoryCache()` (endet bei Zeile 90) einfügen:

```swift
    @Test func trimCacheWirdErstNachNSchreibvorgaengenAusgefuehrt() async throws {
        let cacheDirectory = try Self.temporaryCacheDirectory()
        let loader = StubImageDataLoader(responses: [:])
        let service = ImageCacheService(
            cacheDirectory: cacheDirectory,
            dataLoader: loader,
            autoTrimLimitInBytes: { 1 },
            trimEveryNWrites: 3
        )

        let firstURL = try #require(URL(string: "https://example.com/1.png"))
        let secondURL = try #require(URL(string: "https://example.com/2.png"))
        loader.responses[firstURL] = try Self.pngData()
        loader.responses[secondURL] = try Self.pngData()

        _ = await service.image(for: firstURL)
        _ = await service.image(for: secondURL)

        // Nach 2 von 3 noetigen Schreibvorgaengen darf noch nicht getrimmt worden
        // sein — beide Dateien muessen trotz limitInBytes: 1 noch vorhanden sein.
        try await Task.sleep(for: .milliseconds(50))
        #expect(FileManager.default.fileExists(atPath: service.cachedFileURL(for: firstURL).path))
        #expect(FileManager.default.fileExists(atPath: service.cachedFileURL(for: secondURL).path))
    }
```

- [ ] **Step 2: Test ausführen, Fehlschlag verifizieren**

Run: `xcodebuild -scheme Feedivo -destination 'platform=macOS' test -only-testing:FeedivoTests/ImageCacheServiceTests/trimCacheWirdErstNachNSchreibvorgaengenAusgefuehrt -parallel-testing-enabled NO`
Expected: FAIL — Compile-Fehler, da `trimEveryNWrites` im Initializer noch nicht existiert.

- [ ] **Step 3: Throttling implementieren**

In `Feedivo/Services/ImageCacheService.swift`, den Initializer (Zeile 33–56) erweitern:

```swift
final class ImageCacheService: @unchecked Sendable {
    static let shared = ImageCacheService()

    private let cacheDirectory: URL
    private let dataLoader: ImageDataLoading
    private let fileManager: FileManager
    private let autoTrimLimitInBytes: @Sendable () -> Int64?
    private let memoryCache = NSCache<NSURL, NSImage>()
    private let thumbnailMemoryCache = NSCache<NSString, NSImage>()
    private let trimEveryNWrites: Int
    private var writesSinceLastTrim = 0

    init(
        cacheDirectory: URL = ImageCacheService.defaultCacheDirectory(),
        dataLoader: ImageDataLoading = URLSessionImageDataLoader(),
        fileManager: FileManager = .default,
        autoTrimLimitInBytes: @escaping @Sendable () -> Int64? = { ImageCacheSettings.currentLimitInBytes },
        trimEveryNWrites: Int = 20
    ) {
        self.cacheDirectory = cacheDirectory
        self.dataLoader = dataLoader
        self.fileManager = fileManager
        self.autoTrimLimitInBytes = autoTrimLimitInBytes
        self.trimEveryNWrites = max(1, trimEveryNWrites)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        memoryCache.countLimit = 200
        memoryCache.totalCostLimit = 150_000_000
        thumbnailMemoryCache.countLimit = 200
        thumbnailMemoryCache.totalCostLimit = 30_000_000
    }
```

Die bestehende `trimCacheAfterWriteIfNeeded()` (Zeile 319–325) ersetzen durch:

```swift
    // Ohne Throttling loeste JEDER einzelne Bild-Download einen vollen
    // Verzeichnis-Scan+Sort ueber den kompletten Cache aus (O(n) pro Schreibvorgang,
    // bei vielen kleinen Cache-Dateien in der Praxis O(n^2)-artig ueber einen
    // Refresh-Batch). Jetzt: nur alle `trimEveryNWrites` Schreibvorgaenge, und dann
    // auf einem Hintergrund-Thread statt inline auf dem aufrufenden Actor.
    private func trimCacheAfterWriteIfNeeded() {
        guard let limitInBytes = autoTrimLimitInBytes() else {
            return
        }

        writesSinceLastTrim += 1
        guard writesSinceLastTrim >= trimEveryNWrites else {
            return
        }
        writesSinceLastTrim = 0

        Task.detached(priority: .utility) { [self] in
            try? trimCache(toLimitInBytes: limitInBytes)
        }
    }
```

- [ ] **Step 4: Test ausführen, Erfolg verifizieren**

Run: `xcodebuild -scheme Feedivo -destination 'platform=macOS' test -only-testing:FeedivoTests/ImageCacheServiceTests -parallel-testing-enabled NO`
Expected: PASS — inkl. aller bestehenden Tests der Suite (insbesondere solcher, die `trimCache`/`autoTrimLimitInBytes` mit dem alten Default `trimEveryNWrites: 20` nutzen; falls ein bestehender Test genau 1 Schreibvorgang macht und sofortiges Trimmen erwartet, diesen Test mit `trimEveryNWrites: 1` explizit parametrisieren statt den Produktionscode aufzuweichen).

- [ ] **Step 5: Build verifizieren und committen**

Run: `xcodebuild -scheme Feedivo -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED

```bash
git add Feedivo/Services/ImageCacheService.swift FeedivoTests/ImageCacheServiceTests.swift
git commit -m "Perf: ImageCache-Trim gedrosselt und auf Hintergrund-Thread verschoben"
```

---

### Task 7: OPML-Vorschau — echte Parallelität statt MainActor-Pinning

**Files:**
- Modify: `Feedivo/Services/SQLiteFeedSubscriptionService.swift:367-378`
- Test: `FeedivoTests/SQLiteFeedSubscriptionServiceTests.swift`

**Interfaces:**
- Keine Signaturänderung — reiner interner Fix der Parallelitäts-Implementierung von `previewOPMLFeeds(for:onProgress:)`.

- [ ] **Step 1: Fehlschlagenden Test schreiben (verifiziert echte Nebenläufigkeit)**

In `FeedivoTests/SQLiteFeedSubscriptionServiceTests.swift`, nach `previewParalleelisiertBehaeltReihenfolgeUndStatus()` (endet bei Zeile 485) einfügen:

```swift
    @MainActor
    @Test func previewFeedsWerdenTatsaechlichParallelAbgerufen() async throws {
        actor ConcurrencyCounter {
            private var inFlight = 0
            private(set) var maxInFlight = 0

            func increment() {
                inFlight += 1
                maxInFlight = max(maxInFlight, inFlight)
            }

            func decrement() {
                inFlight -= 1
            }
        }

        let counter = ConcurrencyCounter()
        let database = try FeedivoDatabase.inMemoryForTests()
        let service = SQLiteFeedSubscriptionService(
            database: database,
            fetchFeed: { urlString in
                await counter.increment()
                try? await Task.sleep(for: .milliseconds(30))
                await counter.decrement()
                return ParsedFeed(sourceURL: urlString, title: urlString, description: nil, articles: [])
            },
            discoverFaviconURL: { _ in nil }
        )
        let opmlFeeds = (1...6).map { index in
            OPMLFeed(
                title: "F\(index)",
                xmlURL: "https://f\(index).example.com/feed.xml",
                htmlURL: nil,
                folderName: nil
            )
        }

        _ = await service.previewOPMLFeeds(for: opmlFeeds)

        let maxInFlight = await counter.maxInFlight
        #expect(maxInFlight > 1)
    }
```

- [ ] **Step 2: Test ausführen, Fehlschlag verifizieren**

Run: `xcodebuild -scheme Feedivo -destination 'platform=macOS' test -only-testing:FeedivoTests/SQLiteFeedSubscriptionServiceTests/previewFeedsWerdenTatsaechlichParallelAbgerufen -parallel-testing-enabled NO`
Expected: FAIL — `maxInFlight == 1`, da `group.addTask { @MainActor in ... }` die Kind-Tasks aktuell alle auf den MainActor pinnt und sie dadurch effektiv seriell statt parallel laufen.

- [ ] **Step 3: MainActor-Pinning entfernen**

In `Feedivo/Services/SQLiteFeedSubscriptionService.swift`, innerhalb `previewOPMLFeeds` den `group.addTask { @MainActor in ... }`-Block (Zeile 370–377) ersetzen durch:

```swift
                for item in batch {
                    group.addTask {
                        do {
                            _ = try await self.fetchFeed(item.cleanedURL)
                            return (item.index, .available)
                        } catch {
                            return (item.index, .unreachable)
                        }
                    }
                }
```

(Einzige Änderung: `group.addTask { @MainActor in` → `group.addTask {` — der Rest des Closure-Bodies bleibt identisch. Die nachfolgende `for await (index, status) in group`-Schleife bleibt unverändert im `@MainActor`-Kontext von `previewOPMLFeeds` selbst und aktualisiert `rowsByIndex`/ruft `onProgress?(...)` dort weiterhin korrekt koordiniert auf.)

- [ ] **Step 4: Test ausführen, Erfolg verifizieren**

Run: `xcodebuild -scheme Feedivo -destination 'platform=macOS' test -only-testing:FeedivoTests/SQLiteFeedSubscriptionServiceTests -parallel-testing-enabled NO`
Expected: PASS — inkl. aller bestehenden Tests der Suite, insbesondere `previewParalleelisiertBehaeltReihenfolgeUndStatus` (Reihenfolge/Status-Zuordnung darf sich durch die höhere Parallelität nicht ändern, da `rowsByIndex` weiterhin indexbasiert statt append-basiert befüllt wird).

- [ ] **Step 5: Build verifizieren und committen**

Run: `xcodebuild -scheme Feedivo -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED

```bash
git add Feedivo/Services/SQLiteFeedSubscriptionService.swift FeedivoTests/SQLiteFeedSubscriptionServiceTests.swift
git commit -m "Perf: OPML-Vorschau prueft Feeds tatsaechlich parallel statt MainActor-seriell"
```

---

## Bewusst nicht in diesem Plan (Follow-up-Kandidaten)

Aus dem Review vom 2026-07-11 zurückgestellt, da architektonisch invasiver und ein eigenes, sorgfältigeres Design brauchen — nicht geeignet für einen ersten "in einem Branch testen"-Durchlauf:

- **Async GRDB-Zugriff app-weit** (`FeedivoDatabase.read`/`write` laufen synchron auf dem MainActor, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` verstärkt das für praktisch jede Store-Methode) — größter Hebel, aber breite Blast-Radius über ~20 Store-/View-Dateien.
- **Aufteilung des globalen `sqliteStatusVersion`-Invalidierungskanals** (status-only vs. structure) — braucht Abstimmung, welche Mutationen "nur Status" vs. "Struktur" sind, plus Mehrfenster-Konsistenz-Überlegungen.
- **Doppelte `sidebarFeeds()`-Query zwischen `MenubarStatusItemController` und `ContentView`** — hängt am obigen Kanal-Split, sonst nur Verlagerung des Problems.
- **`RuleEngine`/`SQLiteRuleEvaluationStore.articleRuleSnapshots()`** — volle SQL-`WHERE`-Übersetzung der Regel-Bedingungen ist ein eigenes, größeres Stück Arbeit.
- **`FeedPropertiesView`-`onAppear`/`onChange`-Race** (ungewollter DB-Write beim bloßen Sheet-Öffnen) — kleinerer Fix, aber unabhängig vom Rest dieses Plans und beim nächsten UI-Durchgang gut mit erledigbar.

---

## Self-Review

**Spec-Abdeckung:** Alle 7 im Chat vereinbarten "Empfohlene Reihenfolge"-Punkte (Composite-Index, ORDER-BY-Index, FK-Kaskade, SQLiteFeedSubscriptionService-Parallelität, ImageCache-Throttling) sowie die zwei zusätzlich als "Hoch" markierten View-Findings (loadToken, displayState) sind je einer Task zugeordnet. Die explizit invasiveren Findings (async DB-Zugriff app-weit, Invalidierungs-Kanal-Split, RuleEngine-SQL-Übersetzung, FeedPropertiesView-Race) sind im Abschnitt "Bewusst nicht in diesem Plan" benannt statt stillschweigend wegzulassen.

**Platzhalter-Scan:** Kein Task enthält TBD/TODO-Marker; jeder Code-Block ist vollständig, jede Test-Assertion konkret.

**Typ-Konsistenz:** `SQLiteFeedArticleListLoadToken.make(...)` (Task 4) wird mit identischer Parameterliste sowohl im Test (Step 1) als auch im View-Code (Step 5) aufgerufen. `ImageCacheService.init(..., trimEveryNWrites:)` (Task 6) wird mit demselben Parameternamen in Test und Produktionscode verwendet. Migrationsnummern v11–v13 sind über die drei DB-Tasks hinweg fortlaufend und überschneidungsfrei.
