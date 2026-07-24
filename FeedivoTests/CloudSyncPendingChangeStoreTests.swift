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
}
