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
}

enum SQLiteFeedRefreshError: Error, Equatable {
    case feedNotFound(String)
}

struct SQLiteFeedRefreshService {
    typealias Fetcher = (String, FeedHTTPValidators) async throws -> SQLiteFeedFetchResult

    private let feedStore: FeedStore
    private let articleStore: ArticleStore
    private let statusStore: ArticleStatusStore
    private let logStore: FeedLogStore
    private let tagStore: TagStore
    private let ruleSnapshots: [RuleEngine.RuleSnapshot]
    private let now: () -> Date
    private let fetcher: Fetcher

    init(
        database: FeedivoDatabase,
        ruleSnapshots: [RuleEngine.RuleSnapshot] = [],
        now: @escaping () -> Date = Date.init,
        fetcher: @escaping Fetcher = SQLiteFeedRefreshService.defaultFetcher
    ) {
        self.feedStore = FeedStore(database: database)
        self.articleStore = ArticleStore(database: database)
        self.statusStore = ArticleStatusStore(database: database)
        self.logStore = FeedLogStore(database: database)
        self.tagStore = TagStore(database: database)
        self.ruleSnapshots = ruleSnapshots
        self.now = now
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
                try feedStore.updateAfterRefresh(
                    feedID: feedID,
                    title: nil,
                    websiteURL: nil,
                    validators: updatedValidators,
                    unreadCount: unreadCount,
                    refreshedAt: refreshedAt
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
                    isNotModified: true
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
                        arrivedAt: refreshedAt
                    )
                }
                let upsertResult = try articleStore.upsert(inputs)
                let ruleResult = try applyRules(
                    to: upsertResult.insertedArticleIDs,
                    feedTitle: refreshedTitle,
                    appliedAt: refreshedAt
                )
                let unreadCount = try statusStore.unreadCount(feedID: feedID)
                try feedStore.updateAfterRefresh(
                    feedID: feedID,
                    title: refreshedTitle,
                    websiteURL: parsedFeed.siteURL,
                    validators: updatedValidators,
                    unreadCount: unreadCount,
                    refreshedAt: refreshedAt
                )
                try logStore.append(FeedLogRecord(
                    feedID: feedID,
                    createdAt: refreshedAt,
                    level: "info",
                    message: "Aktualisiert",
                    httpStatusCode: updatedValidators.lastStatusCode,
                    newArticleCount: upsertResult.insertedArticleIDs.count
                ))

                return SQLiteFeedRefreshResult(
                    feedID: feedID,
                    feedTitle: refreshedTitle,
                    insertedArticleIDs: upsertResult.insertedArticleIDs,
                    updatedArticleIDs: upsertResult.updatedArticleIDs,
                    unreadCount: unreadCount,
                    isNotModified: false,
                    ruleNotifications: ruleResult.notifications
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
