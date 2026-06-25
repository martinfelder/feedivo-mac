import Foundation
import Testing
@testable import Feedivo

struct RuleNotificationServiceTests {
    @Test func summaryIgnoriertLeereRuleNotifications() {
        #expect(FeedNotificationService.ruleSummary(from: []) == nil)
    }

    @Test func summaryZeigtEinzelnenRegeltrefferDirektAn() throws {
        let result = RuleNotificationResult(
            ruleID: UUID(),
            ruleName: "Breaking",
            message: "Breaking: Swift 7 ist da",
            articleTitle: "Swift 7 ist da",
            feedTitle: "Mac News",
            priority: .normal
        )

        let summary = try #require(FeedNotificationService.ruleSummary(from: [result]))

        #expect(summary.title == "Breaking: Swift 7 ist da")
        #expect(summary.body == "Mac News")
        #expect(summary.priority == .normal)
    }

    @Test func summaryFasstMehrereRegeltrefferProRegelZusammen() throws {
        let ruleID = UUID()
        let results = [
            RuleNotificationResult(
                ruleID: ruleID,
                ruleName: "Apple",
                message: "Apple: Artikel 1",
                articleTitle: "Artikel 1",
                feedTitle: "Feed A",
                priority: .normal
            ),
            RuleNotificationResult(
                ruleID: ruleID,
                ruleName: "Apple",
                message: "Apple: Artikel 2",
                articleTitle: "Artikel 2",
                feedTitle: "Feed B",
                priority: .critical
            ),
            RuleNotificationResult(
                ruleID: ruleID,
                ruleName: "Apple",
                message: "Apple: Artikel 3",
                articleTitle: "Artikel 3",
                feedTitle: "Feed C",
                priority: .normal
            )
        ]

        let summary = try #require(FeedNotificationService.ruleSummary(from: results))

        #expect(summary.title == "3 neue Apple-Artikel")
        #expect(summary.body == "Artikel 1, Artikel 2, Artikel 3")
        #expect(summary.priority == .critical)
    }
}
