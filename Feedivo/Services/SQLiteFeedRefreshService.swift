import Foundation
import OSLog

enum SQLiteFeedFetchResult: Sendable {
    case updated(ParsedFeed, FeedHTTPValidators)
    case notModified(FeedHTTPValidators)
}

struct SQLiteFeedRefreshResult: Equatable, Sendable {
    var feedTitle: String
    var insertedArticleIDs: [String]
    var ruleNotifications: [RuleNotificationResult] = []
    var newArticleCount: Int = 0
}

enum SQLiteFeedRefreshError: Error, Equatable {
    case feedNotFound(String)
}

struct SQLiteFeedRefreshService {
    typealias Fetcher = (String, FeedHTTPValidators) async throws -> SQLiteFeedFetchResult
    typealias FaviconFetcher = (URL) async -> String?
    typealias SpotlightIndexer = ([ArticleListSnapshot]) -> Void
    typealias ArticleImageEnricher = ([ParsedArticle]) async -> [ParsedArticle]
    typealias DeferredImageEnrichmentObserver = @Sendable () -> Void

    private let database: FeedivoDatabase
    private let feedStore: FeedStore
    private let articleStore: ArticleStore
    private let statusStore: ArticleStatusStore
    private let logStore: FeedLogStore
    private let tagStore: TagStore
    private let ruleSnapshots: [RuleEngine.RuleSnapshot]
    private let now: () -> Date
    private let discoverFaviconURL: FaviconFetcher
    private let indexForSpotlight: SpotlightIndexer
    private let fetcher: Fetcher
    private let enrichArticleImages: ArticleImageEnricher
    private let onDeferredImageEnrichmentComplete: DeferredImageEnrichmentObserver?

    init(
        database: FeedivoDatabase,
        ruleSnapshots: [RuleEngine.RuleSnapshot] = [],
        now: @escaping () -> Date = Date.init,
        discoverFaviconURL: @escaping FaviconFetcher = { siteURL in
            await FaviconService.discoverFaviconURL(siteURL: siteURL)
        },
        indexForSpotlight: @escaping SpotlightIndexer = { SpotlightIndexingService.indexArticles($0) },
        // Standard bewusst ein No-Op statt der echten Anreicherung — anders als
        // sonst in diesem Projekt üblich (Defaults sind sonst die echte
        // Implementierung). `FeedService.enrichArticleImagesIfNeeded` lädt bei
        // fehlendem Bild die Artikelseite über echtes Netzwerk, und die
        // bestehende Testsuite konstruiert diesen Service an vielen Stellen mit
        // Fixture-Artikeln, deren `link` auf echte erreichbare URLs zeigt — ein
        // Netzwerk-Default hier würde diese Tests unbemerkt netzwerkabhängig
        // machen. Der produktive Aufrufer (SQLiteFeedActionService) setzt den
        // echten Wert explizit.
        //
        // WICHTIG: `enrichArticleImages` steht bewusst VOR `fetcher`, nicht
        // danach — `fetcher` muss der letzte Parameter bleiben, weil bestehende
        // Tests ihn per Trailing-Closure-Syntax setzen (`{ url, validators in
        // ... }`). Ein Parameter nach `fetcher` würde die Trailing-Closure
        // stattdessen an diesen neuen Parameter binden (Swift bindet immer an
        // den letzten Parameter) und mit „expects 1 argument, but 2 were used"
        // nicht mehr kompilieren — exakt der bereits einmal in diesem Projekt
        // aufgetretene Fallstrick (siehe Git-Historie zu dieser Datei).
        enrichArticleImages: @escaping ArticleImageEnricher = { $0 },
        // Test-Hook für deterministisches Warten auf den Hintergrund-Task der
        // Bild-Anreicherung (Optimierungsliste Punkt 3) — produktiv ungenutzt
        // (Standard nil), kein Verhalten geändert.
        onDeferredImageEnrichmentComplete: DeferredImageEnrichmentObserver? = nil,
        fetcher: @escaping Fetcher = SQLiteFeedRefreshService.defaultFetcher
    ) {
        self.database = database
        self.feedStore = FeedStore(database: database)
        self.articleStore = ArticleStore(database: database)
        self.statusStore = ArticleStatusStore(database: database)
        self.logStore = FeedLogStore(database: database)
        self.tagStore = TagStore(database: database)
        self.ruleSnapshots = ruleSnapshots
        self.now = now
        self.discoverFaviconURL = discoverFaviconURL
        self.indexForSpotlight = indexForSpotlight
        self.fetcher = fetcher
        self.enrichArticleImages = enrichArticleImages
        self.onDeferredImageEnrichmentComplete = onDeferredImageEnrichmentComplete
    }

    func refresh(feedID: String) async throws -> SQLiteFeedRefreshResult {
        guard let feed = try feedStore.feed(id: feedID) else {
            throw SQLiteFeedRefreshError.feedNotFound(feedID)
        }

        let validators = FeedHTTPValidators(
            eTag: feed.lastETag,
            lastModified: feed.lastModified,
            contentHash: feed.lastBodyHash,
            lastStatusCode: feed.lastHTTPStatusCode
        )
        let refreshedAt = now()

        do {
            switch try await fetcher(feed.url, validators) {
            case .notModified(let updatedValidators):
                let unreadCount = try statusStore.unreadCount(feedID: feedID)
                let faviconURL = await faviconURLIfNeeded(for: feed, parsedFeed: nil)
                try feedStore.updateAfterRefresh(
                    feedID: feedID,
                    title: nil,
                    websiteURL: nil,
                    validators: updatedValidators,
                    unreadCount: unreadCount,
                    refreshedAt: refreshedAt,
                    faviconURL: faviconURL
                )
                try logStore.append(FeedLogRecord(
                    feedID: feedID,
                    createdAt: refreshedAt,
                    level: "info",
                    message: "Nicht geändert",
                    httpStatusCode: updatedValidators.lastStatusCode,
                    newArticleCount: 0
                ))

                return SQLiteFeedRefreshResult(
                    feedTitle: feed.title,
                    insertedArticleIDs: [],
                    newArticleCount: 0
                )

            case .updated(let parsedFeed, let updatedValidators):
                let refreshedTitle = parsedFeed.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? feed.title
                    : parsedFeed.title
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
                let unreadCount = try statusStore.unreadCount(feedID: feedID)
                let faviconURL = await faviconURLIfNeeded(for: feed, parsedFeed: parsedFeed)
                try feedStore.updateAfterRefresh(
                    feedID: feedID,
                    title: refreshedTitle,
                    websiteURL: parsedFeed.siteURL,
                    validators: updatedValidators,
                    unreadCount: unreadCount,
                    refreshedAt: refreshedAt,
                    faviconURL: faviconURL
                )
                try logStore.append(FeedLogRecord(
                    feedID: feedID,
                    createdAt: refreshedAt,
                    level: "info",
                    message: "Aktualisiert",
                    httpStatusCode: updatedValidators.lastStatusCode,
                    newArticleCount: recentNewArticleCount
                ))

                return SQLiteFeedRefreshResult(
                    feedTitle: refreshedTitle,
                    insertedArticleIDs: upsertResult.insertedArticleIDs,
                    ruleNotifications: ruleResult.notifications,
                    newArticleCount: recentNewArticleCount
                )
            }
        } catch {
            try logStore.append(FeedLogRecord(
                feedID: feedID,
                createdAt: refreshedAt,
                level: "error",
                message: error.localizedDescription,
                httpStatusCode: httpStatusCode(from: error),
                newArticleCount: 0
            ))
            throw error
        }
    }

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
            SQLiteDataInvalidation.shared.bumpStatusVersion()
        }
    }

    private static func defaultFetcher(
        urlString: String,
        validators: FeedHTTPValidators
    ) async throws -> SQLiteFeedFetchResult {
        switch try await FeedService.fetchFeedConditionally(urlString: urlString, validators: validators) {
        case .updated(let feed, let validators):
            return .updated(feed, validators)
        case .notModified(let validators):
            return .notModified(validators)
        }
    }

    private func httpStatusCode(from error: Error) -> Int? {
        guard case FeedServiceError.httpError(let statusCode) = error else {
            return nil
        }
        return statusCode
    }

    // Favicons wurden bislang nur beim Einzel-Feed-Hinzufuegen entdeckt
    // (SQLiteFeedSubscriptionService.addFeed). Der OPML-Import und alle
    // spaeteren Refreshs liefen ausschliesslich ueber diesen Service, der
    // faviconURL nie gesetzt hat — deshalb blieben importierte Feeds
    // dauerhaft ohne Icon. Hier wird bei jedem Refresh nachgeholt, sofern
    // noch kein Favicon hinterlegt ist.
    private func faviconURLIfNeeded(for feed: FeedRecord, parsedFeed: ParsedFeed?) async -> String? {
        guard Self.trimmedNonEmpty(feed.faviconURL) == nil else {
            return nil
        }

        let siteURLString = Self.trimmedNonEmpty(parsedFeed?.siteURL) ?? Self.trimmedNonEmpty(feed.websiteURL)
        let siteURL = siteURLString.flatMap(URL.init(string:)) ?? FaviconService.siteURL(from: feed.url)
        guard let siteURL else {
            return nil
        }

        return await discoverFaviconURL(siteURL)
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func applyRules(
        to articleIDs: [String],
        feedTitle: String,
        appliedAt: Date
    ) throws -> RuleEngine.SQLiteRuleApplicationResult {
        guard !ruleSnapshots.isEmpty, !articleIDs.isEmpty else {
            return RuleEngine.SQLiteRuleApplicationResult(
                appliedActionCount: 0,
                hiddenArticleIDs: [],
                tagAssignments: [],
                notifications: []
            )
        }

        let articles = try articleStore.ruleSnapshots(articleIDs: articleIDs, feedTitle: feedTitle)
        let result = RuleEngine.applySQLiteRules(ruleSnapshots, to: articles)

        // Persistiert alle Treffer eines Refreshs in EINER Transaktion statt einer
        // Transaktion pro Treffer (Performance-Fix aus dem NetNewsWire-Vergleich,
        // 2026-07-27) — deshalb die `in db:`-Batch-Overloads statt der öffentlichen,
        // je eigenen `database.write` öffnenden Methoden. Die Statusversion/Sync-
        // Benachrichtigung wird danach bewusst nur einmal für den ganzen Batch
        // ausgelöst, nicht pro Einzeltreffer.
        try database.write { db in
            for articleID in result.hiddenArticleIDs {
                try statusStore.setHidden(true, articleID: articleID, at: appliedAt, in: db)
            }
            for assignment in result.tagAssignments {
                try tagStore.save(
                    TagRecord(
                        id: assignment.tag.id,
                        name: assignment.tag.name,
                        colorHex: assignment.tag.colorHex
                    ),
                    in: db
                )
                try tagStore.assignTag(
                    tagID: assignment.tag.id,
                    toArticleID: assignment.articleID,
                    at: appliedAt,
                    in: db
                )
            }
        }
        if !result.hiddenArticleIDs.isEmpty {
            SQLiteDataInvalidation.shared.bumpStatusVersion()
        }
        if !result.tagAssignments.isEmpty {
            CloudSyncEngine.notifyPendingChangesAvailable(database: database)
        }

        return result
    }
}
