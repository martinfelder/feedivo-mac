import Foundation
import Testing
import GRDB
@testable import Feedivo

struct CloudSyncPendingChangeStoreTests {
    @Test func enqueueUndPendingChangesRoundtrip() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = CloudSyncPendingChangeStore(database: database)

        try store.enqueue(recordType: "tag", recordName: "tag-1", changeType: .save)

        let pending = try store.pendingChanges()
        #expect(pending.count == 1)
        #expect(pending[0].id == "tag-1")
        #expect(pending[0].recordType == "tag")
        #expect(pending[0].changeType == .save)
    }

    @Test func enqueueUeberschreibtBestehendenEintragFuerDieselbeID() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = CloudSyncPendingChangeStore(database: database)

        try store.enqueue(recordType: "tag", recordName: "tag-1", changeType: .save)
        try store.enqueue(recordType: "tag", recordName: "tag-1", changeType: .delete)

        let pending = try store.pendingChanges()
        #expect(pending.count == 1)
        #expect(pending[0].changeType == .delete)
    }

    @Test func dequeueEntferntEintrag() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = CloudSyncPendingChangeStore(database: database)

        try store.enqueue(recordType: "tag", recordName: "tag-1", changeType: .save)
        try store.dequeue(recordName: "tag-1")

        #expect(try store.pendingChanges().isEmpty)
    }

    @Test func pendingChangesSindNachQueuedAtSortiert() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = CloudSyncPendingChangeStore(database: database)

        try store.enqueue(recordType: "tag", recordName: "tag-2", changeType: .save)
        try store.enqueue(recordType: "tag", recordName: "tag-1", changeType: .save)

        let pending = try store.pendingChanges()
        #expect(pending.map(\.id) == ["tag-2", "tag-1"])
    }

    @Test func staticEnqueueFunktioniertInnerhalbBestehenderTransaktion() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        try database.write { db in
            try CloudSyncPendingChangeStore.enqueue(db, recordType: "tag", recordName: "tag-1", changeType: .save)
        }

        let store = CloudSyncPendingChangeStore(database: database)
        #expect(try store.pendingChanges().count == 1)
    }

    @Test func pendingCountsLeereTabelleLiefertLeeresDictionary() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = CloudSyncPendingChangeStore(database: database)

        #expect(try store.pendingCounts().isEmpty)
    }

    @Test func pendingCountsGruppiertNachRecordType() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = CloudSyncPendingChangeStore(database: database)

        try store.enqueue(recordType: "Tag", recordName: "tag-1", changeType: .save)
        try store.enqueue(recordType: "Tag", recordName: "tag-2", changeType: .save)
        try store.enqueue(recordType: "Feed", recordName: "feed-1", changeType: .save)

        let counts = try store.pendingCounts()
        #expect(counts["Tag"] == 2)
        #expect(counts["Feed"] == 1)
        #expect(counts.count == 2)
    }

    @Test func deleteAllLeertDieGesamteTabelle() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = CloudSyncPendingChangeStore(database: database)

        try store.enqueue(recordType: "Tag", recordName: "tag-1", changeType: .save)
        try store.enqueue(recordType: "Feed", recordName: "feed-1", changeType: .save)

        try store.deleteAll()

        #expect(try store.pendingChanges().isEmpty)
    }

    @Test func enqueueSpeichertChangedFieldsAlsJSON() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = CloudSyncPendingChangeStore(database: database)

        try store.enqueue(recordType: "Tag", recordName: "tag-1", changeType: .save, changedFields: ["name"])

        let change = try store.pendingChange(recordName: "tag-1")
        #expect(change?.changedFields == ["name"])
    }

    @Test func enqueueOhneChangedFieldsBleibtNil() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = CloudSyncPendingChangeStore(database: database)

        try store.enqueue(recordType: "Tag", recordName: "tag-1", changeType: .delete)

        let change = try store.pendingChange(recordName: "tag-1")
        #expect(change?.changedFields == nil)
    }
}
