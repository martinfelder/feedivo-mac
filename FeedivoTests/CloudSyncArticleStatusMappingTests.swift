import Foundation
import CloudKit
import GRDB
import Testing
@testable import Feedivo

private func seedArticle(database: FeedivoDatabase, articleID: String = "article-1", feedID: String = "feed-1", sourceID: String = "article-1", title: String = "Titel") throws -> String {
    try FeedStore(database: database).save(FeedRecord(id: feedID, url: "https://example.com/\(feedID)", title: "Feed"))
    return try ArticleStore(database: database).upsert(
        ArticleUpsertInput(feedID: feedID, sourceID: sourceID, title: title, arrivedAt: Date(timeIntervalSince1970: 100))
    )
}

struct CloudSyncArticleStatusMappingTests {
    @Test func makeCKRecordMapptIsReadUndIsStarredUndNutztSyncStableIDAlsRecordID() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let articleID = try seedArticle(database: database)
        var status = try ArticleStatusStore(database: database).status(articleID: articleID)!
        status.isRead = true
        status.isStarred = true
        status.readAt = Date(timeIntervalSince1970: 100)
        status.starredAt = Date(timeIntervalSince1970: 200)

        let record = CloudSyncArticleStatusMapping.makeCKRecord(from: status)

        #expect(record.recordType == "ArticleStatus")
        #expect(record.recordID.recordName == status.syncStableID)
        #expect(record["isRead"] as? Bool == true)
        #expect(record["isStarred"] as? Bool == true)
        #expect(record["readAt"] as? Date == Date(timeIntervalSince1970: 100))
        #expect(record["starredAt"] as? Date == Date(timeIntervalSince1970: 200))
    }

    @Test func allLocalIDsListetSyncStableIDsNurBeruehrterStatusAuf() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let unberuehrtID = try seedArticle(database: database, articleID: "unberuehrt", sourceID: "s-unberuehrt")
        let beruehrtID = try seedArticle(database: database, articleID: "beruehrt", sourceID: "s-beruehrt")
        try ArticleStatusStore(database: database).setRead(true, articleID: beruehrtID, at: Date())
        let beruehrterStatus = try ArticleStatusStore(database: database).status(articleID: beruehrtID)!

        let ids = try CloudSyncArticleStatusMapping.allLocalIDs(database: database)

        #expect(ids == [beruehrterStatus.syncStableID])
        _ = unberuehrtID
    }

    @Test func makeCKRecordFromLocalIDLiefertNilFuerUnbekannteID() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        let record = try CloudSyncArticleStatusMapping.makeCKRecord(fromLocalID: "unbekannt-hash", existing: nil, database: database)

        #expect(record == nil)
    }

    @Test func localUpdatedAtLiefertStatusSyncUpdatedAtUeberSyncStableID() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let articleID = try seedArticle(database: database)
        try ArticleStatusStore(database: database).setRead(true, articleID: articleID, at: Date())
        let status = try ArticleStatusStore(database: database).status(articleID: articleID)!

        let localUpdatedAt = try CloudSyncArticleStatusMapping.localUpdatedAt(forLocalID: status.syncStableID!, database: database)

        #expect(localUpdatedAt != nil)
    }

    @Test func applyIncomingAktualisiertBestehendenArtikelStatusUeberSyncStableID() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let articleID = try seedArticle(database: database)
        let status = try ArticleStatusStore(database: database).status(articleID: articleID)!
        let record = CKRecord(recordType: "ArticleStatus", recordID: CloudSyncArticleStatusMapping.recordID(forLocalID: status.syncStableID!))
        record["isRead"] = true as CKRecordValue
        record["isStarred"] = false as CKRecordValue

        try CloudSyncArticleStatusMapping.applyIncoming(record, database: database)

        let updated = try ArticleStatusStore(database: database).status(articleID: articleID)
        #expect(updated?.isRead == true)
        #expect(updated?.isStarred == false)
    }

    @Test func applyIncomingSimuliertZweitesGeraetMitAndererLokalerArticleID() throws {
        // Zwei unabhängige "Geräte": beide kennen denselben logischen Artikel (gleicher
        // feedID+sourceID), aber jedes hat seine EIGENE lokale articleID-UUID — genau das
        // Szenario, das der ursprüngliche Bug nicht abdeckte. Ein von "Gerät A" gesendeter
        // Status muss auf "Gerät B" trotzdem ankommen.
        let deviceA = try FeedivoDatabase.inMemoryForTests()
        let deviceB = try FeedivoDatabase.inMemoryForTests()
        let articleIDOnA = try seedArticle(database: deviceA, articleID: "a-local-id", feedID: "feed-1", sourceID: "guid-shared", title: "Geteilter Titel")
        let articleIDOnB = try seedArticle(database: deviceB, articleID: "b-local-id", feedID: "feed-1", sourceID: "guid-shared", title: "Geteilter Titel")
        #expect(articleIDOnA != articleIDOnB)

        try ArticleStatusStore(database: deviceA).setRead(true, articleID: articleIDOnA, at: Date())
        let statusOnA = try ArticleStatusStore(database: deviceA).status(articleID: articleIDOnA)!
        let record = CloudSyncArticleStatusMapping.makeCKRecord(from: statusOnA)

        try CloudSyncArticleStatusMapping.applyIncoming(record, database: deviceB)

        let statusOnB = try ArticleStatusStore(database: deviceB).status(articleID: articleIDOnB)
        #expect(statusOnB?.isRead == true)
    }

    @Test func applyIncomingLegtVerwaistenEintragAnFuerUnbekanntesSyncStableID() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let record = CKRecord(recordType: "ArticleStatus", recordID: CloudSyncArticleStatusMapping.recordID(forLocalID: "unbekannt-hash"))
        record["isRead"] = true as CKRecordValue
        record["isStarred"] = false as CKRecordValue

        try CloudSyncArticleStatusMapping.applyIncoming(record, database: database)

        let orphan = try database.read { db in
            try OrphanedArticleStatusUpdateRecord.fetchOne(db, key: "unbekannt-hash")
        }
        #expect(orphan?.isRead == true)
        #expect(orphan?.isStarred == false)
    }

    @Test func applyIncomingDeletionSetztStatusAufDefaultsWennArtikelLokalNochExistiert() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let articleID = try seedArticle(database: database)
        try ArticleStatusStore(database: database).setRead(true, articleID: articleID, at: Date())
        let status = try ArticleStatusStore(database: database).status(articleID: articleID)!

        try CloudSyncArticleStatusMapping.applyIncomingDeletion(recordID: CloudSyncArticleStatusMapping.recordID(forLocalID: status.syncStableID!), database: database)

        let afterDeletion = try ArticleStatusStore(database: database).status(articleID: articleID)
        #expect(afterDeletion != nil)
        #expect(afterDeletion?.isRead == false)
        #expect(afterDeletion?.isStarred == false)
    }

    @Test func applyIncomingDeletionEntferntVerwaistenEintrag() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try database.write { db in
            var orphan = OrphanedArticleStatusUpdateRecord(articleID: "verwaist-hash", isRead: true, isStarred: false, readAt: nil, starredAt: nil, receivedAt: Date())
            try orphan.insert(db)
        }

        try CloudSyncArticleStatusMapping.applyIncomingDeletion(recordID: CloudSyncArticleStatusMapping.recordID(forLocalID: "verwaist-hash"), database: database)

        let orphan = try database.read { db in
            try OrphanedArticleStatusUpdateRecord.fetchOne(db, key: "verwaist-hash")
        }
        #expect(orphan == nil)
    }

    @Test func enqueueDeletionIfSyncedEnqueuedSyncStableIDNurFuerBeruehrteIDs() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let beruehrtID = try seedArticle(database: database, articleID: "beruehrt", sourceID: "s-beruehrt")
        let unberuehrtID = try seedArticle(database: database, articleID: "unberuehrt", sourceID: "s-unberuehrt")
        try ArticleStatusStore(database: database).setStarred(true, articleID: beruehrtID, at: Date())
        let beruehrterStatus = try ArticleStatusStore(database: database).status(articleID: beruehrtID)!
        UserDefaults.standard.set(true, forKey: CloudSyncSettings.isEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey) }

        try database.write { db in
            try CloudSyncArticleStatusMapping.enqueueDeletionIfSynced(articleIDs: [beruehrtID, unberuehrtID], db: db)
        }

        let pending = try CloudSyncPendingChangeStore(database: database).pendingChanges()
        #expect(pending.map(\.id) == [beruehrterStatus.syncStableID])
        #expect(pending.first?.changeType == .delete)
    }
}
