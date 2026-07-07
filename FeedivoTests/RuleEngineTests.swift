import Foundation
import Testing
@testable import Feedivo

struct RuleEngineTests {
    @Test func matchingCountsLiefertTrefferProRegelInEinerMap() throws {
        let articles = [
            RuleEngine.ArticleRuleSnapshot(
                id: UUID().uuidString,
                title: "Swift auf dem Mac",
                summary: nil,
                feedTitle: "Mac News"
            ),
            RuleEngine.ArticleRuleSnapshot(
                id: UUID().uuidString,
                title: "Windows News",
                summary: nil,
                feedTitle: "Mac News"
            ),
            RuleEngine.ArticleRuleSnapshot(
                id: UUID().uuidString,
                title: "Swift 7 ist da",
                summary: nil,
                feedTitle: "Mac News"
            )
        ]

        let rules: [(String, RuleConditionDraft)] = [
            (
                "Swift",
                RuleConditionDraft(field: .title, conditionOperator: .contains, value: "Swift")
            ),
            (
                "Windows",
                RuleConditionDraft(field: .title, conditionOperator: .contains, value: "Windows")
            )
        ]

        var counts: [String: Int] = [:]
        for (name, draft) in rules {
            counts[name] = RuleEngine.matchingArticleCount(
                conditionDrafts: [draft],
                matchMode: .all,
                articles: articles
            )
        }

        let swiftRuleCount = counts["Swift"]
        let windowsRuleCount = counts["Windows"]
        #expect(swiftRuleCount == 2)
        #expect(windowsRuleCount == 1)
        #expect(counts.count == 2)
    }
}
