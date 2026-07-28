import Testing
@testable import Feedivo

struct CloudSyncRecordMappingPolicyTests {
    @Test func tagPolicyEntsprichtDesignSpec() {
        #expect(CloudSyncTagMapping.askFields == ["name"])
        #expect(CloudSyncTagMapping.autoFields == ["colorHex", "sortIndex"])
    }

    @Test func feedFolderPolicyEntsprichtDesignSpec() {
        #expect(CloudSyncFeedFolderMapping.askFields == ["name"])
        #expect(CloudSyncFeedFolderMapping.autoFields == ["sortIndex"])
    }

    @Test func feedPolicyEntsprichtDesignSpec() {
        #expect(CloudSyncFeedMapping.askFields == ["title"])
        #expect(CloudSyncFeedMapping.autoFields.count == 9)
        #expect(CloudSyncFeedMapping.autoFields.contains("folderName"))
        #expect(CloudSyncFeedMapping.autoFields.contains("articleRetentionDays"))
    }

    @Test func rulePolicyEntsprichtDesignSpec() {
        #expect(CloudSyncRuleMapping.askFields == ["name"])
        #expect(CloudSyncRuleMapping.autoFields.count == 7)
    }

    @Test func ruleConditionPolicyEntsprichtDesignSpec() {
        #expect(CloudSyncRuleConditionMapping.askFields == ["value"])
        #expect(CloudSyncRuleConditionMapping.autoFields == ["field", "conditionOperator", "groupIndex", "sortOrder"])
    }

    @Test func smartFolderPolicyEntsprichtDesignSpec() {
        #expect(CloudSyncSmartFolderMapping.askFields == ["name"])
        #expect(CloudSyncSmartFolderMapping.autoFields.count == 6)
    }

    @Test func smartFolderConditionPolicyEntsprichtDesignSpec() {
        #expect(CloudSyncSmartFolderConditionMapping.askFields == ["value"])
        #expect(CloudSyncSmartFolderConditionMapping.autoFields == ["field", "conditionOperator", "sortOrder"])
    }

    @Test func articleStatusHatKeineTouchedFieldsPolicy() {
        #expect(CloudSyncArticleStatusMapping.askFields.isEmpty)
        #expect(CloudSyncArticleStatusMapping.autoFields.isEmpty)
    }
}
