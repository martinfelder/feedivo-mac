import Foundation
import GRDB
import SwiftData

struct SQLiteFeedSubscriptionResult: Equatable, Sendable {
    var feedID: String
    var importedCount: Int
    var skippedDuplicateCount: Int
    var failedFeedTitles: [String]
}

struct SQLiteOPMLImportResult: Equatable, Sendable {
    var total: Int
    var imported: Int
    var skippedDuplicates: Int
    var failedFeedTitles: [String]
}

enum SQLiteFeedSubscriptionError: LocalizedError, Equatable {
    case emptyURL
    case duplicateFeed

    var errorDescription: String? {
        switch self {
        case .emptyURL:
            L10n.feedErrorEmptyURL
        case .duplicateFeed:
            L10n.feedErrorDuplicate
        }
    }
}

@MainActor
struct SQLiteFeedSubscriptionService {
    typealias FeedFetcher = (String) async throws -> ParsedFeed
    typealias FaviconFetcher = (URL) async -> String?
    typealias ArticleUpserter = ([ArticleUpsertInput]) throws -> ArticleUpsertResult
    typealias AfterArticleUpsertHook = () throws -> Void
    typealias AfterOPMLTagsSaveHook = () throws -> Void

    private let database: FeedivoDatabase
    private let fetchFeed: FeedFetcher
    private let discoverFaviconURL: FaviconFetcher
    private let articleUpsert: ArticleUpserter
    private let afterArticleUpsert: AfterArticleUpsertHook
    private let afterOPMLTagsSave: AfterOPMLTagsSaveHook

    init(
        database: FeedivoDatabase,
        fetchFeed: @escaping FeedFetcher = FeedService.fetchFeed,
        discoverFaviconURL: @escaping FaviconFetcher = { siteURL in
            await FaviconService.discoverFaviconURL(siteURL: siteURL)
        },
        articleUpsert: ArticleUpserter? = nil,
        afterArticleUpsert: @escaping AfterArticleUpsertHook = {},
        afterOPMLTagsSave: @escaping AfterOPMLTagsSaveHook = {}
    ) {
        self.database = database
        self.fetchFeed = fetchFeed
        self.discoverFaviconURL = discoverFaviconURL
        self.articleUpsert = articleUpsert ?? { inputs in
            try ArticleStore(database: database).upsert(inputs)
        }
        self.afterArticleUpsert = afterArticleUpsert
        self.afterOPMLTagsSave = afterOPMLTagsSave
    }

    func addFeed(
        urlString: String,
        refreshIntervalMinutes: Int = 60,
        context: ModelContext? = nil
    ) async throws -> SQLiteFeedSubscriptionResult {
        let cleanedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedURL.isEmpty else {
            throw SQLiteFeedSubscriptionError.emptyURL
        }

        let parsedFeed = try await fetchFeed(cleanedURL)
        let feedStore = FeedStore(database: database)
        let candidateURLs = Set([cleanedURL, parsedFeed.sourceURL].map(normalizedFeedURL))
        let existingFeeds = try feedStore.feeds()
        let shouldWriteSwiftDataBridge = shouldUseSwiftDataBridge(context: context)
        let existingSwiftDataFeeds = shouldWriteSwiftDataBridge
            ? (try context?.fetch(FetchDescriptor<Feed>()) ?? [])
            : []
        guard !existingFeeds.contains(where: { candidateURLs.contains(normalizedFeedURL($0.url)) }),
              !existingSwiftDataFeeds.contains(where: { candidateURLs.contains(normalizedFeedURL($0.url)) }) else {
            throw SQLiteFeedSubscriptionError.duplicateFeed
        }

        let now = Date()
        let feedID = UUID().uuidString
        let faviconURL = await faviconURL(for: parsedFeed)
        let feedRecord = FeedRecord(
            id: feedID,
            url: parsedFeed.sourceURL,
            title: parsedFeed.title,
            originalTitle: parsedFeed.title,
            websiteURL: parsedFeed.siteURL,
            faviconURL: faviconURL,
            refreshIntervalMinutes: BackgroundRefreshSettings.clampedIntervalMinutes(refreshIntervalMinutes),
            createdAt: now,
            updatedAt: now
        )

        try feedStore.save(feedRecord)

        do {
            let articleInputs = parsedFeed.articles.map { article in
                ArticleUpsertInput(
                    feedID: feedID,
                    sourceID: article.sourceID,
                    link: article.link,
                    title: article.title,
                    summary: article.summary,
                    content: article.content,
                    imageURL: article.imageURL,
                    publishedAt: article.publishedAt,
                    arrivedAt: now
                )
            }
            _ = try articleUpsert(articleInputs)
            try afterArticleUpsert()
            let unreadCount = try ArticleStatusStore(database: database).unreadCount(feedID: feedID)
            try feedStore.setUnreadCount(unreadCount, feedID: feedID)
            try FeedLogStore(database: database).append(
                FeedLogRecord(
                    feedID: feedID,
                    createdAt: now,
                    level: "info",
                    message: L10n.feedLogAdded,
                    httpStatusCode: nil,
                    newArticleCount: parsedFeed.articles.count
                )
            )
            if shouldWriteSwiftDataBridge {
                try saveSwiftDataBridge(feedRecord, context: context)
            }
        } catch {
            try? cleanupSQLiteSubscription(feedID: feedID)
            if shouldWriteSwiftDataBridge, let context {
                context.rollback()
            }
            throw error
        }

        return SQLiteFeedSubscriptionResult(
            feedID: feedID,
            importedCount: 1,
            skippedDuplicateCount: 0,
            failedFeedTitles: []
        )
    }

    func importOPMLFeeds(
        _ opmlFeeds: [OPMLFeed],
        allowsDuplicates: Bool,
        refreshAfterImport: Bool,
        refreshIntervalMinutes: Int,
        context: ModelContext? = nil
    ) async throws -> SQLiteOPMLImportResult {
        let feedStore = FeedStore(database: database)
        let folderStore = FeedFolderStore(database: database)
        let logStore = FeedLogStore(database: database)
        let clampedRefreshInterval = BackgroundRefreshSettings.clampedIntervalMinutes(refreshIntervalMinutes)
        let shouldWriteSwiftDataBridge = shouldUseSwiftDataBridge(context: context)
        let existingSwiftDataFeeds = shouldWriteSwiftDataBridge
            ? (try context?.fetch(FetchDescriptor<Feed>()) ?? [])
            : []
        var knownURLs = Set(
            (try feedStore.feeds().map(\.url) + existingSwiftDataFeeds.map(\.url))
                .map(normalizedFeedURL)
        )
        var knownFolderNames = Set(try folderStore.folders().map { $0.name.lowercased() })
        var imported = 0
        var skippedDuplicates = 0
        var failedFeedTitles: [String] = []

        for opmlFeed in opmlFeeds {
            let cleanedURL = opmlFeed.xmlURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanedURL.isEmpty else {
                continue
            }

            let normalizedURL = normalizedFeedURL(cleanedURL)
            if !allowsDuplicates, knownURLs.contains(normalizedURL) {
                skippedDuplicates += 1
                continue
            }
            knownURLs.insert(normalizedURL)

            let now = Date()
            let feedID = UUID().uuidString
            let trimmedTitle = opmlFeed.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = trimmedTitle.isEmpty ? cleanedURL : trimmedTitle
            let folderName = FeedFolderOrganizer.normalizedFolderName(opmlFeed.folderName)

            let feedRecord = FeedRecord(
                id: feedID,
                url: cleanedURL,
                title: title,
                originalTitle: title,
                websiteURL: trimmedNonEmpty(opmlFeed.htmlURL),
                folderName: folderName,
                refreshIntervalMinutes: clampedRefreshInterval,
                createdAt: now,
                updatedAt: now
            )
            let shouldWriteCurrentFeedBridge = shouldWriteSwiftDataBridge
            var createdFolder: FeedFolderRecord?
            var createdTagIDs: [String] = []
            do {
                if let folderName, knownFolderNames.insert(folderName.lowercased()).inserted {
                    let folderRecord = FeedFolderRecord(
                        name: folderName,
                        createdAt: now,
                        updatedAt: now
                    )
                    try folderStore.save(folderRecord)
                    createdFolder = folderRecord
                }
                try feedStore.save(feedRecord)
                createdTagIDs = try saveTags(opmlFeed.tagNames, feedID: feedID, createdAt: now)
                try afterOPMLTagsSave()
                try logStore.append(
                    FeedLogRecord(
                        feedID: feedID,
                        createdAt: now,
                        level: "info",
                        message: L10n.feedLogImportedFromOPML,
                        httpStatusCode: nil,
                    newArticleCount: 0
                )
                )
                if shouldWriteCurrentFeedBridge {
                    try saveSwiftDataBridge(feedRecord, context: context)
                }
            } catch {
                try? cleanupSQLiteSubscription(feedID: feedID)
                try? cleanupCreatedTags(createdTagIDs)
                try? cleanupCreatedFolder(createdFolder)
                if shouldWriteCurrentFeedBridge, let context {
                    context.rollback()
                }
                throw error
            }
            imported += 1

            if refreshAfterImport {
                do {
                    let refreshResult = try await SQLiteFeedRefreshService(
                    database: database,
                    fetcher: { [fetchFeed] url, _ in
                        .updated(try await fetchFeed(url), FeedHTTPValidators())
                    }
                )
                .refresh(feedID: feedID)
                if let refreshedFeed = try feedStore.feed(id: refreshResult.feedID) {
                    if shouldWriteCurrentFeedBridge {
                        try saveSwiftDataBridge(refreshedFeed, context: context)
                    }
                }
                } catch {
                    failedFeedTitles.append(title)
                }
            }
        }

        return SQLiteOPMLImportResult(
            total: opmlFeeds.count,
            imported: imported,
            skippedDuplicates: skippedDuplicates,
            failedFeedTitles: failedFeedTitles
        )
    }

    private func faviconURL(for parsedFeed: ParsedFeed) async -> String? {
        let parsedSiteURL = parsedFeed.siteURL
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap(URL.init(string:))
        guard let siteURL = parsedSiteURL ?? FaviconService.siteURL(from: parsedFeed.sourceURL) else {
            return nil
        }

        return await discoverFaviconURL(siteURL)
    }

    private func cleanupSQLiteSubscription(feedID: String) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    DELETE FROM article_statuses
                    WHERE articleID IN (
                        SELECT id
                        FROM articles
                        WHERE feedID = ?
                    )
                    """,
                arguments: [feedID]
            )
            try db.execute(
                sql: """
                    DELETE FROM feeds
                    WHERE id = ?
                    """,
                arguments: [feedID]
            )
        }
    }

    private func shouldUseSwiftDataBridge(context: ModelContext?) -> Bool {
        guard context != nil else {
            return false
        }

        return UserDefaults.standard.object(forKey: SwiftDataBridgeSettings.isEnabledKey) as? Bool
            ?? SwiftDataBridgeSettings.defaultIsEnabled
    }

    // BRÜCKEN-SCHREIBPFAD (hart isoliert, Plan T8): Schreibt einen SQLite-
    // `FeedRecord` zurück in SwiftData, damit die Übergangs-Relationships
    // (`Article.feed`/`Tag.feeds`) konsistent bleiben. Sidebar/ContentView lesen
    // nicht mehr hierüber (sie nutzen `FeedSidebarSnapshot`/`FeedRecord`). Diese
    // Funktion entfällt, sobald `Article`/`Tag` SQLite-only sind und `@Model Feed`
    // entfernt wird. Keine neuen Reads über diese Brücke.
    private func saveSwiftDataBridge(_ feedRecord: FeedRecord, context: ModelContext?) throws {
        guard shouldUseSwiftDataBridge(context: context), let context else {
            return
        }

        let feedID = UUID(uuidString: feedRecord.id) ?? UUID()
        var descriptor = FetchDescriptor<Feed>(
            predicate: #Predicate<Feed> { feed in
                feed.id == feedID
            }
        )
        descriptor.fetchLimit = 1

        let feed: Feed
        if let existingFeed = try context.fetch(descriptor).first {
            feed = existingFeed
        } else {
            feed = Feed(
                url: feedRecord.url,
                title: feedRecord.title,
                feedDescription: nil,
                faviconURL: feedRecord.faviconURL,
                siteURL: feedRecord.websiteURL,
                followedAt: feedRecord.createdAt,
                folderName: feedRecord.folderName,
                lastRefreshed: feedRecord.lastRefreshedAt,
                refreshIntervalMinutes: feedRecord.refreshIntervalMinutes
            )
            feed.id = feedID
            context.insert(feed)
        }

        feed.url = feedRecord.url
        feed.title = feedRecord.title
        feed.originalTitle = feedRecord.originalTitle
        feed.faviconURL = feedRecord.faviconURL
        feed.siteURL = feedRecord.websiteURL
        feed.folderName = feedRecord.folderName
        feed.refreshIntervalMinutes = feedRecord.refreshIntervalMinutes
        feed.articleRetentionOverridesGlobalSetting = feedRecord.articleRetentionOverridesGlobalSetting
        feed.articleRetentionIsEnabled = feedRecord.articleRetentionIsEnabled
        feed.articleRetentionDays = feedRecord.articleRetentionDays
        feed.articleRetentionMinimumArticles = feedRecord.articleRetentionMinimumArticles
        feed.articleRetentionIncludesProtectedArticles = feedRecord.articleRetentionIncludesProtectedArticles
        feed.unreadCount = feedRecord.unreadCount
        try context.save()
    }

    private func saveTags(_ tagNames: [String], feedID: String, createdAt: Date) throws -> [String] {
        let tagStore = TagStore(database: database)
        var tagsByName = Dictionary(
            uniqueKeysWithValues: try tagStore.tags().map { ($0.name.lowercased(), $0) }
        )
        var createdTagIDs: [String] = []

        for tagName in tagNames.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) where !tagName.isEmpty {
            let normalizedName = tagName.lowercased()
            let tag: TagRecord
            if let existingTag = tagsByName[normalizedName] {
                tag = existingTag
            } else {
                let newTag = TagRecord(
                    name: tagName,
                    createdAt: createdAt,
                    updatedAt: createdAt
                )
                try tagStore.save(newTag)
                tagsByName[normalizedName] = newTag
                createdTagIDs.append(newTag.id)
                tag = newTag
            }

            try tagStore.assignTag(tagID: tag.id, toFeedID: feedID, at: createdAt)
        }

        return createdTagIDs
    }

    private func normalizedFeedURL(_ urlString: String) -> String {
        urlString
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func trimmedNonEmpty(_ value: String?) -> String? {
        let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedValue, !trimmedValue.isEmpty else {
            return nil
        }

        return trimmedValue
    }

    private func cleanupCreatedTags(_ tagIDs: [String]) throws {
        guard !tagIDs.isEmpty else {
            return
        }

        try database.write { db in
            for tagID in tagIDs {
                let assignmentCount = try Int.fetchOne(db, sql: """
                    SELECT
                        (
                            SELECT COUNT(*)
                            FROM article_tags
                            WHERE tagID = ?
                        )
                        +
                        (
                            SELECT COUNT(*)
                            FROM feed_tags
                            WHERE tagID = ?
                        )
                    """, arguments: [tagID, tagID]) ?? 0

                if assignmentCount == 0 {
                    try db.execute(
                        sql: """
                            DELETE FROM tags
                            WHERE id = ?
                            """,
                        arguments: [tagID]
                    )
                }
            }
        }
    }

    private func cleanupCreatedFolder(_ folder: FeedFolderRecord?) throws {
        guard let folder else {
            return
        }

        try database.write { db in
            try db.execute(
                sql: """
                    DELETE FROM feed_folders
                    WHERE id = ?
                      AND NOT EXISTS (
                          SELECT 1
                          FROM feeds
                          WHERE folderName = ?
                      )
                    """,
                arguments: [folder.id, folder.name]
            )
        }
    }
}
