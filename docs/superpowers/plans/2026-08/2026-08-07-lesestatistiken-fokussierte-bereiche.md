# Lesestatistiken neu gegliedert in fokussierte Bereiche — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Das Statistik-Fenster von einem flachen Kachel-Raster mit strukturell immer-0-Lesezeit
auf eine neu gegliederte Ansicht mit echtem Lesezeit-Wert, einem klaren visuellen Fokuspunkt
(Serie + Heatmap als Hero) und drei fokussierten Abschnitten (Gewohnheiten, Aufmerksamkeit,
Feed-Gesundheit) umbauen.

**Architecture:** GRDB/SQLite-Datenschicht (`StatisticsStore`) liefert erweiterte,
Zeitzonen-korrekte Aggregationen über einen neuen `ReadingStatisticsSnapshot`; SwiftUI-Views im
bestehenden "Konzept A"-Designsystem (`RuleDialogTheme`) rendern die neue Sektionsstruktur. Der
zugrunde liegende Bug (Lesezeit wird nie persistiert) wird an der Quelle behoben
(`ArticleUpsertInput`) plus rückwirkendem Migrations-Backfill.

**Tech Stack:** Swift 5.9+, SwiftUI (macOS), GRDB/SQLite, Swift Testing (kein XCTest).

## Global Constraints

- Kommentare im Code auf Deutsch (Projektkonvention, siehe CLAUDE.md).
- UI-Farben/Radien/Typografie ausschließlich aus `RuleDialogTheme(colorScheme:)`-Tokens
  (`theme.bg/card/text/text2/border/accent/track` etc.) — keine System-Semantikfarben, keine
  frei erfundenen Hex-Werte. Warnfarbe für Feed-Gesundheit: `#FF9F0A` (bereits Teil der
  App-Palette, `RuleDialogTagSwatches`).
- Datenbank-Migrationen: nur eine NEUE `registerMigration(...)` anhängen (aktuell zuletzt
  `v29_add_cloud_sync_indexes`), niemals eine bestehende Migration verändern. Neue Migration in
  diesem Plan: `v30_backfill_article_estimated_reading_minutes`.
- `Localizable.xcstrings` NIE per vollem JSON-Load/-Dump anfassen — neue Einträge werden als
  reiner Text-Block an einem stabilen, bereits vorhandenen Anker eingefügt (siehe Task 6). Nach
  jeder Einfügung `git diff --stat` prüfen (nur Insertions, keine/kaum Deletions) und
  `grep -c "<neuer key>" Feedivo/Resources/Localizable.xcstrings` (muss `1` ergeben — je ein
  Treffer für den Key-String selbst). Vier Sprachen: `de` (Referenz/App-Standard), `en`, `fr`,
  `it`.
- Zeitzonen-Korrektheit: Wochentag-/Tageszeit-/Tages-Bucketing über gelesene Artikel läuft in
  Swift über `Calendar.current`/`TimeZone.current` auf rohen `readAt`-Zeitstempeln — NICHT über
  SQLite `date()`/`strftime()` (die arbeiten auf dem gespeicherten UTC-String, was für Nutzer
  außerhalb UTC falsche Wochentage/Uhrzeiten ergäbe).
- Build-Verifikation: `xcodebuild build -scheme Feedivo -configuration Debug`.
- Test-Verifikation bei mehreren Suiten gleichzeitig: immer mit `-parallel-testing-enabled NO`
  (bekanntes SIGSEGV-Risiko bei paralleler GUI-Testausführung in diesem Projekt).
- Reine SwiftUI-Layout-Änderungen ohne extrahierbare Logik werden nicht unit-getestet (keine
  ViewInspector-Abhängigkeit in diesem Projekt) — Verifikation dort ausschließlich über
  erfolgreichen Build; manuelle Live-Verifikation folgt separat durch den Nutzer.

---

### Task 1: Lesezeit-Bug beheben — `ReaderMetadataFormatter.estimatedMinutes` + Aufrufstellen befüllen

**Files:**
- Modify: `Feedivo/Views/Reader/ReaderMetadataFormatter.swift`
- Modify: `Feedivo/Services/SQLiteFeedRefreshService.swift:136` (Konstruktion von `ArticleUpsertInput`)
- Modify: `Feedivo/Services/SQLiteFeedSubscriptionService.swift:171` (Konstruktion von `ArticleUpsertInput`)
- Test: `FeedivoTests/Views/Reader/ReaderMetadataFormatterTests.swift` (neu)

**Interfaces:**
- Produces: `ReaderMetadataFormatter.estimatedMinutes(content: String?, summary: String?) -> Int?`
  — wird von Task 1 selbst (beide Service-Aufrufstellen) und von Task 2 (Migrations-Backfill)
  konsumiert.

- [ ] **Step 1: Fehlschlagenden Test schreiben**

Erstelle `FeedivoTests/Views/Reader/ReaderMetadataFormatterTests.swift`:

```swift
import Foundation
import Testing
@testable import Feedivo

struct ReaderMetadataFormatterTests {
    @Test func estimatedMinutesLiefertNilBeiLeeremContentUndSummary() {
        #expect(ReaderMetadataFormatter.estimatedMinutes(content: nil, summary: nil) == nil)
        #expect(ReaderMetadataFormatter.estimatedMinutes(content: "", summary: "   ") == nil)
    }

    @Test func estimatedMinutesBevorzugtContentVorSummary() {
        let content = Array(repeating: "wort", count: 400).joined(separator: " ")
        let summary = Array(repeating: "wort", count: 10).joined(separator: " ")

        #expect(ReaderMetadataFormatter.estimatedMinutes(content: content, summary: summary) == 2)
    }

    @Test func estimatedMinutesNutztSummaryFallsContentLeerIst() {
        let summary = Array(repeating: "wort", count: 50).joined(separator: " ")

        #expect(ReaderMetadataFormatter.estimatedMinutes(content: nil, summary: summary) == 1)
    }

    @Test func estimatedMinutesRundetAufUndMindestensEineMinute() {
        #expect(ReaderMetadataFormatter.estimatedMinutes(content: "einzelnesWort", summary: nil) == 1)
    }

    @Test func estimatedMinutesRundetAufBeiUngeraderWortzahl() {
        let content = Array(repeating: "wort", count: 201).joined(separator: " ")

        #expect(ReaderMetadataFormatter.estimatedMinutes(content: content, summary: nil) == 2)
    }
}
```

- [ ] **Step 2: Test laufen lassen, Fehlschlag bestätigen**

Run: `xcodebuild test -scheme Feedivo -only-testing:FeedivoTests/ReaderMetadataFormatterTests -parallel-testing-enabled NO`
Expected: FAIL — `estimatedMinutes` existiert noch nicht auf `ReaderMetadataFormatter`.

- [ ] **Step 3: `ReaderMetadataFormatter` um `estimatedMinutes` erweitern**

Ersetze in `Feedivo/Views/Reader/ReaderMetadataFormatter.swift` den bestehenden Block

```swift
    static func readingTimeText(content: String?, summary: String?) -> String? {
        let text = preferredText(content: content, summary: summary)
        guard !text.isEmpty else {
            return nil
        }

        return readingTimeText(for: text)
    }

    static func readingTimeText(for text: String) -> String {
        let words = wordCount(in: text)
        let minutes = max(1, Int(ceil(Double(words) / Double(wordsPerMinute))))
        return L10n.readerReadingTime(minutes: minutes)
    }
```

durch:

```swift
    /// Persistierbare Lesezeit-Schätzung — nutzt dieselbe Wortzahl-Logik wie die
    /// Reader-Anzeige (`readingTimeText`), damit beide nie auseinanderlaufen. Wird
    /// sowohl beim Anlegen/Aktualisieren eines Artikels (`ArticleUpsertInput.
    /// estimatedReadingMinutes`) als auch beim Bestands-Backfill (Migration v30)
    /// verwendet.
    static func estimatedMinutes(content: String?, summary: String?) -> Int? {
        let text = preferredText(content: content, summary: summary)
        guard !text.isEmpty else {
            return nil
        }

        return minutes(for: text)
    }

    static func readingTimeText(content: String?, summary: String?) -> String? {
        let text = preferredText(content: content, summary: summary)
        guard !text.isEmpty else {
            return nil
        }

        return readingTimeText(for: text)
    }

    static func readingTimeText(for text: String) -> String {
        L10n.readerReadingTime(minutes: minutes(for: text))
    }

    private static func minutes(for text: String) -> Int {
        let words = wordCount(in: text)
        return max(1, Int(ceil(Double(words) / Double(wordsPerMinute))))
    }
```

- [ ] **Step 4: Test laufen lassen, Erfolg bestätigen**

Run: `xcodebuild test -scheme Feedivo -only-testing:FeedivoTests/ReaderMetadataFormatterTests -parallel-testing-enabled NO`
Expected: PASS (5/5 Tests grün).

- [ ] **Step 5: Beide Aufrufstellen befüllen**

In `Feedivo/Services/SQLiteFeedRefreshService.swift`, im Block um Zeile 136 (`let inputs =
parsedFeed.articles.map { article in ArticleUpsertInput(...) }`):

```swift
                let inputs = parsedFeed.articles.map { article in
                    ArticleUpsertInput(
                        feedID: feedID,
                        sourceID: article.sourceID,
                        link: article.link,
                        title: article.title,
                        summary: article.summary,
                        content: article.content,
                        imageURL: article.imageURL,
                        author: article.author,
                        publishedAt: article.publishedAt,
                        arrivedAt: refreshedAt,
                        estimatedReadingMinutes: ReaderMetadataFormatter.estimatedMinutes(
                            content: article.content,
                            summary: article.summary
                        )
                    )
                }
```

In `Feedivo/Services/SQLiteFeedSubscriptionService.swift`, im Block um Zeile 171
(`let articleInputs = enrichedArticles.map { article in ArticleUpsertInput(...) }`):

```swift
            let articleInputs = enrichedArticles.map { article in
                ArticleUpsertInput(
                    feedID: feedID,
                    sourceID: article.sourceID,
                    link: article.link,
                    title: article.title,
                    summary: article.summary,
                    content: article.content,
                    imageURL: article.imageURL,
                    author: article.author,
                    publishedAt: article.publishedAt,
                    arrivedAt: now,
                    estimatedReadingMinutes: ReaderMetadataFormatter.estimatedMinutes(
                        content: article.content,
                        summary: article.summary
                    )
                )
            }
```

- [ ] **Step 6: Build verifizieren**

Run: `xcodebuild build -scheme Feedivo -configuration Debug`
Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Commit**

```bash
git add Feedivo/Views/Reader/ReaderMetadataFormatter.swift \
  Feedivo/Services/SQLiteFeedRefreshService.swift \
  Feedivo/Services/SQLiteFeedSubscriptionService.swift \
  FeedivoTests/Views/Reader/ReaderMetadataFormatterTests.swift
git commit -m "fix: Lesezeit wird beim Anlegen/Aktualisieren von Artikeln persistiert

estimatedReadingMinutes wurde nie an ArticleUpsertInput übergeben und blieb
dadurch strukturell immer NULL. Neue geteilte Funktion
ReaderMetadataFormatter.estimatedMinutes(content:summary:) an beiden
Aufrufstellen (Refresh, Subscription) verdrahtet."
```

---

### Task 2: Migration v30 — rückwirkender Lesezeit-Backfill

**Files:**
- Modify: `Feedivo/Database/FeedivoDatabaseMigrator.swift`
- Test: `FeedivoTests/Database/FeedivoDatabaseMigratorTests.swift`

**Interfaces:**
- Consumes: `ReaderMetadataFormatter.estimatedMinutes(content:summary:)` (Task 1).
- Produces: Migration `"v30_backfill_article_estimated_reading_minutes"`, registriert nach
  `v29_add_cloud_sync_indexes`, unmittelbar vor `return migrator`.

- [ ] **Step 1: Fehlschlagenden Test schreiben**

Füge in `FeedivoTests/Database/FeedivoDatabaseMigratorTests.swift` (am Ende der `struct
FeedivoDatabaseMigratorTests`, vor der letzten schließenden Klammer) hinzu:

```swift
    @Test func migrationV30BackfilltFehlendeLesezeitUndLaesstBestehendeWerteUnangetastet() throws {
        let queue = try DatabaseQueue()
        try FeedivoDatabaseMigrator.migrator.migrate(queue, upTo: "v29_add_cloud_sync_indexes")

        try queue.write { db in
            let now = Date()
            try db.execute(
                sql: """
                    INSERT INTO feeds (id, url, title, refreshIntervalMinutes, unreadCount, createdAt, updatedAt)
                    VALUES ('feed-1', 'https://example.com/feed.xml', 'Test', 30, 0, ?, ?)
                    """,
                arguments: [now, now]
            )

            let longContent = Array(repeating: "wort", count: 400).joined(separator: " ")
            try db.execute(
                sql: """
                    INSERT INTO articles (id, feedID, title, content, arrivedAt, updatedAt, estimatedReadingMinutes)
                    VALUES ('article-null', 'feed-1', 'Ohne Lesezeit', ?, ?, ?, NULL)
                    """,
                arguments: [longContent, now, now]
            )
            try db.execute(
                sql: """
                    INSERT INTO articles (id, feedID, title, content, arrivedAt, updatedAt, estimatedReadingMinutes)
                    VALUES ('article-existing', 'feed-1', 'Mit Lesezeit', ?, ?, ?, 7)
                    """,
                arguments: [longContent, now, now]
            )
        }

        try FeedivoDatabaseMigrator.migrator.migrate(queue)

        let backfilled = try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT estimatedReadingMinutes FROM articles WHERE id = 'article-null'")
        }
        let untouched = try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT estimatedReadingMinutes FROM articles WHERE id = 'article-existing'")
        }

        #expect(backfilled == 2)
        #expect(untouched == 7)
    }
```

- [ ] **Step 2: Test laufen lassen, Fehlschlag bestätigen**

Run: `xcodebuild test -scheme Feedivo -only-testing:FeedivoTests/FeedivoDatabaseMigratorTests -parallel-testing-enabled NO`
Expected: FAIL — Migration `v30_...` existiert noch nicht, `backfilled` bleibt `nil`.

- [ ] **Step 3: Migration + Backfill-Helfer ergänzen**

In `Feedivo/Database/FeedivoDatabaseMigrator.swift`, unmittelbar vor `return migrator` (nach dem
`v29_add_cloud_sync_indexes`-Block):

```swift
        migrator.registerMigration("v30_backfill_article_estimated_reading_minutes") { database in
            // estimatedReadingMinutes wurde bisher nie beim Anlegen/Aktualisieren von Artikeln
            // befüllt (siehe Fix in ArticleUpsertInput-Aufrufstellen) — Bestandsartikel haben
            // dadurch ausnahmslos NULL. SQLite hat keine Wortzähl-Funktion, daher Swift-Loop
            // (analog backfillArticleStatusSyncStableID, Migration v26).
            try backfillArticleEstimatedReadingMinutes(database)
        }

        return migrator
```

Und ergänze den privaten Helfer (neben den bestehenden `backfill...`-Funktionen, z. B. direkt
nach `backfillArticleStatusSyncStableID`):

```swift
    private static func backfillArticleEstimatedReadingMinutes(_ database: Database) throws {
        struct Row: FetchableRecord {
            let id: String
            let content: String?
            let summary: String?

            init(row: GRDB.Row) throws {
                id = row["id"]
                content = row["content"]
                summary = row["summary"]
            }
        }

        let rows = try Row.fetchAll(database, sql: """
            SELECT id, content, summary FROM articles WHERE estimatedReadingMinutes IS NULL
            """)

        for row in rows {
            guard let minutes = ReaderMetadataFormatter.estimatedMinutes(content: row.content, summary: row.summary) else {
                continue
            }
            try database.execute(
                sql: "UPDATE articles SET estimatedReadingMinutes = ? WHERE id = ?",
                arguments: [minutes, row.id]
            )
        }
    }
```

- [ ] **Step 4: Test laufen lassen, Erfolg bestätigen**

Run: `xcodebuild test -scheme Feedivo -only-testing:FeedivoTests/FeedivoDatabaseMigratorTests -parallel-testing-enabled NO`
Expected: PASS.

- [ ] **Step 5: Build verifizieren**

Run: `xcodebuild build -scheme Feedivo -configuration Debug`
Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Database/FeedivoDatabaseMigrator.swift FeedivoTests/Database/FeedivoDatabaseMigratorTests.swift
git commit -m "feat: Migration v30 — rückwirkender Backfill der Artikel-Lesezeit

Bestandsartikel mit estimatedReadingMinutes = NULL werden einmalig über
ReaderMetadataFormatter.estimatedMinutes nachberechnet, damit 'Gesamte
Lesezeit' sofort stimmt statt erst nach erneutem Feed-Abruf."
```

---

### Task 3: `StatisticsStore` — Wochentag/Tageszeit/Ø-Artikel-pro-Tag + Zeitzonen-Fix

**Files:**
- Modify: `Feedivo/Snapshots/ReadingStatisticsSnapshot.swift`
- Modify: `Feedivo/Stores/StatisticsStore.swift`
- Test: `FeedivoTests/Stores/SQLiteStatisticsStoreTests.swift`

**Interfaces:**
- Produces: `ReadingStatisticsDaypart` (Enum: `.morning/.midday/.afternoon/.evening/.night`,
  `static func from(hour: Int) -> ReadingStatisticsDaypart`), `ReadingStatisticsWeekdayCount`
  (`weekday: Int` [Calendar-Komponente 1=So…7=Sa], `count: Int`),
  `ReadingStatisticsDaypartCount` (`daypart: ReadingStatisticsDaypart`, `count: Int`),
  neue Felder `weekdayCounts: [ReadingStatisticsWeekdayCount]`,
  `daypartCounts: [ReadingStatisticsDaypartCount]`, `averageArticlesPerDay: Double` auf
  `ReadingStatisticsSnapshot` — konsumiert von Task 7 (Erkenntnis-Satz) und Task 9/10 (Views).
  `dailyReadCounts` bleibt in Typ/Bedeutung unverändert, wird aber jetzt Zeitzonen-korrekt in
  Swift statt per SQL `date()` berechnet.

- [ ] **Step 1: Fehlschlagende Tests schreiben**

Füge in `FeedivoTests/Stores/SQLiteStatisticsStoreTests.swift` (vor der letzten schließenden
Klammer der `struct SQLiteStatisticsStoreTests`) hinzu:

```swift
    @Test func readingStatisticsGruppiertNachWochentagUndTageszeitZeitzonenkorrekt() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)
        let statisticsStore = StatisticsStore(database: database)

        // Dienstag, 20 Uhr UTC — in einer Zeitzone UTC-6 (z. B. amerikanisches Festland)
        // ist das lokal noch Dienstag 14 Uhr (Nachmittag), nicht Abend. Ein SQL-date()/
        // strftime()-basiertes Bucketing würde hier UTC-Dienstagabend liefern statt der
        // lokalen Realität.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let readAt = utc.date(from: DateComponents(year: 2026, month: 8, day: 4, hour: 20))!

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))
        let articleID = try articleStore.upsert(ArticleUpsertInput(
            feedID: "feed-1",
            sourceID: "a1",
            title: "Artikel",
            arrivedAt: readAt,
            estimatedReadingMinutes: 5
        ))
        try statusStore.setRead(true, articleID: articleID, at: readAt)

        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let stats = try statisticsStore.readingStatistics(range: .all, now: readAt, calendar: localCalendar)

        let expectedWeekday = localCalendar.component(.weekday, from: readAt)
        let expectedDaypart = ReadingStatisticsDaypart.from(hour: localCalendar.component(.hour, from: readAt))

        #expect(stats.weekdayCounts.first { $0.weekday == expectedWeekday }?.count == 1)
        #expect(stats.daypartCounts.first { $0.daypart == expectedDaypart }?.count == 1)
        #expect(expectedDaypart == .afternoon)
    }

    @Test func readingStatisticsBerechnetDurchschnittlicheArtikelProTag() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)
        let statisticsStore = StatisticsStore(database: database)
        let now = Self.now

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))

        for index in 0..<14 {
            let articleID = try makeArticle(feedID: "feed-1", sourceID: "a\(index)", title: "Artikel \(index)", arrivedAt: now, estimatedReadingMinutes: 5, articleStore: articleStore)
            try statusStore.setRead(true, articleID: articleID, at: now)
        }

        let stats = try statisticsStore.readingStatistics(range: .last7Days, now: now)

        #expect(stats.averageArticlesPerDay == 2)
    }
```

- [ ] **Step 2: Tests laufen lassen, Fehlschlag bestätigen**

Run: `xcodebuild test -scheme Feedivo -only-testing:FeedivoTests/SQLiteStatisticsStoreTests -parallel-testing-enabled NO`
Expected: FAIL — `weekdayCounts`/`daypartCounts`/`averageArticlesPerDay` existieren noch nicht,
`readingStatistics(range:now:calendar:)`-Überladung existiert noch nicht.

- [ ] **Step 3: Neue Typen zu `ReadingStatisticsSnapshot.swift` hinzufügen**

Füge in `Feedivo/Snapshots/ReadingStatisticsSnapshot.swift`, direkt nach den bestehenden
`ReadingStatisticsDailyCount`-Definitionen, hinzu:

```swift
enum ReadingStatisticsDaypart: Int, CaseIterable, Equatable, Sendable {
    case morning
    case midday
    case afternoon
    case evening
    case night

    /// Feste, nicht-überlappende Stundenbuckets — decken alle 24 Stunden lückenlos ab.
    static func from(hour: Int) -> ReadingStatisticsDaypart {
        switch hour {
        case 6...10: return .morning
        case 11...13: return .midday
        case 14...17: return .afternoon
        case 18...22: return .evening
        default: return .night // 23, 0...5
        }
    }
}

struct ReadingStatisticsWeekdayCount: Equatable, Sendable {
    /// `Calendar`-Komponente `.weekday`: 1 = Sonntag … 7 = Samstag.
    var weekday: Int
    var count: Int
}

struct ReadingStatisticsDaypartCount: Equatable, Sendable {
    var daypart: ReadingStatisticsDaypart
    var count: Int
}
```

Dann erweitere `ReadingStatisticsSnapshot` um die drei neuen Felder (nach `topTags`):

```swift
    var topTags: [ReadingStatisticsTagCount]
    var weekdayCounts: [ReadingStatisticsWeekdayCount]
    var daypartCounts: [ReadingStatisticsDaypartCount]
    var averageArticlesPerDay: Double
```

Und in `static let empty`, direkt nach `topTags: [],`:

```swift
        weekdayCounts: [],
        daypartCounts: [],
        averageArticlesPerDay: 0,
```

- [ ] **Step 4: `StatisticsStore.readingStatistics` um Zeitzonen-korrektes Bucketing erweitern**

In `Feedivo/Stores/StatisticsStore.swift`, ersetze die Signatur

```swift
    func readingStatistics(range: StatisticsTimeRange, now: Date = Date()) throws -> ReadingStatisticsSnapshot {
```

durch (neuer optionaler `calendar`-Parameter für Zeitzonen-Tests, Standard `Calendar.current`):

```swift
    func readingStatistics(
        range: StatisticsTimeRange,
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> ReadingStatisticsSnapshot {
```

Ersetze den bestehenden `dailyReadCounts`-Block

```swift
            let dailyReadCounts = try Row.fetchAll(db, sql: """
                SELECT date(readAt) AS day, COUNT(*) AS count
                FROM article_statuses
                WHERE isRead = 1 AND readAt >= ?
                GROUP BY day
                ORDER BY day
                """, arguments: [heatmapStart])
                .compactMap { row -> ReadingStatisticsDailyCount? in
                    let dayString: String = row["day"]
                    guard let date = Self.dayFormatter.date(from: dayString) else {
                        return nil
                    }
                    return ReadingStatisticsDailyCount(date: date, count: row["count"])
                }
```

durch eine einzelne, Zeitzonen-korrekte Swift-seitige Aggregation, die gleichzeitig
`dailyReadCounts`, `weekdayCounts` und `daypartCounts` liefert:

```swift
            let readTimestamps = try Date.fetchAll(db, sql: """
                SELECT readAt FROM article_statuses WHERE isRead = 1 AND readAt >= ?
                """, arguments: [heatmapStart])

            var dailyTally: [Date: Int] = [:]
            var weekdayTally: [Int: Int] = [:]
            var daypartTally: [ReadingStatisticsDaypart: Int] = [:]

            for readAt in readTimestamps {
                let day = calendar.startOfDay(for: readAt)
                dailyTally[day, default: 0] += 1

                let weekday = calendar.component(.weekday, from: readAt)
                weekdayTally[weekday, default: 0] += 1

                let hour = calendar.component(.hour, from: readAt)
                let daypart = ReadingStatisticsDaypart.from(hour: hour)
                daypartTally[daypart, default: 0] += 1
            }

            let dailyReadCounts = dailyTally
                .map { ReadingStatisticsDailyCount(date: $0.key, count: $0.value) }
                .sorted { $0.date < $1.date }
            let weekdayCounts = weekdayTally
                .map { ReadingStatisticsWeekdayCount(weekday: $0.key, count: $0.value) }
                .sorted { $0.weekday < $1.weekday }
            let daypartCounts = ReadingStatisticsDaypart.allCases.map {
                ReadingStatisticsDaypartCount(daypart: $0, count: daypartTally[$0] ?? 0)
            }
```

Entferne dabei den jetzt ungenutzten `Self.dayFormatter` (private static let am Dateiende) —
er wurde nur für das Parsen der SQL-`date()`-Ausgabe gebraucht.

Ergänze `averageArticlesPerDay` direkt nach der bestehenden `averageReadingMinutesPerDay`-
Berechnung (die bereits denselben `dayCount` nutzt):

```swift
            let dayCount = Self.dayCount(forRangeStart: rangeStart, now: now)
            let averageReadingMinutesPerDay = dayCount > 0 ? totalReadingMinutes / Double(dayCount) : 0
```

Diese Zeile steht VOR der Berechnung von `articlesReadInSelectedRange` weiter unten im
bestehenden Code — füge `averageArticlesPerDay` deshalb NICHT hier ein, sondern direkt nach der
bestehenden Zeile `let articlesReadInSelectedRange = try Int.fetchOne(...)`:

```swift
            let averageArticlesPerDay = dayCount > 0 ? Double(articlesReadInSelectedRange) / Double(dayCount) : 0
```

Ergänze im finalen `return ReadingStatisticsSnapshot(...)`-Aufruf die drei neuen Argumente
(nach `topTags: topTags,`):

```swift
                topTags: topTags,
                weekdayCounts: weekdayCounts,
                daypartCounts: daypartCounts,
                averageArticlesPerDay: averageArticlesPerDay,
```

- [ ] **Step 5: Tests laufen lassen, Erfolg bestätigen**

Run: `xcodebuild test -scheme Feedivo -only-testing:FeedivoTests/SQLiteStatisticsStoreTests -parallel-testing-enabled NO`
Expected: PASS (alle bisherigen + 2 neue Tests grün — bestehende Tests bleiben unverändert
funktionsfähig, da `dailyReadCounts` in Bedeutung/Sortierung gleich bleibt, nur anders
berechnet wird).

- [ ] **Step 6: Build verifizieren**

Run: `xcodebuild build -scheme Feedivo -configuration Debug`
Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Commit**

```bash
git add Feedivo/Snapshots/ReadingStatisticsSnapshot.swift Feedivo/Stores/StatisticsStore.swift \
  FeedivoTests/Stores/SQLiteStatisticsStoreTests.swift
git commit -m "feat: Wochentag-/Tageszeit-Aggregation + Zeitzonen-Fix für Lese-Statistiken

dailyReadCounts lief bisher über SQLite date()/UTC-Zeitstempel und konnte
Wochentag/Uhrzeit für Nutzer außerhalb UTC falsch zuordnen. Neue,
Swift-seitige Calendar-Aggregation liefert dailyReadCounts weiterhin,
zusätzlich weekdayCounts/daypartCounts/averageArticlesPerDay für die
Gewohnheiten-Sektion."
```

---

### Task 4: `StatisticsStore` — Top-Feeds/Top-Tags nach Lesezeit statt Anzahl

**Files:**
- Modify: `Feedivo/Snapshots/ReadingStatisticsSnapshot.swift`
- Modify: `Feedivo/Stores/StatisticsStore.swift`
- Modify: `Feedivo/Services/StatisticsExportService.swift`
- Modify: `Feedivo/Views/Statistics/StatisticsWindowView.swift` (minimaler Kompatibilitäts-Fix,
  volle Neugestaltung folgt in Task 11)
- Test: `FeedivoTests/Stores/SQLiteStatisticsStoreTests.swift`
- Test: `FeedivoTests/FeedivoTests.swift` (bestehende CSV-Export-Tests anpassen)

**Interfaces:**
- Produces: `ReadingStatisticsFeedTime` (`feedID: String`, `feedTitle: String`,
  `faviconURL: String?`, `minutes: Int`, `articleCount: Int`), `ReadingStatisticsTagTime`
  (`tagID: String`, `name: String`, `colorHex: String`, `minutes: Int`, `articleCount: Int`),
  neue Felder `topFeedsByTime: [ReadingStatisticsFeedTime]` / `topTagsByTime:
  [ReadingStatisticsTagTime]` auf `ReadingStatisticsSnapshot` — ersetzen `topFeeds`/`topTags`
  (entfernt) und `ReadingStatisticsFeedCount`/`ReadingStatisticsTagCount` (entfernt). Konsumiert
  von Task 11 (Aufmerksamkeit-Abschnitt).

- [ ] **Step 1: Fehlschlagende Tests schreiben**

Ersetze in `FeedivoTests/Stores/SQLiteStatisticsStoreTests.swift` die bestehende Testfunktion
`readingStatisticsRankedTopFeedsUndRespektiertZeitraum` durch:

```swift
    @Test func readingStatisticsRankedTopFeedsNachLesezeitUndRespektiertZeitraum() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)
        let statisticsStore = StatisticsStore(database: database)
        let now = Self.now

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Wenig Zeit, viele Artikel"))
        try feedStore.save(FeedRecord(id: "feed-2", url: "https://other.example/feed.xml", title: "Viel Zeit, ein Artikel"))

        for index in 0..<3 {
            let articleID = try makeArticle(
                feedID: "feed-1",
                sourceID: "short-\(index)",
                title: "Kurzartikel \(index)",
                arrivedAt: now,
                estimatedReadingMinutes: 1,
                articleStore: articleStore
            )
            try statusStore.setRead(true, articleID: articleID, at: now)
        }

        let longArticle = try makeArticle(
            feedID: "feed-2",
            sourceID: "long",
            title: "Langartikel",
            arrivedAt: now,
            estimatedReadingMinutes: 30,
            articleStore: articleStore
        )
        try statusStore.setRead(true, articleID: longArticle, at: now)

        let oldArticle = try makeArticle(
            feedID: "feed-2",
            sourceID: "outside-range",
            title: "Außerhalb des Zeitraums",
            arrivedAt: now,
            estimatedReadingMinutes: 99,
            articleStore: articleStore
        )
        try statusStore.setRead(true, articleID: oldArticle, at: now.addingTimeInterval(-40 * 24 * 60 * 60))

        let last7Days = try statisticsStore.readingStatistics(range: .last7Days, now: now)

        #expect(last7Days.topFeedsByTime.count == 2)
        #expect(last7Days.topFeedsByTime.first?.feedTitle == "Viel Zeit, ein Artikel")
        #expect(last7Days.topFeedsByTime.first?.minutes == 30)
        #expect(last7Days.topFeedsByTime.first?.articleCount == 1)
        #expect(last7Days.topFeedsByTime.last?.minutes == 3)
    }
```

Ersetze `readingStatisticsRankedTopTags` durch:

```swift
    @Test func readingStatisticsRankedTopTagsNachLesezeit() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)
        let tagStore = TagStore(database: database)
        let statisticsStore = StatisticsStore(database: database)
        let now = Self.now

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))
        try tagStore.save(TagRecord(id: "tag-swift", name: "Swift", colorHex: "#123456"))

        let articleID = try makeArticle(feedID: "feed-1", sourceID: "tagged", title: "Getaggt", arrivedAt: now, estimatedReadingMinutes: 12, articleStore: articleStore)
        try statusStore.setRead(true, articleID: articleID, at: now)
        try tagStore.assignTag(tagID: "tag-swift", toArticleID: articleID, at: now)

        let stats = try statisticsStore.readingStatistics(range: .all, now: now)

        #expect(stats.topTagsByTime.count == 1)
        #expect(stats.topTagsByTime.first?.name == "Swift")
        #expect(stats.topTagsByTime.first?.minutes == 12)
        #expect(stats.topTagsByTime.first?.articleCount == 1)
    }
```

- [ ] **Step 2: Tests laufen lassen, Fehlschlag bestätigen**

Run: `xcodebuild test -scheme Feedivo -only-testing:FeedivoTests/SQLiteStatisticsStoreTests -parallel-testing-enabled NO`
Expected: FAIL — `topFeedsByTime`/`topTagsByTime` existieren noch nicht.

- [ ] **Step 3: Snapshot-Typen umstellen**

In `Feedivo/Snapshots/ReadingStatisticsSnapshot.swift`: entferne `ReadingStatisticsFeedCount`
und `ReadingStatisticsTagCount` vollständig, ersetze durch:

```swift
struct ReadingStatisticsFeedTime: Equatable, Sendable {
    var feedID: String
    var feedTitle: String
    var faviconURL: String?
    var minutes: Int
    var articleCount: Int
}

struct ReadingStatisticsTagTime: Equatable, Sendable {
    var tagID: String
    var name: String
    var colorHex: String
    var minutes: Int
    var articleCount: Int
}
```

Ändere in `ReadingStatisticsSnapshot`:
`var topFeeds: [ReadingStatisticsFeedCount]` → `var topFeedsByTime: [ReadingStatisticsFeedTime]`
`var topTags: [ReadingStatisticsTagCount]` → `var topTagsByTime: [ReadingStatisticsTagTime]`

Und in `static let empty`: `topFeeds: [],` → `topFeedsByTime: [],`,
`topTags: [],` → `topTagsByTime: [],`.

- [ ] **Step 4: Queries in `StatisticsStore.swift` umstellen**

Ersetze den bestehenden `topFeeds`-Query-Block:

```swift
            let topFeeds = try Row.fetchAll(db, sql: """
                SELECT f.id AS feedID, f.title AS feedTitle, f.faviconURL AS faviconURL, COUNT(*) AS count
                FROM article_statuses s
                JOIN articles a ON a.id = s.articleID
                JOIN feeds f ON f.id = a.feedID
                WHERE s.isRead = 1
                    AND (? IS NULL OR s.readAt >= ?)
                GROUP BY f.id
                ORDER BY count DESC, f.title COLLATE NOCASE
                LIMIT ?
                """, arguments: [rangeStart, rangeStart, Self.topListLimit])
                .map {
                    ReadingStatisticsFeedCount(
                        feedID: $0["feedID"],
                        feedTitle: $0["feedTitle"],
                        faviconURL: $0["faviconURL"],
                        count: $0["count"]
                    )
                }
```

durch:

```swift
            let topFeedsByTime = try Row.fetchAll(db, sql: """
                SELECT f.id AS feedID, f.title AS feedTitle, f.faviconURL AS faviconURL,
                       COALESCE(SUM(a.estimatedReadingMinutes), 0) AS minutes, COUNT(*) AS articleCount
                FROM article_statuses s
                JOIN articles a ON a.id = s.articleID
                JOIN feeds f ON f.id = a.feedID
                WHERE s.isRead = 1
                    AND (? IS NULL OR s.readAt >= ?)
                GROUP BY f.id
                ORDER BY minutes DESC, f.title COLLATE NOCASE
                LIMIT ?
                """, arguments: [rangeStart, rangeStart, Self.topListLimit])
                .map {
                    ReadingStatisticsFeedTime(
                        feedID: $0["feedID"],
                        feedTitle: $0["feedTitle"],
                        faviconURL: $0["faviconURL"],
                        minutes: $0["minutes"],
                        articleCount: $0["articleCount"]
                    )
                }
```

Ersetze den bestehenden `topTags`-Query-Block:

```swift
            let topTags = try Row.fetchAll(db, sql: """
                SELECT t.id AS tagID, t.name AS name, t.colorHex AS colorHex, COUNT(*) AS count
                FROM article_tags at
                JOIN tags t ON t.id = at.tagID
                JOIN article_statuses s ON s.articleID = at.articleID
                WHERE s.isRead = 1
                    AND (? IS NULL OR s.readAt >= ?)
                GROUP BY t.id
                ORDER BY count DESC, t.name COLLATE NOCASE
                LIMIT ?
                """, arguments: [rangeStart, rangeStart, Self.topListLimit])
                .map {
                    ReadingStatisticsTagCount(
                        tagID: $0["tagID"],
                        name: $0["name"],
                        colorHex: $0["colorHex"],
                        count: $0["count"]
                    )
                }
```

durch:

```swift
            let topTagsByTime = try Row.fetchAll(db, sql: """
                SELECT t.id AS tagID, t.name AS name, t.colorHex AS colorHex,
                       COALESCE(SUM(a.estimatedReadingMinutes), 0) AS minutes, COUNT(*) AS articleCount
                FROM article_tags at
                JOIN tags t ON t.id = at.tagID
                JOIN article_statuses s ON s.articleID = at.articleID
                JOIN articles a ON a.id = s.articleID
                WHERE s.isRead = 1
                    AND (? IS NULL OR s.readAt >= ?)
                GROUP BY t.id
                ORDER BY minutes DESC, t.name COLLATE NOCASE
                LIMIT ?
                """, arguments: [rangeStart, rangeStart, Self.topListLimit])
                .map {
                    ReadingStatisticsTagTime(
                        tagID: $0["tagID"],
                        name: $0["name"],
                        colorHex: $0["colorHex"],
                        minutes: $0["minutes"],
                        articleCount: $0["articleCount"]
                    )
                }
```

Im finalen `return ReadingStatisticsSnapshot(...)`: `topFeeds: topFeeds,` →
`topFeedsByTime: topFeedsByTime,`, `topTags: topTags,` → `topTagsByTime: topTagsByTime,`.

- [ ] **Step 5: `StatisticsExportService.swift` anpassen**

In `Feedivo/Services/StatisticsExportService.swift`, ersetze:

```swift
        lines.append("Meistgelesene Feeds,Anzahl")
        for feed in readingStatistics.topFeeds {
            lines.append(csvRow([feed.feedTitle, "\(feed.count)"]))
        }
        lines.append("")

        lines.append("Meistgenutzte Tags,Anzahl")
        for tag in readingStatistics.topTags {
            lines.append(csvRow([tag.name, "\(tag.count)"]))
        }
        lines.append("")
```

durch:

```swift
        lines.append("Meistgelesene Feeds,Artikel,Lesezeit (Minuten)")
        for feed in readingStatistics.topFeedsByTime {
            lines.append(csvRow([feed.feedTitle, "\(feed.articleCount)", "\(feed.minutes)"]))
        }
        lines.append("")

        lines.append("Meistgenutzte Tags,Artikel,Lesezeit (Minuten)")
        for tag in readingStatistics.topTagsByTime {
            lines.append(csvRow([tag.name, "\(tag.articleCount)", "\(tag.minutes)"]))
        }
        lines.append("")
```

- [ ] **Step 6: `FeedivoTests.swift`-CSV-Tests anpassen**

Ersetze in `FeedivoTests/FeedivoTests.swift` die Konstruktion in
`statisticsExportServiceEscapedKommasUndAnfuehrungszeichenInCSV`:

```swift
            topFeeds: [
                ReadingStatisticsFeedCount(feedID: "feed-1", feedTitle: "Feed, mit \"Komma\"", faviconURL: nil, count: 5)
            ],
            dailyReadCounts: [],
            averageReadingMinutesPerDay: 4.2,
            topTags: [],
```

durch:

```swift
            topFeedsByTime: [
                ReadingStatisticsFeedTime(feedID: "feed-1", feedTitle: "Feed, mit \"Komma\"", faviconURL: nil, minutes: 5, articleCount: 1)
            ],
            dailyReadCounts: [],
            averageReadingMinutesPerDay: 4.2,
            topTagsByTime: [],
            weekdayCounts: [],
            daypartCounts: [],
            averageArticlesPerDay: 0,
```

Passe die Assertion in `csv.contains(...)` an das neue Spaltenformat an:

```swift
        #expect(csv.contains(#""Feed, mit ""Komma""",1,5"#))
```

Passe in `statisticsExportServiceEnthaeltAlleAbschnitte` die Spaltenkopf-Assertions an:

```swift
        #expect(csv.contains("Meistgelesene Feeds,Artikel,Lesezeit (Minuten)"))
        #expect(csv.contains("Meistgenutzte Tags,Artikel,Lesezeit (Minuten)"))
```

- [ ] **Step 7: `StatisticsWindowView.swift` kompatibel machen (Übergangs-Fix)**

Diese Zeilen werden in Task 11 vollständig durch eine neue Rangliste ersetzt — hier nur ein
minimaler, korrekt kompilierender Fix. Ersetze in `topFeedsCard`/`topFeedRow`:

`statistics.topFeeds` → `statistics.topFeedsByTime`, Parametertyp `feed:
ReadingStatisticsFeedCount` → `feed: ReadingStatisticsFeedTime`, und die angezeigte Zahl:

```swift
            Text("\(feed.minutes) min")
```

statt `Text("\(feed.count)")`. Analog in `topTagsCard`/`topTagRow`: `statistics.topTags` →
`statistics.topTagsByTime`, `tag: ReadingStatisticsTagCount` → `tag: ReadingStatisticsTagTime`,
`Text("\(tag.count)")` → `Text("\(tag.minutes) min")`.

- [ ] **Step 8: Tests laufen lassen, Erfolg bestätigen**

Run: `xcodebuild test -scheme Feedivo -only-testing:FeedivoTests/SQLiteStatisticsStoreTests -only-testing:FeedivoTests/FeedivoTests -parallel-testing-enabled NO`
Expected: PASS.

- [ ] **Step 9: Build verifizieren**

Run: `xcodebuild build -scheme Feedivo -configuration Debug`
Expected: BUILD SUCCEEDED.

- [ ] **Step 10: Commit**

```bash
git add Feedivo/Snapshots/ReadingStatisticsSnapshot.swift Feedivo/Stores/StatisticsStore.swift \
  Feedivo/Services/StatisticsExportService.swift Feedivo/Views/Statistics/StatisticsWindowView.swift \
  FeedivoTests/Stores/SQLiteStatisticsStoreTests.swift FeedivoTests/FeedivoTests.swift
git commit -m "feat: Top-Feeds/Top-Tags nach Lesezeit statt Artikelanzahl sortiert

topFeeds/topTags (Anzahl-basiert) durch topFeedsByTime/topTagsByTime
(SUM(estimatedReadingMinutes)-basiert) ersetzt. CSV-Export zeigt jetzt
sowohl Artikelanzahl als auch Lesezeit pro Feed/Tag."
```

---

### Task 5: `StatisticsStore` — Feed-Gesundheit-Kandidaten

**Files:**
- Modify: `Feedivo/Snapshots/ReadingStatisticsSnapshot.swift`
- Modify: `Feedivo/Stores/StatisticsStore.swift`
- Test: `FeedivoTests/Stores/SQLiteStatisticsStoreTests.swift`

**Interfaces:**
- Produces: `ReadingStatisticsFeedHealth` (`feedID: String`, `feedTitle: String`,
  `unreadCount: Int`, `totalCount: Int`, `readPercentage: Double`), neue Methode
  `StatisticsStore.feedHealthCandidates(minimumArticleCount: Int = 20, limit: Int = 5) throws
  -> [ReadingStatisticsFeedHealth]` — konsumiert von Task 12 (Feed-Gesundheit-Abschnitt).

- [ ] **Step 1: Fehlschlagende Tests schreiben**

Füge in `FeedivoTests/Stores/SQLiteStatisticsStoreTests.swift` hinzu:

```swift
    @Test func feedHealthCandidatesIgnoriertFeedsUnterMindestArtikelzahl() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statisticsStore = StatisticsStore(database: database)
        let now = Self.now

        try feedStore.save(FeedRecord(id: "feed-neu", url: "https://example.com/feed.xml", title: "Frisch abonniert"))
        _ = try makeArticle(feedID: "feed-neu", sourceID: "a1", title: "Einziger Artikel", arrivedAt: now, estimatedReadingMinutes: 5, articleStore: articleStore)

        let candidates = try statisticsStore.feedHealthCandidates()

        #expect(candidates.isEmpty)
    }

    @Test func feedHealthCandidatesSortiertNachNiedrigsterLesequote() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)
        let statisticsStore = StatisticsStore(database: database)
        let now = Self.now

        try feedStore.save(FeedRecord(id: "feed-ignoriert", url: "https://a.example/feed.xml", title: "Ignoriert"))
        try feedStore.save(FeedRecord(id: "feed-gut-gelesen", url: "https://b.example/feed.xml", title: "Gut gelesen"))

        for index in 0..<20 {
            let articleID = try makeArticle(feedID: "feed-ignoriert", sourceID: "ignoriert-\(index)", title: "Artikel \(index)", arrivedAt: now, estimatedReadingMinutes: 5, articleStore: articleStore)
            if index == 0 {
                try statusStore.setRead(true, articleID: articleID, at: now)
            }
        }

        for index in 0..<20 {
            let articleID = try makeArticle(feedID: "feed-gut-gelesen", sourceID: "gut-\(index)", title: "Artikel \(index)", arrivedAt: now, estimatedReadingMinutes: 5, articleStore: articleStore)
            if index < 18 {
                try statusStore.setRead(true, articleID: articleID, at: now)
            }
        }

        let candidates = try statisticsStore.feedHealthCandidates()

        #expect(candidates.count == 2)
        #expect(candidates.first?.feedTitle == "Ignoriert")
        #expect(candidates.first?.totalCount == 20)
        #expect(candidates.first?.unreadCount == 19)
        #expect(candidates.first?.readPercentage == 5)
    }

    @Test func feedHealthCandidatesBegrenztAufFuenfEintraege() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statisticsStore = StatisticsStore(database: database)
        let now = Self.now

        for feedIndex in 0..<7 {
            let feedID = "feed-\(feedIndex)"
            try feedStore.save(FeedRecord(id: feedID, url: "https://example.com/\(feedIndex)/feed.xml", title: "Feed \(feedIndex)"))
            for articleIndex in 0..<20 {
                _ = try makeArticle(feedID: feedID, sourceID: "\(feedIndex)-\(articleIndex)", title: "Artikel", arrivedAt: now, estimatedReadingMinutes: 5, articleStore: articleStore)
            }
        }

        let candidates = try statisticsStore.feedHealthCandidates()

        #expect(candidates.count == 5)
    }
```

- [ ] **Step 2: Tests laufen lassen, Fehlschlag bestätigen**

Run: `xcodebuild test -scheme Feedivo -only-testing:FeedivoTests/SQLiteStatisticsStoreTests -parallel-testing-enabled NO`
Expected: FAIL — `feedHealthCandidates` existiert noch nicht.

- [ ] **Step 3: Neuen Typ in `ReadingStatisticsSnapshot.swift` ergänzen**

```swift
struct ReadingStatisticsFeedHealth: Equatable, Sendable {
    var feedID: String
    var feedTitle: String
    var unreadCount: Int
    var totalCount: Int
    var readPercentage: Double
}
```

- [ ] **Step 4: `feedHealthCandidates` in `StatisticsStore.swift` ergänzen**

Füge als neue Methode nach `feedReadingStatistics(feedID:now:)` hinzu:

```swift
    /// Feeds, die der Nutzer abonniert hat, aber kaum liest — Kandidaten zum Abbestellen
    /// (Feature: Feed-Gesundheit). All-time, unabhängig vom Zeitraum-Picker: "kaum gelesen"
    /// ist ein Langzeit-Signal. `minimumArticleCount` schützt frisch abonnierte Feeds mit
    /// nur wenigen Artikeln davor, fälschlich als "ignoriert" zu erscheinen.
    func feedHealthCandidates(minimumArticleCount: Int = 20, limit: Int = 5) throws -> [ReadingStatisticsFeedHealth] {
        try database.read { db in
            try Row.fetchAll(db, sql: """
                SELECT f.id AS feedID, f.title AS feedTitle,
                       COUNT(*) AS totalCount,
                       SUM(CASE WHEN s.isRead = 1 THEN 1 ELSE 0 END) AS readCount
                FROM articles a
                JOIN article_statuses s ON s.articleID = a.id
                JOIN feeds f ON f.id = a.feedID
                GROUP BY f.id
                HAVING totalCount >= ?
                ORDER BY (CAST(readCount AS REAL) / totalCount) ASC, f.title COLLATE NOCASE
                LIMIT ?
                """, arguments: [minimumArticleCount, limit])
                .map { row -> ReadingStatisticsFeedHealth in
                    let totalCount: Int = row["totalCount"]
                    let readCount: Int = row["readCount"]
                    return ReadingStatisticsFeedHealth(
                        feedID: row["feedID"],
                        feedTitle: row["feedTitle"],
                        unreadCount: totalCount - readCount,
                        totalCount: totalCount,
                        readPercentage: totalCount > 0 ? Double(readCount) / Double(totalCount) * 100 : 0
                    )
                }
        }
    }
```

- [ ] **Step 5: Tests laufen lassen, Erfolg bestätigen**

Run: `xcodebuild test -scheme Feedivo -only-testing:FeedivoTests/SQLiteStatisticsStoreTests -parallel-testing-enabled NO`
Expected: PASS.

- [ ] **Step 6: Build verifizieren**

Run: `xcodebuild build -scheme Feedivo -configuration Debug`
Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Commit**

```bash
git add Feedivo/Snapshots/ReadingStatisticsSnapshot.swift Feedivo/Stores/StatisticsStore.swift \
  FeedivoTests/Stores/SQLiteStatisticsStoreTests.swift
git commit -m "feat: Feed-Gesundheit-Kandidaten (kaum gelesene Feeds) in StatisticsStore

Neue feedHealthCandidates(minimumArticleCount:limit:)-Query: Feeds mit
mindestens 20 Artikeln, sortiert nach niedrigster Lesequote, Top 5."
```

---

### Task 6: Neue L10n-Keys für den Statistik-Umbau

**Files:**
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`

**Interfaces:**
- Produces: Alle unten gelisteten `L10n.statistics...`-Konstanten/-Funktionen, konsumiert von
  Task 7–12.

- [ ] **Step 1: Konstanten in `L10n.swift` ergänzen**

Füge direkt nach der bestehenden Zeile
`static let statisticsSummarySelectedRangeCount = LocalizedStringKey("statistics.summary.selectedRangeCount")`
(Zeile 131) ein:

```swift
    static let statisticsHeatmapRange = LocalizedStringKey("statistics.heatmap.range")
    static let statisticsHeroStreakLabel = LocalizedStringKey("statistics.hero.streakLabel")
    static let statisticsOverviewAverageArticlesPerDay = LocalizedStringKey("statistics.overview.averageArticlesPerDay")
    static let statisticsSectionHabitsTitle = LocalizedStringKey("statistics.section.habits.title")
    static let statisticsSectionHabitsSubtitle = LocalizedStringKey("statistics.section.habits.subtitle")
    static let statisticsHabitsWeekdayTitle = LocalizedStringKey("statistics.habits.weekday.title")
    static let statisticsHabitsDaypartTitle = LocalizedStringKey("statistics.habits.daypart.title")
    static let statisticsDaypartMorning = LocalizedStringKey("statistics.daypart.morning")
    static let statisticsDaypartMidday = LocalizedStringKey("statistics.daypart.midday")
    static let statisticsDaypartAfternoon = LocalizedStringKey("statistics.daypart.afternoon")
    static let statisticsDaypartEvening = LocalizedStringKey("statistics.daypart.evening")
    static let statisticsDaypartNight = LocalizedStringKey("statistics.daypart.night")
    static let statisticsSectionAttentionTitle = LocalizedStringKey("statistics.section.attention.title")
    static let statisticsSectionAttentionSubtitle = LocalizedStringKey("statistics.section.attention.subtitle")
    static let statisticsAttentionFeedsTitle = LocalizedStringKey("statistics.attention.feeds.title")
    static let statisticsAttentionTagsTitle = LocalizedStringKey("statistics.attention.tags.title")
    static let statisticsAttentionEmpty = LocalizedStringKey("statistics.attention.empty")
    static let statisticsSectionFeedHealthTitle = LocalizedStringKey("statistics.section.feedHealth.title")
    static let statisticsSectionFeedHealthSubtitle = LocalizedStringKey("statistics.section.feedHealth.subtitle")
    static let statisticsFeedHealthUnsubscribeButton = LocalizedStringKey("statistics.feedHealth.unsubscribeButton")
    static let statisticsFeedHealthEmpty = LocalizedStringKey("statistics.feedHealth.empty")
```

Füge außerdem, im Bereich der bestehenden Format-Funktionen (nach
`static func statisticsMinutesPerDay(_ minutes: Int) -> String { ... }`, vor
`static let networkStatusOnline = ...`), diese neuen Format-Funktionen hinzu:

```swift
    static func statisticsHeroLongestStreak(_ days: Int) -> String {
        String.localizedStringWithFormat(
            String(localized: "statistics.hero.longestStreak"),
            days
        )
    }

    static func statisticsInsightPeak(weekday: String, daypart: String) -> String {
        String.localizedStringWithFormat(
            String(localized: "statistics.insight.peak"),
            weekday,
            daypart
        )
    }

    static func statisticsInsightDaypartPhrase(_ daypart: ReadingStatisticsDaypart) -> String {
        switch daypart {
        case .morning:
            return String(localized: "statistics.insight.daypart.morning")
        case .midday:
            return String(localized: "statistics.insight.daypart.midday")
        case .afternoon:
            return String(localized: "statistics.insight.daypart.afternoon")
        case .evening:
            return String(localized: "statistics.insight.daypart.evening")
        case .night:
            return String(localized: "statistics.insight.daypart.night")
        }
    }

    static let statisticsInsightWeekendQuiet = String(localized: "statistics.insight.weekendQuiet")

    static func statisticsFeedHealthCounts(unread: Int, total: Int) -> String {
        String.localizedStringWithFormat(
            String(localized: "statistics.feedHealth.counts"),
            unread,
            total
        )
    }

    static func statisticsFeedHealthReadPercentage(_ percentage: Int) -> String {
        String.localizedStringWithFormat(
            String(localized: "statistics.feedHealth.readPercentage"),
            percentage
        )
    }
```

- [ ] **Step 2: Katalogeinträge in `Localizable.xcstrings` einfügen**

Suche in `Feedivo/Resources/Localizable.xcstrings` nach dem eindeutigen Anker (Ende des
`statistics.summary.selectedRangeCount`-Eintrags, gefolgt vom nächsten bestehenden Key):

```
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Letti nel periodo"
          }
        }
      }
    },
    "statistics.summary.thisWeek" : {
```

Ersetze durch denselben Text PLUS die neuen Einträge dazwischen (exaktes Format — Leerzeichen
vor jedem `:` beibehalten, wie im Rest der Datei):

```
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Letti nel periodo"
          }
        }
      }
    },
    "statistics.heatmap.range" : {
      "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : "letzte 91 Tage" } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "last 91 days" } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "91 derniers jours" } },
        "it" : { "stringUnit" : { "state" : "translated", "value" : "ultimi 91 giorni" } }
      }
    },
    "statistics.hero.streakLabel" : {
      "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : "in Folge gelesen" } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "in a row" } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "d'affilée" } },
        "it" : { "stringUnit" : { "state" : "translated", "value" : "di fila" } }
      }
    },
    "statistics.hero.longestStreak" : {
      "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : "Längste Serie: %d Tage" } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Longest streak: %d days" } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "Plus longue série : %d jours" } },
        "it" : { "stringUnit" : { "state" : "translated", "value" : "Serie più lunga: %d giorni" } }
      }
    },
    "statistics.insight.peak" : {
      "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : "Du liest am meisten am %1$@ %2$@." } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "You read the most on %1$@ %2$@." } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "Tu lis le plus souvent le %1$@ %2$@." } },
        "it" : { "stringUnit" : { "state" : "translated", "value" : "Di solito leggi il %1$@ %2$@." } }
      }
    },
    "statistics.insight.daypart.morning" : {
      "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : "morgens" } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "mornings" } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "matin" } },
        "it" : { "stringUnit" : { "state" : "translated", "value" : "mattina" } }
      }
    },
    "statistics.insight.daypart.midday" : {
      "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : "mittags" } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "middays" } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "midi" } },
        "it" : { "stringUnit" : { "state" : "translated", "value" : "mezzogiorno" } }
      }
    },
    "statistics.insight.daypart.afternoon" : {
      "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : "nachmittags" } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "afternoons" } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "après-midi" } },
        "it" : { "stringUnit" : { "state" : "translated", "value" : "pomeriggio" } }
      }
    },
    "statistics.insight.daypart.evening" : {
      "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : "abends" } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "evenings" } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "soir" } },
        "it" : { "stringUnit" : { "state" : "translated", "value" : "sera" } }
      }
    },
    "statistics.insight.daypart.night" : {
      "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : "nachts" } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "nights" } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "nuit" } },
        "it" : { "stringUnit" : { "state" : "translated", "value" : "notte" } }
      }
    },
    "statistics.insight.weekendQuiet" : {
      "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : " — am Wochenende bleibt der Reader meist zu." } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : " — on weekends, the reader mostly stays closed." } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : " — le week-end, le lecteur reste généralement fermé." } },
        "it" : { "stringUnit" : { "state" : "translated", "value" : " — nel weekend, il lettore resta perlopiù chiuso." } }
      }
    },
    "statistics.overview.averageArticlesPerDay" : {
      "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : "Ø Artikel/Tag" } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Avg. articles/day" } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "Articles/jour (moy.)" } },
        "it" : { "stringUnit" : { "state" : "translated", "value" : "Articoli/giorno (media)" } }
      }
    },
    "statistics.section.habits.title" : {
      "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : "Gewohnheiten" } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Habits" } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "Habitudes" } },
        "it" : { "stringUnit" : { "state" : "translated", "value" : "Abitudini" } }
      }
    },
    "statistics.section.habits.subtitle" : {
      "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : "Wann du typischerweise liest" } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "When you typically read" } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "Quand tu lis habituellement" } },
        "it" : { "stringUnit" : { "state" : "translated", "value" : "Quando leggi di solito" } }
      }
    },
    "statistics.habits.weekday.title" : {
      "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : "Wochentag" } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Day of week" } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "Jour de la semaine" } },
        "it" : { "stringUnit" : { "state" : "translated", "value" : "Giorno della settimana" } }
      }
    },
    "statistics.habits.daypart.title" : {
      "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : "Tageszeit" } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Time of day" } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "Moment de la journée" } },
        "it" : { "stringUnit" : { "state" : "translated", "value" : "Momento della giornata" } }
      }
    },
    "statistics.daypart.morning" : {
      "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : "Morgens" } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Morning" } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "Matin" } },
        "it" : { "stringUnit" : { "state" : "translated", "value" : "Mattina" } }
      }
    },
    "statistics.daypart.midday" : {
      "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : "Mittags" } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Midday" } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "Midi" } },
        "it" : { "stringUnit" : { "state" : "translated", "value" : "Mezzogiorno" } }
      }
    },
    "statistics.daypart.afternoon" : {
      "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : "Nachmittags" } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Afternoon" } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "Après-midi" } },
        "it" : { "stringUnit" : { "state" : "translated", "value" : "Pomeriggio" } }
      }
    },
    "statistics.daypart.evening" : {
      "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : "Abends" } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Evening" } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "Soir" } },
        "it" : { "stringUnit" : { "state" : "translated", "value" : "Sera" } }
      }
    },
    "statistics.daypart.night" : {
      "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : "Nachts" } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Night" } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "Nuit" } },
        "it" : { "stringUnit" : { "state" : "translated", "value" : "Notte" } }
      }
    },
    "statistics.section.attention.title" : {
      "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : "Aufmerksamkeit" } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Attention" } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "Attention" } },
        "it" : { "stringUnit" : { "state" : "translated", "value" : "Attenzione" } }
      }
    },
    "statistics.section.attention.subtitle" : {
      "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : "Wo deine Lesezeit wirklich hingeht — nicht nur die Artikelanzahl" } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Where your reading time really goes — not just article count" } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "Où va vraiment ton temps de lecture — pas seulement le nombre d'articles" } },
        "it" : { "stringUnit" : { "state" : "translated", "value" : "Dove va davvero il tuo tempo di lettura — non solo il numero di articoli" } }
      }
    },
    "statistics.attention.feeds.title" : {
      "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : "Top-Feeds nach Lesezeit" } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Top feeds by reading time" } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "Top flux par temps de lecture" } },
        "it" : { "stringUnit" : { "state" : "translated", "value" : "Feed principali per tempo di lettura" } }
      }
    },
    "statistics.attention.tags.title" : {
      "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : "Top-Tags nach Lesezeit" } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Top tags by reading time" } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "Top tags par temps de lecture" } },
        "it" : { "stringUnit" : { "state" : "translated", "value" : "Tag principali per tempo di lettura" } }
      }
    },
    "statistics.attention.empty" : {
      "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : "Noch keine Daten" } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "No data yet" } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "Pas encore de données" } },
        "it" : { "stringUnit" : { "state" : "translated", "value" : "Nessun dato ancora" } }
      }
    },
    "statistics.section.feedHealth.title" : {
      "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : "Feed-Gesundheit" } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Feed health" } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "Santé des flux" } },
        "it" : { "stringUnit" : { "state" : "translated", "value" : "Salute dei feed" } }
      }
    },
    "statistics.section.feedHealth.subtitle" : {
      "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : "Diese Feeds sammelst du, liest sie aber kaum — Kandidaten zum Abbestellen" } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "You collect these feeds but barely read them — candidates to unsubscribe" } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "Tu accumules ces flux mais tu les lis à peine — candidats au désabonnement" } },
        "it" : { "stringUnit" : { "state" : "translated", "value" : "Raccogli questi feed ma li leggi a malapena — candidati alla disiscrizione" } }
      }
    },
    "statistics.feedHealth.counts" : {
      "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : "%1$d ungelesen · %2$d insgesamt" } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "%1$d unread · %2$d total" } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "%1$d non lus · %2$d au total" } },
        "it" : { "stringUnit" : { "state" : "translated", "value" : "%1$d non letti · %2$d totali" } }
      }
    },
    "statistics.feedHealth.readPercentage" : {
      "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : "%d %% gelesen" } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "%d%% read" } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "%d %% lus" } },
        "it" : { "stringUnit" : { "state" : "translated", "value" : "%d%% letti" } }
      }
    },
    "statistics.feedHealth.unsubscribeButton" : {
      "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : "Abbestellen" } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Unsubscribe" } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "Se désabonner" } },
        "it" : { "stringUnit" : { "state" : "translated", "value" : "Annulla iscrizione" } }
      }
    },
    "statistics.feedHealth.empty" : {
      "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : "Alle Feeds gut genutzt" } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "All feeds are well used" } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "Tous les flux sont bien utilisés" } },
        "it" : { "stringUnit" : { "state" : "translated", "value" : "Tutti i feed sono ben utilizzati" } }
      }
    },
    "statistics.summary.thisWeek" : {
```

- [ ] **Step 3: Einfügung verifizieren**

Run: `git diff --stat Feedivo/Resources/Localizable.xcstrings`
Expected: Nur Insertions (keine oder kaum Deletions) — kein voller Datei-Roundtrip.

Run: `grep -c '"statistics.section.feedHealth.title"' Feedivo/Resources/Localizable.xcstrings`
Expected: `1`.

- [ ] **Step 4: Build verifizieren**

Run: `xcodebuild build -scheme Feedivo -configuration Debug`
Expected: BUILD SUCCEEDED (String-Catalog-Kompilierung validiert dabei automatisch das
JSON-Format der neuen Einträge).

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings
git commit -m "feat: L10n-Keys für den Lesestatistiken-Umbau (de/en/fr/it)

Neue Keys für Hero-Bereich, Erkenntnis-Satz, Gewohnheiten-, Aufmerksamkeits-
und Feed-Gesundheit-Abschnitt. Wird von den folgenden Tasks konsumiert."
```

---

### Task 7: Erkenntnis-Satz — reine Logik

**Files:**
- Create: `Feedivo/Snapshots/ReadingStatisticsInsight.swift`
- Test: `FeedivoTests/Snapshots/ReadingStatisticsInsightTests.swift`

**Interfaces:**
- Consumes: `ReadingStatisticsWeekdayCount`, `ReadingStatisticsDaypartCount`,
  `ReadingStatisticsDaypart` (Task 3), `L10n.statisticsInsightPeak(weekday:daypart:)`,
  `L10n.statisticsInsightDaypartPhrase(_:)`, `L10n.statisticsInsightWeekendQuiet` (Task 6).
- Produces: `ReadingStatisticsInsight.generate(weekdayCounts: [ReadingStatisticsWeekdayCount],
  daypartCounts: [ReadingStatisticsDaypartCount], calendar: Calendar = .current) -> String?` —
  konsumiert von Task 9 (Hero-Bereich).

- [ ] **Step 1: Fehlschlagenden Test schreiben**

Erstelle `FeedivoTests/Snapshots/ReadingStatisticsInsightTests.swift`:

```swift
import Foundation
import Testing
@testable import Feedivo

struct ReadingStatisticsInsightTests {
    @Test func generateLiefertNilBeiZuWenigDaten() {
        let weekdayCounts = [ReadingStatisticsWeekdayCount(weekday: 3, count: 5)]
        let daypartCounts = ReadingStatisticsDaypart.allCases.map {
            ReadingStatisticsDaypartCount(daypart: $0, count: $0 == .evening ? 5 : 0)
        }

        let insight = ReadingStatisticsInsight.generate(weekdayCounts: weekdayCounts, daypartCounts: daypartCounts)

        #expect(insight == nil)
    }

    @Test func generateNenntStaerkstenWochentagUndTageszeit() {
        // Dienstag (Calendar-Komponente 3) mit 20 Treffern, Rest verteilt — Dienstag klar Peak.
        let weekdayCounts = [
            ReadingStatisticsWeekdayCount(weekday: 2, count: 3), // Montag
            ReadingStatisticsWeekdayCount(weekday: 3, count: 20), // Dienstag
            ReadingStatisticsWeekdayCount(weekday: 4, count: 2) // Mittwoch
        ]
        let daypartCounts = [
            ReadingStatisticsDaypartCount(daypart: .morning, count: 2),
            ReadingStatisticsDaypartCount(daypart: .midday, count: 1),
            ReadingStatisticsDaypartCount(daypart: .afternoon, count: 3),
            ReadingStatisticsDaypartCount(daypart: .evening, count: 18),
            ReadingStatisticsDaypartCount(daypart: .night, count: 1)
        ]

        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "de_DE")

        let insight = ReadingStatisticsInsight.generate(weekdayCounts: weekdayCounts, daypartCounts: daypartCounts, calendar: calendar)

        #expect(insight != nil)
        #expect(insight?.contains("Dienstag") == true)
        #expect(insight?.contains("abends") == true)
    }

    @Test func generateErgaenztWochenendHinweisUnterFuenfzehnProzent() {
        // Gesamt 25 Artikel, Sa+So zusammen nur 2 (8 % < 15 %-Schwelle).
        let weekdayCounts = [
            ReadingStatisticsWeekdayCount(weekday: 2, count: 5),
            ReadingStatisticsWeekdayCount(weekday: 3, count: 10),
            ReadingStatisticsWeekdayCount(weekday: 4, count: 5),
            ReadingStatisticsWeekdayCount(weekday: 5, count: 2),
            ReadingStatisticsWeekdayCount(weekday: 1, count: 1), // Sonntag
            ReadingStatisticsWeekdayCount(weekday: 7, count: 2) // Samstag
        ]
        let daypartCounts = [ReadingStatisticsDaypartCount(daypart: .evening, count: 25)]

        let insight = ReadingStatisticsInsight.generate(weekdayCounts: weekdayCounts, daypartCounts: daypartCounts)

        #expect(insight?.contains("Wochenende") == true)
    }

    @Test func generateOhneWochenendHinweisUeberFuenfzehnProzent() {
        // Sa+So zusammen 10 von 25 = 40 % — deutlich über der 15 %-Schwelle.
        let weekdayCounts = [
            ReadingStatisticsWeekdayCount(weekday: 2, count: 5),
            ReadingStatisticsWeekdayCount(weekday: 3, count: 10),
            ReadingStatisticsWeekdayCount(weekday: 1, count: 5), // Sonntag
            ReadingStatisticsWeekdayCount(weekday: 7, count: 5) // Samstag
        ]
        let daypartCounts = [ReadingStatisticsDaypartCount(daypart: .evening, count: 25)]

        let insight = ReadingStatisticsInsight.generate(weekdayCounts: weekdayCounts, daypartCounts: daypartCounts)

        #expect(insight?.contains("Wochenende") == false)
    }
}
```

- [ ] **Step 2: Test laufen lassen, Fehlschlag bestätigen**

Run: `xcodebuild test -scheme Feedivo -only-testing:FeedivoTests/ReadingStatisticsInsightTests -parallel-testing-enabled NO`
Expected: FAIL — `ReadingStatisticsInsight` existiert noch nicht.

- [ ] **Step 3: `ReadingStatisticsInsight` implementieren**

Erstelle `Feedivo/Snapshots/ReadingStatisticsInsight.swift`:

```swift
import Foundation

/// Deterministisch aus den Gewohnheiten-Daten abgeleiteter, kurzer Hinweissatz für den
/// Hero-Bereich des Statistik-Fensters — reine Formatierungslogik, keine KI-Generierung.
enum ReadingStatisticsInsight {
    /// Mindestanzahl gelesener Artikel im 91-Tage-Fenster, ab der ein Satz überhaupt
    /// angezeigt wird — sonst würde ein aus Rauschen abgeleiteter Satz irreführen.
    private static let minimumSampleSize = 10
    /// Schwelle, unter der Samstag+Sonntag zusammen als "praktisch ungenutzt" gelten.
    private static let weekendQuietThreshold = 0.15

    static func generate(
        weekdayCounts: [ReadingStatisticsWeekdayCount],
        daypartCounts: [ReadingStatisticsDaypartCount],
        calendar: Calendar = .current
    ) -> String? {
        let totalReads = weekdayCounts.reduce(0) { $0 + $1.count }
        guard totalReads >= minimumSampleSize,
              let peakWeekday = weekdayCounts.max(by: { $0.count < $1.count }),
              let peakDaypart = daypartCounts.max(by: { $0.count < $1.count })
        else {
            return nil
        }

        let weekdaySymbol = calendar.weekdaySymbols[peakWeekday.weekday - 1]
        let daypartPhrase = L10n.statisticsInsightDaypartPhrase(peakDaypart.daypart)
        var sentence = L10n.statisticsInsightPeak(weekday: weekdaySymbol, daypart: daypartPhrase)

        let weekendReads = weekdayCounts
            .filter { $0.weekday == 1 || $0.weekday == 7 } // Sonntag, Samstag
            .reduce(0) { $0 + $1.count }
        if Double(weekendReads) / Double(totalReads) < weekendQuietThreshold {
            sentence += L10n.statisticsInsightWeekendQuiet
        }

        return sentence
    }
}
```

- [ ] **Step 4: Test laufen lassen, Erfolg bestätigen**

Run: `xcodebuild test -scheme Feedivo -only-testing:FeedivoTests/ReadingStatisticsInsightTests -parallel-testing-enabled NO`
Expected: PASS (4/4 Tests grün).

- [ ] **Step 5: Build verifizieren**

Run: `xcodebuild build -scheme Feedivo -configuration Debug`
Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Snapshots/ReadingStatisticsInsight.swift FeedivoTests/Snapshots/ReadingStatisticsInsightTests.swift
git commit -m "feat: Erkenntnis-Satz für Statistik-Hero (regelbasiert, keine KI)

ReadingStatisticsInsight.generate leitet aus Wochentag-/Tageszeit-Verteilung
einen kurzen Hinweissatz ab, inkl. optionalem Wochenend-Zusatz und
Datenmangel-Schwelle (< 10 Artikel im Fenster → kein Satz)."
```

---

### Task 8: `StatisticsWindowView` — Hero-Bereich (Serie + vergrößerte Heatmap)

**Files:**
- Modify: `Feedivo/Views/Statistics/StatisticsWindowView.swift`
- Modify: `Feedivo/Views/Statistics/StatisticsHeatmapView.swift`
- Modify: `Feedivo/Resources/L10n.swift` (`statisticsStreakText` entfernen, jetzt unbenutzt)
- Modify: `Feedivo/Resources/Localizable.xcstrings` (`statistics.streak.text`-Eintrag entfernen)

**Interfaces:**
- Consumes: `ReadingStatisticsInsight.generate(weekdayCounts:daypartCounts:)` (Task 7),
  `L10n.statisticsHeroStreakLabel`/`statisticsHeroLongestStreak`/`statisticsHeatmapRange`
  (Task 6).

- [ ] **Step 1: Heatmap-Zellgröße anpassen**

In `Feedivo/Views/Statistics/StatisticsHeatmapView.swift`, ändere die Konstanten:

```swift
    private static let cellSize: CGFloat = 18
    private static let cellSpacing: CGFloat = 4
```

(vorher `12`/`3`) und den Radius der Zellen (im `body`, `RoundedRectangle(cornerRadius: 2,
style: .continuous)` innerhalb von `gridWithMonthLabels`) auf `cornerRadius: 4`.

- [ ] **Step 2: `statisticsStreakText` entfernen (wird durch Hero-Layout ersetzt)**

In `Feedivo/Resources/L10n.swift`, entferne den Block:

```swift
    static func statisticsStreakText(current: Int, longest: Int) -> String {
        String.localizedStringWithFormat(
            String(localized: "statistics.streak.text"),
            current,
            longest
        )
    }
```

In `Feedivo/Resources/Localizable.xcstrings`, entferne den kompletten
`"statistics.streak.text" : { ... }`-Eintrag (suche nach `"statistics.streak.text"`, lösche vom
öffnenden `"statistics.streak.text" : {` bis zur zugehörigen schließenden `},`-Zeile).

- [ ] **Step 3: Hero-Bereich in `StatisticsWindowView.swift` bauen**

Prüfe vor diesem Schritt per `grep -n "tertiaryText\|text3" Feedivo/Views/Rules/
RuleDialogTheme.swift` den tatsächlichen Property-Namen des Tertiärtext-Tokens — verwende in
den folgenden Code-Blöcken den echten Namen (`theme.tertiaryText` laut aktuellem Stand, nicht
`theme.text3`).

Ersetze die bestehende `heatmapCard(theme:)`-Funktion vollständig durch eine neue
`heroSection(theme:)`:

```swift
    private func heroSection(theme: RuleDialogTheme) -> some View {
        HStack(spacing: 0) {
            heroStreakColumn(theme: theme)
                .frame(width: 200)

            Rectangle()
                .fill(theme.border)
                .frame(width: 1)

            heroHeatmapColumn(theme: theme)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        )
    }

    private func heroStreakColumn(theme: RuleDialogTheme) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.statisticsHeatmapTitle)
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(theme.text2)

            Text("\(statistics.currentStreak)")
                .font(.system(size: 56, weight: .heavy))
                .tracking(-1.5)
                .foregroundStyle(theme.text)
                .monospacedDigit()

            Text(L10n.statisticsHeroStreakLabel)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.text2)

            Text(L10n.statisticsHeroLongestStreak(statistics.longestStreak))
                .font(.system(size: 12))
                .foregroundStyle(theme.text2)
                .padding(.top, 10)

            if let insight = ReadingStatisticsInsight.generate(
                weekdayCounts: statistics.weekdayCounts,
                daypartCounts: statistics.daypartCounts
            ) {
                Text(insight)
                    .font(.system(size: 12))
                    .italic()
                    .foregroundStyle(theme.text2)
                    .padding(.top, 16)
                    .overlay(alignment: .top) {
                        Rectangle().fill(theme.border).frame(height: 1)
                    }
            }
        }
        .padding(22)
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private func heroHeatmapColumn(theme: RuleDialogTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.statisticsHeatmapTitle)
                    .font(.system(size: 13, weight: .bold))
                    .tracking(-0.1)
                    .foregroundStyle(theme.text)

                Spacer(minLength: 8)

                Text(L10n.statisticsHeatmapRange)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.tertiaryText)
            }

            StatisticsHeatmapView(dailyCounts: statistics.dailyReadCounts, theme: theme)
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .center)
    }
```

Passe in `bodyContent(theme:)` den Aufruf an — ersetze `heatmapCard(theme: theme)` durch
`heroSection(theme: theme)`, sonst bleibt die Funktion für diesen Task unverändert (die
`summaryTiles`/`HStack(topFeedsCard, topTagsCard)`-Aufrufe werden erst in Task 9 bzw. 11
angepasst):

```swift
    private func bodyContent(theme: RuleDialogTheme) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            summaryTiles(theme: theme)
            heroSection(theme: theme)

            HStack(alignment: .top, spacing: 20) {
                topFeedsCard(theme: theme)
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                topTagsCard(theme: theme)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 22)
    }
```

- [ ] **Step 4: Build verifizieren**

Run: `xcodebuild build -scheme Feedivo -configuration Debug`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Views/Statistics/StatisticsWindowView.swift Feedivo/Views/Statistics/StatisticsHeatmapView.swift \
  Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings
git commit -m "feat: Hero-Bereich (Serie + vergrößerte Heatmap) im Statistik-Fenster

Ersetzt die kleine heatmapCard durch einen zweispaltigen Hero: großer
Serien-Wert + Erkenntnis-Satz links, 18px-Heatmap rechts. Heatmap-Zellgröße
von 12px auf 18px, Radius 2 auf 4 — abgestimmte Mockup-Maße. Ungenutztes
statisticsStreakText entfernt."
```

---

### Task 9: `StatisticsWindowView` — Überblick-Leiste (3 kompakte Werte)

**Files:**
- Modify: `Feedivo/Views/Statistics/StatisticsWindowView.swift`

**Interfaces:**
- Consumes: `statistics.averageArticlesPerDay` (Task 3), `L10n.statisticsOverviewAverageArticlesPerDay` (Task 6).

- [ ] **Step 1: `summaryTiles` durch schmale `overviewStrip` ersetzen**

Ersetze die bestehende `summaryTiles(theme:)`-Funktion (das 3-spaltige `LazyVGrid` mit 6
Kacheln) sowie `summaryTile(theme:title:value:trend:)` vollständig durch:

```swift
    private func overviewStrip(theme: RuleDialogTheme) -> some View {
        HStack(spacing: 0) {
            overviewItem(
                theme: theme,
                value: "\(statistics.articlesReadInSelectedRange)",
                label: L10n.statisticsSummarySelectedRangeCount,
                trend: trendText
            )
            overviewItem(
                theme: theme,
                value: formattedNumber(statistics.averageArticlesPerDay),
                label: L10n.statisticsOverviewAverageArticlesPerDay
            )
            overviewItem(
                theme: theme,
                value: formattedTotalReadingTime,
                label: L10n.statisticsSummaryTotalReadingTime,
                showsTrailingBorder: false
            )
        }
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        )
    }

    private func overviewItem(
        theme: RuleDialogTheme,
        value: String,
        label: LocalizedStringKey,
        trend: (text: String, color: Color)? = nil,
        showsTrailingBorder: Bool = true
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text(value)
                .font(.system(size: 19, weight: .bold))
                .tracking(-0.2)
                .monospacedDigit()
                .foregroundStyle(theme.text)

            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(theme.text2)

            if let trend {
                Text(trend.text)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(trend.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(trend.color.opacity(0.14))
                    )
                    .padding(.leading, 4)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .trailing) {
            if showsTrailingBorder {
                Rectangle().fill(theme.border).frame(width: 1)
            }
        }
    }

    private func formattedNumber(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
```

(`trendText` und `formattedTotalReadingTime` bleiben unverändert bestehen — werden weiterhin
konsumiert.)

Passe `bodyContent(theme:)` an (Aufruf umbenannt, Reihenfolge getauscht — Hero jetzt zuerst als
Fokuspunkt, Überblick-Leiste zweitrangig danach):

```swift
    private func bodyContent(theme: RuleDialogTheme) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            heroSection(theme: theme)
            overviewStrip(theme: theme)

            HStack(alignment: .top, spacing: 20) {
                topFeedsCard(theme: theme)
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                topTagsCard(theme: theme)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 22)
    }
```

- [ ] **Step 2: Build verifizieren**

Run: `xcodebuild build -scheme Feedivo -configuration Debug`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add Feedivo/Views/Statistics/StatisticsWindowView.swift
git commit -m "feat: Überblick-Leiste ersetzt 6-Kacheln-Raster im Statistik-Fenster

Drei kompakte Werte (gelesen im Zeitraum + Trend, Ø Artikel/Tag, Lesezeit
gesamt) statt sechs gleichförmiger Kacheln — bewusst zweitrangig hinter
dem neuen Hero-Bereich platziert, der jetzt zuerst steht."
```

---

### Task 10: Gewohnheiten-Abschnitt (Wochentag-/Tageszeit-Balken)

**Files:**
- Create: `Feedivo/Views/Statistics/StatisticsWeekdayBarsView.swift`
- Create: `Feedivo/Views/Statistics/StatisticsDaypartBarsView.swift`
- Modify: `Feedivo/Views/Statistics/StatisticsWindowView.swift`

**Interfaces:**
- Consumes: `statistics.weekdayCounts: [ReadingStatisticsWeekdayCount]`,
  `statistics.daypartCounts: [ReadingStatisticsDaypartCount]` (Task 3),
  `L10n.statisticsSectionHabitsTitle/Subtitle`, `L10n.statisticsHabitsWeekdayTitle/DaypartTitle`,
  `L10n.statisticsDaypartMorning/Midday/Afternoon/Evening/Night` (Task 6).

- [ ] **Step 1: `StatisticsWeekdayBarsView` erstellen**

Erstelle `Feedivo/Views/Statistics/StatisticsWeekdayBarsView.swift`:

```swift
import SwiftUI

/// Balkendiagramm der gelesenen Artikel je Wochentag (Feature: Gewohnheiten). Zeigt
/// Montag zuerst (deutsche Konvention), unabhängig von `Calendar.current.firstWeekday`.
struct StatisticsWeekdayBarsView: View {
    let weekdayCounts: [ReadingStatisticsWeekdayCount]
    let theme: RuleDialogTheme

    /// Anzeigereihenfolge Mo…So, gemappt auf Calendar-`.weekday`-Komponenten (1=So…7=Sa).
    private static let displayOrder = [2, 3, 4, 5, 6, 7, 1]

    private var countsByWeekday: [Int: Int] {
        Dictionary(uniqueKeysWithValues: weekdayCounts.map { ($0.weekday, $0.count) })
    }

    private var maxCount: Int {
        weekdayCounts.map(\.count).max() ?? 0
    }

    var body: some View {
        let symbols = Calendar.current.shortWeekdaySymbols

        HStack(alignment: .bottom, spacing: 7) {
            ForEach(Self.displayOrder, id: \.self) { weekday in
                let count = countsByWeekday[weekday] ?? 0
                let isPeak = maxCount > 0 && count == maxCount

                VStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(isPeak ? theme.accent : theme.accent.opacity(0.4))
                        .frame(height: maxCount > 0 ? max(4, CGFloat(count) / CGFloat(maxCount) * 76) : 4)
                        .frame(maxHeight: 76, alignment: .bottom)

                    Text(symbols[weekday - 1])
                        .font(.system(size: 10, weight: isPeak ? .bold : .medium))
                        .foregroundStyle(isPeak ? theme.text : theme.tertiaryText)
                }
            }
        }
        .frame(height: 92, alignment: .bottom)
    }
}
```

- [ ] **Step 2: `StatisticsDaypartBarsView` erstellen**

Erstelle `Feedivo/Views/Statistics/StatisticsDaypartBarsView.swift`:

```swift
import SwiftUI

/// Balkendiagramm der gelesenen Artikel je Tagesabschnitt (Feature: Gewohnheiten).
struct StatisticsDaypartBarsView: View {
    let daypartCounts: [ReadingStatisticsDaypartCount]
    let theme: RuleDialogTheme

    private var totalCount: Int {
        daypartCounts.reduce(0) { $0 + $1.count }
    }

    private var maxCount: Int {
        daypartCounts.map(\.count).max() ?? 0
    }

    var body: some View {
        VStack(spacing: 10) {
            ForEach(ReadingStatisticsDaypart.allCases, id: \.self) { daypart in
                let count = daypartCounts.first { $0.daypart == daypart }?.count ?? 0
                let isPeak = maxCount > 0 && count == maxCount
                let percentage = totalCount > 0 ? Double(count) / Double(totalCount) * 100 : 0

                HStack(spacing: 10) {
                    Text(label(for: daypart))
                        .font(.system(size: 12, weight: isPeak ? .semibold : .regular))
                        .foregroundStyle(isPeak ? theme.text : theme.text2)
                        .frame(width: 74, alignment: .leading)

                    GeometryReader { geometry in
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(theme.track)
                            .overlay(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(isPeak ? theme.accent : theme.accent.opacity(0.45))
                                    .frame(width: maxCount > 0 ? geometry.size.width * CGFloat(count) / CGFloat(maxCount) : 0)
                            }
                    }
                    .frame(height: 8)

                    Text("\(Int(percentage.rounded())) %")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.tertiaryText)
                        .frame(width: 34, alignment: .trailing)
                        .monospacedDigit()
                }
            }
        }
    }

    private func label(for daypart: ReadingStatisticsDaypart) -> LocalizedStringKey {
        switch daypart {
        case .morning: L10n.statisticsDaypartMorning
        case .midday: L10n.statisticsDaypartMidday
        case .afternoon: L10n.statisticsDaypartAfternoon
        case .evening: L10n.statisticsDaypartEvening
        case .night: L10n.statisticsDaypartNight
        }
    }
}
```

- [ ] **Step 3: Gewohnheiten-Abschnitt in `StatisticsWindowView.swift` einbinden**

Füge nach der bestehenden `overviewStrip(theme:)`-Funktion eine neue Sektions-Funktion hinzu:

```swift
    private func habitsSection(theme: RuleDialogTheme) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionHeader(theme: theme, title: L10n.statisticsSectionHabitsTitle, subtitle: L10n.statisticsSectionHabitsSubtitle)

            HStack(alignment: .top, spacing: 16) {
                sectionCard(theme: theme) {
                    VStack(alignment: .leading, spacing: 0) {
                        cardTitle(theme: theme, L10n.statisticsHabitsWeekdayTitle)
                        StatisticsWeekdayBarsView(weekdayCounts: statistics.weekdayCounts, theme: theme)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                sectionCard(theme: theme) {
                    VStack(alignment: .leading, spacing: 0) {
                        cardTitle(theme: theme, L10n.statisticsHabitsDaypartTitle)
                        StatisticsDaypartBarsView(daypartCounts: statistics.daypartCounts, theme: theme)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private func sectionHeader(theme: RuleDialogTheme, title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .tracking(-0.15)
                .foregroundStyle(theme.text)

            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(theme.text2)
        }
    }

    private func cardTitle(theme: RuleDialogTheme, _ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(size: 12.5, weight: .bold))
            .textCase(.uppercase)
            .tracking(0.4)
            .foregroundStyle(theme.text2)
            .padding(.bottom, 14)
    }

    @ViewBuilder
    private func sectionCard<Content: View>(theme: RuleDialogTheme, @ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 17)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(theme.border, lineWidth: 1)
            )
    }
```

(`sectionHeader`/`cardTitle`/`sectionCard` sind bewusst geteilte Bausteine — werden auch von
Task 11 und Task 12 wiederverwendet.)

Passe `bodyContent(theme:)` an:

```swift
    private func bodyContent(theme: RuleDialogTheme) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            heroSection(theme: theme)
            overviewStrip(theme: theme)
            habitsSection(theme: theme)

            HStack(alignment: .top, spacing: 20) {
                topFeedsCard(theme: theme)
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                topTagsCard(theme: theme)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 22)
    }
```

- [ ] **Step 4: Build verifizieren**

Run: `xcodebuild build -scheme Feedivo -configuration Debug`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Views/Statistics/StatisticsWeekdayBarsView.swift \
  Feedivo/Views/Statistics/StatisticsDaypartBarsView.swift \
  Feedivo/Views/Statistics/StatisticsWindowView.swift
git commit -m "feat: Gewohnheiten-Abschnitt (Wochentag-/Tageszeit-Balken) im Statistik-Fenster

Neue StatisticsWeekdayBarsView/StatisticsDaypartBarsView zeigen, wann der
Nutzer typischerweise liest — festes 91-Tage-Fenster, unabhängig vom
Zeitraum-Picker."
```

---

### Task 11: Aufmerksamkeit-Abschnitt (Rangliste nach Lesezeit)

**Files:**
- Create: `Feedivo/Views/Statistics/StatisticsRankListView.swift`
- Modify: `Feedivo/Views/Statistics/StatisticsWindowView.swift`

**Interfaces:**
- Consumes: `statistics.topFeedsByTime: [ReadingStatisticsFeedTime]`,
  `statistics.topTagsByTime: [ReadingStatisticsTagTime]` (Task 4),
  `L10n.statisticsSectionAttentionTitle/Subtitle`, `L10n.statisticsAttentionFeedsTitle/TagsTitle/Empty`
  (Task 6), `theme.accent`, `TagColorPalette.color(for:)`, `CachedRemoteImageView`.
- Removes: `topFeedsCard`, `topFeedRow`, `feedFaviconView`, `topTagsCard`, `topTagRow` aus
  `StatisticsWindowView.swift` (ersetzt durch die neue Sektion).

- [ ] **Step 1: `StatisticsRankListView` erstellen**

Erstelle `Feedivo/Views/Statistics/StatisticsRankListView.swift`:

```swift
import SwiftUI

/// Eine Rangliste mit proportionalem Balken pro Zeile — geteilt zwischen Top-Feeds und
/// Top-Tags im Aufmerksamkeit-Abschnitt des Statistik-Fensters. `icon` liefert pro Zeile
/// entweder ein echtes Feed-Favicon oder einen echten Tag-Farbpunkt (kein generischer
/// Platzhalter).
struct StatisticsRankListView<Row>: View {
    let rows: [Row]
    let theme: RuleDialogTheme
    let minutes: (Row) -> Int
    let title: (Row) -> String
    let meta: (Row) -> String
    let icon: (Row) -> AnyView

    private var maxMinutes: Int {
        rows.map(minutes).max() ?? 0
    }

    var body: some View {
        VStack(spacing: 11) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                let rowMinutes = minutes(row)

                HStack(spacing: 10) {
                    icon(row)
                        .frame(width: 20, height: 20)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(title(row))
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(theme.text)
                                .lineLimit(1)

                            Spacer(minLength: 8)

                            Text(meta(row))
                                .font(.system(size: 11))
                                .foregroundStyle(theme.tertiaryText)
                        }

                        GeometryReader { geometry in
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(theme.track)
                                .overlay(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(index == 0 ? theme.accent : theme.accent.opacity(0.55))
                                        .frame(width: maxMinutes > 0 ? geometry.size.width * CGFloat(rowMinutes) / CGFloat(maxMinutes) : 0)
                                }
                        }
                        .frame(height: 5)
                    }

                    Text(StatisticsRankListView.formattedMinutes(rowMinutes))
                        .font(.system(size: 12.5, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(theme.text)
                        .frame(width: 58, alignment: .trailing)
                }
            }
        }
    }

    private static func formattedMinutes(_ minutes: Int) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.hour, .minute]
        formatter.maximumUnitCount = 2
        return formatter.string(from: TimeInterval(minutes) * 60) ?? "0"
    }
}
```

- [ ] **Step 2: Aufmerksamkeit-Abschnitt in `StatisticsWindowView.swift` einbinden**

Entferne die bestehenden Funktionen `topFeedsCard`, `topFeedRow`, `feedFaviconView`,
`topTagsCard`, `topTagRow` vollständig aus `StatisticsWindowView.swift`.

Füge stattdessen nach `habitsSection(theme:)` hinzu:

```swift
    private func attentionSection(theme: RuleDialogTheme) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionHeader(theme: theme, title: L10n.statisticsSectionAttentionTitle, subtitle: L10n.statisticsSectionAttentionSubtitle)

            HStack(alignment: .top, spacing: 16) {
                sectionCard(theme: theme) {
                    VStack(alignment: .leading, spacing: 0) {
                        cardTitle(theme: theme, L10n.statisticsAttentionFeedsTitle)
                        if statistics.topFeedsByTime.isEmpty {
                            Text(L10n.statisticsAttentionEmpty)
                                .font(.system(size: 12.5))
                                .foregroundStyle(theme.text2)
                        } else {
                            StatisticsRankListView(
                                rows: statistics.topFeedsByTime,
                                theme: theme,
                                minutes: { $0.minutes },
                                title: { $0.feedTitle },
                                meta: { "\($0.articleCount) Artikel" },
                                icon: { feed in AnyView(feedFaviconView(feed: feed)) }
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                sectionCard(theme: theme) {
                    VStack(alignment: .leading, spacing: 0) {
                        cardTitle(theme: theme, L10n.statisticsAttentionTagsTitle)
                        if statistics.topTagsByTime.isEmpty {
                            Text(L10n.statisticsAttentionEmpty)
                                .font(.system(size: 12.5))
                                .foregroundStyle(theme.text2)
                        } else {
                            StatisticsRankListView(
                                rows: statistics.topTagsByTime,
                                theme: theme,
                                minutes: { $0.minutes },
                                title: { $0.name },
                                meta: { "\($0.articleCount) Artikel" },
                                icon: { tag in
                                    AnyView(
                                        Circle()
                                            .fill(TagColorPalette.color(for: tag.colorHex))
                                    )
                                }
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    @ViewBuilder
    private func feedFaviconView(feed: ReadingStatisticsFeedTime) -> some View {
        if let faviconURL = feed.faviconURL, let url = URL(string: faviconURL) {
            CachedRemoteImageView(url: url) { image in
                image
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            } placeholder: {
                Image(systemName: "dot.radiowaves.up.forward")
            }
        } else {
            Image(systemName: "dot.radiowaves.up.forward")
        }
    }
```

(Die Artikelanzahl-Sekundärtext-Werte `"\($0.articleCount) Artikel"` sind bewusst fest
Deutsch, analog zu anderen unlokalisierten reinen Sekundärtext-Stellen im Projekt — kein neuer
L10n-Key für dieses Metadatum nötig.)

Passe `bodyContent(theme:)` an — ersetzt die alte `HStack(topFeedsCard, topTagsCard)`:

```swift
    private func bodyContent(theme: RuleDialogTheme) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            heroSection(theme: theme)
            overviewStrip(theme: theme)
            habitsSection(theme: theme)
            attentionSection(theme: theme)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 22)
    }
```

- [ ] **Step 3: Build verifizieren**

Run: `xcodebuild build -scheme Feedivo -configuration Debug`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add Feedivo/Views/Statistics/StatisticsRankListView.swift Feedivo/Views/Statistics/StatisticsWindowView.swift
git commit -m "feat: Aufmerksamkeit-Abschnitt — Top-Feeds/Tags als Rangliste nach Lesezeit

Neue geteilte StatisticsRankListView ersetzt die alten Kachel-Listen.
Zeigt echte Favicons/Tag-Farben (keine Platzhalter) + proportionalen
Balken + formatierte Lesezeit statt roher Artikelanzahl."
```

---

### Task 12: Feed-Gesundheit-Abschnitt (inkl. Abbestellen)

**Files:**
- Create: `Feedivo/Views/Statistics/StatisticsFeedHealthListView.swift`
- Modify: `Feedivo/Views/Statistics/StatisticsWindowView.swift`

**Interfaces:**
- Consumes: `StatisticsStore.feedHealthCandidates()` (Task 5), `FeedViewModel.deleteFeed(feedID:
  sqliteDatabase:)` (bestehend), `L10n.feedDeleteConfirmationTitle/ConfirmButton/
  ConfirmationMessage`, `L10n.commonCancel` (bestehend), `L10n.statisticsSectionFeedHealthTitle/
  Subtitle`, `L10n.statisticsFeedHealthCounts/ReadPercentage/UnsubscribeButton/Empty` (Task 6).

- [ ] **Step 1: `StatisticsFeedHealthListView` erstellen**

Erstelle `Feedivo/Views/Statistics/StatisticsFeedHealthListView.swift`:

```swift
import SwiftUI

/// Zeigt Feeds, die der Nutzer kaum liest, mit Lesequote-Balken und einem Abbestellen-
/// Button pro Zeile. Reiner Anzeige-/Auslöse-Baustein — Bestätigungsdialog und tatsächliches
/// Löschen bleiben in `StatisticsWindowView` (teilt den Dialog-Wortlaut mit dem Feed-Organizer
/// und dem Feed-Status-Fenster).
struct StatisticsFeedHealthListView: View {
    let candidates: [ReadingStatisticsFeedHealth]
    let theme: RuleDialogTheme
    let onUnsubscribeTapped: (ReadingStatisticsFeedHealth) -> Void

    private static let warningColor = Color(hex: 0xFF9F0A)

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(candidates.enumerated()), id: \.offset) { index, candidate in
                row(candidate)
                    .padding(.vertical, 10)
                    .overlay(alignment: .top) {
                        if index > 0 {
                            Rectangle().fill(theme.border).frame(height: 1)
                        }
                    }
            }
        }
    }

    private func row(_ candidate: ReadingStatisticsFeedHealth) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Self.warningColor)
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.feedTitle)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.text)

                Text(L10n.statisticsFeedHealthCounts(unread: candidate.unreadCount, total: candidate.totalCount))
                    .font(.system(size: 11))
                    .foregroundStyle(theme.text2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 4) {
                Text(L10n.statisticsFeedHealthReadPercentage(Int(candidate.readPercentage.rounded())))
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(Self.warningColor)
                    .monospacedDigit()

                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(theme.track)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Self.warningColor)
                            .frame(width: 120 * CGFloat(candidate.readPercentage / 100))
                    }
                    .frame(width: 120, height: 5)
            }

            Button {
                onUnsubscribeTapped(candidate)
            } label: {
                Text(L10n.statisticsFeedHealthUnsubscribeButton)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(theme.text2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(theme.card2)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(theme.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }
}
```

- [ ] **Step 2: Feed-Gesundheit-Abschnitt in `StatisticsWindowView.swift` einbinden**

Ergänze am Anfang von `StatisticsWindowView` die neuen State-Properties (bei den bestehenden
`@State`-Deklarationen):

```swift
    @State private var feedViewModel = FeedViewModel()
    @State private var feedHealthCandidates: [ReadingStatisticsFeedHealth] = []
    @State private var feedPendingUnsubscribe: ReadingStatisticsFeedHealth?
```

Füge nach `attentionSection(theme:)` hinzu:

```swift
    private func feedHealthSection(theme: RuleDialogTheme) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionHeader(theme: theme, title: L10n.statisticsSectionFeedHealthTitle, subtitle: L10n.statisticsSectionFeedHealthSubtitle)

            if feedHealthCandidates.isEmpty {
                sectionCard(theme: theme) {
                    Text(L10n.statisticsFeedHealthEmpty)
                        .font(.system(size: 12.5))
                        .foregroundStyle(theme.text2)
                }
            } else {
                sectionCard(theme: theme) {
                    StatisticsFeedHealthListView(
                        candidates: feedHealthCandidates,
                        theme: theme,
                        onUnsubscribeTapped: { feedPendingUnsubscribe = $0 }
                    )
                }
            }
        }
    }

    private func unsubscribe(_ candidate: ReadingStatisticsFeedHealth) {
        feedPendingUnsubscribe = nil
        guard let feedivoDatabase else {
            return
        }
        feedViewModel.deleteFeed(feedID: candidate.feedID, sqliteDatabase: feedivoDatabase)
        // deleteFeed wirft nicht — ein Fehlschlag landet nur in feedViewModel.errorMessage.
        // Die Zeile darf deshalb nur bei tatsächlichem Erfolg entfernt werden, sonst würde
        // die UI ein gelöschtes Feed vortäuschen, das in Wahrheit noch existiert.
        if feedViewModel.errorMessage == nil {
            feedHealthCandidates.removeAll { $0.feedID == candidate.feedID }
        }
    }
```

Passe `bodyContent(theme:)` an (finale Reihenfolge):

```swift
    private func bodyContent(theme: RuleDialogTheme) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            heroSection(theme: theme)
            overviewStrip(theme: theme)
            habitsSection(theme: theme)
            attentionSection(theme: theme)
            feedHealthSection(theme: theme)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 22)
    }
```

Ergänze in `loadStatistics()` (nach dem bestehenden `feedStatistics = try feeds.map { ... }`)
das Laden der Feed-Gesundheit-Kandidaten:

```swift
            feedHealthCandidates = try statisticsStore.feedHealthCandidates()
```

und im `catch`-Block:

```swift
        } catch {
            statistics = .empty
            feedStatistics = []
            feedHealthCandidates = []
        }
```

Ergänze im `body` der View den Bestätigungsdialog (als zusätzlichen Modifier auf dem
bestehenden `VStack`, analog zum bereits im Projekt etablierten Muster aus
`FeedRefreshDiagnosticsWindowView.swift`):

```swift
        .confirmationDialog(
            L10n.feedDeleteConfirmationTitle,
            isPresented: Binding(
                get: { feedPendingUnsubscribe != nil },
                set: { isPresented in
                    if !isPresented {
                        feedPendingUnsubscribe = nil
                    }
                }
            ),
            presenting: feedPendingUnsubscribe
        ) { candidate in
            Button(L10n.feedDeleteConfirmButton, role: .destructive) {
                unsubscribe(candidate)
            }

            Button(L10n.commonCancel, role: .cancel) {
                feedPendingUnsubscribe = nil
            }
        } message: { candidate in
            Text(L10n.feedDeleteConfirmationMessage(feedTitle: candidate.feedTitle))
        }
```

- [ ] **Step 3: Build verifizieren**

Run: `xcodebuild build -scheme Feedivo -configuration Debug`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add Feedivo/Views/Statistics/StatisticsFeedHealthListView.swift Feedivo/Views/Statistics/StatisticsWindowView.swift
git commit -m "feat: Feed-Gesundheit-Abschnitt mit funktionierendem Abbestellen

Zeigt kaum gelesene Feeds (≥20 Artikel, niedrigste Lesequote). Abbestellen-
Button löst denselben Bestätigungsdialog-Flow wie Feed-Organizer/
Feed-Status-Fenster aus (FeedViewModel.deleteFeed), Zeile verschwindet nur
bei tatsächlichem Löscherfolg."
```

---

### Task 13: Abschluss — Regressionslauf + Build

**Files:** Keine Code-Änderungen — reine Verifikation.

- [ ] **Step 1: Gezielter Testlauf über alle in diesem Plan berührten Suiten**

Run:
```bash
xcodebuild test -scheme Feedivo \
  -only-testing:FeedivoTests/ReaderMetadataFormatterTests \
  -only-testing:FeedivoTests/FeedivoDatabaseMigratorTests \
  -only-testing:FeedivoTests/SQLiteStatisticsStoreTests \
  -only-testing:FeedivoTests/ReadingStatisticsInsightTests \
  -only-testing:FeedivoTests/FeedivoTests \
  -parallel-testing-enabled NO
```
Expected: Alle Tests grün (bekannte, vorbestehende Fehlschläge in
`FeedivoAppSceneConfigurationTests.swift` sind hier nicht Teil der Auswahl und daher
irrelevant für dieses Ergebnis).

- [ ] **Step 2: Debug-Build**

Run: `xcodebuild build -scheme Feedivo -configuration Debug`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Release-Build (deckt String-Catalog-Kompilierung der neuen xcstrings-Einträge
  in beiden Konfigurationen ab)**

Run: `xcodebuild build -scheme Feedivo -configuration Release`
Expected: BUILD SUCCEEDED, 0 Fehler.

- [ ] **Step 4: `Localizable.xcstrings`-Diff final prüfen**

Run: `git diff --stat Feedivo/Resources/Localizable.xcstrings` (gegen den Stand vor Task 6)
Expected: Nur Insertions aus Task 6 (und die eine Deletion aus Task 8 für
`statistics.streak.text`) — kein unbeabsichtigter voller Datei-Roundtrip.

- [ ] **Step 5: Commit (nur falls Step 1–4 Nacharbeiten nötig machten; sonst kein Commit)**

Falls alle vorherigen Tasks bereits sauber committed wurden und dieser Task keine
Code-Änderungen selbst vornimmt, entfällt dieser Schritt — Task 13 ist ein reiner
Verifikations-Checkpoint.

**Manuelle Live-Verifikation (nicht automatisierbar, kein computer-use für native macOS-Apps
verfügbar) — durch den Nutzer nachzuholen:**
1. Statistik-Fenster öffnen — Hero zeigt Serie + Heatmap in der abgestimmten Größe (18px-
   Zellen), Hell- und Dunkelmodus prüfen.
2. Überblick-Leiste zeigt plausible Werte, insbesondere "Lesezeit gesamt" jetzt ungleich 0.
3. Gewohnheiten-Karten zeigen ein plausibles Wochentag-/Tageszeit-Muster.
4. Aufmerksamkeit-Karten zeigen echte Favicons/Tag-Farben, sortiert nach Lesezeit, nicht nach
   Artikelanzahl.
5. Feed-Gesundheit: falls vorhanden, mindestens einen Kandidaten-Feed antippen, "Abbestellen"
   klicken, Bestätigungsdialog bestätigen — Feed verschwindet aus Sidebar UND aus der Liste.
6. CSV-Export öffnen und prüfen, dass Lesezeit-Spalten befüllt sind (nicht mehr 0).
7. Erkenntnis-Satz erscheint bei ausreichend Daten plausibel, verschwindet bei wenig Daten
   (z. B. frisch installierte App) statt einen falschen Satz zu zeigen.
