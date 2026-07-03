import Foundation
import Testing
@testable import Feedivo

struct SQLiteRuleEvaluationStoreTests {
    @Test func matchingArticleCountUsesSQLiteArticleSnapshots() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let ruleStore = SQLiteRuleEvaluationStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Mac News"))
        try feedStore.save(FeedRecord(id: "feed-2", url: "https://other.example/feed.xml", title: "Other News"))
        _ = try articleStore.upsert(ArticleUpsertInput(feedID: "feed-1", sourceID: "swift", title: "Swift auf dem Mac"))
        _ = try articleStore.upsert(ArticleUpsertInput(feedID: "feed-2", sourceID: "other", title: "Swift auf dem Mac"))

        let count = try ruleStore.matchingArticleCount(
            conditionDrafts: [
                RuleConditionDraft(field: .title, conditionOperator: .contains, value: "Swift"),
                RuleConditionDraft(field: .feedTitle, conditionOperator: .contains, value: "Mac")
            ],
            matchMode: .all
        )

        #expect(count == 1)
    }

    @Test func applyRulesToExistingArticlesWritesHiddenAndTagStateToSQLite() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)
        let tagStore = TagStore(database: database)
        let ruleStore = SQLiteRuleEvaluationStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Mac News"))
        let swiftID = try articleStore.upsert(ArticleUpsertInput(feedID: "feed-1", sourceID: "swift", title: "Swift auf dem Mac"))
        let spoilerID = try articleStore.upsert(ArticleUpsertInput(feedID: "feed-1", sourceID: "spoiler", title: "Spoiler zum Film"))
        _ = try articleStore.upsert(ArticleUpsertInput(feedID: "feed-1", sourceID: "other", title: "Normale News"))
        try feedStore.setUnreadCount(3, feedID: "feed-1")

        let tag = RuleEngine.TagSnapshot(id: "tag-swift", name: "Swift", colorHex: "#3B82F6")
        let tagRule = RuleEngine.RuleSnapshot(
            id: UUID(),
            name: "Swift",
            isEnabled: true,
            conditionMatchMode: RuleMatchMode.all.rawValue,
            actionRaw: RuleAction.assignTag.rawValue,
            notificationTemplate: "{Titel}",
            notificationPriorityRaw: RuleNotificationPriority.normal.rawValue,
            sortOrder: 0,
            conditions: [
                RuleEngine.RuleConditionSnapshot(
                    field: RuleConditionField.title.rawValue,
                    conditionOperator: RuleConditionOperator.contains.rawValue,
                    value: "Swift",
                    sortOrder: 0
                )
            ],
            assignTag: tag
        )
        let hideRule = RuleEngine.RuleSnapshot(
            id: UUID(),
            name: "Spoiler",
            isEnabled: true,
            conditionMatchMode: RuleMatchMode.all.rawValue,
            actionRaw: RuleAction.hideArticle.rawValue,
            notificationTemplate: "{Titel}",
            notificationPriorityRaw: RuleNotificationPriority.normal.rawValue,
            sortOrder: 1,
            conditions: [
                RuleEngine.RuleConditionSnapshot(
                    field: RuleConditionField.title.rawValue,
                    conditionOperator: RuleConditionOperator.contains.rawValue,
                    value: "Spoiler",
                    sortOrder: 0
                )
            ],
            assignTag: nil
        )

        let appliedCount = try ruleStore.applyRulesToExistingArticles([tagRule, hideRule])

        let swiftTags = try tagStore.tags(articleID: swiftID)
        let spoilerStatus = try statusStore.status(articleID: spoilerID)
        let feed = try feedStore.feed(id: "feed-1")

        #expect(appliedCount == 2)
        #expect(swiftTags.map(\.name) == ["Swift"])
        #expect(spoilerStatus?.isHidden == true)
        #expect(feed?.unreadCount == 2)
    }
}
