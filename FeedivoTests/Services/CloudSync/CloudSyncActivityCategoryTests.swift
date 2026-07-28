import Foundation
import Testing
@testable import Feedivo

struct CloudSyncActivityCategoryTests {
    @Test func einzelKategorienUmfassenGenauIhrenEigenenRecordType() {
        #expect(CloudSyncActivityCategory.tags.recordTypes == ["Tag"])
        #expect(CloudSyncActivityCategory.feeds.recordTypes == ["Feed"])
        #expect(CloudSyncActivityCategory.folders.recordTypes == ["FeedFolder"])
    }

    @Test func rulesKategorieUmfasstRuleUndRuleCondition() {
        #expect(CloudSyncActivityCategory.rules.recordTypes == ["Rule", "RuleCondition"])
    }

    @Test func smartFoldersKategorieUmfasstSmartFolderUndSmartFolderCondition() {
        #expect(CloudSyncActivityCategory.smartFolders.recordTypes == ["SmartFolder", "SmartFolderCondition"])
    }

    @Test func pendingCountSummiertAlleZugehoerigenRecordTypes() {
        let counts = ["Rule": 2, "RuleCondition": 3, "Tag": 5]
        #expect(CloudSyncActivityCategory.rules.pendingCount(in: counts) == 5)
        #expect(CloudSyncActivityCategory.tags.pendingCount(in: counts) == 5)
    }

    @Test func pendingCountIstNullWennKeineEintraege() {
        #expect(CloudSyncActivityCategory.feeds.pendingCount(in: [:]) == 0)
    }
}
