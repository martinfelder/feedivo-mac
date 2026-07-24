import Foundation
import CloudKit
import Testing
@testable import Feedivo

/// Tests für `CloudSyncFeedFolderMapping` (iCloud Sync Phase 2a, Task 5). Anders als
/// `CloudSyncFeedMapping` gibt es hier keine syncbare Teilmenge — `feed_folders` hat keine
/// lokal-only Felder, deshalb wird die Tabelle vollständig gemappt (`updatedAt` ist hier das
/// korrekte Last-Write-Wins-Feld, siehe Design-Spec).
struct CloudSyncFeedFolderMappingTests {
    @Test func makeCKRecordMapptAlleFelder() {
        let folder = FeedFolderRecord(id: "folder-1", name: "Tech", sortIndex: 2)

        let record = CloudSyncFeedFolderMapping.makeCKRecord(from: folder)

        #expect(record.recordType == "FeedFolder")
        #expect(record["name"] as? String == "Tech")
        #expect(record["sortIndex"] as? Int == 2)
    }

    @Test func makeCKRecordAktualisiertBestehendesRecordStattEinNeuesZuErzeugen() {
        let folder = FeedFolderRecord(id: "folder-1", name: "Tech", sortIndex: 2)
        let existing = CKRecord(recordType: "FeedFolder", recordID: CloudSyncFeedFolderMapping.recordID(forLocalID: "folder-1"))

        let record = CloudSyncFeedFolderMapping.makeCKRecord(from: folder, existing: existing)

        #expect(record === existing)
        #expect(record["name"] as? String == "Tech")
    }

    @Test func feedFolderRecordFromCKRecordMapptZurueck() {
        let folder = FeedFolderRecord(id: "folder-1", name: "Tech", sortIndex: 2)
        let record = CloudSyncFeedFolderMapping.makeCKRecord(from: folder)

        let mapped = CloudSyncFeedFolderMapping.feedFolderRecord(from: record)

        #expect(mapped?.id == "folder-1")
        #expect(mapped?.name == "Tech")
        #expect(mapped?.sortIndex == 2)
    }

    @Test func feedFolderRecordFromCKRecordLiefertNilBeiFehlendenPflichtfeldern() {
        let ckRecord = CKRecord(recordType: "FeedFolder", recordID: CloudSyncFeedFolderMapping.recordID(forLocalID: "folder-1"))

        #expect(CloudSyncFeedFolderMapping.feedFolderRecord(from: ckRecord) == nil)
    }

    @Test func makeCKRecordFromLocalIDLiefertNilFuerUnbekannteID() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        let record = try CloudSyncFeedFolderMapping.makeCKRecord(fromLocalID: "unbekannt", database: database)

        #expect(record == nil)
    }

    @Test func makeCKRecordFromLocalIDLaedtBestehendenOrdner() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = FeedFolderStore(database: database)
        try store.save(FeedFolderRecord(id: "folder-1", name: "Tech", sortIndex: 4))

        let record = try CloudSyncFeedFolderMapping.makeCKRecord(fromLocalID: "folder-1", database: database)

        #expect(record?["name"] as? String == "Tech")
        #expect(record?["sortIndex"] as? Int == 4)
    }

    @Test func applyIncomingFuegtNeuenOrdnerEin() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let folder = FeedFolderRecord(id: "folder-neu", name: "Neu", sortIndex: 1)
        let record = CloudSyncFeedFolderMapping.makeCKRecord(from: folder)

        try CloudSyncFeedFolderMapping.applyIncoming(record, database: database)

        let loaded = try FeedFolderStore(database: database).folders().first { $0.id == "folder-neu" }
        #expect(loaded?.name == "Neu")
        #expect(loaded?.sortIndex == 1)
    }

    @Test func applyIncomingAktualisiertBestehendenOrdner() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = FeedFolderStore(database: database)
        try store.save(FeedFolderRecord(id: "folder-1", name: "Alt", sortIndex: 0))

        let updatedFolder = FeedFolderRecord(id: "folder-1", name: "Neu Betitelt", sortIndex: 3)
        let record = CloudSyncFeedFolderMapping.makeCKRecord(from: updatedFolder)

        try CloudSyncFeedFolderMapping.applyIncoming(record, database: database)

        let loaded = try store.folders().first { $0.id == "folder-1" }
        #expect(loaded?.name == "Neu Betitelt")
        #expect(loaded?.sortIndex == 3)
    }

    @Test func applyIncomingDeletionEntferntOrdner() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = FeedFolderStore(database: database)
        try store.save(FeedFolderRecord(id: "folder-1", name: "Tech"))

        try CloudSyncFeedFolderMapping.applyIncomingDeletion(recordID: CloudSyncFeedFolderMapping.recordID(forLocalID: "folder-1"), database: database)

        #expect(try store.folders().first { $0.id == "folder-1" } == nil)
    }

    @Test func localUpdatedAtLiefertUpdatedAt() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = FeedFolderStore(database: database)
        let updatedAt = Date(timeIntervalSince1970: 1_000)
        try store.save(FeedFolderRecord(id: "folder-1", name: "Tech", updatedAt: updatedAt))

        let localUpdatedAt = try CloudSyncFeedFolderMapping.localUpdatedAt(forLocalID: "folder-1", database: database)

        #expect(localUpdatedAt == updatedAt)
    }

    @Test func localUpdatedAtLiefertNilFuerUnbekannteID() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        let localUpdatedAt = try CloudSyncFeedFolderMapping.localUpdatedAt(forLocalID: "unbekannt", database: database)

        #expect(localUpdatedAt == nil)
    }
}
