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
