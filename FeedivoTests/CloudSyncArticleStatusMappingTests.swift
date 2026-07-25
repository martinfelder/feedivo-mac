import Foundation
import CloudKit
import GRDB
import Testing
@testable import Feedivo

private func seedArticle(database: FeedivoDatabase, articleID: String = "article-1", feedID: String = "feed-1") throws -> String {
    try FeedStore(database: database).save(FeedRecord(id: feedID, url: "https://example.com/\(feedID)", title: "Feed"))
    return try ArticleStore(database: database).upsert(
        ArticleUpsertInput(feedID: feedID, sourceID: articleID, title: "Titel", arrivedAt: Date(timeIntervalSince1970: 100))
    )
}

/// Setzt `article_statuses.statusSyncUpdatedAt` direkt per SQL. `ArticleStatusStore.setRead`/
/// `.setStarred` setzen diese Spalte erst ab Task 4 (siehe Plan) — dieser Task (3) testet nur
/// `CloudSyncArticleStatusMapping` selbst, unabhängig davon, WER die Spalte später befüllt.
/// Direkt gegen die Spalte zu schreiben hält diesen Testfall unabhängig von der noch
/// ausstehenden Task-4-Implementierung.
private func markStatusSyncUpdatedAt(database: FeedivoDatabase, articleID: String, at date: Date = Date()) throws {
    try database.write { db in
        try db.execute(sql: "UPDATE article_statuses SET statusSyncUpdatedAt = ? WHERE articleID = ?", arguments: [date, articleID])
    }
}

struct CloudSyncArticleStatusMappingTests {
    @Test func makeCKRecordMapptIsReadUndIsStarred() {
        let status = ArticleStatusRecord(
            articleID: "article-1",
            isRead: true,
            isStarred: true,
            readAt: Date(timeIntervalSince1970: 100),
            starredAt: Date(timeIntervalSince1970: 200),
            statusSyncUpdatedAt: Date(timeIntervalSince1970: 300)
        )

        let record = CloudSyncArticleStatusMapping.makeCKRecord(from: status)

        #expect(record.recordType == "ArticleStatus")
        #expect(record["isRead"] as? Bool == true)
        #expect(record["isStarred"] as? Bool == true)
        #expect(record["readAt"] as? Date == Date(timeIntervalSince1970: 100))
        #expect(record["starredAt"] as? Date == Date(timeIntervalSince1970: 200))
    }

    @Test func allLocalIDsListetNurBeruehrteStatusAuf() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let unberuehrtID = try seedArticle(database: database, articleID: "unberuehrt", feedID: "feed-1")
        let beruehrtID = try seedArticle(database: database, articleID: "beruehrt", feedID: "feed-1")
        try ArticleStatusStore(database: database).setRead(true, articleID: beruehrtID, at: Date())
        // `ArticleStatusStore.setRead` setzt `statusSyncUpdatedAt` erst ab Task 4 — hier direkt
        // simuliert, um das "berührt"-Kriterium unabhängig von Task 4 zu testen.
        try markStatusSyncUpdatedAt(database: database, articleID: beruehrtID)

        let ids = try CloudSyncArticleStatusMapping.allLocalIDs(database: database)

        #expect(ids == [beruehrtID])
        _ = unberuehrtID
    }

    @Test func makeCKRecordFromLocalIDLiefertNilFuerUnbekannteID() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        let record = try CloudSyncArticleStatusMapping.makeCKRecord(fromLocalID: "unbekannt", existing: nil, database: database)

        #expect(record == nil)
    }

    @Test func localUpdatedAtLiefertStatusSyncUpdatedAt() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let articleID = try seedArticle(database: database)
        let touchedAt = Date(timeIntervalSince1970: 5_000)
        try ArticleStatusStore(database: database).setRead(true, articleID: articleID, at: touchedAt)
        // `ArticleStatusStore.setRead` setzt `statusSyncUpdatedAt` erst ab Task 4 — hier direkt
        // simuliert, um `localUpdatedAt` unabhängig von Task 4 zu testen.
        try markStatusSyncUpdatedAt(database: database, articleID: articleID, at: touchedAt)

        let localUpdatedAt = try CloudSyncArticleStatusMapping.localUpdatedAt(forLocalID: articleID, database: database)

        #expect(localUpdatedAt != nil)
    }

    @Test func applyIncomingAktualisiertBestehendenArtikelStatus() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let articleID = try seedArticle(database: database)
        let record = CKRecord(recordType: "ArticleStatus", recordID: CloudSyncArticleStatusMapping.recordID(forLocalID: articleID))
        record["isRead"] = true as CKRecordValue
        record["isStarred"] = false as CKRecordValue

        try CloudSyncArticleStatusMapping.applyIncoming(record, database: database)

        let status = try ArticleStatusStore(database: database).status(articleID: articleID)
        #expect(status?.isRead == true)
        #expect(status?.isStarred == false)
    }

    @Test func applyIncomingLegtVerwaistenEintragAnFuerUnbekannteArticleID() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let record = CKRecord(recordType: "ArticleStatus", recordID: CloudSyncArticleStatusMapping.recordID(forLocalID: "unbekannt"))
        record["isRead"] = true as CKRecordValue
        record["isStarred"] = false as CKRecordValue

        try CloudSyncArticleStatusMapping.applyIncoming(record, database: database)

        let orphan = try database.read { db in
            try OrphanedArticleStatusUpdateRecord.fetchOne(db, key: "unbekannt")
        }
        #expect(orphan?.isRead == true)
        #expect(orphan?.isStarred == false)
    }

    @Test func applyIncomingDeletionEntferntStatusUndVerwaistenEintrag() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let articleID = try seedArticle(database: database)
        try ArticleStatusStore(database: database).setRead(true, articleID: articleID, at: Date())
        try database.write { db in
            var orphan = OrphanedArticleStatusUpdateRecord(articleID: "verwaist", isRead: true, isStarred: false, readAt: nil, starredAt: nil, receivedAt: Date())
            try orphan.insert(db)
        }

        try CloudSyncArticleStatusMapping.applyIncomingDeletion(recordID: CloudSyncArticleStatusMapping.recordID(forLocalID: articleID), database: database)
        try CloudSyncArticleStatusMapping.applyIncomingDeletion(recordID: CloudSyncArticleStatusMapping.recordID(forLocalID: "verwaist"), database: database)

        // Design-Spec Abschnitt 3: `applyIncomingDeletion` löscht die `article_statuses`-Zeile
        // vollständig (`DELETE FROM article_statuses WHERE articleID = ?`) — die Zeile
        // existiert danach nicht mehr, `status(articleID:)` liefert deshalb `nil`, nicht einen
        // auf Default zurückgesetzten Datensatz.
        let status = try ArticleStatusStore(database: database).status(articleID: articleID)
        #expect(status == nil)
        let orphan = try database.read { db in
            try OrphanedArticleStatusUpdateRecord.fetchOne(db, key: "verwaist")
        }
        #expect(orphan == nil)
    }

    @Test func enqueueDeletionIfSyncedEnqueuedNurBeruehrteIDs() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let beruehrtID = try seedArticle(database: database, articleID: "beruehrt", feedID: "feed-1")
        let unberuehrtID = try seedArticle(database: database, articleID: "unberuehrt", feedID: "feed-1")
        try ArticleStatusStore(database: database).setStarred(true, articleID: beruehrtID, at: Date())
        // `ArticleStatusStore.setStarred` setzt `statusSyncUpdatedAt` erst ab Task 4 — hier
        // direkt simuliert, um "berührt" unabhängig von Task 4 zu testen.
        try markStatusSyncUpdatedAt(database: database, articleID: beruehrtID)
        // Sync erst NACH dem Seeding aktivieren — sonst würde `FeedStore.save` (aufgerufen aus
        // `seedArticle`) selbst schon einen "Feed"-Pending-Change enqueuen und die unten
        // geprüfte, auf `ArticleStatus` beschränkte Erwartung verfälschen.
        UserDefaults.standard.set(true, forKey: CloudSyncSettings.isEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey) }

        try database.write { db in
            try CloudSyncArticleStatusMapping.enqueueDeletionIfSynced(articleIDs: [beruehrtID, unberuehrtID], db: db)
        }

        let pending = try CloudSyncPendingChangeStore(database: database).pendingChanges()
        #expect(pending.map(\.id) == [beruehrtID])
        #expect(pending.first?.changeType == .delete)
    }
}
