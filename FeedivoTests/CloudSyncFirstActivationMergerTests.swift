import Foundation
import CloudKit
import GRDB
import Testing
@testable import Feedivo

struct CloudSyncFirstActivationMergerTests {
    @Test func mergeTagSchreibtArticleTagsAufDieCloudIDUm() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try TagStore(database: database).save(TagRecord(id: "local-tag-1", name: "Intune", colorHex: "#FF0000", sortIndex: 0))
        try FeedStore(database: database).save(FeedRecord(id: "feed-1", url: "https://example.com/feed", title: "Feed", sortIndex: 0))
        // Artikel direkt über SQL anlegen, um nicht von der exakten ArticleUpsertInput-Signatur
        // abzuhängen (nur article_tags-FK-Umschreiben ist Testgegenstand). `updatedAt` ist laut
        // v1_create_core_tables ebenfalls NOT NULL, deshalb hier zusätzlich zum Brief-Vorschlag
        // mit befüllt.
        try database.write { db in
            try db.execute(
                sql: "INSERT INTO articles (id, feedID, title, arrivedAt, updatedAt) VALUES (?, ?, ?, ?, ?)",
                arguments: ["article-1", "feed-1", "Artikel", Date(), Date()]
            )
        }
        try TagStore(database: database).assignTag(tagID: "local-tag-1", toArticleID: "article-1", at: Date())

        let cloudRecordID = CKRecord.ID(recordName: "cloud-tag-1", zoneID: CloudSyncTagMapping.zoneID())
        let collision = CloudSyncFirstActivationAnalyzer.FirstActivationCollision(
            recordType: CloudSyncTagMapping.recordType, name: "Intune", localID: "local-tag-1", cloudRecordID: cloudRecordID
        )

        try CloudSyncFirstActivationMerger.merge(collision, database: database)

        let remappedCount = try database.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM article_tags WHERE tagID = ?", arguments: ["cloud-tag-1"]) ?? 0
        }
        #expect(remappedCount == 1)
        let oldTagStillReferenced = try database.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM article_tags WHERE tagID = ?", arguments: ["local-tag-1"]) ?? 0
        }
        #expect(oldTagStillReferenced == 0)
    }

    @Test func mergeTagSchreibtDieAlteLokaleTagZeileAufDieCloudIDUm() throws {
        // Ohne article_tags/feed_tags-Referenzen (dieser Test) muss trotzdem exakt eine Zeile
        // mit der Cloud-ID überleben statt die Zeile ersatzlos zu löschen: würde merge()
        // stattdessen unbedingt löschen, gäbe es für Tags MIT Referenzen keine Zeile mehr, auf
        // die article_tags/feed_tags nach dem FK-Umschreiben zeigen könnten (Fremdschlüssel-
        // Verletzung beim Commit) — merge() behandelt beide Fälle deshalb bewusst identisch:
        // Zeile per ID-Umschreiben "übernehmen", statt löschen+neu anlegen (siehe
        // Implementierungskommentar in CloudSyncFirstActivationMerger.swift).
        let database = try FeedivoDatabase.inMemoryForTests()
        try TagStore(database: database).save(TagRecord(id: "local-tag-1", name: "Intune", colorHex: "#FF0000", sortIndex: 0))
        let collision = CloudSyncFirstActivationAnalyzer.FirstActivationCollision(
            recordType: CloudSyncTagMapping.recordType, name: "Intune", localID: "local-tag-1",
            cloudRecordID: CKRecord.ID(recordName: "cloud-tag-1", zoneID: CloudSyncTagMapping.zoneID())
        )

        try CloudSyncFirstActivationMerger.merge(collision, database: database)

        let tags = try TagStore(database: database).tags()
        #expect(tags.count == 1)
        #expect(tags.first?.id == "cloud-tag-1")
        #expect(tags.first?.name == "Intune")
    }

    @Test func mergeTagVermeidetDoppelteZuordnungBeiBereitsVorhandenerCloudTagReferenz() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try TagStore(database: database).save(TagRecord(id: "local-tag-1", name: "Intune", colorHex: "#FF0000", sortIndex: 0))
        // Simuliert die Situation, dass derselbe Artikel bereits (unabhängig) mit einer Zeile
        // referenziert ist, deren tagID der künftigen Cloud-ID entspricht — der Dedupe-Schutz
        // muss die alte Zeile in diesem Fall nur löschen statt ein zweites Mal einzufügen
        // (sonst Primärschlüsselverletzung auf (articleID, tagID)).
        try TagStore(database: database).save(TagRecord(id: "cloud-tag-1", name: "Intune-Duplikat", colorHex: "#00FF00", sortIndex: 1))
        try FeedStore(database: database).save(FeedRecord(id: "feed-1", url: "https://example.com/feed", title: "Feed", sortIndex: 0))
        try database.write { db in
            try db.execute(
                sql: "INSERT INTO articles (id, feedID, title, arrivedAt, updatedAt) VALUES (?, ?, ?, ?, ?)",
                arguments: ["article-1", "feed-1", "Artikel", Date(), Date()]
            )
        }
        try TagStore(database: database).assignTag(tagID: "local-tag-1", toArticleID: "article-1", at: Date())
        try TagStore(database: database).assignTag(tagID: "cloud-tag-1", toArticleID: "article-1", at: Date())

        let collision = CloudSyncFirstActivationAnalyzer.FirstActivationCollision(
            recordType: CloudSyncTagMapping.recordType, name: "Intune", localID: "local-tag-1",
            cloudRecordID: CKRecord.ID(recordName: "cloud-tag-1", zoneID: CloudSyncTagMapping.zoneID())
        )

        try CloudSyncFirstActivationMerger.merge(collision, database: database)

        let articleTagCount = try database.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM article_tags WHERE articleID = ?", arguments: ["article-1"]) ?? 0
        }
        #expect(articleTagCount == 1)
    }

    @Test func mergeTagVermeidetDoppelteZuordnungInFeedTagsBeiBereitsVorhandenerCloudTagReferenz() throws {
        // Analog zu `mergeTagVermeidetDoppelteZuordnungBeiBereitsVorhandenerCloudTagReferenz`,
        // aber für den `feed_tags`-Zweig von `remapTagReferences` — dieser Zweig war bislang
        // komplett ungetestet (Whole-Branch-Review-Fund, Important 4b). Ein Feed hat bereits
        // BEIDE Tags zugewiesen (den zu ersetzenden UND den überlebenden Cloud-Tag) — ein
        // blindes UPDATE würde hier mit einer Primärschlüsselverletzung auf (feedID, tagID)
        // abstürzen, der Dedupe-Schutz muss die alte Zeile statt dessen nur löschen.
        let database = try FeedivoDatabase.inMemoryForTests()
        try TagStore(database: database).save(TagRecord(id: "local-tag-1", name: "Intune", colorHex: "#FF0000", sortIndex: 0))
        try TagStore(database: database).save(TagRecord(id: "cloud-tag-1", name: "Intune-Duplikat", colorHex: "#00FF00", sortIndex: 1))
        try FeedStore(database: database).save(FeedRecord(id: "feed-1", url: "https://example.com/feed", title: "Feed", sortIndex: 0))
        try TagStore(database: database).assignTag(tagID: "local-tag-1", toFeedID: "feed-1", at: Date())
        try TagStore(database: database).assignTag(tagID: "cloud-tag-1", toFeedID: "feed-1", at: Date())

        let collision = CloudSyncFirstActivationAnalyzer.FirstActivationCollision(
            recordType: CloudSyncTagMapping.recordType, name: "Intune", localID: "local-tag-1",
            cloudRecordID: CKRecord.ID(recordName: "cloud-tag-1", zoneID: CloudSyncTagMapping.zoneID())
        )

        try CloudSyncFirstActivationMerger.merge(collision, database: database)

        let feedTagCount = try database.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM feed_tags WHERE feedID = ?", arguments: ["feed-1"]) ?? 0
        }
        #expect(feedTagCount == 1)
        let remainingTagID = try database.read { db in
            try String.fetchOne(db, sql: "SELECT tagID FROM feed_tags WHERE feedID = ?", arguments: ["feed-1"])
        }
        #expect(remainingTagID == "cloud-tag-1")
    }

    @Test func mergeTagSchreibtFeedTagsAufDieCloudIDUmOhneBereitsVorhandeneReferenz() throws {
        // Normalfall (kein Dedupe-Konflikt): der Feed hat NUR den zu ersetzenden Tag —
        // `feed_tags.tagID` muss nach dem Merge auf die Cloud-ID zeigen.
        let database = try FeedivoDatabase.inMemoryForTests()
        try TagStore(database: database).save(TagRecord(id: "local-tag-1", name: "Intune", colorHex: "#FF0000", sortIndex: 0))
        try FeedStore(database: database).save(FeedRecord(id: "feed-1", url: "https://example.com/feed", title: "Feed", sortIndex: 0))
        try TagStore(database: database).assignTag(tagID: "local-tag-1", toFeedID: "feed-1", at: Date())

        let collision = CloudSyncFirstActivationAnalyzer.FirstActivationCollision(
            recordType: CloudSyncTagMapping.recordType, name: "Intune", localID: "local-tag-1",
            cloudRecordID: CKRecord.ID(recordName: "cloud-tag-1", zoneID: CloudSyncTagMapping.zoneID())
        )

        try CloudSyncFirstActivationMerger.merge(collision, database: database)

        let remappedCount = try database.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM feed_tags WHERE tagID = ?", arguments: ["cloud-tag-1"]) ?? 0
        }
        #expect(remappedCount == 1)
    }

    @Test func keepBothVergibtDisambiguierendenNamenszusatz() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try TagStore(database: database).save(TagRecord(id: "local-tag-1", name: "Intune", colorHex: "#FF0000", sortIndex: 0))
        let collision = CloudSyncFirstActivationAnalyzer.FirstActivationCollision(
            recordType: CloudSyncTagMapping.recordType, name: "Intune", localID: "local-tag-1",
            cloudRecordID: CKRecord.ID(recordName: "cloud-tag-1", zoneID: CloudSyncTagMapping.zoneID())
        )

        try CloudSyncFirstActivationMerger.keepBoth(collision, database: database)

        let tag = try TagStore(database: database).tags().first { $0.id == "local-tag-1" }
        #expect(tag?.name == "Intune (2)")
    }

    @Test func keepBothVergibtDisambiguierendenNamenszusatzFuerFeedFolder() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try FeedFolderStore(database: database).save(FeedFolderRecord(id: "local-folder-1", name: "Technik", sortIndex: 0, createdAt: Date(), updatedAt: Date()))
        let collision = CloudSyncFirstActivationAnalyzer.FirstActivationCollision(
            recordType: CloudSyncFeedFolderMapping.recordType, name: "Technik", localID: "local-folder-1",
            cloudRecordID: CKRecord.ID(recordName: "cloud-folder-1", zoneID: CloudSyncTagMapping.zoneID())
        )

        try CloudSyncFirstActivationMerger.keepBoth(collision, database: database)

        let folder = try FeedFolderStore(database: database).folders().first { $0.id == "local-folder-1" }
        #expect(folder?.name == "Technik (2)")
    }

    @Test func keepBothSchreibtFeedsFolderNameAufDenNeuenNamenUmUndMarkiertSieAlsGeaendert() throws {
        // Whole-Branch-Review-Fund (Critical 2): ohne diesen Test hätte `keepBoth` für
        // FeedFolder unentdeckt jeden Feed im kollidierenden Ordner verwaist zurückgelassen —
        // die bereits bestehenden Tests für diese Datei legen bewusst KEINEN Feed an, genau
        // deshalb konnte der Bug hier durchschlüpfen.
        let database = try FeedivoDatabase.inMemoryForTests()
        try FeedFolderStore(database: database).save(FeedFolderRecord(id: "local-folder-1", name: "Technik", sortIndex: 0, createdAt: Date(), updatedAt: Date()))
        try FeedStore(database: database).save(FeedRecord(id: "feed-1", url: "https://example.com/feed", title: "Feed", folderName: "Technik", sortIndex: 0))

        let collision = CloudSyncFirstActivationAnalyzer.FirstActivationCollision(
            recordType: CloudSyncFeedFolderMapping.recordType, name: "Technik", localID: "local-folder-1",
            cloudRecordID: CKRecord.ID(recordName: "cloud-folder-1", zoneID: CloudSyncTagMapping.zoneID())
        )

        try CloudSyncFirstActivationMerger.keepBoth(collision, database: database)

        let feed = try FeedStore(database: database).feeds().first { $0.id == "feed-1" }
        #expect(feed?.folderName == "Technik (2)")

        // Der Feed muss zusätzlich als sync-pending mit Feld-Ebene-Tracking eingereiht sein —
        // sonst käme die geänderte Ordner-Zuordnung nie bei CloudKit an.
        let pendingChange = try CloudSyncPendingChangeStore(database: database).pendingChange(recordName: "feed-1")
        #expect(pendingChange?.recordType == CloudSyncFeedMapping.recordType)
        #expect(pendingChange?.changedFields == ["folderName"])
    }

    @Test func mergeFeedFolderLoeschtNurDieAlteZeileOhneFKUmschreiben() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try FeedFolderStore(database: database).save(FeedFolderRecord(id: "local-folder-1", name: "Technik", sortIndex: 0, createdAt: Date(), updatedAt: Date()))
        let collision = CloudSyncFirstActivationAnalyzer.FirstActivationCollision(
            recordType: CloudSyncFeedFolderMapping.recordType, name: "Technik", localID: "local-folder-1",
            cloudRecordID: CKRecord.ID(recordName: "cloud-folder-1", zoneID: CloudSyncTagMapping.zoneID())
        )

        try CloudSyncFirstActivationMerger.merge(collision, database: database)

        let folders = try FeedFolderStore(database: database).folders()
        #expect(folders.isEmpty)
    }
}
