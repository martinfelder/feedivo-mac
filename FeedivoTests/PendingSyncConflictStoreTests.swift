import Foundation
import Testing
@testable import Feedivo

struct PendingSyncConflictStoreTests {
    @Test func recordSpeichertEinenKonfliktUndConflictsListetIhnAuf() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = PendingSyncConflictStore(database: database)

        try store.record(recordType: "Rule", recordName: "rule-1", fieldName: "name", localValue: "Neu-A", serverValue: "Neu-B")

        let conflicts = try store.conflicts()
        #expect(conflicts.count == 1)
        #expect(conflicts.first?.recordType == "Rule")
        #expect(conflicts.first?.fieldName == "name")
        #expect(conflicts.first?.localValue == "Neu-A")
        #expect(conflicts.first?.serverValue == "Neu-B")
    }

    @Test func resolveEntferntDenKonflikt() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = PendingSyncConflictStore(database: database)
        try store.record(recordType: "Rule", recordName: "rule-1", fieldName: "name", localValue: "Neu-A", serverValue: "Neu-B")
        let conflictID = try store.conflicts()[0].id

        try store.resolve(id: conflictID!)

        #expect(try store.conflicts().isEmpty)
    }
}
