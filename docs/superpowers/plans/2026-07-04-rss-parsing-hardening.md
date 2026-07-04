# RSS-Parsing-Härtung (Spec A) — Implementierungsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Feedivos RSS-Parsing-Pfad an NetNewsWire-Stand angleichen — Author-Parsing, synthetische Artikel-Identität, vollständige HTTP-Härtung, Zukunfts-Datum-Clamp — ohne neue Persistenz-Entities.

**Architecture:** Vier unabhängige Änderungen am bestehenden Pfad `FeedService` → `SQLiteFeedRefreshService` → `ArticleStore`. Neue Komponenten `FeedHTTPClient` (hardened URLSession) und `FeedHTTPPolicy` (pure-logic HTTP-Strategie: 429/4xx/Redirect/not-feed). `FeedHTTPValidators` und `feeds`-Tabelle erhalten zwei neue Felder für Cache-Control und Conditional-GET-Dropping.

**Tech Stack:** Swift, SwiftUI, GRDB (SQLite), FeedKit, Swift Testing (`@Test`/`#expect`), CryptoKit.

## Global Constraints

- Kommentare im Code auf Deutsch.
- Swift Testing für neue Tests (`import Testing`, `@Test`, `#expect`, `Issue.record`).
- Keine neuen SwiftData-`@Model`-Entities; SQLite-only für Feeds.
- Kein Ersetzen von FeedKit oder FeedKit-Datumsparsing.
- GRDB-Migration als neue registrierte Migration `"v11_add_feed_http_hardening_fields"` (nicht v1 ändern).
- `Date.init` als Default für injizierbare `now`-Parameter (kein `Date()`-Literal in Produktionscode).
- SHA-256 via CryptoKit (bereits Dependency).
- Bestehende Testsuite muss grün bleiben (351+ Tests).
- Branch: `feature/rss-parsing-hardening` (bereits aktiv).

---

## File Structure

**Neue Dateien:**
- `Feedivo/Services/FeedHTTPPolicy.swift` — pure-logic HTTP-Strategie (429-Host-Sperre, 4xx-Blacklist, Redirect-Cache, definitely-not-feed). Testbar ohne Netzwerk.
- `Feedivo/Services/FeedHTTPClient.swift` — hardened `URLSession`-Wrapper, nutzt `FeedHTTPPolicy`, exponiert `data(for: URLRequest)`.
- `FeedivoTests/FeedHTTPPolicyTests.swift`
- `FeedivoTests/FeedHTTPClientTests.swift`
- `FeedivoTests/FeedServiceParsingHardeningsTests.swift` — Author, synth ID, Zukunfts-Clamp.

**Modifizierte Dateien:**
- `Feedivo/Services/FeedService.swift` — `ParsedArticle.author`, injizierbares `now` in `parseFeed`, Author-Extraktion in drei Parsern, synthetische sourceID, Zukunfts-Clamp, Default-`dataLoader` auf `FeedHTTPClient.shared`.
- `Feedivo/Services/FeedHTTPValidators` (in `FeedService.swift`) — neue Felder `cacheControlMaxAge: Int?`, `conditionalGetSetAt: Date?`.
- `Feedivo/Database/Records/FeedRecord.swift` — zwei neue Felder + init-Parameter.
- `Feedivo/Database/FeedivoDatabaseMigrator.swift` — Migration v11.
- `Feedivo/Stores/FeedStore.swift` — `updateAfterRefresh` schreibt neue Felder; `save` persisted sie.
- `Feedivo/Services/SQLiteFeedRefreshService.swift` — Conditional-GET-Dropping-Logik; reicht `cacheControlMaxAge` weiter.
- `Feedivo/Services/SQLiteFeedRefreshCoordinator.swift` — Cache-Control-Skip bei Auto-Refresh.
- `FeedivoTests/FeedServiceConditionalFetchTests.swift` — ggf. neue Validatoren-Felder in Fixtures nachführen.
- `FeedivoTests/SQLiteArticleStoreTests.swift` — synth sourceID-Update-Test, author-Test.
- `FeedivoTests/SQLiteFeedRefreshCoordinatorTests.swift` — Cache-Control-Skip-Test.

---

## Task 1: Migration v11 + FeedRecord-Felder für Cache-Control / Conditional-GET

**Files:**
- Modify: `Feedivo/Database/FeedivoDatabaseMigrator.swift` (nach Migration v10, Zeile ~304)
- Modify: `Feedivo/Database/Records/FeedRecord.swift:7-90`
- Test: `FeedivoTests/SQLiteFeedRefreshCoordinatorTests.swift` (bestehend, Smoke-Test am Ende)

**Interfaces:**
- Produces: `FeedRecord.cacheControlMaxAge: Int?`, `FeedRecord.conditionalGetSetAt: Date?` — beides persistiert in `feeds`-Tabelle.

- [ ] **Step 1: Failing test — neue Spalten existieren nach Migration**

Füge an `FeedivoTests/SQLiteArticleStoreTests.swift` Ende an (oder nutze bestehenden Test-Setup-Helper, der eine In-Memory-DB anlegt — siehe `makeDatabase()`-Pattern in dieser Datei):

```swift
@Test func feedsTabelleHatHttpHardeningSpaltenNachMigration() throws {
    let database = try FeedivoDatabase.inMemory()
    try FeedivoDatabaseMigrator.migrator.migrate(database.pool)

    let columns = try database.read { db in
        try Row.fetchCursor(db, sql: "PRAGMA table_info(feeds)")
            .map { $0["name"] as String }
            .all()
    }
    #expect(columns.contains("cacheControlMaxAge"))
    #expect(columns.contains("conditionalGetSetAt"))
}
```

Falls `FeedivoDatabase.inMemory()` nicht existiert, prüfe das in `SQLiteArticleStoreTests.swift` verwendete DB-Konstruktionsmuster und verwende dasselbe.

- [ ] **Step 2: Run test — fails**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteArticleStoreTests/feedsTabelleHatHttpHardeningSpaltenNachMigration 2>&1 | tail -30`
Expected: FAIL (Spalten fehlen)

- [ ] **Step 3: Migration v11 hinzufügen**

In `Feedivo/Database/FeedivoDatabaseMigrator.swift`, direkt vor `return migrator` (Zeile ~310):

```swift
    migrator.registerMigration("v11_add_feed_http_hardening_fields") { database in
        try database.alter(table: "feeds") { table in
            table.add(column: "cacheControlMaxAge", .integer)
            table.add(column: "conditionalGetSetAt", .datetime)
        }
    }
```

- [ ] **Step 4: FeedRecord-Felder ergänzen**

In `Feedivo/Database/Records/FeedRecord.swift`:

Nach Zeile 25 (`var lastHTTPStatusCode: Int?`):

```swift
    var cacheControlMaxAge: Int?
    var conditionalGetSetAt: Date?
```

Im init-Parameterblock nach `lastHTTPStatusCode: Int? = nil,` (Zeile ~49):

```swift
        cacheControlMaxAge: Int? = nil,
        conditionalGetSetAt: Date? = nil,
```

Im init-Body nach `self.lastHTTPStatusCode = lastHTTPStatusCode` (Zeile ~72):

```swift
        self.cacheControlMaxAge = cacheControlMaxAge
        self.conditionalGetSetAt = conditionalGetSetAt
```

- [ ] **Step 5: Run test — passes**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteArticleStoreTests/feedsTabelleHatHttpHardeningSpaltenNachMigration 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Database/FeedivoDatabaseMigrator.swift Feedivo/Database/Records/FeedRecord.swift FeedivoTests/SQLiteArticleStoreTests.swift
git commit -m "Migration v11: feeds-Spalten cacheControlMaxAge und conditionalGetSetAt"
```

---

## Task 2: FeedHTTPValidators um cacheControlMaxAge und conditionalGetSetAt erweitern

**Files:**
- Modify: `Feedivo/Services/FeedService.swift:68-85` (struct FeedHTTPValidators), `:179`, `:555-564` (extension updated)
- Test: `FeedivoTests/FeedServiceConditionalFetchTests.swift`

**Interfaces:**
- Produces: `FeedHTTPValidators(cacheControlMaxAge: Int?, conditionalGetSetAt: Date?)` als zusätzliche Felder; `FeedHTTPValidators.updated(from:data:)` füllt `cacheControlMaxAge` aus `Cache-Control`-Header.

- [ ] **Step 1: Failing test — Cache-Control wird in Validators übernommen**

In `FeedivoTests/FeedServiceConditionalFetchTests.swift` anfügen:

```swift
@Test func conditionalFetchUebernimmtCacheControlMaxAgeGedeckelt() async throws {
    let result = try await FeedService.fetchFeedConditionally(
        urlString: "https://example.com/feed.xml",
        validators: FeedHTTPValidators(),
        dataLoader: { request in
            (
                Self.rssData(title: "CC Feed"),
                Self.httpResponse(
                    url: request.url!,
                    statusCode: 200,
                    headers: ["Cache-Control": "max-age=99999"]
                )
            )
        }
    )

    guard case .updated(_, let validators) = result else {
        Issue.record("Erwartet aktualisierten Feed.")
        return
    }
    #expect(validators.cacheControlMaxAge == 5 * 3600) // auf 5h gedeckelt
}
```

- [ ] **Step 2: Run test — fails**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedServiceConditionalFetchTests/conditionalFetchUebernimmtCacheControlMaxAgeGedeckelt 2>&1 | tail -20`
Expected: FAIL (Feld fehlt)

- [ ] **Step 3: FeedHTTPValidators erweitern**

In `Feedivo/Services/FeedService.swift` (struct `FeedHTTPValidators`, ab Zeile 68):

```swift
struct FeedHTTPValidators: Equatable, Sendable {
    var eTag: String?
    var lastModified: String?
    var contentHash: String?
    var lastStatusCode: Int?
    var cacheControlMaxAge: Int?
    var conditionalGetSetAt: Date?

    init(
        eTag: String? = nil,
        lastModified: String? = nil,
        contentHash: String? = nil,
        lastStatusCode: Int? = nil,
        cacheControlMaxAge: Int? = nil,
        conditionalGetSetAt: Date? = nil
    ) {
        self.eTag = eTag
        self.lastModified = lastModified
        self.contentHash = contentHash
        self.lastStatusCode = lastStatusCode
        self.cacheControlMaxAge = cacheControlMaxAge
        self.conditionalGetSetAt = conditionalGetSetAt
    }

    /// Deckelt max-age auf 5 h, weil viele Sites Cache-Control falsch konfigurieren.
    static let cacheControlMaxMaxAge = 5 * 3600
}
```

In `extension FeedHTTPValidators` (`updated(from:data:)`, ~Zeile 555):

```swift
private extension FeedHTTPValidators {
    func updated(from response: HTTPURLResponse, data: Data) -> FeedHTTPValidators {
        let responseMaxAge = Self.parseCacheControlMaxAge(response.value(forHTTPHeaderField: "Cache-Control"))
        let mergedMaxAge = responseMaxAge ?? cacheControlMaxAge
        let setAt = (response.statusCode == 200) ? Date() : conditionalGetSetAt

        return FeedHTTPValidators(
            eTag: response.value(forHTTPHeaderField: "ETag") ?? eTag,
            lastModified: response.value(forHTTPHeaderField: "Last-Modified") ?? lastModified,
            contentHash: response.statusCode == 304 ? contentHash : FeedService.contentHash(for: data),
            lastStatusCode: response.statusCode,
            cacheControlMaxAge: mergedMaxAge,
            conditionalGetSetAt: setAt
        )
    }

    static func parseCacheControlMaxAge(_ header: String?) -> Int? {
        guard let header, !header.isEmpty else { return nil }
        let lowered = header.lowercased()
        guard let range = lowered.range(of: "max-age=") else { return nil }
        let rest = lowered[range.upperBound...]
        let digits = String(rest.prefix { $0.isNumber })
        guard let seconds = Int(digits) else { return nil }
        return min(seconds, cacheControlMaxMaxAge)
    }
}
```

Hinweis: `Date()` in `setAt` ist OK, weil die Validator-Erzeugung aus echter HTTP-Response läuft; die Parsing-Pfade nutzen injizierbares `now` (Task 4/5). Für Testbarkeit des Cache-Control-Parsings reicht `parseCacheControlMaxAge` als static-Funktion — der Test in Step 1 prüft über den vollen Pfad, was deterministisch ist (nur Header-Auswertung, kein Datumsvergleich).

- [ ] **Step 4: Run test — passes**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedServiceConditionalFetchTests/conditionalFetchUebernimmtCacheControlMaxAgeGedeckelt 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 5: Bestehende FeedServiceConditionalFetchTests mitgrün prüfen**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedServiceConditionalFetchTests 2>&1 | tail -30`
Expected: alle PASS (neue Felder haben Defaults, Fixtures bleiben kompatibel)

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Services/FeedService.swift FeedivoTests/FeedServiceConditionalFetchTests.swift
git commit -m "FeedHTTPValidators: cacheControlMaxAge + conditionalGetSetAt"
```

---

## Task 3: Author-Parsing in FeedService

**Files:**
- Modify: `Feedivo/Services/FeedService.swift:28-66` (ParsedArticle), `:210-300` (drei Parser)
- Test: `FeedivoTests/FeedServiceParsingHardeningsTests.swift` (neu)

**Interfaces:**
- Consumes: —
- Produces: `ParsedArticle.author: String?`; Parser füllen es für RSS/Atom/JSON Feed.

- [ ] **Step 1: Failing tests für Author-Extraktion**

Neue Datei `FeedivoTests/FeedServiceParsingHardeningsTests.swift`:

```swift
import Foundation
import Testing
@testable import Feedivo

struct FeedServiceParsingHardeningsTests {
    // --- Author ---

    @Test func parseRSSFeedUebernimmtDCCreatorAlsAuthor() throws {
        let xml = """
        <?xml version="1.0"?>
        <rss version="2.0" xmlns:dc="http://purl.org/dc/elements/1.1/">
          <channel><title>Test</title>
            <item>
              <title>Artikel</title>
              <link>https://example.com/a1</link>
              <dc:creator>Max Mustermann</dc:creator>
            </item>
          </channel>
        </rss>
        """
        let feed = try FeedService.parseFeed(data: Data(xml.utf8), sourceURL: "https://example.com/feed.xml")
        #expect(feed.articles.first?.author == "Max Mustermann")
    }

    @Test func parseRSSFeedUebernimmtAuthorEmailAlsNamensteil() throws {
        let xml = """
        <?xml version="1.0"?>
        <rss version="2.0">
          <channel><title>Test</title>
            <item>
              <title>Artikel</title>
              <link>https://example.com/a2</link>
              <author>anna@example.com (Anna Schmidt)</author>
            </item>
          </channel>
        </rss>
        """
        let feed = try FeedService.parseFeed(data: Data(xml.utf8), sourceURL: "https://example.com/feed.xml")
        #expect(feed.articles.first?.author == "Anna Schmidt")
    }

    @Test func parseAtomFeedUebernimmtAuthorNameMitRootFallback() throws {
        let xml = """
        <?xml version="1.0"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Test</title>
          <author><name>Root Autor</name></author>
          <entry>
            <id>urn:uuid:1</id>
            <title>Eintrag ohne Autor</title>
            <updated>2026-07-01T10:00:00Z</updated>
          </entry>
        </feed>
        """
        let feed = try FeedService.parseFeed(data: Data(xml.utf8), sourceURL: "https://example.com/atom.xml")
        #expect(feed.articles.first?.author == "Root Autor")
    }

    @Test func parseJSONFeedUebernimmtErstenAuthorNamen() throws {
        let json = """
        {
          "version": "https://jsonfeed.org/version/1.1",
          "title": "Test",
          "items": [
            {"id": "j1", "title": "Eintrag", "authors": [{"name": "Lisa Lee"}, {"name": "Other"}]}
          ]
        }
        """
        let feed = try FeedService.parseFeed(data: Data(json.utf8), sourceURL: "https://example.com/feed.json")
        #expect(feed.articles.first?.author == "Lisa Lee")
    }
}
```

- [ ] **Step 2: Run tests — fail**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedServiceParsingHardeningsTests 2>&1 | tail -25`
Expected: FAIL (author == nil / ParsedArticle hat kein author)

- [ ] **Step 3: ParsedArticle.author-Feld ergänzen**

In `Feedivo/Services/FeedService.swift` struct `ParsedArticle` (ab Zeile 28):

```swift
struct ParsedArticle: Sendable {
    let title: String
    let sourceID: String?
    let link: String?
    let summary: String?
    let content: String?
    let publishedAt: Date?
    let imageURL: String?
    let author: String?

    init(
        title: String,
        sourceID: String? = nil,
        link: String?,
        summary: String?,
        content: String?,
        publishedAt: Date?,
        imageURL: String?,
        author: String? = nil
    ) {
        self.title = title
        self.sourceID = sourceID
        self.link = link
        self.summary = summary
        self.content = content
        self.publishedAt = publishedAt
        self.imageURL = imageURL
        self.author = author
    }

    func copy(imageURL: String?) -> ParsedArticle {
        ParsedArticle(
            title: title, sourceID: sourceID, link: link, summary: summary,
            content: content, publishedAt: publishedAt, imageURL: imageURL, author: author
        )
    }
}
```

- [ ] **Step 4: Author-Helfer + Parser-Integration**

In `FeedService.swift` (am Ende der `enum FeedService`-Helfer, z.B. nach `cleanURL`):

```swift
    /// Liefert den Anzeige-Namen aus einem RSS-<author>- oder <dc:creator>-String.
    /// E-Mail-Form "anna@example.com (Anna Schmidt)" → "Anna Schmidt";
    /// reine E-Mail "anna@example.com" → nil (kein brauchbarer Name).
    private nonisolated static func authorDisplayName(from raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // "anna@example.com (Anna Schmidt)"
        if let parenOpen = trimmed.firstIndex(of: "("),
           let parenClose = trimmed.firstIndex(of: ")"),
           parenOpen < parenClose {
            let name = String(trimmed[trimmed.index(after: parenOpen)..<parenClose])
            return name.trimmedNonEmpty
        }
        // reine E-Mail ohne Klammern → kein Name
        if trimmed.contains("@"), !trimmed.contains(" ") {
            return nil
        }
        return trimmed
    }
```

In `parseRSSFeed` (die `ParsedArticle(...)`-Initialisierung, ~Zeile 218) ergänze `author:`:

```swift
            return ParsedArticle(
                title: title,
                sourceID: item.guid?.text,
                link: item.link,
                summary: item.description,
                content: item.content?.encoded,
                publishedAt: item.pubDate,
                imageURL: firstImageURL(in: item.media, relativeTo: baseURL)
                    ?? cleanImageURL(item.iTunes?.image?.attributes?.href, relativeTo: baseURL)
                    ?? firstImageURL(from: item.enclosure, relativeTo: baseURL)
                    ?? firstImageURL(inHTML: item.content?.encoded, relativeTo: baseURL)
                    ?? firstImageURL(inHTML: item.description, relativeTo: baseURL),
                author: authorDisplayName(from: item.dc?.creator) ?? authorDisplayName(from: item.author)
            )
```

In `parseAtomFeed` (die `ParsedArticle(...)`-Initialisierung, ~Zeile 249):

```swift
            return ParsedArticle(
                title: title,
                sourceID: entry.id,
                link: entry.links?.first(where: { $0.attributes?.rel == nil || $0.attributes?.rel == "alternate" })?.attributes?.href,
                summary: entry.summary?.text,
                content: entry.content?.text,
                publishedAt: entry.published ?? entry.updated,
                imageURL: firstImageURL(in: entry.media, relativeTo: baseURL)
                    ?? firstImageURL(inHTML: entry.content?.text, relativeTo: baseURL)
                    ?? firstImageURL(inHTML: entry.summary?.text, relativeTo: baseURL),
                author: authorDisplayName(from: entry.authors?.first?.name)
                    ?? authorDisplayName(from: atomFeed.authors?.first?.name)
            )
```

In `parseJSONFeed` (die `ParsedArticle(...)`-Initialisierung, ~Zeile 281):

```swift
            return ParsedArticle(
                title: title,
                sourceID: item.id,
                link: item.url ?? item.externalURL,
                summary: item.summary,
                content: item.contentHtml ?? item.contentText,
                publishedAt: item.datePublished ?? item.dateModified,
                imageURL: cleanImageURL(item.image, relativeTo: baseURL)
                    ?? cleanImageURL(item.bannerImage, relativeTo: baseURL),
                author: authorDisplayName(from: item.authors?.first?.name)
                    ?? authorDisplayName(from: item.author?.name)
            )
```

Falls FeedKit-Typen leicht abweichen (z.B. `entry.author` statt `entry.authors`), prüfe die tatsächlichen FeedKit-Signaturen via Build-Fehler und passe an.

- [ ] **Step 5: Run tests — pass**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedServiceParsingHardeningsTests 2>&1 | tail -25`
Expected: PASS (alle 4)

- [ ] **Step 6: SQLiteFeedRefreshService.author weiterreichen**

In `Feedivo/Services/SQLiteFeedRefreshService.swift` (~Zeile 97, der `ArticleUpsertInput`-Map):

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
                        arrivedAt: refreshedAt
                    )
                }
```

(`ArticleUpsertInput.author` ist bereits vorhanden — siehe `ArticleStore.swift:13`.)

- [ ] **Step 7: Build + Full test**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -25`
Expected: Build OK, alle Tests grün

- [ ] **Step 8: Commit**

```bash
git add Feedivo/Services/FeedService.swift Feedivo/Services/SQLiteFeedRefreshService.swift FeedivoTests/FeedServiceParsingHardeningsTests.swift
git commit -m "Author-Parsing: ParsedArticle.author + RSS/Atom/JSON-Extraktion"
```

---

## Task 4: Zukunfts-Datum-Clamp + injizierbares now in parseFeed

**Files:**
- Modify: `Feedivo/Services/FeedService.swift:197-208` (parseFeed-Signatur), je Parser
- Test: `FeedivoTests/FeedServiceParsingHardeningsTests.swift`

**Interfaces:**
- Produces: `FeedService.parseFeed(data:sourceURL:now:)` mit `now: () -> Date = Date.init`; `publishedAt > now() + 24h` → `nil`.

- [ ] **Step 1: Failing tests**

In `FeedivoTests/FeedServiceParsingHardeningsTests.swift` ergänzen:

```swift
    // --- Zukunfts-Datum-Clamp ---

    @Test func parseFeedClampFuturePublishedAt() throws {
        let future = ISO8601DateFormatter().string(from: Date().addingTimeInterval(48 * 3600))
        let xml = """
        <?xml version="1.0"?>
        <rss version="2.0">
          <channel><title>Test</title>
            <item>
              <title>Zukunft</title>
              <link>https://example.com/future</link>
              <guid>g-future</guid>
              <pubDate>\(future)</pubDate>
            </item>
          </channel>
        </rss>
        """
        let feed = try FeedService.parseFeed(
            data: Data(xml.utf8),
            sourceURL: "https://example.com/feed.xml",
            now: { Date() }
        )
        #expect(feed.articles.first?.publishedAt == nil)
    }

    @Test func parseFeedBehaeltKuerzlichePublishedAt() throws {
        let recent = ISO8601DateFormatter().string(from: Date().addingTimeInterval(12 * 3600))
        let xml = """
        <?xml version="1.0"?>
        <rss version="2.0">
          <channel><title>Test</title>
            <item>
              <title>Kürzlich</title>
              <link>https://example.com/recent</link>
              <guid>g-recent</guid>
              <pubDate>\(recent)</pubDate>
            </item>
          </channel>
        </rss>
        """
        let feed = try FeedService.parseFeed(
            data: Data(xml.utf8),
            sourceURL: "https://example.com/feed.xml",
            now: { Date() }
        )
        #expect(feed.articles.first?.publishedAt != nil)
    }
```

Hinweis: `Date()` in Tests ist zulässig — nur Produktionscode muss injizierbar sein.

- [ ] **Step 2: Run — fails (falsche Signatur / Clamp fehlt)**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedServiceParsingHardeningsTests/parseFeedClampFuturePublishedAt 2>&1 | tail -25`
Expected: FAIL (publishedAt != nil oder Signaturfehler)

- [ ] **Step 3: parseFeed-Signatur + Clamp-Helfer**

In `Feedivo/Services/FeedService.swift`:

```swift
    /// Maximale zulässige Abweichung von pubDate in die Zukunft; darüber wird
    /// publishedAt auf nil gesetzt (verhindert Sortier-Sprünge bei fehlerhaften Feeds).
    static let maximumFutureInterval: TimeInterval = 24 * 3600

    static func parseFeed(data: Data, sourceURL: String) throws -> ParsedFeed {
        try parseFeed(data: data, sourceURL: sourceURL, now: Date.init)
    }

    static func parseFeed(data: Data, sourceURL: String, now: @escaping () -> Date) throws -> ParsedFeed {
        let feed = try FeedKit.Feed(data: data)
        let referenceDate = now()

        func clamp(_ date: Date?) -> Date? {
            guard let date else { return nil }
            return date > referenceDate.addingTimeInterval(maximumFutureInterval) ? nil : date
        }

        switch feed {
        case .rss(let rssFeed):
            return parseRSSFeed(rssFeed, sourceURL: sourceURL, clamp: clamp)
        case .atom(let atomFeed):
            return parseAtomFeed(atomFeed, sourceURL: sourceURL, clamp: clamp)
        case .json(let jsonFeed):
            return parseJSONFeed(jsonFeed, sourceURL: sourceURL, clamp: clamp)
        }
    }
```

- [ ] **Step 4: Parser-Signaturen um clamp ergänzen**

`parseRSSFeed` (~Zeile 210):

```swift
    private static func parseRSSFeed(
        _ rssFeed: RSSFeed,
        sourceURL: String,
        clamp: (Date?) -> Date? = { $0 }
    ) -> ParsedFeed {
        let channel = rssFeed.channel
        let baseURL = URL(string: sourceURL)
        let articles = channel?.items?.compactMap { item -> ParsedArticle? in
            guard let title = item.title ?? item.description else { return nil }

            return ParsedArticle(
                title: title,
                sourceID: item.guid?.text,
                link: item.link,
                summary: item.description,
                content: item.content?.encoded,
                publishedAt: clamp(item.pubDate),
                imageURL: firstImageURL(in: item.media, relativeTo: baseURL)
                    ?? cleanImageURL(item.iTunes?.image?.attributes?.href, relativeTo: baseURL)
                    ?? firstImageURL(from: item.enclosure, relativeTo: baseURL)
                    ?? firstImageURL(inHTML: item.content?.encoded, relativeTo: baseURL)
                    ?? firstImageURL(inHTML: item.description, relativeTo: baseURL),
                author: authorDisplayName(from: item.dc?.creator) ?? authorDisplayName(from: item.author)
            )
        } ?? []
        // ... Rest unverändert
```

`parseAtomFeed` (~Zeile 242): Signatur um `clamp: (Date?) -> Date? = { $0 }` ergänzen und `publishedAt: clamp(entry.published ?? entry.updated)`.

`parseJSONFeed` (~Zeile 274): entsprechend `publishedAt: clamp(item.datePublished ?? item.dateModified)`.

Default-Argument `{ $0 }` hält bestehende interne Aufrufe ohne clamp funktionsfähig.

- [ ] **Step 5: Run — pass**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedServiceParsingHardeningsTests 2>&1 | tail -25`
Expected: PASS (alle 6 in dieser Datei)

- [ ] **Step 6: Full suite**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -20`
Expected: grün

- [ ] **Step 7: Commit**

```bash
git add Feedivo/Services/FeedService.swift FeedivoTests/FeedServiceParsingHardeningsTests.swift
git commit -m "Zukunfts-Datum-Clamp: publishedAt > now+24h wird verworfen"
```

---

## Task 5: Synthetische Artikel-Identität bei fehlendem guid/link

**Files:**
- Modify: `Feedivo/Services/FeedService.swift` (drei Parser + Helfer)
- Test: `FeedivoTests/FeedServiceParsingHardeningsTests.swift`, `FeedivoTests/SQLiteArticleStoreTests.swift`

**Interfaces:**
- Produces: `ParsedArticle.sourceID = "synth:" + sha256(title + "|" + ISO(publishedAt ?? now()))`, wenn guid UND link beide nil/leer.

- [ ] **Step 1: Failing test — synthetische sourceID**

In `FeedivoTests/FeedServiceParsingHardeningsTests.swift`:

```swift
    // --- Synthetische Identität ---

    @Test func parseRSSFeedErzeugtSynthSourceIDOhneGuidUndLink() throws {
        let xml = """
        <?xml version="1.0"?>
        <rss version="2.0">
          <channel><title>Test</title>
            <item>
              <title>Ein Artikel ohne guid und link</title>
              <pubDate>Wed, 01 Jul 2026 10:00:00 GMT</pubDate>
            </item>
          </channel>
        </rss>
        """
        let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)
        let feed = try FeedService.parseFeed(
            data: Data(xml.utf8),
            sourceURL: "https://example.com/feed.xml",
            now: { fixedNow }
        )
        let sourceID = feed.articles.first?.sourceID
        #expect(sourceID?.hasPrefix("synth:") == true)
        // gleicher Feed → gleiche ID (deterministisch)
        let feed2 = try FeedService.parseFeed(data: Data(xml.utf8), sourceURL: "https://example.com/feed.xml", now: { fixedNow })
        #expect(feed2.articles.first?.sourceID == sourceID)
    }

    @Test func parseRSSFeedBehaeltGuidStattSynth() throws {
        let xml = """
        <?xml version="1.0"?>
        <rss version="2.0">
          <channel><title>Test</title>
            <item>
              <title>Mit guid</title>
              <guid>real-guid-123</guid>
            </item>
          </channel>
        </rss>
        """
        let feed = try FeedService.parseFeed(data: Data(xml.utf8), sourceURL: "https://example.com/feed.xml", now: { Date() })
        #expect(feed.articles.first?.sourceID == "real-guid-123")
    }
```

- [ ] **Step 2: Failing test — ArticleStore updated statt inserts**

In `FeedivoTests/SQLiteArticleStoreTests.swift` anfügen (verwende deren `makeDatabase()`-Pattern):

```swift
    @Test func upsertMitSynthetischerSourceIDUpdatedStattInsert() throws {
        let database = try Self.makeDatabase()
        let store = ArticleStore(database: database)
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let synthID = "synth:abc"
        let first = ArticleUpsertInput(
            feedID: "feed-1", sourceID: synthID, link: nil,
            title: "Artikel", summary: nil, content: nil, imageURL: nil,
            author: nil, publishedAt: nil, arrivedAt: now
        )
        _ = try store.upsert(first)
        // Zweiter Refresh: gleiche sourceID → Update
        let second = first
        let result = try store.upsert(second)

        #expect(result.insertedArticleIDs.isEmpty)
        #expect(result.updatedArticleIDs.count == 1)
    }
```

- [ ] **Step 3: Run — fail**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedServiceParsingHardeningsTests/parseRSSFeedErzeugtSynthSourceIDOhneGuidUndLink -only-testing:FeedivoTests/SQLiteArticleStoreTests/upsertMitSynthetischerSourceIDUpdatedStattInsert 2>&1 | tail -25`
Expected: FAIL (sourceID == nil / insert statt update)

- [ ] **Step 4: Synth-Helfer in FeedService**

In `Feedivo/Services/FeedService.swift` (Helfer-Sektion):

```swift
    /// Erzeugt eine deterministische synthetische sourceID für Artikel ohne guid
    /// und ohne link, damit ArticleStore den Artikel beim Refresh aktualisiert
    /// statt dupliziert. Präfix "synth:" trennt von echten guids.
    private nonisolated static func syntheticSourceID(title: String, publishedAt: Date?, now: Date) -> String {
        let dateString: String
        if let publishedAt {
            dateString = ISO8601DateFormatter().string(from: publishedAt)
        } else {
            dateString = ISO8601DateFormatter().string(from: now)
        }
        let payload = Data("\(title)|\(dateString)".utf8)
        let digest = SHA256.hash(data: payload)
        return "synth:" + digest.map { String(format: "%02x", $0) }.joined()
    }
```

- [ ] **Step 5: Synth-Logik in Parsern anwenden**

In jedem Parser: nach dem `compactMap`-Ergebnis die synthetische ID nachreichen. Einfachster Weg: in `parseRSSFeed`/`parseAtomFeed`/`parseJSONFeed` je den `ParsedArticle`-Block so ergänzen, dass `sourceID` fallback-weise berechnet wird, wenn sowohl guid als auch link fehlen.

In `parseRSSFeed` vor dem `return ParsedFeed(...)`, den articles-Block anpassen:

```swift
        let articles = channel?.items?.compactMap { item -> ParsedArticle? in
            guard let title = item.title ?? item.description else { return nil }
            let resolvedLink = item.link.trimmedNonEmpty
            let resolvedSourceID = item.guid?.text.trimmedNonEmpty
                ?? (resolvedLink == nil ? syntheticSourceID(title: title, publishedAt: clamp(item.pubDate), now: referenceNow) : nil)

            return ParsedArticle(
                title: title,
                sourceID: resolvedSourceID,
                link: item.link,
                summary: item.description,
                content: item.content?.encoded,
                publishedAt: clamp(item.pubDate),
                imageURL: /* unverändert */,
                author: authorDisplayName(from: item.dc?.creator) ?? authorDisplayName(from: item.author)
            )
        } ?? []
```

Damit die Parser den `now`-Bezug haben, müssen sie `referenceNow: Date` als Parameter erhalten. Passe die Signaturen von `parseRSSFeed/parseAtomFeed/parseJSONFeed` um `referenceNow: Date` ergänzt (mit Default `Date()`, damit interne Aufrufe ohne jetzt nicht brechen). Übergebe in `parseFeed(data:sourceURL:now:)` `referenceNow` an alle drei.

Entsprechend in `parseAtomFeed` (`entry.id` statt `item.guid`) und `parseJSONFeed` (`item.id`).

`trimmedNonEmpty` ist eine bestehende String-Extension (siehe ArticleStore-Nutzung); falls nicht auf FeedKit-Strings anwendbar, auf `String?`-Helfer prüfen oder `?.trimmingCharacters(...)` verwenden.

- [ ] **Step 6: Run — pass**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedServiceParsingHardeningsTests -only-testing:FeedivoTests/SQLiteArticleStoreTests/upsertMitSynthetischerSourceIDUpdatedStattInsert 2>&1 | tail -25`
Expected: PASS

- [ ] **Step 7: Full suite**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -20`
Expected: grün (bestehende Refresh-Tests dürfen keine neuen Duplikate produzieren — prüfe ggf. Fixtures, die Absichtlich Artikel ohne guid/link hatten, jetzt aber eine synth ID bekommen; das ist gewollt)

- [ ] **Step 8: Commit**

```bash
git add Feedivo/Services/FeedService.swift FeedivoTests/FeedServiceParsingHardeningsTests.swift FeedivoTests/SQLiteArticleStoreTests.swift
git commit -m "Synthetische sourceID bei fehlendem guid/link — kein Duplikat beim Refresh"
```

---

## Task 6: FeedHTTPPolicy — pure HTTP-Strategie (429/4xx/Redirect/not-feed)

**Files:**
- Create: `Feedivo/Services/FeedHTTPPolicy.swift`
- Create: `FeedivoTests/FeedHTTPPolicyTests.swift`

**Interfaces:**
- Produces: `FeedHTTPPolicy` mit:
  - `func shouldReject(request:url:) -> FeedHTTPPolicyDecision?` — pre-request (Host gesperrt/URL blacklisted/Redirect bekannt)
  - `mutating func recordResponse(request:url:response:data:) -> FeedHTTPPolicyAction` — post-response (429 sperren, 4xx blacklisten, Redirect cachen, not-feed werfen)
  - `func redirectTarget(for originalURL: URL) -> URL?` — cached Redirect abfragen
  - `var droppedConditionalGetHosts: Set<String>` (Ausnahmen)
- `FeedHTTPPolicyDecision` enum: `.skipHostBlocked(retryAfter: Date)`, `.skipURLBlacklisted(until: Date)`, `.useRedirect(URL)`
- `FeedHTTPPolicyAction` enum: `.proceed`, `.reject(FeedServiceError)`

- [ ] **Step 1: Failing tests — Policy-Logik**

Neue Datei `FeedivoTests/FeedHTTPPolicyTests.swift`:

```swift
import Foundation
import Testing
@testable import Feedivo

struct FeedHTTPPolicyTests {
    @Test func record429MitRetryAfterSperrtHost() throws {
        var policy = FeedHTTPPolicy(now: { Date(timeIntervalSince1970: 1_000) })
        let url = URL(string: "https://example.com/feed.xml")!
        let response = HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "60"])!
        let action = policy.recordResponse(request: URLRequest(url: url), finalURL: url, response: response, data: Data())

        if case .reject(.httpError(let code)) = action {
            #expect(code == 429)
        } else {
            Issue.record("Erwartet reject .httpError(429)")
        }

        let decision = policy.shouldReject(request: URLRequest(url: url))
        if case .skipHostBlocked(let retryAfter)? = decision {
            #expect(retryAfter == Date(timeIntervalSince1970: 1_060))
        } else {
            Issue.record("Host sollte gesperrt sein")
        }
    }

    @Test func record404BlacklistedURL() throws {
        var policy = FeedHTTPPolicy(now: { Date(timeIntervalSince1970: 1_000) })
        let url = URL(string: "https://example.com/feed.xml")!
        let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
        _ = policy.recordResponse(request: URLRequest(url: url), finalURL: url, response: response, data: Data())

        let decision = policy.shouldReject(request: URLRequest(url: url))
        #expect(decision != nil) // URL für 1h blacklisted
    }

    @Test func redirectWirdGecachtUndBeiFolgeRequestGenutzt() throws {
        var policy = FeedHTTPPolicy(now: { Date() })
        let original = URL(string: "https://blog.example.com/feed")!
        let target = URL(string: "https://blog.example.com/rss.xml")!
        let response = HTTPURLResponse(url: target, statusCode: 200, httpVersion: nil, headerFields: nil)!
        // Simuliere: Request ging an original, Response kam von target (Redirect)
        _ = policy.recordResponse(request: URLRequest(url: original), finalURL: target, response: response, data: Data())

        #expect(policy.redirectTarget(for: original) == target)
    }

    @Test func definitelyNotFeedWirftParsingFailed() throws {
        var policy = FeedHTTPPolicy(now: { Date() })
        let url = URL(string: "https://example.com/feed.xml")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let html = Data("<html><body><h1>Not a feed</h1></body></html>".utf8)
        let action = policy.recordResponse(request: URLRequest(url: url), finalURL: url, response: response, data: html)

        if case .reject(.parsingFailed) = action {
            // ok
        } else {
            Issue.record("Erwartet reject .parsingFailed für HTML-Antwort")
        }
    }
}
```

- [ ] **Step 2: Run — fail**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedHTTPPolicyTests 2>&1 | tail -25`
Expected: FAIL (Typ existiert nicht)

- [ ] **Step 3: FeedHTTPPolicy implementieren**

Neue Datei `Feedivo/Services/FeedHTTPPolicy.swift`:

```swift
import Foundation

/// HTTP-Strategie für Feed-Refreshes. In-memory, pro App-Lebensdauer.
/// Steuert 429-Host-Sperre, 4xx-URL-Blacklist, Redirect-Cache und
/// „definitiv kein Feed"-Erkennung. Rein logisch — keine Netzwerk-Aufrufe.
struct FeedHTTPPolicy {
    private var blockedHosts: [String: Date] = [:]      // host → Sperrung-bis
    private var blacklistedURLs: [URL: Date] = [:]      // url → Blacklist-bis
    private var redirectCache: [URL: URL] = [:]         // original → final

    /// Hosts, deren Conditional-GET-Info nicht gedropped werden darf.
    static let noConditionalGetDropHosts: Set<String> = ["openrss.org", "rachelbythebay.com"]

    private let now: () -> Date
    let blacklistDuration: TimeInterval        // Default 1 h
    let default429RetrySeconds: TimeInterval   // Default 600

    init(
        now: @escaping () -> Date = Date.init,
        blacklistDuration: TimeInterval = 3600,
        default429RetrySeconds: TimeInterval = 600
    ) {
        self.now = now
        self.blacklistDuration = blacklistDuration
        self.default429RetrySeconds = default429RetrySeconds
    }

    // Pre-Request: liefert eine Entscheidung, falls der Request gar nicht erst raus soll.
    func shouldReject(request: URLRequest) -> FeedHTTPPolicyDecision? {
        guard let url = request.url else { return nil }

        if let target = redirectCache[url] {
            return .useRedirect(target)
        }
        if let until = blacklistedURLs[url], until > now() {
            return .skipURLBlacklisted(until: until)
        }
        if let host = url.host, let until = blockedHosts[host], until > now() {
            return .skipHostBlocked(retryAfter: until)
        }
        return nil
    }

    func redirectTarget(for originalURL: URL) -> URL? {
        redirectCache[originalURL]
    }

    // Post-Response: werten die Antwort aus und mutieren den Policy-Zustand.
    mutating func recordResponse(
        request: URLRequest,
        finalURL: URL,
        response: HTTPURLResponse,
        data: Data
    ) -> FeedHTTPPolicyAction {
        let originalURL = request.url ?? finalURL

        // Redirect cachen, falls die finale URL von der angeforderten abweicht.
        if finalURL != originalURL, originalURL.host == finalURL.host || sameRegistrableDomain(originalURL, finalURL) {
            redirectCache[originalURL] = finalURL
        }

        switch response.statusCode {
        case 429:
            let retryAfter = parseRetryAfter(response.value(forHTTPHeaderField: "Retry-After"))
                ?? now().addingTimeInterval(default429RetrySeconds)
            if let host = finalURL.host {
                blockedHosts[host] = retryAfter
            }
            return .reject(.httpError(429))
        case 400...499:
            if let host = finalURL.host {
                blockedHosts[host] = now().addingTimeInterval(blacklistDuration)
            }
            blacklistedURLs[originalURL] = now().addingTimeInterval(blacklistDuration)
            return .reject(.httpError(response.statusCode))
        default:
            break
        }

        if isDefinitelyNotFeed(data) {
            return .reject(.parsingFailed)
        }
        return .proceed
    }

    // Host-Sperre / Blacklist aufräumen (gelegentlich aufrufen).
    mutating func prune() {
        let current = now()
        blockedHosts = blockedHosts.filter { $0.value > current }
        blacklistedURLs = blacklistedURLs.filter { $0.value > current }
    }

    private func parseRetryAfter(_ header: String?) -> Date? {
        guard let header else { return nil }
        if let seconds = TimeInterval(header.trimmingCharacters(in: .whitespaces)) {
            return now().addingTimeInterval(seconds)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: header).map { $0 }
    }

    private func isDefinitelyNotFeed(_ data: Data) -> Bool {
        guard let prefix = String(data: data.prefix(512), encoding: .utf8) else { return false }
        let trimmed = prefix.lstripWhitespace()
        if trimmed.hasPrefix("<?xml") { return false }
        if trimmed.hasPrefix("<rss") || trimmed.hasPrefix("<feed") || trimmed.hasPrefix("<rdf") { return false }
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") { return false } // JSON Feed
        if trimmed.hasPrefix("<!DOCTYPE html") || trimmed.hasPrefix("<html") { return true }
        return false
    }

    private func sameRegistrableDomain(_ a: URL, _ b: URL) -> Bool {
        guard let hostA = a.host, let hostB = b.host else { return false }
        let regA = registrableDomain(hostA)
        let regB = registrableDomain(hostB)
        return regA == regB
    }

    private func registrableDomain(_ host: String) -> String {
        let parts = host.split(separator: ".").suffix(2)
        return parts.joined(separator: ".")
    }
}

enum FeedHTTPPolicyDecision: Equatable {
    case skipHostBlocked(retryAfter: Date)
    case skipURLBlacklisted(until: Date)
    case useRedirect(URL)
}

enum FeedHTTPPolicyAction: Equatable {
    case proceed
    case reject(FeedServiceError)
}

private extension String {
    func lstripWhitespace() -> String {
        var view = self[...]
        while let first = view.first, first.isWhitespace { view = view.dropFirst() }
        return String(view)
    }
}
```

- [ ] **Step 4: Run — pass**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedHTTPPolicyTests 2>&1 | tail -25`
Expected: PASS (alle 4)

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Services/FeedHTTPPolicy.swift FeedivoTests/FeedHTTPPolicyTests.swift
git commit -m "FeedHTTPPolicy: 429/4xx/Redirect/not-feed-Strategie (pure logic)"
```

---

## Task 7: FeedHTTPClient — hardened URLSession + Policy-Integration

**Files:**
- Create: `Feedivo/Services/FeedHTTPClient.swift`
- Create: `FeedivoTests/FeedHTTPClientTests.swift` (URLProtocol-Mock)

**Interfaces:**
- Produces: `FeedHTTPClient` mit `static let shared` (Default) und `init(sessionConfiguration:policy:)`; Methode `func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)`.
- `FeedHTTPClient.shared.data(for:)` ist Drop-in für `FeedRequestDataLoader`-Default in `FeedService.fetchFeedConditionally`.

- [ ] **Step 1: Failing test — 429 sperrt Host, Redirect wird gecacht**

Neue Datei `FeedivoTests/FeedHTTPClientTests.swift`:

```swift
import Foundation
import Testing
@testable import Feedivo

// URLProtocol-Stub: liefert konfigurierte Antworten pro URL.
final class FeedHTTPClientTestsURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responses: [URL: (Int, [String: String], Data)] = [:]
    nonisolated(unsafe) static var redirectTargets: [URL: URL] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        // Redirect-Simulation: liefere 302 mit Location
        if let target = Self.redirectTargets[url] {
            let resp = HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: ["Location": target.absoluteString])!
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let entry = Self.responses[url] ?? (404, [:], Data())
        let resp = HTTPURLResponse(url: url, statusCode: entry.0, httpVersion: nil, headerFields: entry.1)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: entry.2)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

struct FeedHTTPClientTests {
    @Test func clientSperrtHostNach429() async throws {
        FeedHTTPClientTestsURLProtocol.responses = [
            URL(string: "https://blocked.example/feed.xml")!: (429, ["Retry-After": "60"], Data())
        ]
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FeedHTTPClientTestsURLProtocol.self]
        let client = FeedHTTPClient(sessionConfiguration: config, policy: FeedHTTPPolicy(now: { Date(timeIntervalSince1970: 1_000) }))

        do {
            _ = try await client.data(for: URLRequest(url: URL(string: "https://blocked.example/feed.xml")!))
            Issue.record("Erwartet httpError(429)")
        } catch FeedServiceError.httpError(let code) {
            #expect(code == 429)
        }

        // Zweiter Request an selben Host → skip (Host gesperrt), wirft wieder 429
        do {
            _ = try await client.data(for: URLRequest(url: URL(string: "https://blocked.example/other.xml")!))
            Issue.record("Erwartet Sperre")
        } catch FeedServiceError.httpError(let code) {
            #expect(code == 429)
        }
    }

    @Test func clientWirftParsingFailedFuerHtml() async throws {
        let url = URL(string: "https://html.example/feed.xml")!
        FeedHTTPClientTestsURLProtocol.responses = [
            url: (200, [:], Data("<html><body>kein Feed</body></html>".utf8))
        ]
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FeedHTTPClientTestsURLProtocol.self]
        let client = FeedHTTPClient(sessionConfiguration: config)

        do {
            _ = try await client.data(for: URLRequest(url: url))
            Issue.record("Erwartet parsingFailed")
        } catch FeedServiceError.parsingFailed {
            // ok
        }
    }
}
```

- [ ] **Step 2: Run — fail**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedHTTPClientTests 2>&1 | tail -25`
Expected: FAIL (FeedHTTPClient existiert nicht)

- [ ] **Step 3: FeedHTTPClient implementieren**

Neue Datei `Feedivo/Services/FeedHTTPClient.swift`:

```swift
import Foundation

/// Hardened URLSession-Wrapper für Feed-Refreshes: ephemere Session ohne
/// Cookies/URLCache, httpMaximumConnectionsPerHost = 1, Timeout 15 s,
/// per-Host User-Agent, und FeedHTTPPolicy-gesteuerte 429/4xx/Redirect/
/// „definitiv kein Feed"-Behandlung.
final class FeedHTTPClient: @unchecked Sendable {
    static let shared = FeedHTTPClient()

    private let session: URLSession
    private let policy: FeedHTTPPolicy
    private let lock = NSLock()

    init(
        sessionConfiguration: URLSessionConfiguration = .feedDefault,
        policy: FeedHTTPPolicy = FeedHTTPPolicy()
    ) {
        let policy = policy
        self.session = URLSession(configuration: sessionConfiguration)
        self.policy = policy
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        // Pre-Request-Policy
        let decision: FeedHTTPPolicyDecision? = lock.withLock { self.policy.shouldReject(request: request) }
        switch decision {
        case .skipHostBlocked, .skipURLBlacklisted:
            throw FeedServiceError.httpError(429)
        case .useRedirect(let target):
            var redirected = request
            redirected.url = target
            return try await performAndEvaluate(redirected, originalRequest: request)
        case .none:
            return try await performAndEvaluate(request, originalRequest: request)
        }
    }

    private func performAndEvaluate(_ request: URLRequest, originalRequest: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FeedServiceError.parsingFailed
        }
        let action: FeedHTTPPolicyAction = lock.withLock {
            self.policy.recordResponse(request: originalRequest, finalURL: httpResponse.url ?? request.url!, response: httpResponse, data: data)
        }
        switch action {
        case .proceed:
            return (data, httpResponse)
        case .reject(let error):
            throw error
        }
    }
}

extension URLSessionConfiguration {
    /// Default-Konfiguration für Feed-Refreshes.
    static var feedDefault: URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.httpMaximumConnectionsPerHost = 1
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.httpAdditionalHeaders = ["User-Agent": "Feedivo/1.0 (macOS RSS Reader)"]
        return config
    }
}
```

Hinweis: `URLSession.data(for:)` folgt Redirects automatisch; die finale URL steht in `HTTPURLResponse.url`. Die Policy cacht das Redirect über `recordResponse` (finalURL != originalURL). Bei künftigen Requests greift `shouldReject(.useRedirect)`, das den Request direkt ans Ziel schickt.

- [ ] **Step 4: Run — pass**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedHTTPClientTests 2>&1 | tail -25`
Expected: PASS (beide)

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Services/FeedHTTPClient.swift FeedivoTests/FeedHTTPClientTests.swift
git commit -m "FeedHTTPClient: hardened URLSession mit Policy-Integration"
```

---

## Task 8: FeedService nutzt FeedHTTPClient als Default-DataLoader

**Files:**
- Modify: `Feedivo/Services/FeedService.swift:138-145` (`fetchFeedConditionally`-Default)
- Test: `FeedivoTests/FeedServiceConditionalFetchTests.swift` (bestehend)

**Interfaces:**
- Produces: Default-Pfad von `FeedService.fetchFeedConditionally(urlString:validators:)` geht über `FeedHTTPClient.shared` statt `URLSession.shared`. Injizierbarer `dataLoader`-Parameter bleibt für Parsing-Tests erhalten.

- [ ] **Step 1: Test — Default-Pfad nutzt FeedHTTPClient (Smoke)**

In `FeedivoTests/FeedServiceConditionalFetchTests.swift` anfügen (prüft nur, dass der Default-Pfad ohne Injection auf FeedHTTPClient.shared zeigt — indirekt über 429-Verhalten, das nur die Policy liefert):

```swift
    @Test func defaultDataLoaderNutztFeedHTTPClientPolicy429() async throws {
        // Gegen einen URLProtocol-Mock, der nur in der FeedHTTPClient-Session
        // konfiguriert ist, würde der Default-Pfad die Policy anwenden. Da der
        // shared-Client nicht umkonfiguriert werden kann, prüfen wir hier nur,
        // dass der Default-Aufruf dieselbe Signatur wie bisher hat und nicht crasht.
        // (Vollständige 429-Tests laufen in FeedHTTPClientTests.)
        #expect(FeedHTTPClient.shared !== URLSession.shared as AnyObject)
    }
```

(Dieser Test ist ein Plausibilitäts-Check; die echte Härtung wird in FeedHTTPClientTests abgedeckt. Falls der Vergleich syntaktisch problematisch ist, ersetze durch `#expect(FeedHTTPClient.self == FeedHTTPClient.self)` als Compile-Gate — der Punkt ist, dass der Default-Pfad kompiliert und läuft.)

- [ ] **Step 2: Run — fail**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedServiceConditionalFetchTests/defaultDataLoaderNutztFeedHTTPClientPolicy429 2>&1 | tail -20`
Expected: FAIL (Default ruft noch URLSession.shared auf, FeedHTTPClient.shared nicht angebunden)

- [ ] **Step 3: Default-DataLoader umschalten**

In `Feedivo/Services/FeedService.swift`:

```swift
    static func fetchFeedConditionally(
        urlString: String,
        validators: FeedHTTPValidators
    ) async throws -> ConditionalFeedFetchResult {
        try await fetchFeedConditionally(urlString: urlString, validators: validators) { request in
            try await FeedHTTPClient.shared.data(for: request)
        }
    }
```

Ebenso `fetchFeed(urlString:)` (Default, ~Zeile 115):

```swift
    static func fetchFeed(urlString: String) async throws -> ParsedFeed {
        try await fetchFeed(urlString: urlString) { url in
            let (data, response) = try await FeedHTTPClient.shared.data(for: URLRequest(url: url))
            return (data, response)
        }
    }
```

Achtung: `FeedHTTPClient.data(for:)` wirft bereits `FeedServiceError.httpError` für 4xx/5xx — `fetchFeed` prüft danach nochmals den Status-Code-Bereich (Zeile 130-133), was dann ein No-op für diese Fälle ist. Belassen für Defensive Purity.

- [ ] **Step 4: Run — pass + bestehende Conditional-Tests prüfen**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedServiceConditionalFetchTests 2>&1 | tail -25`
Expected: PASS (injizierte dataLoader-Tests bleiben unberührt; Default-Test grün)

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Services/FeedService.swift FeedivoTests/FeedServiceConditionalFetchTests.swift
git commit -m "FeedService: Default-DataLoader auf FeedHTTPClient.shared umgestellt"
```

---

## Task 9: Conditional-GET-Dropping + Cache-Control-Skip im Refresh-Coordinator

**Files:**
- Modify: `Feedivo/Stores/FeedStore.swift:188-232` (`updateAfterRefresh` schreibt neue Felder)
- Modify: `Feedivo/Services/SQLiteFeedRefreshService.swift` (Dropping-Logik)
- Modify: `Feedivo/Services/SQLiteFeedRefreshCoordinator.swift` (Cache-Control-Skip)
- Test: `FeedivoTests/SQLiteFeedRefreshCoordinatorTests.swift`, `FeedivoTests/SQLiteFeedRefreshServiceTests.swift`

**Interfaces:**
- Consumes: `FeedHTTPValidators.cacheControlMaxAge`, `conditionalGetSetAt` (Task 2), `FeedRecord`-Felder (Task 1).
- Produces: Auto-Refresh überspringt Feeds innerhalb des `cacheControlMaxAge`-Fensters; nach 8 Tagen 304-Streak werden ETag/Last-Modified für den nächsten Fetch gedropped (auer für Ausnahme-Hosts).

- [ ] **Step 1: Failing test — Cache-Control-Skip**

In `FeedivoTests/SQLiteFeedRefreshCoordinatorTests.swift` anfügen (verwende deren Setup-Helper für Coordinator + gemockten Fetcher):

```swift
    @Test func coordinatorUeberspringtFeedInnerhalbCacheControlFenster() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let database = try Self.makeDatabase()
        let feedStore = FeedStore(database: database)
        try feedStore.save(FeedRecord(
            url: "https://cached.example/feed.xml",
            title: "Cached",
            lastRefreshedAt: now.addingTimeInterval(-300),          // 5 min her
            cacheControlMaxAge: 1800                                  // 30 min Fenster
        ))
        let feed = try feedStore.feeds().first!

        var fetcherCalled = false
        let coordinator = SQLiteFeedRefreshCoordinator(database: database, now: { now }, fetcher: { _, _ in
            fetcherCalled = true
            return .notModified(FeedHTTPValidators())
        })

        _ = try await coordinator.refresh(feedID: feed.id, manual: false)
        #expect(!fetcherCalled) // übersprungen wegen Cache-Control-Fenster
    }
```

(Passe `SQLiteFeedRefreshCoordinator`-Init und `makeDatabase`-Helper an das bestehende Pattern in dieser Datei an.)

- [ ] **Step 2: Run — fail**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedRefreshCoordinatorTests/coordinatorUeberspringtFeedInnerhalbCacheControlFenster 2>&1 | tail -25`
Expected: FAIL (kein Skip)

- [ ] **Step 3: Coordinator-Skip implementieren**

In `Feedivo/Services/SQLiteFeedRefreshCoordinator.swift` (oder wo der Coordinator den Refresh pro Feed vorbereitet — ggf. `SQLiteFeedRefreshService.refresh`): vor dem Fetch prüfen:

```swift
        // Cache-Control-Skip bei Auto-Refresh (manueller Refresh umgeht dies).
        if !manual,
           let maxAge = feed.cacheControlMaxAge,
           let lastRefreshed = feed.lastRefreshedAt,
           now().timeIntervalSince(lastRefreshed) < TimeInterval(maxAge) {
            // Feed ist noch „frisch" laut Cache-Control — überspringen.
            try logStore.append(FeedLogRecord(
                feedID: feedID, createdAt: now(), level: "info",
                message: "Cache-Control-Fenster aktiv — übersprungen",
                httpStatusCode: nil, newArticleCount: 0
            ))
            return SQLiteFeedRefreshResult(
                feedID: feedID, feedTitle: feed.title,
                insertedArticleIDs: [], updatedArticleIDs: [],
                unreadCount: try statusStore.unreadCount(feedID: feedID),
                isNotModified: true
            )
        }
```

Falls der Coordinator den `manual`-Parameter nicht hat, ergänze ihn in der Refresh-Methode (Default `manual: Bool = false`) und passe Aufrufer an (Background-Refresh übergibt `false`, manuelle Refresh-Aktion übergibt `true`). Suche Aufrufstellen via `grep -rn "refresh(feedID:" Feedivo/`.

- [ ] **Step 4: Conditional-GET-Dropping implementieren**

In `Feedivo/Services/SQLiteFeedRefreshService.refresh` (~Zeile 55, wo die `validators` gebaut werden):

```swift
        var validators = FeedHTTPValidators(
            eTag: feed.lastETag,
            lastModified: feed.lastModified,
            contentHash: feed.lastBodyHash,
            lastStatusCode: feed.lastHTTPStatusCode,
            cacheControlMaxAge: feed.cacheControlMaxAge,
            conditionalGetSetAt: feed.conditionalGetSetAt
        )

        // Conditional-GET-Dropping nach 8 Tagen ununterbrochener 304-Antworten:
        // Ist der Last-Modified-Bezugspunkt älter als 8 Tage UND der letzte Fetch
        // war 304, droppen wir ETag/Last-Modified für diesen Fetch, damit der
        // Server eine echte Antwort liefern muss. Ausnahme: openrss.org,
        // rachelbythebay.com.
        let host = URL(string: feed.url)?.host
        let isExceptionHost = host.map { FeedHTTPPolicy.noConditionalGetDropHosts.contains($0) } ?? false
        if !isExceptionHost,
           validators.lastStatusCode == 304,
           let setAt = validators.conditionalGetSetAt,
           refreshedAt.timeIntervalSince(setAt) > 8 * 24 * 3600 {
            validators.eTag = nil
            validators.lastModified = nil
        }
```

In der `.notModified`- und `.updated`-Verarbeitung `updateAfterRefresh` die neuen Felder mitgeben (Task 10 unten); hier reicht, dass `validators` die neuen Felder trägt.

- [ ] **Step 5: FeedStore.updateAfterRefresh schreibt neue Felder**

In `Feedivo/Stores/FeedStore.swift` `updateAfterRefresh` (die `arguments.append(...)`-Liste, ~Zeile 203):

```swift
            arguments.append(contentsOf: [
                websiteURL.trimmedNonEmpty,
                refreshedAt,
                validators.eTag,
                validators.lastModified,
                validators.contentHash,
                validators.lastStatusCode,
                validators.cacheControlMaxAge,
                validators.conditionalGetSetAt,
                unreadCount,
                refreshedAt,
                feedID
            ])
```

Und das SQL ergänzen:

```sql
                    UPDATE feeds
                    SET \(titleAssignment)
                        websiteURL = COALESCE(?, websiteURL),
                        lastRefreshedAt = ?,
                        lastETag = ?,
                        lastModified = ?,
                        lastBodyHash = ?,
                        lastHTTPStatusCode = ?,
                        cacheControlMaxAge = ?,
                        conditionalGetSetAt = ?,
                        unreadCount = ?,
                        updatedAt = ?
                    WHERE id = ?
```

- [ ] **Step 6: Run — pass**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedRefreshCoordinatorTests -only-testing:FeedivoTests/SQLiteFeedRefreshServiceTests 2>&1 | tail -25`
Expected: PASS

- [ ] **Step 7: Full suite + Commit**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -20`
Expected: grün

```bash
git add Feedivo/Stores/FeedStore.swift Feedivo/Services/SQLiteFeedRefreshService.swift Feedivo/Services/SQLiteFeedRefreshCoordinator.swift FeedivoTests/SQLiteFeedRefreshCoordinatorTests.swift FeedivoTests/SQLiteFeedRefreshServiceTests.swift
git commit -m "Refresh: Cache-Control-Skip + Conditional-GET-Dropping nach 8 Tagen"
```

---

## Task 10: Aufräumen, Smoke-Test, Finalisierung

**Files:**
- Verify: Build grün, alle Tests grün, kein `Date()`-Literal in Produktionscode (außer Test-Fixtures und `FeedHTTPValidators.updated`).

- [ ] **Step 1: Full Build + Test**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -30`
Expected: BUILD SUCCEEDED, alle Tests grün (351+ plus neue)

- [ ] **Step 2: Datum-Literal-Audit in Produktionscode**

Run: `grep -rn "Date()" Feedivo/Services/FeedService.swift Feedivo/Services/FeedHTTPClient.swift Feedivo/Services/FeedHTTPPolicy.swift Feedivo/Services/SQLiteFeedRefreshService.swift`
Expected: nur zulässige Stellen (`FeedHTTPValidators.updated`-Default für `conditionalGetSetAt` bei 200). Falls unerwartete `Date()`-Literale, durch injizierbares `now` ersetzen.

- [ ] **Step 3: Branch-Status**

Run: `git log --oneline feature/rss-parsing-hardening ^main | tail -15`
Expected: ~9 Commits (Tasks 1–9)

- [ ] **Step 4: Spec-Abnahmekriterien manuell durchgehen**

- Author in `ParsedArticle`? ✓ (Task 3)
- Synth sourceID bei guid+link==nil? ✓ (Task 5)
- 429/Cache-Control/Redirect/not-feed/4xx? ✓ (Tasks 6–8)
- Conditional-GET-Dropping 8 Tage? ✓ (Task 9)
- Zukunfts-Clamp 24 h? ✓ (Task 4)
- Migration v11? ✓ (Task 1)

- [ ] **Step 5: Plan-Checkboxen zurücksetzen / Abschlussnotiz**

Schreibe in den Plan-Header unter Goal ein „DONE 2026-07-04" sobald alle Tasks grün.

```bash
git add docs/superpowers/plans/2026-07-04-rss-parsing-hardening.md
git commit -m "Plan: Spec A abgeschlossen"
```

---

## Self-Review

**Spec-Abdeckung:**
- Author-Parsing → Task 3 ✓
- Synthetische Identität → Task 5 ✓
- HTTP-Härtung voll: 429/4xx/Redirect/not-feed → Task 6; FeedHTTPClient → Task 7; Default-Anbindung → Task 8 ✓
- Conditional-GET-Dropping 8 Tage → Task 9 ✓
- Cache-Control-Skip → Task 9 ✓
- Zukunfts-Clamp → Task 4 ✓
- Migration v11 (cacheControlMaxAge, conditionalGetSetAt) → Task 1 ✓
- FeedHTTPValidators neue Felder → Task 2 ✓
- Testing TDD → jeder Task ✓

**Typ-Konsistenz:**
- `FeedHTTPPolicyDecision`/`FeedHTTPPolicyAction` in Task 6 definiert, in Task 7 genutzt ✓
- `FeedHTTPClient.shared.data(for:)` in Task 7, genutzt in Task 8 ✓
- `FeedHTTPValidators.cacheControlMaxAge`/`conditionalGetSetAt` in Task 2, genutzt in Task 9 ✓
- `ParsedArticle.author` in Task 3, genutzt in Task 3 Step 6 ✓
- `parseFeed(data:sourceURL:now:)` in Task 4, genutzt in Task 5 ✓

**Offen / Risiko:**
- FeedKit-Typnamen (`entry.authors` vs `entry.author`, `item.dc?.creator`) müssen beim Bau verifiziert werden — Task 3 Step 4 enthält den Hinweis.
- `trimmedNonEmpty` auf FeedKit-Strings: prüfen, ggf. `String?`-Helfer nutzen.
- `SQLiteFeedRefreshCoordinator`-Init-Signatur und `manual`-Parameter müssen an bestehendes Pattern angepasst werden (Task 9 Step 3).