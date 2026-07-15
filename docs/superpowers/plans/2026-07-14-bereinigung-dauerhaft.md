# Bereinigte Artikel bleiben dauerhaft weg + Start-Reihenfolge — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bereinigte Artikel bleiben nach einem Feed-Refresh dauerhaft weg (statt sofort wieder eingefügt zu werden), und die automatische Bereinigung läuft beim App-Start garantiert vor einem eventuellen Start-Refresh.

**Architecture:** Zwei unabhängige Komponenten. (1) Die Start-Reihenfolge wird durch reines Verschieben eines bestehenden, synchronen Funktionsaufrufs von einem eigenen `.task`-Block in den bereits existierenden `handleContentAppear()`-Hook repariert — kein neuer Code, nur eine andere Aufrufreihenfolge. (2) `ArticleStore.upsert()` bekommt eine neue Prüfung: Bevor ein "neuer" Artikel eingefügt wird, wird geprüft, ob die `article_identity_history` für ihn ein neues `wasRemovedByRetention`-Flag trägt und der Artikel nach den *aktuellen* Bereinigungs-Einstellungen weiterhin abgelaufen wäre — falls ja, wird der Insert übersprungen. Das Flag wird ausschließlich von der periodischen Bereinigung auf `true` gesetzt und bei jedem erfolgreichen Upsert wieder auf `false` zurückgesetzt.

**Tech Stack:** Swift, GRDB (SQLite), Swift Testing (`@Test`/`#expect`/`#require`), bestehende Projektkonventionen (siehe unten).

## Global Constraints

- Migrationen werden **nur angehängt** — der aktuelle Migrationsstand ist bereits `v13_add_article_statuses_foreign_key` (nicht v10, wie in einer älteren Version der Design-Spec vermutet — inzwischen sind v11–v13 dazugekommen). Die neue Migration in diesem Plan heißt daher **`v14_add_article_identity_history_retention_flag`**, nicht v11. Bestehende Migrationen werden nicht verändert.
- Kein fester, von den Bereinigungs-Einstellungen unabhängiger Sperrzeitraum ("Snooze") — die Kopplung an die aktuellen Einstellungen ist bewusst die einzige Regel.
- Brandneue, noch nie gesehene Artikel (kein Treffer in `article_identity_history`) sind von der neuen Prüfung nicht betroffen.
- Keine Änderung an der `minimumArticlesPerFeed`-Schutzlogik der periodischen Bereinigung selbst (die neue Upsert-Prüfung ist bewusst einfacher: nur `isEnabled` + `cutoffDate`, keine Stern/Archiv- oder Mindestanzahl-Berücksichtigung).
- Kommentare im Code auf Deutsch (Projektkonvention).

## Gelöste offene Detailfragen aus der Design-Spec

**Frage 1 (Sichtbarkeit von `ArticleRetentionConfiguration`):** Der bestehende `private struct ArticleRetentionConfiguration` in `ArticleRetentionCleanupService.swift:458` wird wiederverwendet — dafür wird nur das `private`-Keyword vor der Struct-Deklaration entfernt (→ implizit `internal`, modulweit sichtbar). Keine neue, zweite Konfigurationsberechnung in `ArticleStore.swift`. Begründung: identisch zur bereits im Projekt dokumentierten Lehre aus Befund B — divergente Duplikate derselben Cutoff-Logik sind ein bekanntes Risikomuster.

**Frage 2 (Rückgabewert-Semantik bei übersprungenen Artikeln):** **Kein neues Feld** auf `ArticleUpsertResult` nötig. Verifiziert per Call-Graph-Analyse: Es gibt genau zwei Produktions-Aufrufer von `ArticleStore.upsert(_ inputs:)` — `SQLiteFeedRefreshService.swift:120` (nutzt nur `insertedArticleIDs`/`updatedArticleIDs` für Regel-Anwendung, Benachrichtigungen und `recentlyPublishedCount`) und `SQLiteFeedSubscriptionService.swift:172` (verwirft das Ergebnis komplett mit `_ = try articleUpsert(...)`). Ein übersprungener Artikel landet einfach in **keiner** der drei Ergebnislisten (`insertedArticleIDs`, `updatedArticleIDs`, `articleIDs`) — beide bestehenden Aufrufer verhalten sich dadurch automatisch korrekt (keine Benachrichtigung, keine Regelanwendung, kein Einfluss auf Ungelesen-Zähler für einen Artikel, der de facto nicht existiert). Die private Ein-Element-Convenience-Methode `upsert(_ input:) -> String` wirft in diesem Fall weiterhin ihren bestehenden `ArticleStoreError.emptyBatch` (technisch korrekt: der Batch aus einem Element hat keine ID produziert). Per Grep bestätigt: diese Convenience-Methode hat aktuell **keine** Produktions-Aufrufer, nur Tests — das Verhalten ist also folgenlos für die App selbst.

---

### Task 1: Migration v14 + `wasRemovedByRetention`-Feld auf `ArticleIdentityHistoryRecord`

**Files:**
- Modify: `Feedivo/Database/FeedivoDatabaseMigrator.swift:310-364` (neue Migration nach `v13_add_article_statuses_foreign_key` anhängen, vor `return migrator`)
- Modify: `Feedivo/Database/Records/ArticleIdentityHistoryRecord.swift` (neues Feld)
- Test: `FeedivoTests/SQLiteDatabaseMigrationTests.swift`

**Interfaces:**
- Produces: Spalte `article_identity_history.wasRemovedByRetention` (`BOOLEAN NOT NULL DEFAULT FALSE`); `ArticleIdentityHistoryRecord.wasRemovedByRetention: Bool` (Default `false` im Initializer, damit die zwei bestehenden Direkt-Konstruktions-Stellen — `ArticleStore.swift:516` und `FeedivoTests/SQLiteArticleStoreTests.swift:154` — unverändert kompilieren).

- [ ] **Step 1: Schreibe fehlschlagenden Migrationstest**

In `FeedivoTests/SQLiteDatabaseMigrationTests.swift`, füge nach `migrationCreatesArticlesPublishedCoalesceExpressionIndex()` (Zeile 71-77) diesen neuen Test ein:

```swift
    @Test func migrationFuegtWasRemovedByRetentionSpalteZuIdentityHistoryHinzu() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        let columns = try database.read { db in
            try Row.fetchAll(db, sql: "PRAGMA table_info(article_identity_history)")
        }
        let column = columns.first { ($0["name"] as String?) == "wasRemovedByRetention" }

        #expect(column != nil)
        #expect((column?["notnull"] as Int?) == 1)
        #expect((column?["dflt_value"] as String?) == "0")
    }
```

- [ ] **Step 2: Test ausführen, Fehlschlag bestätigen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteDatabaseMigrationTests/migrationFuegtWasRemovedByRetentionSpalteZuIdentityHistoryHinzu`
Expected: FAIL (`column` ist `nil`, da die Spalte noch nicht existiert)

- [ ] **Step 3: Migration hinzufügen**

In `Feedivo/Database/FeedivoDatabaseMigrator.swift`, füge nach dem `v13_add_article_statuses_foreign_key`-Block (endet aktuell bei Zeile 363 mit der letzten `try database.create(index: ...)`-Zeile) und vor `return migrator` (Zeile 365) ein:

```swift
        migrator.registerMigration("v14_add_article_identity_history_retention_flag") { database in
            try database.alter(table: "article_identity_history") { table in
                table.add(column: "wasRemovedByRetention", .boolean)
                    .notNull()
                    .defaults(to: false)
            }
        }
```

- [ ] **Step 4: Feld auf `ArticleIdentityHistoryRecord` ergänzen**

In `Feedivo/Database/Records/ArticleIdentityHistoryRecord.swift`, füge nach `var hiddenAt: Date?` (Zeile 23) ein neues Feld mit Default-Wert hinzu, damit bestehende Konstruktionsaufrufe ohne dieses Argument weiter kompilieren:

```swift
    var hiddenAt: Date?
    var wasRemovedByRetention: Bool = false
}
```

(Ersetzt die bisherigen letzten zwei Zeilen der Datei — `var hiddenAt: Date?` gefolgt von der schließenden `}` — durch die drei obigen Zeilen.)

- [ ] **Step 5: Tests ausführen, Erfolg bestätigen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteDatabaseMigrationTests`
Expected: PASS (alle Tests in dieser Suite, inkl. des neuen)

- [ ] **Step 6: Vollständigen Build prüfen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED (stellt sicher, dass die zwei bestehenden `ArticleIdentityHistoryRecord(...)`-Konstruktionsaufrufe in `Feedivo/Stores/ArticleStore.swift:516` und `Feedivo/Services/ArticleRetentionCleanupService.swift:379` ohne Änderung weiter kompilieren, da das neue Feld einen Default-Wert hat)

- [ ] **Step 7: Commit**

```bash
git add Feedivo/Database/FeedivoDatabaseMigrator.swift Feedivo/Database/Records/ArticleIdentityHistoryRecord.swift FeedivoTests/SQLiteDatabaseMigrationTests.swift
git commit -m "$(cat <<'EOF'
Feature: Migration v14 fuegt wasRemovedByRetention-Flag zu article_identity_history hinzu

Grundlage fuer die Unterdrueckung des Wiedereinfuegens bereinigter Artikel.
EOF
)"
```

---

### Task 2: `ArticleRetentionCleanupService` setzt das Flag beim Bereinigen

**Files:**
- Modify: `Feedivo/Services/ArticleRetentionCleanupService.swift:358-479`
- Test: `FeedivoTests/ArticleRetentionCleanupServiceTests.swift:55-98`

**Interfaces:**
- Consumes: `ArticleIdentityHistoryRecord.wasRemovedByRetention: Bool` (aus Task 1)
- Produces: `ArticleRetentionConfiguration` (Zeile 458) wird von `private struct` zu `struct` (modulweit sichtbar) — Task 3 nutzt sie über `ArticleRetentionConfiguration(isEnabled:retentionDays:minimumArticlesPerFeed:includeProtectedArticles:now:)` mit den gelesenen Properties `.isEnabled: Bool` und `.cutoffDate: Date`.

- [ ] **Step 1: Bestehenden Test um fehlschlagende Assertion erweitern**

In `FeedivoTests/ArticleRetentionCleanupServiceTests.swift`, erweitere den bestehenden Test `sqliteCleanupSichertIdentitaetsHistorieVorDemLoeschen()` (Zeile 55-98) um eine neue Assertion direkt nach der letzten bestehenden (`#expect(history?.firstSeenAt == oldDate)`, Zeile 97):

```swift
        #expect(removedCount == 1)
        #expect(history?.lastArticleID == expiredID)
        #expect(history?.isRead == true)
        #expect(history?.readAt == readAt)
        #expect(history?.firstSeenAt == oldDate)
        #expect(history?.wasRemovedByRetention == true)
    }
```

- [ ] **Step 2: Test ausführen, Fehlschlag bestätigen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ArticleRetentionCleanupServiceTests/sqliteCleanupSichertIdentitaetsHistorieVorDemLoeschen`
Expected: FAIL (`history?.wasRemovedByRetention` ist `false`, der Default-Wert aus Task 1)

- [ ] **Step 3: Flag beim Speichern der History setzen**

In `Feedivo/Services/ArticleRetentionCleanupService.swift`, in `SQLiteArticleIdentityHistoryCandidate.saveHistory(now:db:)` (Zeile 358-399), setze das Flag in **beiden** Zweigen explizit auf `true`.

Im "existing history aktualisieren"-Zweig (Zeile 359-377), füge vor `try history.save(db)` (Zeile 375) ein:

```swift
            history.hiddenAt = hiddenAt
            history.wasRemovedByRetention = true
            try history.save(db)
            return
```

Im "neue history anlegen"-Zweig (Zeile 379-398), ergänze den Initializer-Aufruf um das neue Argument:

```swift
        var history = ArticleIdentityHistoryRecord(
            id: UUID().uuidString,
            feedID: feedID,
            sourceID: sourceID.trimmedNonEmpty,
            link: link.trimmedNonEmpty,
            titleHash: ArticleStore.titleHash(title),
            publishedAt: publishedAt,
            firstSeenAt: dateArrived,
            lastSeenAt: now,
            lastArticleID: id,
            isRead: isRead,
            isStarred: isStarred,
            isArchived: isArchived,
            isHidden: isHidden,
            readAt: readAt,
            starredAt: starredAt,
            archivedAt: archivedAt,
            hiddenAt: hiddenAt,
            wasRemovedByRetention: true
        )
        try history.insert(db)
    }
```

- [ ] **Step 4: Sichtbarkeit von `ArticleRetentionConfiguration` anheben**

In derselben Datei, Zeile 458, entferne `private` von der Struct-Deklaration:

```swift
struct ArticleRetentionConfiguration {
    let isEnabled: Bool
    let cutoffDate: Date
    let minimumArticlesPerFeed: Int
    let includeProtectedArticles: Bool

    init(
        isEnabled: Bool,
        retentionDays: Int,
        minimumArticlesPerFeed: Int,
        includeProtectedArticles: Bool,
        now: Date
    ) {
```

- [ ] **Step 5: Tests ausführen, Erfolg bestätigen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ArticleRetentionCleanupServiceTests`
Expected: PASS (alle Tests in dieser Suite)

- [ ] **Step 6: Vollständigen Build prüfen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Commit**

```bash
git add Feedivo/Services/ArticleRetentionCleanupService.swift FeedivoTests/ArticleRetentionCleanupServiceTests.swift
git commit -m "$(cat <<'EOF'
Fix: Automatische Bereinigung markiert entfernte Artikel als wasRemovedByRetention

Voraussetzung dafuer, dass ein spaeterer Feed-Refresh diese Artikel nicht
sofort wieder einfuegt (Komponente 2 der Bereinigung-dauerhaft-Spec).
EOF
)"
```

---

### Task 3: `ArticleStore.upsert()` unterdrückt Wiedereinfügen bereinigter Artikel

**Files:**
- Modify: `Feedivo/Stores/ArticleStore.swift:51-64` (Init), `:66-88` (Batch-Upsert), `:357-436` (privater Upsert), `:505-552` (`saveIdentityHistory`)
- Test: `FeedivoTests/SQLiteArticleStoreTests.swift`

**Interfaces:**
- Consumes: `ArticleRetentionConfiguration` (aus Task 2, jetzt modulweit sichtbar), `ArticleIdentityHistoryRecord.wasRemovedByRetention` (aus Task 1), `ArticleRetentionSettings.{isEnabledKey,retentionDaysKey,minimumArticlesPerFeedKey,includesProtectedArticlesKey,defaultIsEnabled,defaultRetentionDays,defaultMinimumArticlesPerFeed,defaultIncludesProtectedArticles}`, `FeedRecord.{articleRetentionOverridesGlobalSetting,articleRetentionIsEnabled,articleRetentionDays,articleRetentionMinimumArticles,articleRetentionIncludesProtectedArticles}`
- Produces: `ArticleStore.init(database:userDefaults:)` — neuer optionaler Parameter `userDefaults: UserDefaults = .standard` (Default erhält alle ~15 bestehenden Call-Sites unverändert kompilierbar). `ArticleUpsertResult` bleibt strukturell **unverändert** (siehe gelöste Frage 2 oben).

- [ ] **Step 1: Fehlschlagende Tests schreiben — Artikel bleibt weg, wenn weiterhin abgelaufen**

In `FeedivoTests/SQLiteArticleStoreTests.swift`, füge nach `upsertRestoresStatusFromIdentityHistory()` (endet Zeile 189) zwei neue Tests ein:

```swift

    @Test func upsertUeberspringtArtikelDerDurchBereinigungEntferntWurdeUndWeiterhinAbgelaufenIst() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let oldPublishedAt = Date().addingTimeInterval(-100 * 24 * 60 * 60)

        try feedStore.save(FeedRecord(
            id: "feed-1",
            url: "https://example.com/feed.xml",
            title: "Example",
            articleRetentionOverridesGlobalSetting: true,
            articleRetentionIsEnabled: true,
            articleRetentionDays: 90
        ))

        var history = ArticleIdentityHistoryRecord(
            id: "history-1",
            feedID: "feed-1",
            sourceID: "source-1",
            link: "https://example.com/articles/1",
            titleHash: ArticleStore.titleHash("Alter Artikel"),
            publishedAt: oldPublishedAt,
            firstSeenAt: oldPublishedAt,
            lastSeenAt: oldPublishedAt,
            lastArticleID: "deleted-article",
            isRead: false,
            isStarred: false,
            isArchived: false,
            isHidden: false,
            readAt: nil,
            starredAt: nil,
            archivedAt: nil,
            hiddenAt: nil,
            wasRemovedByRetention: true
        )
        try database.write { db in
            try history.insert(db)
        }

        let result = try articleStore.upsert([ArticleUpsertInput(
            feedID: "feed-1",
            sourceID: "source-1",
            link: "https://example.com/articles/1",
            title: "Alter Artikel",
            publishedAt: oldPublishedAt,
            arrivedAt: Date()
        )])

        #expect(result.articleIDs.isEmpty)
        #expect(result.insertedArticleIDs.isEmpty)
        let articleCount = try database.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM articles") ?? 0
        }
        #expect(articleCount == 0)
    }

    @Test func upsertFuegtArtikelWiederEinWennBereinigungNichtMehrGreiftUndSetztFlagZurueck() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let oldPublishedAt = Date().addingTimeInterval(-100 * 24 * 60 * 60)
        let readAt = Date().addingTimeInterval(-90 * 24 * 60 * 60)

        try feedStore.save(FeedRecord(
            id: "feed-1",
            url: "https://example.com/feed.xml",
            title: "Example",
            articleRetentionOverridesGlobalSetting: true,
            articleRetentionIsEnabled: false,
            articleRetentionDays: 90
        ))

        var history = ArticleIdentityHistoryRecord(
            id: "history-1",
            feedID: "feed-1",
            sourceID: "source-1",
            link: "https://example.com/articles/1",
            titleHash: ArticleStore.titleHash("Alter Artikel"),
            publishedAt: oldPublishedAt,
            firstSeenAt: oldPublishedAt,
            lastSeenAt: oldPublishedAt,
            lastArticleID: "deleted-article",
            isRead: true,
            isStarred: false,
            isArchived: false,
            isHidden: false,
            readAt: readAt,
            starredAt: nil,
            archivedAt: nil,
            hiddenAt: nil,
            wasRemovedByRetention: true
        )
        try database.write { db in
            try history.insert(db)
        }

        let result = try articleStore.upsert([ArticleUpsertInput(
            feedID: "feed-1",
            sourceID: "source-1",
            link: "https://example.com/articles/1",
            title: "Alter Artikel",
            publishedAt: oldPublishedAt,
            arrivedAt: Date()
        )])

        #expect(result.insertedArticleIDs.count == 1)
        let articleID = try #require(result.insertedArticleIDs.first)
        let restoredHistory = try database.read { db in
            try ArticleIdentityHistoryRecord.fetchOne(db, sql: """
                SELECT * FROM article_identity_history WHERE feedID = ? AND sourceID = ? LIMIT 1
                """, arguments: ["feed-1", "source-1"])
        }

        #expect(restoredHistory?.wasRemovedByRetention == false)
        #expect(restoredHistory?.lastArticleID == articleID)
        let status = try ArticleStatusStore(database: database).status(articleID: articleID)
        #expect(status?.isRead == true)
    }
```

- [ ] **Step 2: Tests ausführen, Fehlschlag bestätigen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteArticleStoreTests/upsertUeberspringtArtikelDerDurchBereinigungEntferntWurdeUndWeiterhinAbgelaufenIst -only-testing:FeedivoTests/SQLiteArticleStoreTests/upsertFuegtArtikelWiederEinWennBereinigungNichtMehrGreiftUndSetztFlagZurueck`
Expected: FAIL — im ersten Test wird der Artikel trotzdem eingefügt (`articleCount == 1` statt `0`), da die Unterdrückungs-Prüfung noch nicht existiert.

- [ ] **Step 3: `userDefaults`-Abhängigkeit auf `ArticleStore` ergänzen**

In `Feedivo/Stores/ArticleStore.swift`, ändere den Struct-Kopf (Zeile 51-56):

```swift
struct ArticleStore {
    private let database: FeedivoDatabase
    private let userDefaults: UserDefaults

    init(database: FeedivoDatabase, userDefaults: UserDefaults = .standard) {
        self.database = database
        self.userDefaults = userDefaults
    }
```

- [ ] **Step 4: Privaten Upsert-Rückgabetyp auf ein Outcome-Enum umstellen**

Füge direkt vor der privaten `upsert(_:db:)`-Methode (vor Zeile 357) das neue private Enum ein:

```swift
    private enum UpsertOutcome {
        case inserted(articleID: String)
        case updated(articleID: String)
        case skipped
    }

```

Ersetze die gesamte private Methode (aktuell Zeile 357-436) durch:

```swift
    private func upsert(_ input: ArticleUpsertInput, db: Database) throws -> UpsertOutcome {
        let sourceID = input.sourceID.trimmedNonEmpty
        let link = input.link.trimmedNonEmpty

        if let articleID = try findExistingArticleID(input: input, db: db) {
            let sourceIDAssignment = sourceID == nil ? "" : "sourceID = COALESCE(sourceID, ?),"
            var arguments = StatementArguments()
            if let sourceID {
                _ = arguments.append(contentsOf: [sourceID])
            }
            _ = arguments.append(contentsOf: [
                link,
                input.title,
                input.summary,
                input.content,
                input.imageURL,
                input.author,
                input.publishedAt,
                Date(),
                input.estimatedReadingMinutes,
                articleID
            ])

            try db.execute(
                sql: """
                    UPDATE articles
                    SET \(sourceIDAssignment)
                        link = ?,
                        title = ?,
                        summary = ?,
                        content = ?,
                        imageURL = ?,
                        author = ?,
                        publishedAt = ?,
                        updatedAt = ?,
                        estimatedReadingMinutes = ?
                    WHERE id = ?
                    """,
                arguments: arguments
            )
            try saveIdentityHistory(forArticleID: articleID, input: input, db: db)
            return .updated(articleID: articleID)
        }

        let history = try findIdentityHistory(input: input, db: db)
        if let history, history.wasRemovedByRetention {
            let configuration = try currentRetentionConfiguration(forFeedID: input.feedID, db: db)
            let effectiveDate = input.publishedAt ?? input.arrivedAt
            if configuration.isEnabled, effectiveDate < configuration.cutoffDate {
                // Artikel wurde bewusst bereinigt und ist nach aktuellen Einstellungen
                // weiterhin abgelaufen — nicht wieder einfügen.
                return .skipped
            }
        }

        let articleID = UUID().uuidString
        var article = ArticleRecord(
            id: articleID,
            feedID: input.feedID,
            sourceID: sourceID,
            link: link,
            title: input.title,
            summary: input.summary,
            content: input.content,
            imageURL: input.imageURL,
            author: input.author,
            publishedAt: input.publishedAt,
            arrivedAt: input.arrivedAt,
            updatedAt: Date(),
            estimatedReadingMinutes: input.estimatedReadingMinutes
        )
        try article.insert(db)

        var status = ArticleStatusRecord(
            articleID: articleID,
            isRead: history?.isRead ?? false,
            isStarred: history?.isStarred ?? false,
            isArchived: history?.isArchived ?? false,
            isHidden: history?.isHidden ?? false,
            readAt: history?.readAt,
            starredAt: history?.starredAt,
            archivedAt: history?.archivedAt,
            hiddenAt: history?.hiddenAt,
            dateArrived: history?.firstSeenAt ?? input.arrivedAt
        )
        try status.insert(db)
        try saveIdentityHistory(forArticleID: articleID, input: input, status: status, db: db)

        return .inserted(articleID: articleID)
    }

    private func currentRetentionConfiguration(forFeedID feedID: String, db: Database) throws -> ArticleRetentionConfiguration {
        let now = Date()
        guard
            let feed = try FeedRecord.fetchOne(db, key: feedID),
            feed.articleRetentionOverridesGlobalSetting
        else {
            return ArticleRetentionConfiguration(
                isEnabled: userDefaults.object(forKey: ArticleRetentionSettings.isEnabledKey) as? Bool
                    ?? ArticleRetentionSettings.defaultIsEnabled,
                retentionDays: userDefaults.object(forKey: ArticleRetentionSettings.retentionDaysKey) as? Int
                    ?? ArticleRetentionSettings.defaultRetentionDays,
                minimumArticlesPerFeed: userDefaults.object(forKey: ArticleRetentionSettings.minimumArticlesPerFeedKey) as? Int
                    ?? ArticleRetentionSettings.defaultMinimumArticlesPerFeed,
                includeProtectedArticles: userDefaults.object(forKey: ArticleRetentionSettings.includesProtectedArticlesKey) as? Bool
                    ?? ArticleRetentionSettings.defaultIncludesProtectedArticles,
                now: now
            )
        }

        return ArticleRetentionConfiguration(
            isEnabled: feed.articleRetentionIsEnabled,
            retentionDays: feed.articleRetentionDays,
            minimumArticlesPerFeed: feed.articleRetentionMinimumArticles,
            includeProtectedArticles: feed.articleRetentionIncludesProtectedArticles,
            now: now
        )
    }
```

- [ ] **Step 5: Batch-Upsert an das neue Outcome-Enum anpassen**

Ersetze `upsert(_ inputs:)` (aktuell Zeile 66-88):

```swift
    func upsert(_ inputs: [ArticleUpsertInput]) throws -> ArticleUpsertResult {
        try database.write { db in
            var insertedArticleIDs: [String] = []
            var updatedArticleIDs: [String] = []
            var articleIDs: [String] = []

            for input in inputs {
                switch try upsert(input, db: db) {
                case .inserted(let articleID):
                    articleIDs.append(articleID)
                    insertedArticleIDs.append(articleID)
                case .updated(let articleID):
                    articleIDs.append(articleID)
                    updatedArticleIDs.append(articleID)
                case .skipped:
                    break
                }
            }

            return ArticleUpsertResult(
                insertedArticleIDs: insertedArticleIDs,
                updatedArticleIDs: updatedArticleIDs,
                articleIDs: articleIDs
            )
        }
    }
```

(Die Ein-Element-Convenience-Methode `upsert(_ input:) -> String` direkt darüber bleibt unverändert — sie wirft weiterhin `ArticleStoreError.emptyBatch`, wenn `articleIDs` leer ist, was jetzt auch beim Überspringen zutrifft.)

- [ ] **Step 6: `saveIdentityHistory` setzt das Flag bei erfolgreichem Upsert zurück**

In `saveIdentityHistory(forArticleID:input:status:db:)` (aktuell Zeile 505-552), füge vor `try history.save(db)` (Zeile 551) eine Zeile ein:

```swift
        history.hiddenAt = status.hiddenAt
        history.wasRemovedByRetention = false

        try history.save(db)
    }
```

- [ ] **Step 7: Tests ausführen, Erfolg bestätigen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteArticleStoreTests`
Expected: PASS (alle Tests in dieser Suite, inkl. der zwei neuen und der bestehenden `upsertRestoresStatusFromIdentityHistory`/`upsertInsertsArticleAndCreatesStatus`)

- [ ] **Step 8: Betroffene Nachbar-Suiten laufen lassen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ArticleRetentionCleanupServiceTests -only-testing:FeedivoTests/SQLiteFeedRefreshServiceTests`
Expected: PASS (beide Suiten nutzen `ArticleStore.upsert` intensiv — stellt sicher, dass die Signaturänderung des privaten Enums keine bestehenden Konsumenten bricht)

- [ ] **Step 9: Vollständigen Build prüfen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED

- [ ] **Step 10: Commit**

```bash
git add Feedivo/Stores/ArticleStore.swift FeedivoTests/SQLiteArticleStoreTests.swift
git commit -m "$(cat <<'EOF'
Fix: ArticleStore.upsert() fuegt bereinigte Artikel nicht wieder ein, solange sie abgelaufen bleiben

Prueft article_identity_history.wasRemovedByRetention gegen die aktuellen
Bereinigungs-Einstellungen (global oder Feed-Override) vor dem Insert eines
"neuen" Artikels. Setzt das Flag bei jedem erfolgreichen Upsert zurueck, damit
ein Artikel nach einer Einstellungsaenderung (laengere Aufbewahrung,
Bereinigung deaktiviert) regulaer wieder erscheinen kann.
EOF
)"
```

---

### Task 4: Start-Reihenfolge — Bereinigung läuft garantiert vor Start-Refresh

**Files:**
- Modify: `Feedivo/App/FeedivoApp.swift:87-92`
- Modify: `Feedivo/Views/ContentView.swift:389-395`
- Test: `FeedivoTests/FeedivoAppSceneConfigurationTests.swift`

**Interfaces:**
- Consumes: `BackgroundRefreshService.cleanupExpiredArticlesIfNeeded(database:userDefaults:now:)` (bereits existierende Funktion aus Befund C, liest Retention-Einstellungen direkt aus `UserDefaults.standard` — kein neuer Code nötig)
- Produces: keine neuen öffentlichen Symbole — reine Verschiebung eines Aufrufs.

- [ ] **Step 1: Fehlschlagenden Reihenfolge-Test schreiben**

In `FeedivoTests/FeedivoAppSceneConfigurationTests.swift`, füge am Ende der Struct (vor der letzten schließenden `}`, direkt nach der letzten bestehenden `@Test`-Methode) diesen Test ein:

```swift

    @Test func startupBereinigungLaeuftVorDemStartRefreshOhneRace() throws {
        let projectRoot = projectRootURL()
        let appSource = try source(at: "Feedivo/App/FeedivoApp.swift", projectRoot: projectRoot)
        let contentSource = try source(at: "Feedivo/Views/ContentView.swift", projectRoot: projectRoot)

        let taskStart = try #require(appSource.range(of: ".task {"))
        let onChangeStart = try #require(appSource.range(of: ".onChange(of: backgroundRefreshIsEnabled)"))
        let taskBlockSource = appSource[taskStart.lowerBound..<onChangeStart.lowerBound]
        #expect(!taskBlockSource.contains("cleanupExpiredArticlesIfNeeded()"))

        let handleContentAppearStart = try #require(contentSource.range(of: "private func handleContentAppear()"))
        let nextFunctionStart = try #require(contentSource.range(of: "private func reloadFeedSnapshots"))
        let handleContentAppearSource = contentSource[handleContentAppearStart.lowerBound..<nextFunctionStart.lowerBound]

        #expect(handleContentAppearSource.contains("BackgroundRefreshService.cleanupExpiredArticlesIfNeeded(database: feedivoDatabase)"))

        let cleanupCallRange = try #require(handleContentAppearSource.range(of: "cleanupExpiredArticlesIfNeeded(database: feedivoDatabase)"))
        let refreshCallRange = try #require(handleContentAppearSource.range(of: "refreshFeedsOnLaunchIfNeeded()"))
        #expect(cleanupCallRange.lowerBound < refreshCallRange.lowerBound)
    }
```

- [ ] **Step 2: Test ausführen, Fehlschlag bestätigen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoAppSceneConfigurationTests/startupBereinigungLaeuftVorDemStartRefreshOhneRace`
Expected: FAIL — der `.task`-Block in `FeedivoApp.swift` enthält aktuell noch `cleanupExpiredArticlesIfNeeded()`, und `handleContentAppear()` in `ContentView.swift` enthält den neuen Aufruf noch gar nicht.

- [ ] **Step 3: Aufruf aus `FeedivoApp.swift`s `.task`-Block entfernen**

In `Feedivo/App/FeedivoApp.swift`, ändere den `.task`-Block (Zeile 87-92):

```swift
                .task {
                    backfillStoredArticleMetadataIfNeeded()
                    trimImageCacheToSelectedLimit()
                    scheduleBackgroundRefresh()
                }
```

Die private Methode `cleanupExpiredArticlesIfNeeded()` (Zeile 212-221) und die vier `.onChange`-Handler, die sie bei Retention-Einstellungsänderungen aufrufen (Zeile 99-113), bleiben **unverändert** — nur der `.task`-Aufruf beim App-Start wird entfernt.

- [ ] **Step 4: Aufruf in `ContentView.handleContentAppear()` ergänzen**

In `Feedivo/Views/ContentView.swift`, ändere `handleContentAppear()` (Zeile 389-395):

```swift
    private func handleContentAppear() {
        if let feedivoDatabase {
            BackgroundRefreshService.cleanupExpiredArticlesIfNeeded(database: feedivoDatabase)
        }
        updateFirstRunWizardPresentation()
        selectDefaultSmartFolderIfNeeded()
        updateAppIconBadge()
        restoreArticleWindowsIfNeeded()
        refreshFeedsOnLaunchIfNeeded()
    }
```

Der Bereinigungsaufruf muss der erste Schritt sein und läuft synchron auf dem MainActor (`ArticleRetentionCleanupService.runAutomaticCleanup`/`removeExpiredSQLiteArticles` sind nicht-async `@MainActor`-Funktionen) — dadurch ist die Reihenfolge vor `refreshFeedsOnLaunchIfNeeded()` (das einen `Task { await refreshAllFeeds() }` startet) garantiert, ohne dass ein Race möglich ist.

- [ ] **Step 5: Test ausführen, Erfolg bestätigen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoAppSceneConfigurationTests/startupBereinigungLaeuftVorDemStartRefreshOhneRace`
Expected: PASS

- [ ] **Step 6: Bekannte Vorbestands-Fehlschläge der Suite prüfen (nicht neu einführen)**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoAppSceneConfigurationTests`
Expected: Wie in `CLAUDE.md` dokumentiert bestehen bereits 9 vorbestehende Fehlschläge in dieser Suite (unabhängig von dieser Änderung) — es dürfen **keine zusätzlichen** Fehlschläge über diese 9 hinaus auftreten. Bei Abweichung: prüfen, ob eine der Änderungen aus Task 4 einen der 9 bekannten Fälle zufällig mit repariert oder einen neuen bricht, und im Plan-Ausführungsprotokoll dokumentieren.

- [ ] **Step 7: Vollständigen Build prüfen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED

- [ ] **Step 8: Commit**

```bash
git add Feedivo/App/FeedivoApp.swift Feedivo/Views/ContentView.swift FeedivoTests/FeedivoAppSceneConfigurationTests.swift
git commit -m "$(cat <<'EOF'
Fix: Automatische Bereinigung laeuft beim App-Start garantiert vor dem Start-Refresh

Der Cleanup-Aufruf zog aus dem eigenstaendigen .task-Block in FeedivoApp.swift
in ContentView.handleContentAppear() um, als allererster Schritt vor
refreshFeedsOnLaunchIfNeeded(). Beide liefen zuvor als unabhaengige,
ungeordnete SwiftUI-Lifecycle-Hooks parallel — der Start-Refresh konnte
gerade bereinigte Artikel sofort wieder einfuegen, bevor der Nutzer die
Bereinigung ueberhaupt sah.
EOF
)"
```

---

## Manuelle Verifikation (nach Abschluss aller Tasks)

Nicht automatisierbar (kein computer-use für native macOS-Apps in dieser Umgebung) — vom Nutzer nachzustellen:

1. Retention aktivieren, einen alten Artikel manuell bereinigen lassen (oder auf die automatische Bereinigung warten).
2. Feeds manuell aktualisieren (oder App neu starten mit aktiviertem "Beim Start aktualisieren") — der zuvor bereinigte Artikel darf **nicht** wieder auftauchen, auch wenn der Feed ihn weiterhin liefert.
3. Retention-Einstellungen ändern (z. B. Tage stark erhöhen oder Bereinigung deaktivieren) und erneut aktualisieren — der zuvor bereinigte Artikel darf jetzt **wieder** regulär erscheinen.
4. App mit aktiviertem "Beim Start aktualisieren" neu starten — die Bereinigung muss sichtbar VOR dem sichtbaren Start-Refresh-Ergebnis abgeschlossen sein (kein kurzes Aufblitzen zuvor bereinigter Artikel).
