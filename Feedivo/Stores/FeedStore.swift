import Foundation
import GRDB

struct FeedStore {
    private let database: FeedivoDatabase

    init(database: FeedivoDatabase) {
        self.database = database
    }

    func save(_ feed: FeedRecord) throws {
        try database.write { db in
            var feed = feed
            try feed.save(db)
        }
    }

    func feed(id: String) throws -> FeedRecord? {
        try database.read { db in
            try FeedRecord.fetchOne(db, key: id)
        }
    }

    func feed(url: String) throws -> FeedRecord? {
        try database.read { db in
            try FeedRecord.fetchOne(db, sql: """
                SELECT *
                FROM feeds
                WHERE url = ?
                LIMIT 1
                """, arguments: [url])
        }
    }

    func feeds() throws -> [FeedRecord] {
        try database.read { db in
            try FeedRecord.fetchAll(db, sql: """
                SELECT *
                FROM feeds
                ORDER BY title COLLATE NOCASE, url COLLATE NOCASE
                """)
        }
    }

    func renameFeed(id: String, displayTitle: String) throws {
        let title = displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw FeedStoreError.emptyTitle
        }

        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE feeds
                    SET title = ?,
                        originalTitle = COALESCE(NULLIF(originalTitle, ''), title),
                        updatedAt = ?
                    WHERE id = ?
                    """,
                arguments: [title, Date(), id]
            )

            if db.changesCount == 0 {
                throw FeedStoreError.missingFeed
            }
        }
    }

    func restoreOriginalTitle(id: String) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE feeds
                    SET title = COALESCE(NULLIF(originalTitle, ''), title),
                        updatedAt = ?
                    WHERE id = ?
                    """,
                arguments: [Date(), id]
            )

            if db.changesCount == 0 {
                throw FeedStoreError.missingFeed
            }
        }
    }

    func updateRefreshInterval(id: String, minutes: Int) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE feeds
                    SET refreshIntervalMinutes = ?, updatedAt = ?
                    WHERE id = ?
                    """,
                arguments: [BackgroundRefreshSettings.clampedIntervalMinutes(minutes), Date(), id]
            )

            if db.changesCount == 0 {
                throw FeedStoreError.missingFeed
            }
        }
    }

    func updateFolderName(id: String, folderName: String?) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE feeds
                    SET folderName = ?, updatedAt = ?
                    WHERE id = ?
                    """,
                arguments: [FeedFolderOrganizer.normalizedFolderName(folderName), Date(), id]
            )

            if db.changesCount == 0 {
                throw FeedStoreError.missingFeed
            }
        }
    }

    func updateNotificationEnabled(id: String, isEnabled: Bool) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE feeds
                    SET isNotificationEnabled = ?, updatedAt = ?
                    WHERE id = ?
                    """,
                arguments: [isEnabled, Date(), id]
            )

            if db.changesCount == 0 {
                throw FeedStoreError.missingFeed
            }
        }
    }

    func updateRetentionSettings(
        id: String,
        overridesGlobal: Bool,
        isEnabled: Bool,
        days: Int,
        includesProtectedArticles: Bool
    ) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE feeds
                    SET articleRetentionOverridesGlobalSetting = ?,
                        articleRetentionIsEnabled = ?,
                        articleRetentionDays = ?,
                        articleRetentionIncludesProtectedArticles = ?,
                        updatedAt = ?
                    WHERE id = ?
                    """,
                arguments: [
                    overridesGlobal,
                    isEnabled,
                    ArticleRetentionSettings.clampedRetentionDays(days),
                    includesProtectedArticles,
                    Date(),
                    id
                ]
            )

            if db.changesCount == 0 {
                throw FeedStoreError.missingFeed
            }
        }
    }

    func delete(id: String) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    DELETE FROM feeds
                    WHERE id = ?
                    """,
                arguments: [id]
            )
        }
    }

    func updateAfterRefresh(
        feedID: String,
        title: String?,
        websiteURL: String?,
        validators: FeedHTTPValidators,
        unreadCount: Int,
        refreshedAt: Date
    ) throws {
        try database.write { db in
            let trimmedTitle = title.trimmedNonEmpty
            let titleAssignment = trimmedTitle == nil ? "" : "title = ?,"
            var arguments = StatementArguments()
            if let trimmedTitle {
                arguments.append(contentsOf: [trimmedTitle])
            }
            arguments.append(contentsOf: [
                websiteURL.trimmedNonEmpty,
                refreshedAt,
                validators.eTag,
                validators.lastModified,
                validators.contentHash,
                validators.lastStatusCode,
                unreadCount,
                refreshedAt,
                feedID
            ])

            try db.execute(
                sql: """
                    UPDATE feeds
                    SET \(titleAssignment)
                        websiteURL = COALESCE(?, websiteURL),
                        lastRefreshedAt = ?,
                        lastETag = ?,
                        lastModified = ?,
                        lastBodyHash = ?,
                        lastHTTPStatusCode = ?,
                        unreadCount = ?,
                        updatedAt = ?
                    WHERE id = ?
                    """,
                arguments: arguments
            )
        }
    }

    func setUnreadCount(_ unreadCount: Int, feedID: String) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE feeds
                    SET unreadCount = ?, updatedAt = ?
                    WHERE id = ?
                    """,
                arguments: [unreadCount, Date(), feedID]
            )
        }
    }

    func sidebarFeeds() throws -> [FeedSidebarSnapshot] {
        try database.read { db in
            let snapshots = try FeedSidebarSnapshot.fetchAll(db, sql: """
                SELECT id, title, url, faviconURL, folderName, unreadCount
                FROM feeds
                ORDER BY title COLLATE NOCASE, id COLLATE NOCASE
                """)
            return snapshots.sorted {
                let titleOrder = $0.title.localizedStandardCompare($1.title)
                if titleOrder != .orderedSame {
                    return titleOrder == .orderedAscending
                }

                return $0.id.localizedStandardCompare($1.id) == .orderedAscending
            }
        }
    }

    func sidebarFeeds(showsReadFeeds: Bool) throws -> [FeedSidebarSnapshot] {
        let snapshots = try sidebarFeeds()
        guard !showsReadFeeds else {
            return snapshots
        }

        return snapshots.filter { $0.unreadCount > 0 }
    }

    func opmlFeedsForExport() throws -> [OPMLFeed] {
        try database.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT
                    f.id,
                    f.title,
                    f.url,
                    f.websiteURL,
                    f.folderName,
                    GROUP_CONCAT(t.name, '\u{1F}') AS tagNames
                FROM feeds f
                LEFT JOIN feed_tags ft ON ft.feedID = f.id
                LEFT JOIN tags t ON t.id = ft.tagID
                GROUP BY f.id
                ORDER BY f.title COLLATE NOCASE, f.id COLLATE NOCASE
                """)

            return rows.map { row in
                let tagList = (row["tagNames"] as String?)
                    .map { $0.split(separator: "\u{1F}").map(String.init) }
                    ?? []

                return OPMLFeed(
                    title: row["title"],
                    xmlURL: row["url"],
                    htmlURL: row["websiteURL"],
                    folderName: row["folderName"],
                    description: nil,
                    tagNames: tagList.sorted {
                        $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
                    }
                )
            }
        }
    }
}

enum FeedStoreError: Error, Equatable {
    case emptyTitle
    case missingFeed
}

private extension Optional where Wrapped == String {
    var trimmedNonEmpty: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }
}

extension FeedSidebarSnapshot: FetchableRecord {
    init(row: Row) throws {
        id = row["id"]
        title = row["title"]
        url = row["url"]
        faviconURL = row["faviconURL"]
        folderName = row["folderName"]
        unreadCount = row["unreadCount"]
    }
}
