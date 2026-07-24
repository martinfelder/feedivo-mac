import Foundation
import GRDB

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

// MARK: - OPML-Importvorschau
//
// Diese UI-Nutz-Modelle werden vom `SQLiteFeedSubscriptionService` gefüllt und
// von der OPML-Import-Oberfläche (Preview-Controller, Feed-Zeilen) gerendert.
// Sie leben hier beim produzierenden Service und nicht im `FeedViewModel`, damit
// der ViewModel nur noch UI-State delegiert und keine eigene Feed-Abruflogik
// besitzt.

enum OPMLImportFeedStatus: Equatable, Sendable {
    case available
    case duplicate
    case unreachable
}

struct OPMLImportPreviewRow: Identifiable, Equatable, Sendable {
    let id = UUID()
    var feed: OPMLFeed
    var status: OPMLImportFeedStatus
    var isSelected: Bool
}

struct OPMLImportPreviewProgress: Equatable, Sendable {
    var currentFeedTitle: String
    var currentIndex: Int
    var totalCount: Int

    var displayText: String {
        "Feed \(currentIndex) von \(totalCount) wird geprüft: \(currentFeedTitle)"
    }
}

@MainActor
struct SQLiteFeedSubscriptionService {
    typealias FeedFetcher = (String) async throws -> ParsedFeed
    typealias FaviconFetcher = (URL) async -> String?
    typealias ArticleUpserter = ([ArticleUpsertInput]) throws -> ArticleUpsertResult
    typealias AfterArticleUpsertHook = () throws -> Void
    typealias AfterOPMLTagsSaveHook = () throws -> Void
    typealias SpotlightIndexer = ([ArticleListSnapshot]) -> Void

    private let database: FeedivoDatabase
    private let fetchFeed: FeedFetcher
    private let discoverFaviconURL: FaviconFetcher
    private let articleUpsert: ArticleUpserter
    private let afterArticleUpsert: AfterArticleUpsertHook
    private let afterOPMLTagsSave: AfterOPMLTagsSaveHook
    private let indexForSpotlight: SpotlightIndexer
    private let userDefaults: UserDefaults

    init(
        database: FeedivoDatabase,
        fetchFeed: @escaping FeedFetcher = FeedService.fetchFeed,
        discoverFaviconURL: @escaping FaviconFetcher = { siteURL in
            await FaviconService.discoverFaviconURL(siteURL: siteURL)
        },
        articleUpsert: ArticleUpserter? = nil,
        afterArticleUpsert: @escaping AfterArticleUpsertHook = {},
        afterOPMLTagsSave: @escaping AfterOPMLTagsSaveHook = {},
        indexForSpotlight: @escaping SpotlightIndexer = { SpotlightIndexingService.indexArticles($0) },
        userDefaults: UserDefaults = .standard
    ) {
        self.database = database
        self.fetchFeed = fetchFeed
        self.discoverFaviconURL = discoverFaviconURL
        self.articleUpsert = articleUpsert ?? { inputs in
            try ArticleStore(database: database).upsert(inputs)
        }
        self.afterArticleUpsert = afterArticleUpsert
        self.afterOPMLTagsSave = afterOPMLTagsSave
        self.indexForSpotlight = indexForSpotlight
        self.userDefaults = userDefaults
    }

    func addFeed(
        urlString: String,
        refreshIntervalMinutes: Int = 60,
        folderName: String? = nil
    ) async throws -> SQLiteFeedSubscriptionResult {
        let cleanedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedURL.isEmpty else {
            throw SQLiteFeedSubscriptionError.emptyURL
        }

        let parsedFeed = try await fetchFeed(cleanedURL)
        let feedStore = FeedStore(database: database)
        let folderStore = FeedFolderStore(database: database)
        let normalizedFolderName = FeedFolderOrganizer.normalizedFolderName(folderName)
        let candidateURLs = Set([cleanedURL, parsedFeed.sourceURL].map(normalizedFeedURL))
        let existingFeeds = try feedStore.feeds()
        guard !existingFeeds.contains(where: { candidateURLs.contains(normalizedFeedURL($0.url)) }) else {
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
            folderName: normalizedFolderName,
            refreshIntervalMinutes: BackgroundRefreshSettings.clampedIntervalMinutes(refreshIntervalMinutes),
            isNotificationEnabled: NotificationSettings.isEnabledForNewFeeds(in: userDefaults),
            createdAt: now,
            updatedAt: now
        )

        // Analog zum OPML-Import (siehe importOPMLFeeds) wird der ggf. neu
        // angelegte Ordner hier festgehalten, damit der catch-Block ihn bei
        // einem nachgelagerten Fehler wieder entfernen kann — sonst bleibt ein
        // verwaister leerer Ordner in der Sidebar zurueck.
        var createdFolder: FeedFolderRecord?

        do {
            // Bei neuem (normalisiertem) Ordnernamen zusaetzlich einen expliziten
            // feed_folders-Record anlegen — analog zum OPML-Import. Case-insensitiver
            // Abgleich verhindert Duplikate zu bestehenden Ordnern.
            if let normalizedFolderName {
                let knownFolderNames = Set(try folderStore.folders().map { $0.name.lowercased() })
                if !knownFolderNames.contains(normalizedFolderName.lowercased()) {
                    let folderRecord = FeedFolderRecord(
                        name: normalizedFolderName,
                        createdAt: now,
                        updatedAt: now
                    )
                    try folderStore.save(folderRecord)
                    createdFolder = folderRecord
                }
            }

            try feedStore.save(feedRecord)

            let articleInputs = parsedFeed.articles.map { article in
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
                    arrivedAt: now
                )
            }
            let upsertResult = try articleUpsert(articleInputs)
            try afterArticleUpsert()
            logIfThrows(context: "Spotlight-Indexierung nach Feed-Abo") {
                guard !upsertResult.insertedArticleIDs.isEmpty else {
                    return
                }
                let snapshotsToIndex = try ArticleDatabase(database: database).fetchArticles(
                    articleIDs: Set(upsertResult.insertedArticleIDs),
                    includeHidden: false
                )
                indexForSpotlight(snapshotsToIndex)
            }
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
        } catch {
            logIfThrows(context: "Rollback nach addFeed-Fehler (Feed/Artikel-Status löschen)") {
                try cleanupSQLiteSubscription(feedID: feedID)
            }
            logIfThrows(context: "Rollback nach addFeed-Fehler (leeren Ordner entfernen)") {
                try cleanupCreatedFolder(createdFolder)
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
        refreshIntervalMinutes: Int
    ) async throws -> SQLiteOPMLImportResult {
        let feedStore = FeedStore(database: database)
        let folderStore = FeedFolderStore(database: database)
        let logStore = FeedLogStore(database: database)
        let clampedRefreshInterval = BackgroundRefreshSettings.clampedIntervalMinutes(refreshIntervalMinutes)
        var knownURLs = Set(
            try feedStore.feeds().map(\.url)
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
                isNotificationEnabled: NotificationSettings.isEnabledForNewFeeds(in: userDefaults),
                createdAt: now,
                updatedAt: now
            )
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
            } catch {
                logIfThrows(context: "Rollback nach OPML-Import-Fehler (Feed/Artikel-Status löschen)") {
                    try cleanupSQLiteSubscription(feedID: feedID)
                }
                logIfThrows(context: "Rollback nach OPML-Import-Fehler (neu angelegte Tags entfernen)") {
                    try cleanupCreatedTags(createdTagIDs)
                }
                logIfThrows(context: "Rollback nach OPML-Import-Fehler (leeren Ordner entfernen)") {
                    try cleanupCreatedFolder(createdFolder)
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

    /// OPML-Importvorschau: erzeugt für jede OPML-Feed-URL eine Zeile mit Status
    /// `available`, `duplicate` oder `unreachable`. Duplikate werden gegen die
    /// bereits in SQLite gespeicherten Feeds geprüft; die Erreichbarkeit wird
    /// parallel und gedrosselt über den injizierten `fetchFeed`-Abruf geprüft.
    ///
    /// Diese Methode ist der produktive Vorschau-Pfad und lag zuvor inline im
    /// `FeedViewModel`. Sie wurde hierher verschoben, damit `FeedViewModel` nur
    /// noch UI-State hält und keine eigene Feed-Arbeit mehr ausführt.
    @MainActor
    func previewOPMLFeeds(
        for opmlFeeds: [OPMLFeed],
        onProgress: ((OPMLImportPreviewProgress) -> Void)? = nil
    ) async -> [OPMLImportPreviewRow] {
        let sqliteFeedURLs = (try? FeedStore(database: database).feeds().map(\.url)) ?? []
        var knownFeedURLs = Set(sqliteFeedURLs.map { normalizedFeedURL($0) })

        // Indexiertes Ergebnis-Array, damit die Abrufe in Phase 2 parallel laufen
        // können, ohne die Original-Reihenfolge zu verlieren.
        struct PendingFeed {
            let index: Int
            let cleanedURL: String
        }
        var pending: [PendingFeed] = []
        var rowsByIndex = Array<OPMLImportPreviewRow?>(repeating: nil, count: opmlFeeds.count)

        // Phase 1 — sequenziell: Duplikat-Status feststellen und Abruf-Bedarf
        // sammeln. Das URL-Set darf nicht concurrent mutiert werden, daher bleibt
        // diese Phase bewusst seriell. Der onProgress-Callback wird hier pro Feed
        // in Original-Reihenfolge aufgerufen.
        for (index, opmlFeed) in opmlFeeds.enumerated() {
            onProgress?(
                OPMLImportPreviewProgress(
                    currentFeedTitle: opmlFeed.title.trimmingCharacters(in: .whitespacesAndNewlines),
                    currentIndex: index + 1,
                    totalCount: opmlFeeds.count
                )
            )
            let cleanedURL = opmlFeed.xmlURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedURL = normalizedFeedURL(cleanedURL)
            let isDuplicate = !knownFeedURLs.insert(normalizedURL).inserted

            if isDuplicate {
                rowsByIndex[index] = OPMLImportPreviewRow(
                    feed: opmlFeed,
                    status: .duplicate,
                    isSelected: false
                )
            } else if !isSyntacticallyValidFeedURL(cleanedURL) {
                // Offensichtlich kaputte URLs (Leerzeichen, fehlendes Schema) sofort als
                // nicht erreichbar markieren statt einen Netzwerk-Roundtrip zu verschwenden,
                // der ohnehin fehlschlagen würde.
                rowsByIndex[index] = OPMLImportPreviewRow(
                    feed: opmlFeed,
                    status: .unreachable,
                    isSelected: false
                )
            } else {
                pending.append(PendingFeed(index: index, cleanedURL: cleanedURL))
            }
        }

        // Phase 2 — parallel: Erreichbarkeit prüfen, in begrenzten Gruppen
        // (gleiche Drosselung wie der Sammel-Refresh). Ergebnisse werden indexiert
        // in `rowsByIndex` einsortiert, nicht in eine gemeinsam mutierte Liste
        // appendet — so bleibt die Original-Reihenfolge erhalten.
        //
        // `completedFetches` ist ein monotoner MainActor-Zähler, der unabhängig
        // von der Completion-Reihenfolge der Tasks deterministisch 1..k hochzählt.
        // Ohne diese Phase-2-Updates würde der Fortschrittsbalken während der
        // langsamen Abruf-Phase sichtbar „einfrieren".
        var completedFetches = 0
        for batch in batches(pending, size: FeedViewModel.maxConcurrentFeedRefreshes) {
            await withTaskGroup(of: (Int, OPMLImportFeedStatus).self) { group in
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
                for await (index, status) in group {
                    completedFetches += 1
                    let isSelected = (status == .available)
                    rowsByIndex[index] = OPMLImportPreviewRow(
                        feed: opmlFeeds[index],
                        status: status,
                        isSelected: isSelected
                    )
                    onProgress?(
                        OPMLImportPreviewProgress(
                            currentFeedTitle: opmlFeeds[index].title.trimmingCharacters(in: .whitespacesAndNewlines),
                            currentIndex: completedFetches,
                            totalCount: opmlFeeds.count
                        )
                    )
                }
            }
        }

        return rowsByIndex.compactMap { $0 }
    }

    private func batches<T>(_ items: [T], size: Int) -> [[T]] {
        guard !items.isEmpty else {
            return []
        }
        return stride(from: 0, to: items.count, by: size).map { start in
            Array(items[start ..< min(start + size, items.count)])
        }
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

    /// Lokale Syntax-Prüfung für OPML-`xmlUrl`-Werte, bevor ein Netzwerk-Fetch versucht
    /// wird. Verlangt nur Schema + Host (kein `http`/`https`-Zwang), damit z. B. Test-
    /// Platzhalter wie `fail://broken` weiterhin über den echten Fetch-Pfad laufen und
    /// nicht schon hier als "ungültig" abgefangen werden.
    private func isSyntacticallyValidFeedURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString), let scheme = url.scheme, !scheme.isEmpty, url.host != nil else {
            return false
        }
        return true
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
