import Foundation
import CloudKit
import GRDB

/// Mapping für die syncbare TEILMENGE der `feeds`-Tabelle. NUR Konfigurationsfelder syncen —
/// Refresh-Metadaten (`lastRefreshedAt`/`lastETag`/`lastModified`/`lastBodyHash`/
/// `lastHTTPStatusCode`) und `unreadCount` bleiben bewusst rein lokal (siehe Design-Spec
/// `docs/superpowers/specs/2026-07-24-icloud-sync-phase2a-design.md`). Diese Felder werden von
/// `FeedStore.updateAfterRefresh`/`setUnreadCount` bei praktisch jedem RSS-Refresh geschrieben —
/// würden sie mitgesynct, würde jeder normale Feed-Refresh auf jedem Gerät einen CloudKit-Upload
/// auslösen und (schlimmer) über die Last-Write-Wins-Konfliktauflösung mit den echten
/// Konfigurationsänderungen eines anderen Geräts kollidieren können.
enum CloudSyncFeedMapping: CloudSyncRecordMapping {
    static let recordType = "Feed"

    /// Reine, aus einem `CKRecord` gelesene Konfigurationswerte — Zwischenformat für
    /// `applyIncoming`, das zwischen "Feed existiert lokal bereits" (partielles UPDATE) und
    /// "Feed ist neu für dieses Gerät" (voller INSERT) unterscheiden muss.
    struct FeedConfig {
        let url: String
        let title: String
        let originalTitle: String?
        let websiteURL: String?
        let faviconURL: String?
        let folderName: String?
        let sortIndex: Int
        let refreshIntervalMinutes: Int
        let isNotificationEnabled: Bool
        let articleRetentionOverridesGlobalSetting: Bool
        let articleRetentionIsEnabled: Bool
        let articleRetentionDays: Int
        let articleRetentionMinimumArticles: Int
        let articleRetentionIncludesProtectedArticles: Bool
    }

    static func makeCKRecord(from feed: FeedRecord, existing: CKRecord? = nil) -> CKRecord {
        let record = existing ?? CKRecord(recordType: recordType, recordID: recordID(forLocalID: feed.id))
        record["url"] = feed.url as CKRecordValue
        record["title"] = feed.title as CKRecordValue
        record["originalTitle"] = feed.originalTitle as CKRecordValue?
        record["websiteURL"] = feed.websiteURL as CKRecordValue?
        record["faviconURL"] = feed.faviconURL as CKRecordValue?
        record["folderName"] = feed.folderName as CKRecordValue?
        record["sortIndex"] = feed.sortIndex as CKRecordValue
        record["refreshIntervalMinutes"] = feed.refreshIntervalMinutes as CKRecordValue
        record["isNotificationEnabled"] = feed.isNotificationEnabled as CKRecordValue
        record["articleRetentionOverridesGlobalSetting"] = feed.articleRetentionOverridesGlobalSetting as CKRecordValue
        record["articleRetentionIsEnabled"] = feed.articleRetentionIsEnabled as CKRecordValue
        record["articleRetentionDays"] = feed.articleRetentionDays as CKRecordValue
        record["articleRetentionMinimumArticles"] = feed.articleRetentionMinimumArticles as CKRecordValue
        record["articleRetentionIncludesProtectedArticles"] = feed.articleRetentionIncludesProtectedArticles as CKRecordValue
        return record
    }

    static func feedConfig(from ckRecord: CKRecord) -> FeedConfig? {
        guard
            let url = ckRecord["url"] as? String,
            let title = ckRecord["title"] as? String,
            let sortIndex = ckRecord["sortIndex"] as? Int,
            let refreshIntervalMinutes = ckRecord["refreshIntervalMinutes"] as? Int,
            let isNotificationEnabled = ckRecord["isNotificationEnabled"] as? Bool,
            let overridesGlobal = ckRecord["articleRetentionOverridesGlobalSetting"] as? Bool,
            let retentionIsEnabled = ckRecord["articleRetentionIsEnabled"] as? Bool,
            let retentionDays = ckRecord["articleRetentionDays"] as? Int,
            let retentionMinimumArticles = ckRecord["articleRetentionMinimumArticles"] as? Int,
            let retentionIncludesProtected = ckRecord["articleRetentionIncludesProtectedArticles"] as? Bool
        else {
            return nil
        }

        return FeedConfig(
            url: url,
            title: title,
            originalTitle: ckRecord["originalTitle"] as? String,
            websiteURL: ckRecord["websiteURL"] as? String,
            faviconURL: ckRecord["faviconURL"] as? String,
            folderName: ckRecord["folderName"] as? String,
            sortIndex: sortIndex,
            refreshIntervalMinutes: refreshIntervalMinutes,
            isNotificationEnabled: isNotificationEnabled,
            articleRetentionOverridesGlobalSetting: overridesGlobal,
            articleRetentionIsEnabled: retentionIsEnabled,
            articleRetentionDays: retentionDays,
            articleRetentionMinimumArticles: retentionMinimumArticles,
            articleRetentionIncludesProtectedArticles: retentionIncludesProtected
        )
    }

    // MARK: - CloudSyncRecordMapping

    static func makeCKRecord(fromLocalID id: String, existing: CKRecord?, database: FeedivoDatabase) throws -> CKRecord? {
        guard let feed = try FeedStore(database: database).feed(id: id) else { return nil }
        return makeCKRecord(from: feed, existing: existing)
    }

    static func applyIncoming(_ record: CKRecord, database: FeedivoDatabase) throws {
        guard let config = feedConfig(from: record) else { return }
        let localID = record.recordID.recordName
        let modificationDate = record.modificationDate ?? Date()

        try database.write { db in
            let exists = try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM feeds WHERE id = ?)", arguments: [localID]) ?? false

            if exists {
                try db.execute(
                    sql: """
                        UPDATE feeds
                        SET url = ?, title = ?, originalTitle = ?, websiteURL = ?, faviconURL = ?,
                            folderName = ?, sortIndex = ?, refreshIntervalMinutes = ?,
                            isNotificationEnabled = ?, articleRetentionOverridesGlobalSetting = ?,
                            articleRetentionIsEnabled = ?, articleRetentionDays = ?,
                            articleRetentionMinimumArticles = ?, articleRetentionIncludesProtectedArticles = ?,
                            configUpdatedAt = ?
                        WHERE id = ?
                        """,
                    arguments: [
                        config.url, config.title, config.originalTitle, config.websiteURL, config.faviconURL,
                        config.folderName, config.sortIndex, config.refreshIntervalMinutes,
                        config.isNotificationEnabled, config.articleRetentionOverridesGlobalSetting,
                        config.articleRetentionIsEnabled, config.articleRetentionDays,
                        config.articleRetentionMinimumArticles, config.articleRetentionIncludesProtectedArticles,
                        modificationDate, localID
                    ]
                )
            } else {
                var newFeed = FeedRecord(
                    id: localID,
                    url: config.url,
                    title: config.title,
                    originalTitle: config.originalTitle,
                    websiteURL: config.websiteURL,
                    faviconURL: config.faviconURL,
                    folderName: config.folderName,
                    sortIndex: config.sortIndex,
                    refreshIntervalMinutes: config.refreshIntervalMinutes,
                    isNotificationEnabled: config.isNotificationEnabled,
                    articleRetentionOverridesGlobalSetting: config.articleRetentionOverridesGlobalSetting,
                    articleRetentionIsEnabled: config.articleRetentionIsEnabled,
                    articleRetentionDays: config.articleRetentionDays,
                    articleRetentionMinimumArticles: config.articleRetentionMinimumArticles,
                    articleRetentionIncludesProtectedArticles: config.articleRetentionIncludesProtectedArticles,
                    configUpdatedAt: modificationDate
                )
                try newFeed.insert(db)
            }
        }
    }

    static func applyIncomingDeletion(recordID: CKRecord.ID, database: FeedivoDatabase) throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM feeds WHERE id = ?", arguments: [recordID.recordName])
        }
    }

    static func localUpdatedAt(forLocalID id: String, database: FeedivoDatabase) throws -> Date? {
        try FeedStore(database: database).feed(id: id)?.configUpdatedAt
    }

    static func allLocalIDs(database: FeedivoDatabase) throws -> [String] {
        try database.read { db in
            try String.fetchAll(db, sql: "SELECT id FROM feeds")
        }
    }
}
