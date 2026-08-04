# Feed-Refresh: Bild-Anreicherung aus dem synchronen Pfad lösen — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `SQLiteFeedRefreshService.refresh(feedID:)` soll nicht mehr auf die Bild-Anreicherung fehlender Artikelbilder warten, bevor ein Feed als fertig aktualisiert gilt — die Anreicherung läuft stattdessen in einem nicht-awaiteten Hintergrund-`Task` nach dem Speichern.

**Architecture:** Neu eingefügte Artikel werden sofort mit dem feed-eigenen Bild (oder ohne) gespeichert. Der bereits bestehende Snapshot-Abruf für die Spotlight-Indexierung wird für die Kandidaten-Ermittlung wiederverwendet (kein zusätzlicher DB-Zugriff). Ein `Task { }` reichert die Kandidaten im Hintergrund an und schreibt Treffer gezielt per neuer `ArticleStore.updateImageURL(articleID:imageURL:)` zurück, statt eines vollen Upserts.

**Tech Stack:** Swift, GRDB, Swift Testing (`Testing`-Framework, keine XCTest).

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08/2026-08-04-feed-refresh-bild-anreicherung-hintergrund-design.md`
- Kommentare im Code auf Deutsch (Projektkonvention, siehe `CLAUDE.md`).
- `SQLiteFeedActionService` und `SQLiteFeedSubscriptionService` bleiben unverändert — ihre synchrone Bild-Anreicherung ist explizit außerhalb des Scopes.
- Kein globales, feedübergreifendes Concurrency-Limit für die Hintergrund-Anreicherung (bewusste Scope-Entscheidung aus der Spec).
- Kein neuer UI-Ladezustand für „Bild lädt noch nach".
- `enrichArticleImages` muss im `SQLiteFeedRefreshService`-Initializer vor `fetcher` stehen, `fetcher` muss der letzte Parameter bleiben (bestehende Tests nutzen Trailing-Closure-Syntax dafür). Der neue Parameter `onDeferredImageEnrichmentComplete` wird direkt nach `enrichArticleImages` eingefügt, weiterhin vor `fetcher`.
- Tests dürfen nicht auf Wanduhrzeiten/`Task.sleep` zur Synchronisation mit dem Hintergrund-Task setzen (Lehre aus Optimierungsliste Punkt 1) — stattdessen der neue `onDeferredImageEnrichmentComplete`-Hook + ein deterministisches Signal (Continuation/Actor).

---

## Task 1: `ArticleStore.updateImageURL(articleID:imageURL:)`

**Files:**
- Modify: `Feedivo/Stores/ArticleStore.swift`
- Test: `FeedivoTests/Stores/SQLiteArticleStoreTests.swift`

**Interfaces:**
- Produces: `ArticleStore.updateImageURL(articleID: String, imageURL: String) throws` — schreibt nur die `imageURL`-Spalte eines bereits existierenden Artikels, kein Upsert.

- [ ] **Step 1: Write the failing test**

Öffne `FeedivoTests/Stores/SQLiteArticleStoreTests.swift` und füge am Ende der `struct SQLiteArticleStoreTests { ... }` (vor der letzten schließenden Klammer der Struct) folgenden Test ein:

```swift
    @Test func updateImageURLAktualisiertNurDieBildURLEinesBestehendenArtikels() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Feed"))
        let articleID = try articleStore.upsert(
            ArticleUpsertInput(feedID: "feed-1", sourceID: "one", title: "Titel", imageURL: nil)
        )

        try articleStore.updateImageURL(articleID: articleID, imageURL: "https://example.com/found.jpg")

        let article = try articleStore.article(id: articleID)
        #expect(article?.imageURL == "https://example.com/found.jpg")
        #expect(article?.title == "Titel")
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteArticleStoreTests/updateImageURLAktualisiertNurDieBildURLEinesBestehendenArtikels -parallel-testing-enabled NO`

Expected: FAIL — Compile-Fehler „value of type 'ArticleStore' has no member 'updateImageURL'".

- [ ] **Step 3: Write minimal implementation**

Öffne `Feedivo/Stores/ArticleStore.swift`. Füge die neue Methode direkt nach der bestehenden `func upsert(_ inputs: [ArticleUpsertInput]) throws -> ArticleUpsertResult { ... }` (vor `func article(id: String) throws -> ArticleRecord? { ... }`) ein:

```swift
    /// Aktualisiert gezielt nur die `imageURL`-Spalte eines bereits
    /// existierenden Artikels — kein voller Upsert. Genutzt von der
    /// nachgelagerten Bild-Anreicherung nach einem Feed-Refresh
    /// (Optimierungsliste Punkt 3,
    /// docs/performance/feed-refresh-optimierungsliste.md), wo der Artikel
    /// bereits vollständig gespeichert ist und nur sein Bild nachträglich
    /// gefunden wurde.
    func updateImageURL(articleID: String, imageURL: String) throws {
        try database.write { db in
            try db.execute(
                sql: "UPDATE articles SET imageURL = ? WHERE id = ?",
                arguments: [imageURL, articleID]
            )
        }
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteArticleStoreTests/updateImageURLAktualisiertNurDieBildURLEinesBestehendenArtikels -parallel-testing-enabled NO`

Expected: PASS

- [ ] **Step 5: Run the full SQLiteArticleStoreTests suite to confirm no regression**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteArticleStoreTests -parallel-testing-enabled NO`

Expected: alle Tests PASS

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Stores/ArticleStore.swift FeedivoTests/Stores/SQLiteArticleStoreTests.swift
git commit -m "$(cat <<'EOF'
feat: ArticleStore.updateImageURL für gezieltes Nachtragen einzelner Artikelbilder

Vorbereitung für Optimierungsliste Punkt 3 (Bild-Anreicherung aus dem
synchronen Feed-Refresh-Pfad lösen) — schreibt nur die imageURL-Spalte
eines bereits existierenden Artikels, kein voller Upsert.
EOF
)"
```

---

## Task 2: Bild-Anreicherung aus `SQLiteFeedRefreshService.refresh` entkoppeln

**Files:**
- Modify: `Feedivo/Services/SQLiteFeedRefreshService.swift`
- Test: `FeedivoTests/Services/SQLiteFeedRefreshServiceTests.swift`

**Interfaces:**
- Consumes: `ArticleStore.updateImageURL(articleID: String, imageURL: String) throws` (Task 1).
- Produces: neuer Init-Parameter `onDeferredImageEnrichmentComplete: DeferredImageEnrichmentObserver? = nil` auf `SQLiteFeedRefreshService`, wobei `typealias DeferredImageEnrichmentObserver = @Sendable () -> Void`. Verhalten von `refresh(feedID:)` ändert sich: neu eingefügte Artikel werden sofort mit dem feed-eigenen `imageURL` gespeichert (kann `nil` sein), fehlende Bilder werden danach in einem nicht-awaiteten `Task` nachgeladen.

### Vorher/Nachher in `refresh(feedID:)`

Der Abschnitt im `.updated`-Zweig von `refresh(feedID:)` sieht aktuell so aus:

```swift
            case .updated(let parsedFeed, let updatedValidators):
                let refreshedTitle = parsedFeed.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? feed.title
                    : parsedFeed.title
                let enrichedArticles = await enrichArticleImages(parsedFeed.articles)
                let inputs = enrichedArticles.map { article in
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
                let upsertResult = try articleStore.upsert(inputs)
                let recentCutoff = now().addingTimeInterval(-48 * 60 * 60)
                let recentNewArticleCount = try articleStore.recentlyPublishedCount(
                    articleIDs: upsertResult.insertedArticleIDs,
                    since: recentCutoff
                )
                let ruleResult = try applyRules(
                    to: upsertResult.insertedArticleIDs,
                    feedTitle: refreshedTitle,
                    appliedAt: refreshedAt
                )
                // Läuft NACH applyRules, damit ein Artikel, den eine Regel
                // sofort beim Eintreffen ausblendet (isHidden), korrekt von
                // der Spotlight-Indexierung ausgeschlossen bleibt
                // (includeHidden: false).
                logIfThrows(context: "Spotlight-Indexierung nach Feed-Refresh") {
                    guard !upsertResult.insertedArticleIDs.isEmpty else {
                        return
                    }
                    let snapshotsToIndex = try ArticleDatabase(database: database).fetchArticles(
                        articleIDs: Set(upsertResult.insertedArticleIDs),
                        includeHidden: false
                    )
                    indexForSpotlight(snapshotsToIndex)
                }
```

- [ ] **Step 1: Write the failing tests**

Öffne `FeedivoTests/Services/SQLiteFeedRefreshServiceTests.swift`. Entferne den gesamten bestehenden Test `refreshRuftEnrichArticleImagesAufUndSpeichertDerenErgebnis` samt seinem vorangestellten Kommentarblock (Zeilen 71–131 im aktuellen Stand — der Kommentar beginnt bei `// Regressionstest für den enrichArticleImages-Verdrahtungsfix...` und der Test endet mit der schließenden `}` nach `#expect(storedArticle?.imageURL == "https://example.com/enriched.jpg")`). Ersetze diesen Block durch die folgenden zwei neuen Tests (an derselben Stelle, zwischen `refreshInsertsParsedArticlesAndUpdatesUnreadCount` und `refreshIndexiertNeueArtikelInSpotlight`):

**Korrektur (2026-08-04, gefunden während der Implementierung von Task 2):**
Eine erste Fassung dieses Tests prüfte `storedArticle?.imageURL == nil`
**direkt** nach `try await service.refresh(...)`, mit einer sofort
erfolgreichen `enrichArticleImages`-Closure. Das schlug unter diesem Projekt
(`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, siehe `CLAUDE.md`-Gotcha)
**deterministisch fehl**, nicht durch einen Implementierungsfehler: Sowohl
`refresh()` als auch der neue `Task { }` aus `scheduleDeferredImageEnrichmentIfNeeded`
laufen implizit auf derselben `MainActor`-Warteschlange. Da `refresh()` nach
dem Einplanen des Hintergrund-Tasks noch einen echten `await`-Punkt durchläuft
(`faviconURLIfNeeded`), bekommt die `MainActor`-Queue währenddessen legitim
die Gelegenheit, den bereits eingereihten Hintergrund-Task VOR der Rückkehr
von `refresh()` fertig laufen zu lassen — der Test konnte dadurch strukturell
nie zuverlässig zwischen „altes blockierendes" und „neues, zufällig schon
fertiges" Verhalten unterscheiden. Die korrekte, deterministische Fassung
nutzt stattdessen ein Timeout-Rennen: `enrichArticleImages` blockiert
absichtlich für immer (Gate wird nie geöffnet) — würde `refresh()`
`enrichArticleImages` synchron awaiten (altes Verhalten), schlägt der Test
zuverlässig nach 2s per Timeout fehl, statt zu hängen oder zu flackern.
Nutze **diese** Fassung, nicht die ursprüngliche:

```swift
    // Optimierungsliste Punkt 3 (docs/performance/feed-refresh-optimierungsliste.md,
    // 2026-08-04): enrichArticleImages lief bisher synchron VOR dem Insert und
    // blockierte damit den Abschluss von refresh(). enrichArticleImages blockiert
    // hier absichtlich für immer (Gate wird nie geöffnet) — ein Timeout-Rennen
    // beweist per Fehlschlag-nach-2s, dass refresh() NICHT auf die Anreicherung
    // wartet. Ein direkter "sofort danach prüfen"-Test wäre unter diesem Projekt
    // (SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor) nicht robust: refresh() und der
    // Hintergrund-Task teilen sich dieselbe MainActor-Warteschlange, sodass der
    // Hintergrund-Task durch einen späteren await-Punkt in refresh() (Favicon-
    // Discovery) bereits fertig sein kann, bevor refresh() selbst zurückkehrt.
    @Test func refreshSpeichertArtikelSofortOhneAufBildAnreicherungZuWarten() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Old"))

        let neverOpens = SingleShotSignal()
        let service = SQLiteFeedRefreshService(
            database: database,
            enrichArticleImages: { articles in
                await neverOpens.wait()
                return articles.map { $0.copy(imageURL: "https://example.com/enriched.jpg") }
            },
            fetcher: { url, _ in
                .updated(
                    ParsedFeed(
                        sourceURL: url,
                        title: "Example",
                        description: nil,
                        siteURL: nil,
                        articles: [
                            ParsedArticle(
                                title: "Ohne Bild",
                                sourceID: "one",
                                link: "https://example.com/one",
                                summary: nil,
                                content: nil,
                                publishedAt: Date(timeIntervalSince1970: 1_000),
                                imageURL: nil
                            )
                        ]
                    ),
                    FeedHTTPValidators()
                )
            }
        )

        let result = try await withRefreshTimeout(seconds: 2) {
            try await service.refresh(feedID: "feed-1")
        }
        let storedArticle = try articleStore.readerArticle(id: result.insertedArticleIDs[0])

        #expect(storedArticle?.imageURL == nil)
    }

    // Gegenstück zum obigen Test: der Hintergrund-Task holt das Bild tatsächlich
    // nach. Nutzt den onDeferredImageEnrichmentComplete-Hook + ein deterministisches
    // Signal statt Task.sleep/Wanduhrzeiten (Lehre aus Optimierungsliste Punkt 1 —
    // siehe dortige Regressionstest-Historie zu geflackerten Zeit-basierten Tests).
    @Test func refreshReichertFehlendeBilderImHintergrundAnUndAktualisiertDenArtikel() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Old"))

        let enrichmentDone = SingleShotSignal()
        let service = SQLiteFeedRefreshService(
            database: database,
            enrichArticleImages: { articles in
                articles.map { $0.copy(imageURL: "https://example.com/enriched.jpg") }
            },
            onDeferredImageEnrichmentComplete: {
                Task { await enrichmentDone.fire() }
            },
            fetcher: { url, _ in
                .updated(
                    ParsedFeed(
                        sourceURL: url,
                        title: "Example",
                        description: nil,
                        siteURL: nil,
                        articles: [
                            ParsedArticle(
                                title: "Ohne Bild",
                                sourceID: "one",
                                link: "https://example.com/one",
                                summary: nil,
                                content: nil,
                                publishedAt: Date(timeIntervalSince1970: 1_000),
                                imageURL: nil
                            )
                        ]
                    ),
                    FeedHTTPValidators()
                )
            }
        )

        let result = try await service.refresh(feedID: "feed-1")
        await enrichmentDone.wait()

        let storedArticle = try articleStore.readerArticle(id: result.insertedArticleIDs[0])
        #expect(storedArticle?.imageURL == "https://example.com/enriched.jpg")
    }
```

Füge außerdem am Ende der Datei, nach der schließenden `}` von `struct SQLiteFeedRefreshServiceTests { ... }`, folgenden privaten Hilfs-Actor hinzu (analog zum bereits in `SQLiteFeedRefreshCoordinatorTests.swift` etablierten Gate-Muster, hier als einfaches Einmal-Signal):

```swift

private actor SingleShotSignal {
    private var continuation: CheckedContinuation<Void, Never>?
    private var hasFired = false

    func wait() async {
        if hasFired {
            return
        }
        await withCheckedContinuation { continuation = $0 }
    }

    func fire() {
        hasFired = true
        continuation?.resume()
        continuation = nil
    }
}
```

Füge direkt danach (ebenfalls file-level, außerhalb der Struct) den Timeout-Helfer für den korrigierten ersten Test hinzu:

```swift

private enum RefreshTestTimeoutError: Error {
    case timedOut
}

private func withRefreshTimeout<T: Sendable>(
    seconds: Double,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw RefreshTestTimeoutError.timedOut
        }
        guard let result = try await group.next() else {
            throw RefreshTestTimeoutError.timedOut
        }
        group.cancelAll()
        return result
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedRefreshServiceTests -parallel-testing-enabled NO`

Expected: FAIL — Compile-Fehler „no member 'onDeferredImageEnrichmentComplete'" (der zweite neue Test nutzt den noch nicht existierenden Init-Parameter, wodurch die ganze Datei nicht kompiliert und beide neuen Tests als fehlgeschlagen gelten).

- [ ] **Step 3: Write minimal implementation**

Öffne `Feedivo/Services/SQLiteFeedRefreshService.swift`.

**3a.** Füge den neuen Typalias direkt nach `typealias ArticleImageEnricher = ([ParsedArticle]) async -> [ParsedArticle]` ein:

```swift
    typealias DeferredImageEnrichmentObserver = @Sendable () -> Void
```

**3b.** Füge die neue Property direkt nach `private let enrichArticleImages: ArticleImageEnricher` ein:

```swift
    private let onDeferredImageEnrichmentComplete: DeferredImageEnrichmentObserver?
```

**3c.** Im Initializer: füge den neuen Parameter direkt nach `enrichArticleImages: @escaping ArticleImageEnricher = { $0 },` und vor `fetcher: @escaping Fetcher = SQLiteFeedRefreshService.defaultFetcher` ein:

```swift
        // Test-Hook für deterministisches Warten auf den Hintergrund-Task der
        // Bild-Anreicherung (Optimierungsliste Punkt 3) — produktiv ungenutzt
        // (Standard nil), kein Verhalten geändert.
        onDeferredImageEnrichmentComplete: DeferredImageEnrichmentObserver? = nil,
```

Und im Initializer-Body direkt nach `self.enrichArticleImages = enrichArticleImages`:

```swift
        self.onDeferredImageEnrichmentComplete = onDeferredImageEnrichmentComplete
```

**3d.** Ersetze im `.updated`-Zweig von `refresh(feedID:)` den Block

```swift
                let enrichedArticles = await enrichArticleImages(parsedFeed.articles)
                let inputs = enrichedArticles.map { article in
```

durch (nur die Zeile mit `enrichedArticles` entfällt, die Map-Quelle wechselt auf `parsedFeed.articles`):

```swift
                let inputs = parsedFeed.articles.map { article in
```

**3e.** Ersetze den bestehenden Spotlight-Indexierungs-Block

```swift
                logIfThrows(context: "Spotlight-Indexierung nach Feed-Refresh") {
                    guard !upsertResult.insertedArticleIDs.isEmpty else {
                        return
                    }
                    let snapshotsToIndex = try ArticleDatabase(database: database).fetchArticles(
                        articleIDs: Set(upsertResult.insertedArticleIDs),
                        includeHidden: false
                    )
                    indexForSpotlight(snapshotsToIndex)
                }
```

durch:

```swift
                if !upsertResult.insertedArticleIDs.isEmpty {
                    logIfThrows(context: "Snapshot-Abruf für neu eingefügte Artikel nach Feed-Refresh") {
                        let insertedSnapshots = try ArticleDatabase(database: database).fetchArticles(
                            articleIDs: Set(upsertResult.insertedArticleIDs),
                            includeHidden: false
                        )
                        indexForSpotlight(insertedSnapshots)
                        scheduleDeferredImageEnrichmentIfNeeded(for: insertedSnapshots)
                    }
                }
```

**3f.** Füge zwei neue private Methoden hinzu — direkt nach dem Ende von `func refresh(feedID:) async throws -> SQLiteFeedRefreshResult { ... }` (vor `private static func defaultFetcher`):

```swift
    // Startet einen von refresh() unabhängigen Hintergrund-Task für Artikel,
    // die weder im Feed selbst noch beim Parsen ein Bild bekommen haben
    // (Optimierungsliste Punkt 3, docs/performance/feed-refresh-optimierungsliste.md).
    // refresh() wartet NICHT auf diesen Task — der Feed gilt sofort als fertig
    // aktualisiert, sobald sein Inhalt gespeichert ist.
    private func scheduleDeferredImageEnrichmentIfNeeded(for snapshots: [ArticleListSnapshot]) {
        let candidates = snapshots.filter { $0.imageURL == nil && $0.link != nil }
        guard !candidates.isEmpty else {
            return
        }

        let enrichArticleImages = self.enrichArticleImages
        let database = self.database
        let onComplete = self.onDeferredImageEnrichmentComplete

        Task {
            await Self.enrichAndPersistImages(
                candidates: candidates,
                database: database,
                enrichArticleImages: enrichArticleImages
            )
            onComplete?()
        }
    }

    // Nutzt Platzhalter-ParsedArticle-Werte für enrichArticleImages, da diese
    // Closure nur `.link` liest und nur `.imageURL` über `.copy(imageURL:)`
    // zurückschreibt (siehe FeedService.enrichArticleImagesIfNeeded) — Titel/
    // Summary/Content werden hier nicht gebraucht, der Artikel existiert
    // bereits vollständig in der Datenbank. zip(candidates, enriched) ist
    // sicher, da enrichArticleImagesIfNeeded Ein- und Ausgabe-Array garantiert
    // gleich lang und index-gleich hält.
    private static func enrichAndPersistImages(
        candidates: [ArticleListSnapshot],
        database: FeedivoDatabase,
        enrichArticleImages: ArticleImageEnricher
    ) async {
        let placeholders = candidates.map { candidate in
            ParsedArticle(
                title: "",
                link: candidate.link,
                summary: nil,
                content: nil,
                publishedAt: nil,
                imageURL: nil
            )
        }
        let enriched = await enrichArticleImages(placeholders)

        let articleStore = ArticleStore(database: database)
        var didUpdateAny = false
        for (candidate, result) in zip(candidates, enriched) {
            guard let imageURL = result.imageURL else {
                continue
            }
            do {
                try articleStore.updateImageURL(articleID: candidate.id, imageURL: imageURL)
                didUpdateAny = true
            } catch {
                AppLogger.dataAccess.error("Nachträgliche Bild-Anreicherung: Speichern für Artikel \(candidate.id, privacy: .public) fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            }
        }
        if didUpdateAny {
            SQLiteDataInvalidation.bumpStatusVersion()
        }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedRefreshServiceTests -parallel-testing-enabled NO`

Expected: alle Tests PASS (9 Tests: die 7 unveränderten + die 2 neuen — `refreshRuftEnrichArticleImagesAufUndSpeichertDerenErgebnis` existiert nicht mehr).

- [ ] **Step 5: Full regression sweep**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedRefreshServiceTests -only-testing:FeedivoTests/SQLiteFeedRefreshCoordinatorTests -only-testing:FeedivoTests/FeedViewModelTests -only-testing:FeedivoTests/SQLiteArticleStoreTests -parallel-testing-enabled NO`

Expected: alle Tests PASS. Falls `refreshCountsOnlyRecentlyPublishedArticlesAsNew` oder
`applyRulesPersistiertTrefferInEinerTransaktionUnabhaengigVonDerTrefferzahl` unerwartet
fehlschlagen: beide Tests nutzen den No-Op-Default `enrichArticleImages: { $0 }`, wodurch
der neue Hintergrund-Task zwar startet (Kandidaten haben `link` gesetzt), aber niemals ein
Bild findet (`didUpdateAny` bleibt `false`) — kein zusätzliches `UPDATE`/`COMMIT`. Ein
Fehlschlag hier deutet auf einen Fehler in Schritt 3f hin, nicht auf ein grundsätzliches
Scope-Problem.

- [ ] **Step 6: Full debug build**

Run: `xcodebuild build -scheme Feedivo -destination 'platform=macOS'`

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add Feedivo/Services/SQLiteFeedRefreshService.swift FeedivoTests/Services/SQLiteFeedRefreshServiceTests.swift
git commit -m "$(cat <<'EOF'
perf: Feed-Refresh — Bild-Anreicherung läuft nicht mehr blockierend

Optimierungsliste Punkt 3 (docs/performance/feed-refresh-optimierungsliste.md,
NetNewsWire-Vergleich): SQLiteFeedRefreshService.refresh speichert neue Artikel
jetzt sofort mit dem feed-eigenen Bild (oder ohne), statt vor dem Insert auf
zusätzliche Seiten-Downloads für fehlende Bilder zu warten. Ein nicht-awaiteter
Hintergrund-Task holt fehlende Bilder danach nach und aktualisiert nur die
imageURL-Spalte der betroffenen Artikel. Nebeneffekt: Anreicherung läuft künftig
nur noch für neu eingefügte statt für alle im Feed enthaltenen Artikel — verhindert
das versehentliche Zurücksetzen bereits gefundener Bilder auf NULL bei einem
späteren, fehlschlagenden Wiederholungsversuch.
EOF
)"
```

---

## Nach Abschluss beider Tasks

- [ ] Punkt 3 in `docs/performance/feed-refresh-optimierungsliste.md` abhaken
  (analog zu Punkt 1/2 dort — Umsetzungsnotiz mit Testabdeckung und
  Verweis auf diesen Plan/diese Spec ergänzen).
