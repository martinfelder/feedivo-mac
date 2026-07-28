# SQL-/HTML-Duplikation konsolidieren (Findings 1.8 + 1.9) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Die 7-fach duplizierte `ArticleListSnapshot`-SQL-Projektion (Finding 1.8) und die
3-fach duplizierte HTML-Escaping-/Link-Filter-Logik für den Artikel-Export (Finding 1.9) auf
je einen gemeinsamen, getesteten Ort konsolidieren, damit zukünftige Feldänderungen nicht
erneut unbemerkt auseinanderlaufen können (wie beim bereits dokumentierten `faviconURL`-Bug).

**Architecture:** Zwei neue, kleine geteilte Bausteine, die bestehende Store-/Service-Dateien
referenzieren statt eigene Kopien zu pflegen:
- `Feedivo/Stores/ArticleListSQL.swift` — zwei `String`-Konstanten (Spaltenliste + Standard-
  `FROM`/`JOIN`-Klausel), die `ArticleStore.swift`, `TimelineStore.swift` und
  `ArticleDatabase.swift` per String-Interpolation in ihre SQL-Strings einsetzen.
- `Feedivo/Services/ArticleExportSanitizing.swift` — ein `enum` mit `escapedHTML`,
  `escapedHTMLAttribute`, `isSafeLinkTarget` und `publishedDateFormatter`, das
  `ArticleExportService.swift` (beide dort enthaltenen Enums) und
  `Feedivo/Services/ArticleDocumentExportRenderers.swift`s `ArticlePDFExportRenderer`
  referenzieren.

Beide Konsolidierungen sind reine Refactorings ohne beabsichtigte Verhaltensänderung — mit
einer dokumentierten Ausnahme (siehe Global Constraints, Punkt 3).

**Tech Stack:** Swift, GRDB (SQLite), Swift Testing (`@Test`/`#expect`/`#require`, kein XCTest).

## Global Constraints

- Zielumgebung: `xcodebuild test -scheme Feedivo -destination 'platform=macOS'
  -only-testing:FeedivoTests/<SuiteName> -parallel-testing-enabled NO` — nie die volle
  Testsuite ungescoped laufen lassen (hängt reproduzierbar, siehe CLAUDE.md-Gotcha).
- Kommentare im Code auf Deutsch, nur wo eine nicht offensichtliche Begründung nötig ist
  (Projekt-Konvention laut CLAUDE.md — Entwickler ist Swift-Anfänger).
- `ArticleListSQL.selectColumns`/`.standardFromJoin` werden per String-Interpolation in
  GRDB-`sql:`-Strings eingesetzt. GRDB mappt `ArticleListSnapshot`-Spalten über
  `row["spaltenname"]` (siehe `TimelineStore.swift:768-786`), nicht positionell — die exakte
  Einrückung der eingesetzten Konstante ist daher irrelevant für die Korrektheit.
- **Bewusste Verhaltensänderung in Task 6:** `ArticleDocumentExportRenderers.swift`s
  bisheriges lokales `escapedHTML` escapte zusätzlich `"` in normalem Text-Content (im
  Gegensatz zu `ArticleExportService.swift`s Variante, die dort nur `& < >` escaped und `"`
  erst in `escapedHTMLAttribute` behandelt). Die Konsolidierung übernimmt bewusst
  `ArticleExportService.swift`s Verhalten als kanonisch (semantisch korrekter: Text-Content
  braucht kein Attribut-Escaping). Sichtbarer Effekt: keiner — `&quot;` und `"` rendern im
  Browser/PDF identisch als `"`, betrifft nur den rohen HTML-Quelltext.
- `isSafeImageSource` (`ArticleExportService.swift:569`) und `escapedXML`
  (`ArticleDocumentExportRenderers.swift:499`, DOCX-spezifisch) sind NICHT Teil dieser
  Konsolidierung — nicht dupliziert bzw. ein strukturell eigenständiges Escaping-Schema
  (OpenXML statt HTML). Nicht anfassen.
- Alle Commits laufen direkt auf `main` (Nutzerentscheidung für diese Gruppe).

---

## Vorab-Verifikation (bereits erledigt, hier dokumentiert)

Beide Findings wurden vor diesem Plan gegen den aktuellen Code auf `main` (HEAD `10eb54b0`)
verifiziert:
- **Finding 1.8:** 6 (nicht 7, siehe Korrektur unten) wortidentische Kopien des 16-Spalten-
  `SELECT` bestätigt in `ArticleStore.swift` (4×: `latestArticleForFeed` 2 Queries,
  `searchArticles(matching:)`, `searchArticles(state:)`), `TimelineStore.swift` (1×,
  `articles(scope:...)`), `ArticleDatabase.swift` (1×, privater `fetchArticles`-Helper).
  Das Review zählte zusätzlich `ArticleStore.swift:119` — das ist aber `readerArticle`s
  SELECT für `ArticleReaderSnapshot` (andere Spaltenmenge, u. a. `offlineContent`), keine
  Kopie der 16-Spalten-`ArticleListSnapshot`-Projektion. Bleibt außerhalb dieses Plans.
- **Finding 1.9:** Duplikation bestätigt, aber **nicht byte-identisch** wie im Review
  behauptet — die drei Kopien haben bereits leicht auseinandergelaufene `escapedHTML`-
  Semantik (siehe Global Constraints, Punkt 3). Kein Sicherheitsbug (beide Call-Sites sind
  Text-Content, nicht Attribut-Content), aber ein reales Beispiel für das befürchtete
  Auseinanderlaufen. Die im Review behauptete "0 Testdateien" für
  `ArticleDocumentExportRenderers.swift` ist ebenfalls ungenau: `ArticlePDFExportRenderer`
  wird bereits indirekt UND an mehreren Stellen direkt (`ArticlePDFExportRenderer.html(...)`)
  aus `FeedivoTests/ArticleExportServiceTests.swift` getestet — es fehlt keine eigene
  `*Tests.swift`-Datei, aber tatsächlich fehlt eine direkte Testabdeckung speziell für
  Link-Schema-Filterung im PDF-Pfad (wird in Task 6 ergänzt, wie vom Review gefordert).

---

### Task 1: `ArticleListSQL` — gemeinsame SQL-Fragment-Konstante anlegen

**Files:**
- Create: `Feedivo/Stores/ArticleListSQL.swift`
- Test: `FeedivoTests/ArticleListSQLTests.swift`

**Interfaces:**
- Produces: `enum ArticleListSQL { static let selectColumns: String; static let
  standardFromJoin: String }` — `selectColumns` liefert die 16 Spalten (ohne `SELECT`-
  Schlüsselwort, ohne Komma am Ende), `standardFromJoin` liefert `FROM articles a JOIN
  feeds f ... LEFT JOIN article_offline o ...` (ohne `WHERE`). Beide werden von Task 2 und
  Task 3 per `\(ArticleListSQL.selectColumns)` in GRDB-`sql:`-Strings referenziert.

- [ ] **Step 1: Fehlschlagenden Test schreiben**

Erstelle `FeedivoTests/ArticleListSQLTests.swift`:

```swift
import Foundation
import GRDB
import Testing
@testable import Feedivo

struct ArticleListSQLTests {
    @Test func selectColumnsUndStandardFromJoinLiefernAlleSnapshotFelder() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)

        try feedStore.save(FeedRecord(
            id: "feed-a",
            url: "https://a.example.com/feed",
            title: "Feed A",
            faviconURL: "https://a.example.com/favicon.ico"
        ))
        let articleID = try articleStore.upsert(ArticleUpsertInput(
            feedID: "feed-a",
            sourceID: "article-1",
            title: "Artikel 1",
            summary: "Kurzfassung",
            arrivedAt: Date(timeIntervalSince1970: 100)
        ))

        let snapshot = try database.read { db in
            try ArticleListSnapshot.fetchOne(db, sql: """
                SELECT
                    \(ArticleListSQL.selectColumns)
                \(ArticleListSQL.standardFromJoin)
                WHERE a.id = ?
                """, arguments: [articleID])
        }

        let unwrapped = try #require(snapshot)
        #expect(unwrapped.id == articleID)
        #expect(unwrapped.feedID == "feed-a")
        #expect(unwrapped.feedTitle == "Feed A")
        #expect(unwrapped.faviconURL == "https://a.example.com/favicon.ico")
        #expect(unwrapped.title == "Artikel 1")
        #expect(unwrapped.summary == "Kurzfassung")
        #expect(unwrapped.isRead == false)
        #expect(unwrapped.offlineState == .none)
    }
}
```

- [ ] **Step 2: Test laufen lassen, RED bestätigen**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ArticleListSQLTests -parallel-testing-enabled NO`
Expected: FAIL (Build-Fehler: "cannot find 'ArticleListSQL' in scope" — `ArticleListSQL`
existiert noch nicht).

- [ ] **Step 3: `ArticleListSQL.swift` implementieren**

Erstelle `Feedivo/Stores/ArticleListSQL.swift`:

```swift
import Foundation

/// Gemeinsame SQL-Fragmente für alle Stellen, die `ArticleListSnapshot` aus
/// `articles`/`feeds`/`article_statuses`/`article_offline` laden. Vorher war dieser
/// 16-Spalten-SELECT 6-fach unabhängig kopiert — genau diese Duplikation hat bereits einen
/// `faviconURL`-Bug verursacht (siehe CLAUDE.md-Gotcha "Duplizierte SQL-SELECT-Listen").
enum ArticleListSQL {
    static let selectColumns = """
        a.id,
        a.feedID,
        f.title AS feedTitle,
        f.faviconURL AS faviconURL,
        a.title,
        a.summary,
        a.link,
        a.imageURL,
        a.publishedAt,
        a.arrivedAt,
        a.estimatedReadingMinutes,
        s.isRead,
        s.isStarred,
        s.isArchived,
        s.isHidden,
        COALESCE(o.state, 'none') AS offlineStateRaw
        """

    static let standardFromJoin = """
        FROM articles a
        JOIN feeds f ON f.id = a.feedID
        JOIN article_statuses s ON s.articleID = a.id
        LEFT JOIN article_offline o ON o.articleID = a.id
        """
}
```

- [ ] **Step 4: Test laufen lassen, GREEN bestätigen**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ArticleListSQLTests -parallel-testing-enabled NO`
Expected: PASS

- [ ] **Step 5: Committen**

```bash
git add Feedivo/Stores/ArticleListSQL.swift FeedivoTests/ArticleListSQLTests.swift
git commit -m "$(cat <<'EOF'
Refactor: ArticleListSQL als gemeinsame SQL-Fragment-Konstante angelegt (Finding 1.8, Vorbereitung)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: `ArticleStore.swift` — 4 Vorkommen auf `ArticleListSQL` umstellen

**Files:**
- Modify: `Feedivo/Stores/ArticleStore.swift:212-269` (`latestArticleForFeed`, 2 Queries),
  `Feedivo/Stores/ArticleStore.swift:271-314` (`searchArticles(matching:)`),
  `Feedivo/Stores/ArticleStore.swift:316-405` (`searchArticles(state:)`)
- Test: `FeedivoTests/SQLiteArticleStoreTests.swift` (bestehende Suite, keine neuen Tests
  nötig — dient als Regressionsnetz)

**Interfaces:**
- Consumes: `ArticleListSQL.selectColumns`, `ArticleListSQL.standardFromJoin` (Task 1)

- [ ] **Step 1: `latestArticleForFeed` (2 Queries) umstellen**

In `Feedivo/Stores/ArticleStore.swift`, ersetze die erste Query in
`latestArticleForFeed(feedID:db:)` (aktuell Zeilen ~213-239):

```swift
    private func latestArticleForFeed(feedID: String, db: Database) throws -> ArticleListSnapshot? {
        if let datedArticle = try ArticleListSnapshot.fetchOne(db, sql: """
            SELECT
                \(ArticleListSQL.selectColumns)
            \(ArticleListSQL.standardFromJoin)
            WHERE a.feedID = ?
                AND a.publishedAt IS NOT NULL
            ORDER BY a.publishedAt DESC, a.arrivedAt DESC
            LIMIT 1
            """, arguments: [feedID]) {
            return datedArticle
        }

        return try ArticleListSnapshot.fetchOne(db, sql: """
            SELECT
                \(ArticleListSQL.selectColumns)
            \(ArticleListSQL.standardFromJoin)
            WHERE a.feedID = ?
            ORDER BY a.arrivedAt DESC
            LIMIT 1
            """, arguments: [feedID])
    }
```

- [ ] **Step 2: `searchArticles(matching:)` umstellen**

Ersetze in derselben Datei die `SELECT`-Spaltenliste in `searchArticles(matching:...)`
(aktuell Zeilen ~285-312). Die `FROM`-Klausel bleibt unverändert (startet bei
`article_search`, nicht bei `articles` — abweichend von `standardFromJoin`, deshalb wird nur
`selectColumns` referenziert, nicht `standardFromJoin`):

```swift
        return try database.read { db in
            try ArticleListSnapshot.fetchAll(db, sql: """
                SELECT
                    \(ArticleListSQL.selectColumns)
                FROM article_search search
                JOIN articles a ON a.rowid = search.rowid
                JOIN feeds f ON f.id = a.feedID
                JOIN article_statuses s ON s.articleID = a.id
                LEFT JOIN article_offline o ON o.articleID = a.id
                WHERE article_search MATCH ?
                    \(hiddenClause)
                ORDER BY COALESCE(a.publishedAt, a.arrivedAt) DESC, a.arrivedAt DESC
                LIMIT ?
                """, arguments: [trimmedQuery, safeLimit])
        }
```

- [ ] **Step 3: `searchArticles(state:)` umstellen**

Ersetze in derselben Datei die `SELECT`-Spaltenliste und `FROM`/`JOIN`-Klausel in
`searchArticles(state:...)` (aktuell Zeilen ~377-403):

```swift
        return try database.read { db in
            try ArticleListSnapshot.fetchAll(db, sql: """
                SELECT
                    \(ArticleListSQL.selectColumns)
                \(ArticleListSQL.standardFromJoin)
                \(searchJoinSQL)
                \(whereSQL)
                ORDER BY COALESCE(a.publishedAt, a.arrivedAt) DESC, a.arrivedAt DESC
                LIMIT ?
                """, arguments: arguments)
        }
```

- [ ] **Step 4: Tests laufen lassen, GREEN bestätigen**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteArticleStoreTests -parallel-testing-enabled NO`
Expected: PASS (alle bestehenden Tests, u. a.
`feedPropertiesMetricsUseLatestDatedArticleAndRecentCount`,
`feedPropertiesMetricsFallsBackToUndatedArticle`, `searchArticlesFindsTitleSummaryContentAndAuthor`,
`searchWindowQueryHonorsFieldFeedTagAndStatusFilters` — decken alle 4 geänderten Stellen ab)

- [ ] **Step 5: Committen**

```bash
git add Feedivo/Stores/ArticleStore.swift
git commit -m "$(cat <<'EOF'
Refactor: ArticleStore.swift nutzt ArticleListSQL statt 4x eigener SELECT-Kopie (Finding 1.8)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: `TimelineStore.swift` + `ArticleDatabase.swift` umstellen, fehlende Favicon-Testabdeckung ergänzen

**Files:**
- Modify: `Feedivo/Stores/TimelineStore.swift:86-115` (`articles(scope:...)`)
- Modify: `Feedivo/Stores/ArticleDatabase.swift:278-306` (privater `fetchArticles`-Helper)
- Test: `FeedivoTests/SQLiteTimelineStoreTests.swift` (neuer Test), `FeedivoTests/SQLiteArticleDatabaseTests.swift`
  (bestehende Suite, dient als Regressionsnetz — enthält bereits
  `newestUnreadLiefertFaviconURLDesFeedsMit`)

**Interfaces:**
- Consumes: `ArticleListSQL.selectColumns`, `ArticleListSQL.standardFromJoin` (Task 1)

- [ ] **Step 1: Fehlenden Favicon-Regressionstest für `TimelineStore` schreiben**

`SQLiteArticleDatabaseTests.swift` hat bereits `newestUnreadLiefertFaviconURLDesFeedsMit`
als Regressionsschutz gegen genau diese Bug-Klasse — `SQLiteTimelineStoreTests.swift` hat
diese Abdeckung noch nicht. Füge in `FeedivoTests/SQLiteTimelineStoreTests.swift` direkt
nach `timelineFetchesNewestUnreadVisibleSnapshotsForFeed` (nach Zeile 44) ein:

```swift

    @Test func timelineArticlesLiefertFaviconURLDesFeedsMit() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let timelineStore = TimelineStore(database: database)

        try feedStore.save(FeedRecord(
            id: "feed-a",
            url: "https://a.example.com/feed",
            title: "Feed A",
            faviconURL: "https://a.example.com/favicon.ico"
        ))
        _ = try articleStore.upsert(ArticleUpsertInput(
            feedID: "feed-a",
            sourceID: "article-1",
            title: "Artikel 1"
        ))

        let snapshots = try timelineStore.articles(
            scope: .feed("feed-a"),
            includeRead: true,
            includeHidden: false,
            limit: 20
        )

        #expect(snapshots.first?.faviconURL == "https://a.example.com/favicon.ico")
    }
```

- [ ] **Step 2: Test laufen lassen, bestätigen dass er bereits PASST (Charakterisierungstest)**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteTimelineStoreTests -parallel-testing-enabled NO`
Expected: PASS — der aktuelle (noch unrefactorte) Code liefert `faviconURL` bereits korrekt,
dieser Test ist ein Charakterisierungstest, der die anschließende Umstellung auf
`ArticleListSQL` absichert, kein Red-Green-Test für neues Verhalten.

- [ ] **Step 3: `TimelineStore.articles(scope:...)` umstellen**

In `Feedivo/Stores/TimelineStore.swift`, ersetze die `SELECT`-Spaltenliste und
`FROM`/`JOIN`-Klausel (aktuell Zeilen ~87-113):

```swift
        return try database.read { db in
            try ArticleListSnapshot.fetchAll(db, sql: """
                SELECT
                    \(ArticleListSQL.selectColumns)
                \(ArticleListSQL.standardFromJoin)
                \(searchJoinSQL)
                \(whereSQL)
                ORDER BY COALESCE(a.publishedAt, a.arrivedAt) DESC, a.arrivedAt DESC
                LIMIT ?
                """, arguments: arguments)
        }
```

- [ ] **Step 4: `ArticleDatabase.fetchArticles` umstellen**

In `Feedivo/Stores/ArticleDatabase.swift`, ersetze die `SELECT`-Spaltenliste und
`FROM`/`JOIN`-Klausel im privaten `fetchArticles`-Helper (aktuell Zeilen ~279-304):

```swift
        return try database.read { db in
            try ArticleListSnapshot.fetchAll(db, sql: """
                SELECT
                    \(ArticleListSQL.selectColumns)
                \(ArticleListSQL.standardFromJoin)
                WHERE \(whereClauses.joined(separator: " AND "))
                ORDER BY COALESCE(a.publishedAt, a.arrivedAt) DESC, a.arrivedAt DESC
                LIMIT ?
                """, arguments: arguments)
        }
```

- [ ] **Step 5: Tests laufen lassen, GREEN bestätigen**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteTimelineStoreTests -parallel-testing-enabled NO`
Expected: PASS (alle bestehenden Tests + neuer `timelineArticlesLiefertFaviconURLDesFeedsMit`)

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteArticleDatabaseTests -parallel-testing-enabled NO`
Expected: PASS (u. a. `articleDatabaseBietetBreiteFetchAPIWieNetNewsWire`,
`newestUnreadLiefertFaviconURLDesFeedsMit`)

- [ ] **Step 6: Committen**

```bash
git add Feedivo/Stores/TimelineStore.swift Feedivo/Stores/ArticleDatabase.swift FeedivoTests/SQLiteTimelineStoreTests.swift
git commit -m "$(cat <<'EOF'
Refactor: TimelineStore/ArticleDatabase nutzen ArticleListSQL statt eigener SELECT-Kopie, fehlende Favicon-Testabdeckung in TimelineStore ergaenzt (Finding 1.8)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: `ArticleExportSanitizing` — gemeinsamer HTML-/Link-/Datums-Helfer anlegen

**Files:**
- Create: `Feedivo/Services/ArticleExportSanitizing.swift`
- Test: `FeedivoTests/ArticleExportSanitizingTests.swift`

**Interfaces:**
- Produces: `enum ArticleExportSanitizing { static func escapedHTML(_ text: String) -> String;
  static func escapedHTMLAttribute(_ text: String) -> String; static func
  isSafeLinkTarget(_ value: String) -> Bool; static let publishedDateFormatter:
  ISO8601DateFormatter }` — wird von Task 5 und Task 6 referenziert.

- [ ] **Step 1: Fehlschlagende Tests schreiben**

Erstelle `FeedivoTests/ArticleExportSanitizingTests.swift`:

```swift
import Foundation
import Testing
@testable import Feedivo

struct ArticleExportSanitizingTests {
    @Test func escapedHTMLEscaptKaufmannsUndUndSpitzklammernAberKeineAnfuehrungszeichen() {
        let result = ArticleExportSanitizing.escapedHTML(#"Swift & "RSS" <Reader>"#)

        #expect(result == #"Swift &amp; "RSS" &lt;Reader&gt;"#)
    }

    @Test func escapedHTMLAttributeEscaptZusaetzlichAnfuehrungszeichenUndApostroph() {
        let result = ArticleExportSanitizing.escapedHTMLAttribute(#""quoted" & 'single'"#)

        #expect(result == "&quot;quoted&quot; &amp; &#39;single&#39;")
    }

    @Test func isSafeLinkTargetAkzeptiertHttpHttpsUndMailtoUnabhaengigVonGrossKleinschreibung() {
        #expect(ArticleExportSanitizing.isSafeLinkTarget("https://example.com"))
        #expect(ArticleExportSanitizing.isSafeLinkTarget("HTTP://example.com"))
        #expect(ArticleExportSanitizing.isSafeLinkTarget("mailto:test@example.com"))
    }

    @Test func isSafeLinkTargetLehntGefaehrlicheSchemataUndUngueltigeEingabenAb() {
        #expect(!ArticleExportSanitizing.isSafeLinkTarget("javascript:alert(1)"))
        #expect(!ArticleExportSanitizing.isSafeLinkTarget("data:text/html,alert(1)"))
        #expect(!ArticleExportSanitizing.isSafeLinkTarget("file:///etc/passwd"))
        #expect(!ArticleExportSanitizing.isSafeLinkTarget(""))
    }

    @Test func publishedDateFormatterFormatiertAlsISO8601MitZeitzone() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        let result = ArticleExportSanitizing.publishedDateFormatter.string(from: date)

        #expect(result == "2023-11-14T22:13:20Z")
    }
}
```

- [ ] **Step 2: Tests laufen lassen, RED bestätigen**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ArticleExportSanitizingTests -parallel-testing-enabled NO`
Expected: FAIL (Build-Fehler: "cannot find 'ArticleExportSanitizing' in scope")

- [ ] **Step 3: `ArticleExportSanitizing.swift` implementieren**

Erstelle `Feedivo/Services/ArticleExportSanitizing.swift`:

```swift
import Foundation

/// Gemeinsamer HTML-Escaping-/Link-Filter-/Datums-Helfer für den Artikel-Export
/// (HTML/PDF-Pfad). Vorher war `escapedHTML`/`escapedHTMLAttribute`/`isSafeLinkTarget`/
/// `publishedDateFormatter` 3-fach unabhängig implementiert und teilweise bereits
/// auseinandergelaufen: `ArticleDocumentExportRenderers.swift`s alte lokale Kopie escapte
/// zusätzlich `"` in normalem Text-Content. Diese kanonische Version übernimmt bewusst das
/// schlankere Verhalten (Attribut-Escaping bleibt `escapedHTMLAttribute` vorbehalten).
enum ArticleExportSanitizing {
    static func escapedHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    static func escapedHTMLAttribute(_ text: String) -> String {
        escapedHTML(text)
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    static func isSafeLinkTarget(_ value: String) -> Bool {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased()
        else {
            return false
        }

        return ["http", "https", "mailto"].contains(scheme)
    }

    static let publishedDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
```

- [ ] **Step 4: Tests laufen lassen, GREEN bestätigen**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ArticleExportSanitizingTests -parallel-testing-enabled NO`
Expected: PASS

- [ ] **Step 5: Committen**

```bash
git add Feedivo/Services/ArticleExportSanitizing.swift FeedivoTests/ArticleExportSanitizingTests.swift
git commit -m "$(cat <<'EOF'
Refactor: ArticleExportSanitizing als gemeinsamer HTML-/Link-/Datums-Helfer angelegt (Finding 1.9, Vorbereitung)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: `ArticleExportService.swift` — beide Enums auf `ArticleExportSanitizing` umstellen

**Files:**
- Modify: `Feedivo/Services/ArticleExportService.swift` (Enum `ArticleExportService`, Zeilen
  ~83-698; Enum `ArticleExportPreviewRenderer`, Zeilen ~699-875)
- Test: `FeedivoTests/ArticleExportServiceTests.swift` (bestehende Suite, dient als
  Regressionsnetz)

**Interfaces:**
- Consumes: `ArticleExportSanitizing.escapedHTML`, `.escapedHTMLAttribute`,
  `.isSafeLinkTarget`, `.publishedDateFormatter` (Task 4)

Beide Enums in dieser Datei haben je eine eigene lokale Kopie von `escapedHTML`/
`escapedHTMLAttribute` (Enum `ArticleExportService` zusätzlich `isSafeLinkTarget` und
`publishedDateFormatter`). Da beide Enums viele Aufrufstellen haben (u. a. Zeilen 233, 260,
268-271, 277, 456, 478, 505, 520, 532, 815, 860), wird hier bewusst der Compiler als
Vollständigkeits-Check genutzt statt jede Zeile einzeln aufzulisten — nach dem Löschen der
lokalen Definitionen meldet `xcodebuild build` jede verbliebene unqualifizierte Aufrufstelle
als Fehler.

- [ ] **Step 1: Lokale Definitionen in Enum `ArticleExportService` entfernen**

Lösche in `Feedivo/Services/ArticleExportService.swift` innerhalb des Enums
`ArticleExportService` (beginnt Zeile ~83) folgende vier Deklarationen vollständig:
- `private static func isSafeLinkTarget(_ value: String) -> Bool { ... }` (aktuell ~559-567)
- `private static func escapedHTML(_ text: String) -> String { ... }` (aktuell ~642-647)
- `private static func escapedHTMLAttribute(_ text: String) -> String { ... }` (aktuell ~649-653)
- `private static let publishedDateFormatter: ISO8601DateFormatter = { ... }()` (aktuell ~283-287)

Lasse `isSafeImageSource` (aktuell ~569-577) unverändert stehen — nicht Teil dieser
Konsolidierung.

- [ ] **Step 2: Lokale Definitionen in Enum `ArticleExportPreviewRenderer` entfernen**

Lösche im selben File innerhalb des Enums `ArticleExportPreviewRenderer` (beginnt Zeile
~699) folgende zwei Deklarationen vollständig:
- `private static func escapedHTML(_ text: String) -> String { ... }` (aktuell ~863-868)
- `private static func escapedHTMLAttribute(_ text: String) -> String { ... }` (aktuell ~870-874)

- [ ] **Step 3: Build laufen lassen, alle Fehlerstellen sammeln**

Run: `xcodebuild build -scheme Feedivo -destination 'platform=macOS'`
Expected: FAIL mit einer Liste von "cannot find 'escapedHTML'/'escapedHTMLAttribute'/
'isSafeLinkTarget'/'publishedDateFormatter' in scope"-Fehlern — eine pro verbliebener
Aufrufstelle in beiden Enums.

- [ ] **Step 4: Jede gemeldete Aufrufstelle auf `ArticleExportSanitizing.` umstellen**

Für jede vom Compiler gemeldete Zeile: `escapedHTML(` → `ArticleExportSanitizing.escapedHTML(`,
`escapedHTMLAttribute(` → `ArticleExportSanitizing.escapedHTMLAttribute(`,
`isSafeLinkTarget(` → `ArticleExportSanitizing.isSafeLinkTarget(`,
`publishedDateFormatter` → `ArticleExportSanitizing.publishedDateFormatter`. Betrifft u. a.
(Stand vor dieser Umstellung, exakte Zeilen können durch Step 1/2 leicht verschoben sein):
Zeilen 233, 260, 268, 269, 271, 277 (`ArticleExportService.metadataLines`/
`htmlMetadataParagraphs`), 456, 478, 505, 520, 532 (`ArticleExportService`s
HTML-Sanitizing-Pipeline), 815, 860 (`ArticleExportPreviewRenderer`).

- [ ] **Step 5: Build erneut laufen lassen, Erfolg bestätigen**

Run: `xcodebuild build -scheme Feedivo -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Tests laufen lassen, GREEN bestätigen**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ArticleExportServiceTests -parallel-testing-enabled NO`
Expected: PASS (alle bestehenden Tests, insbesondere `htmlExportEscapedTitelUndMetadaten`,
`htmlExportRendertUnsichereMetadatenLinksNurAlsText`, `htmlExportErhaeltSichereArtikelbilder`,
`markdownVorschauRendertBlockMarkdownAlsHTML` — decken beide umgestellten Enums ab)

- [ ] **Step 7: Committen**

```bash
git add Feedivo/Services/ArticleExportService.swift
git commit -m "$(cat <<'EOF'
Refactor: ArticleExportService.swift nutzt ArticleExportSanitizing statt 2x eigener Escaping-Kopie (Finding 1.9)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: `ArticleDocumentExportRenderers.swift` umstellen + PDF-Link-Filter-Regressionstest ergänzen

**Files:**
- Modify: `Feedivo/Services/ArticleDocumentExportRenderers.swift` (Enum
  `ArticlePDFExportRenderer`, Zeilen ~28-459)
- Test: `FeedivoTests/ArticleExportServiceTests.swift` (neuer Test + bestehende Suite als
  Regressionsnetz)

**Interfaces:**
- Consumes: `ArticleExportSanitizing.escapedHTML`, `.escapedHTMLAttribute`,
  `.isSafeLinkTarget`, `.publishedDateFormatter` (Task 4)

Der Review fordert explizit ergänzende Tests für `ArticlePDFExportRenderer.data(for:options:)`
und `ArticleDOCXExportRenderer.data(for:options:)`. Für DOCX existiert bereits eine passende
Testabdeckung (`docxExportErzeugtOpenXMLDokumentMitArtikeltext` prüft `&`-Escaping und
Script-Tag-Filterung) — DOCX rendert über `ArticleExportService.text(for:options: .plainText)`
und hat keine HTML-Anchor-/Link-Schema-Logik, daher kein zusätzlicher Test nötig. Für PDF
fehlt eine direkte Prüfung der Link-Schema-Filterung (`isSafeLinkTarget`) — die wird hier
über die bereits öffentliche, direkt testbare `ArticlePDFExportRenderer.html(for:options:
style:assets:)`-Methode ergänzt (mirror von `htmlExportRendertUnsichereMetadatenLinksNurAlsText`
aus `ArticleExportServiceTests.swift:179`).

- [ ] **Step 1: Regressionstest für PDF-Link-Filterung schreiben**

Füge in `FeedivoTests/ArticleExportServiceTests.swift` direkt nach
`pdfHTMLEnthaeltReaderHeaderUndSichtbareMetadaten` (nach Zeile 411) ein:

```swift

    @Test func pdfHTMLRendertUnsichereMetadatenLinksNurAlsText() {
        let snapshot = ArticleExportSnapshot(
            sqliteSnapshot: makeReaderSnapshot(
                title: "Unsicherer Link",
                link: "javascript:alert(1)",
                content: "<p>Artikeltext</p>"
            )
        )

        let html = ArticlePDFExportRenderer.html(
            for: snapshot,
            options: ArticleExportOptions(format: .pdf, includesMetadata: true),
            style: .default,
            assets: []
        )

        #expect(!html.contains("href=\"javascript:alert(1)\""))
        #expect(html.contains("<strong>Link:</strong> javascript:alert(1)"))
    }
```

- [ ] **Step 2: Test laufen lassen, bestätigen dass er bereits PASST (Charakterisierungstest)**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ArticleExportServiceTests -parallel-testing-enabled NO`
Expected: PASS — `isSafeLinkTarget` filtert bereits vor der Umstellung korrekt (Zeile 362 im
noch unrefactorten Code), dieser Test ist ein Charakterisierungstest, der die anschließende
Umstellung auf `ArticleExportSanitizing` absichert und die vom Review geforderte
Testabdeckung schließt.

- [ ] **Step 3: Lokale Definitionen in `ArticlePDFExportRenderer` entfernen**

Lösche in `Feedivo/Services/ArticleDocumentExportRenderers.swift` innerhalb des Enums
`ArticlePDFExportRenderer` (beginnt Zeile ~28) folgende vier Deklarationen vollständig:
- `private static func escapedHTML(_ text: String) -> String { ... }` (aktuell ~403-409)
- `private static func escapedHTMLAttribute(_ text: String) -> String { ... }` (aktuell ~411-413)
- `private static func isSafeLinkTarget(_ value: String) -> Bool { ... }` (aktuell ~415-422)
- `private static let publishedDateFormatter: ISO8601DateFormatter = { ... }()` (aktuell ~425-429)

Lasse `ArticleDOCXExportRenderer` (beginnt Zeile ~460, `escapedXML`) unverändert — eigenes,
XML-spezifisches Escaping-Schema, nicht Teil dieser Konsolidierung.

- [ ] **Step 4: Build laufen lassen, Fehlerstellen sammeln**

Run: `xcodebuild build -scheme Feedivo -destination 'platform=macOS'`
Expected: FAIL mit "cannot find 'escapedHTML'/'escapedHTMLAttribute'/'isSafeLinkTarget'/
'publishedDateFormatter' in scope"-Fehlern in `ArticlePDFExportRenderer` (u. a. Zeilen 320,
324, 350, 354, 358, 362, 363, 365, 371 vor dieser Umstellung).

- [ ] **Step 5: Jede gemeldete Aufrufstelle auf `ArticleExportSanitizing.` umstellen**

Analog zu Task 5 Step 4: `escapedHTML(` → `ArticleExportSanitizing.escapedHTML(`,
`escapedHTMLAttribute(` → `ArticleExportSanitizing.escapedHTMLAttribute(`,
`isSafeLinkTarget(` → `ArticleExportSanitizing.isSafeLinkTarget(`,
`publishedDateFormatter` → `ArticleExportSanitizing.publishedDateFormatter`.

- [ ] **Step 6: Build erneut laufen lassen, Erfolg bestätigen**

Run: `xcodebuild build -scheme Feedivo -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Tests laufen lassen, GREEN bestätigen**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ArticleExportServiceTests -parallel-testing-enabled NO`
Expected: PASS — alle bestehenden PDF-Tests (`pdfExportErzeugtGueltigePDFDaten`,
`pdfHTMLVerwendetReaderTypografieUndEingebetteteBilder`,
`pdfHTMLEnthaeltReaderHeaderUndSichtbareMetadaten`,
`pdfExportPaginatesLangeArtikelUeberMehrereSeiten`,
`pdfExportBehältLesereihenfolgeUndStartetObenAufErsterSeite`,
`pdfPaketLaedtArtikelbilderAutomatischUndBleibtEinPDFDokument`) sowie der neue
`pdfHTMLRendertUnsichereMetadatenLinksNurAlsText`. Beachte die dokumentierte
Verhaltensänderung aus Global Constraints Punkt 3 (kein Test erwartet mehr escaptes `"` in
reinem Text-Content von `ArticlePDFExportRenderer`).

- [ ] **Step 8: Committen**

```bash
git add Feedivo/Services/ArticleDocumentExportRenderers.swift FeedivoTests/ArticleExportServiceTests.swift
git commit -m "$(cat <<'EOF'
Refactor: ArticlePDFExportRenderer nutzt ArticleExportSanitizing statt eigener Escaping-Kopie, PDF-Link-Filter-Regressionstest ergaenzt (Finding 1.9)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Self-Review (vom Autor dieses Plans durchgeführt)

**1. Spec-Abdeckung:**
- Finding 1.8 (SQL-Konsolidierung): Task 1-3 decken alle 6 real bestätigten Duplikations-
  stellen ab (die vom Review fälschlich mitgezählte 7. Stelle — `readerArticle` — gehört zu
  einem anderen Snapshot-Typ und wird korrekt ausgeklammert, siehe "Vorab-Verifikation").
- Finding 1.9 (HTML-Escaping-Konsolidierung): Task 4-6 decken alle 3 real bestätigten
  Duplikationsstellen ab (`ArticleExportService`-Enum, `ArticleExportPreviewRenderer`-Enum,
  `ArticlePDFExportRenderer`-Enum). Die vom Review geforderten Tests für `isSafeLinkTarget`,
  `escapedHTML`, `ArticlePDFExportRenderer.data(for:options:)` sind in Task 4 + Task 6
  abgedeckt; `ArticleDOCXExportRenderer.data(for:options:)` hatte bereits ausreichende
  Testabdeckung (siehe Task 6, Einleitungstext) — bewusst kein Duplikat-Test ergänzt (YAGNI).
- `publishedDateFormatter`-Duplikation (im Review nur als Line-Referenz genannt, nicht
  explizit im Fix-Text gefordert) wird in Task 4-6 als Nebenprodukt mitkonsolidiert, da
  trivial und risikofrei.
- `isSafeImageSource` und `escapedXML` (DOCX) bewusst außerhalb des Scopes belassen — nicht
  dupliziert bzw. strukturell eigenständig, siehe Global Constraints.

**2. Placeholder-Scan:** Keine "TBD"/"implement later"/generische Fehlerbehandlungs-
Platzhalter gefunden. Task 5/Task 6 Step 4 verzichten bewusst auf eine erschöpfende
Zeile-für-Zeile-Auflistung alter Aufrufstellen (stattdessen: Compiler-gestützte
Vollständigkeitsprüfung) — das ist eine explizite Methodik-Entscheidung, keine Lücke: die
exakten Zeilennummern würden durch Task 5 selbst ohnehin verschoben, bevor Task 6 startet,
und der Compiler kann hier zuverlässiger prüfen als eine hartcodierte Zeilenliste.

**3. Typ-Konsistenz:** `ArticleListSQL.selectColumns`/`.standardFromJoin` (Task 1) werden in
Task 2/3 identisch referenziert. `ArticleExportSanitizing.escapedHTML`/`.escapedHTMLAttribute`/
`.isSafeLinkTarget`/`.publishedDateFormatter` (Task 4) werden in Task 5/6 identisch
referenziert. Keine Signatur-Abweichungen gefunden.
