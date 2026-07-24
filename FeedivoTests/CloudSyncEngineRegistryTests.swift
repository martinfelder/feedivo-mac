import Foundation
import CloudKit
import Testing
@testable import Feedivo

/// Regressionstests für den Registry-Umbau von `CloudSyncEngine` (iCloud Sync Phase 2a,
/// Task 3). Reine Dispatch-Logik — kein echtes CloudKit-Konto nötig.
struct CloudSyncEngineRegistryTests {
    @Test func registryLoestTagRecordTypeAufCloudSyncTagMappingAuf() {
        let mapping = CloudSyncEngine.mapping(forRecordType: "Tag")

        #expect(mapping is CloudSyncTagMapping.Type)
    }

    @Test func registryLoestFeedRecordTypeAufCloudSyncFeedMappingAuf() {
        let mapping = CloudSyncEngine.mapping(forRecordType: "Feed")

        #expect(mapping is CloudSyncFeedMapping.Type)
    }

    @Test func registryLiefertNilFuerUnbekanntenRecordType() {
        let mapping = CloudSyncEngine.mapping(forRecordType: "UnknownType")

        #expect(mapping == nil)
    }

    @Test func sortiertModificationsSoDassElternRecordsVorKindRecordsStehen() {
        let feedRecord = CKRecord(recordType: "RuleCondition", recordID: CKRecord.ID(recordName: "cond-1"))
        let ruleRecord = CKRecord(recordType: "Rule", recordID: CKRecord.ID(recordName: "rule-1"))
        let unsorted = [feedRecord, ruleRecord]

        let sorted = CloudSyncEngine.sortedByDependencyOrder(unsorted)

        #expect(sorted.map(\.recordType) == ["Rule", "RuleCondition"])
    }
}
