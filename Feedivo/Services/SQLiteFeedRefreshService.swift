import Foundation

enum SQLiteFeedFetchResult: Sendable {
    case updated(ParsedFeed, FeedHTTPValidators)
    case notModified(FeedHTTPValidators)
}

struct SQLiteFeedRefreshResult: Equatable, Sendable {
    var feedID: String
    var feedTitle: String
    var insertedArticleIDs: [String]
    var updatedArticleIDs: [String]
    var unreadCount: Int
    var isNotModified: Bool
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

    init(
        database: FeedivoDatabase,
        ruleSnapshots: [RuleEngine.RuleSnapshot] = [],
        now: @escaping () -> Date = Date.init,
        discoverFaviconURL: @escaping FaviconFetcher = { siteURL in
            await FaviconService.discoverFaviconURL(siteURL: siteURL)
        },
        indexForSpotlight: @escaping SpotlightIndexer = { SpotlightIndexingService.indexArticles($0) },
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
                    feedID: feedID,
                    feedTitle: feed.title,
                    insertedArticleIDs: [],
                    updatedArticleIDs: [],
                    unreadCount: unreadCount,
                    isNotModified: true,
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
                    feedID: feedID,
                    feedTitle: refreshedTitle,
                    insertedArticleIDs: upsertResult.insertedArticleIDs,
                    updatedArticleIDs: upsertResult.updatedArticleIDs,
                    unreadCount: unreadCount,
                    isNotModified: false,
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
        for articleID in result.hiddenArticleIDs {
            try statusStore.setHidden(true, articleID: articleID, at: appliedAt)
        }
        for assignment in result.tagAssignments {
            try tagStore.save(
                TagRecord(
                    id: assignment.tag.id,
                    name: assignment.tag.name,
                    colorHex: assignment.tag.colorHex
                )
            )
            try tagStore.assignTag(
                tagID: assignment.tag.id,
                toArticleID: assignment.articleID,
                at: appliedAt
            )
        }

        return result
    }
}
