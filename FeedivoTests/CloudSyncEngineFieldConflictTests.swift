import Foundation
import CloudKit
import Testing
@testable import Feedivo

@MainActor
struct CloudSyncEngineFieldConflictTests {
    @Test func mergeDecisionOhneUnterschiedIstNoConflict() {
        let decision = CloudSyncEngine.mergeDecision(
            fieldName: "name", localValue: "Gleich" as CKRecordValue, serverValue: "Gleich" as CKRecordValue,
            askFields: ["name"], autoFields: []
        )
        #expect(decision == .noConflict)
    }

    @Test func mergeDecisionBeiAskFieldMitUnterschiedIstNeedsUserDecision() {
        let decision = CloudSyncEngine.mergeDecision(
            fieldName: "name", localValue: "Neu-A" as CKRecordValue, serverValue: "Neu-B" as CKRecordValue,
            askFields: ["name"], autoFields: []
        )
        #expect(decision == .needsUserDecision)
    }

    @Test func mergeDecisionBeiAutoFieldMitUnterschiedIstAutoResolved() {
        let decision = CloudSyncEngine.mergeDecision(
            fieldName: "sortIndex", localValue: 1 as CKRecordValue, serverValue: 2 as CKRecordValue,
            askFields: ["name"], autoFields: ["sortIndex"]
        )
        #expect(decision == .autoResolved)
    }

    @Test func pendingChangeOhneChangedFieldsNutztWeiterhinGanzRecordLWW() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let tag = TagRecord(id: "tag-1", name: "Alt", colorHex: "#FF0000", sortIndex: 0)
        try TagStore(database: database).save(tag)

        // Ohne CloudSyncSettings.isEnabled() wird kein changedFields gesetzt — simuliert
        // Altbestand von vor Phase 3.
        try CloudSyncPendingChangeStore(database: database).enqueue(recordType: "Tag", recordName: "tag-1", changeType: .save)

        let change = try CloudSyncPendingChangeStore(database: database).pendingChange(recordName: "tag-1")
        #expect(change?.changedFields == nil)
    }
}
