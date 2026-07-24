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

    @Test func registryLoestFeedFolderRecordTypeAufCloudSyncFeedFolderMappingAuf() {
        let mapping = CloudSyncEngine.mapping(forRecordType: "FeedFolder")

        #expect(mapping is CloudSyncFeedFolderMapping.Type)
    }

    @Test func registryLoestRuleRecordTypeAufCloudSyncRuleMappingAuf() {
        let mapping = CloudSyncEngine.mapping(forRecordType: "Rule")

        #expect(mapping is CloudSyncRuleMapping.Type)
    }

    @Test func registryLoestRuleConditionRecordTypeAufCloudSyncRuleConditionMappingAuf() {
        let mapping = CloudSyncEngine.mapping(forRecordType: "RuleCondition")

        #expect(mapping is CloudSyncRuleConditionMapping.Type)
    }

    @Test func registryLoestSmartFolderRecordTypeAufCloudSyncSmartFolderMappingAuf() {
        let mapping = CloudSyncEngine.mapping(forRecordType: "SmartFolder")

        #expect(mapping is CloudSyncSmartFolderMapping.Type)
    }

    @Test func registryLoestSmartFolderConditionRecordTypeAufCloudSyncSmartFolderConditionMappingAuf() {
        let mapping = CloudSyncEngine.mapping(forRecordType: "SmartFolderCondition")

        #expect(mapping is CloudSyncSmartFolderConditionMapping.Type)
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
