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

    @Test func summaryFasstArtikelAllerRegelGruppenZusammen() throws {
        // Regression: früher wurde im Body nur die größte Regel-Gruppe gezeigt,
        // Artikel kleinerer Gruppen fielen weg. Hier greifen zwei Regeln
        // (Apple 2×, Swift 1×) — alle drei Artikel müssen im Body stehen.
        let ruleA = UUID()
        let ruleB = UUID()
        let results = [
            RuleNotificationResult(
                ruleID: ruleA,
                ruleName: "Apple",
                message: "Apple: A1",
                articleTitle: "A1",
                feedTitle: "Feed A",
                priority: .normal
            ),
            RuleNotificationResult(
                ruleID: ruleA,
                ruleName: "Apple",
                message: "Apple: A2",
                articleTitle: "A2",
                feedTitle: "Feed A",
                priority: .normal
            ),
            RuleNotificationResult(
                ruleID: ruleB,
                ruleName: "Swift",
                message: "Swift: S1",
                articleTitle: "S1",
                feedTitle: "Feed B",
                priority: .normal
            )
        ]

        let summary = try #require(FeedNotificationService.ruleSummary(from: results))

        // Größte Gruppe (Apple, 2 Treffer) bestimmt den Titel.
        #expect(summary.title == "2 neue Apple-Artikel")
        // Aber alle Artikel erscheinen im Body — auch S1 der kleineren Gruppe.
        #expect(summary.body == "A1, A2, S1")
        #expect(summary.priority == .normal)
        #expect(Set(summary.ruleIDs) == Set([ruleA, ruleB]))
    }
}
