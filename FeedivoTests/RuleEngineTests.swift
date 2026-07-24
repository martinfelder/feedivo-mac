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
                articles: articles
            )
        }

        let swiftRuleCount = counts["Swift"]
        let windowsRuleCount = counts["Windows"]
        #expect(swiftRuleCount == 2)
        #expect(windowsRuleCount == 1)
        #expect(counts.count == 2)
    }

    @Test func matchingArticleCountBeiEinerGruppeVerhaeltSichWieBisherigesUnd() {
        let article = RuleEngine.ArticleRuleSnapshot(
            id: "article-1",
            title: "Swift auf dem Mac",
            summary: nil,
            feedTitle: "Mac News"
        )
        // Beide Bedingungen in derselben Gruppe (groupIndex 0, Default) --
        // beide muessen zutreffen.
        let drafts = [
            RuleConditionDraft(field: .title, conditionOperator: .contains, value: "Swift"),
            RuleConditionDraft(field: .title, conditionOperator: .contains, value: "Windows")
        ]

        #expect(RuleEngine.matchingArticleCount(conditionDrafts: drafts, articles: [article]) == 0)
    }

    @Test func matchingArticleCountBeiMehrerenGruppenReichtEineTreffendeGruppe() {
        let article = RuleEngine.ArticleRuleSnapshot(
            id: "article-1",
            title: "Swift auf dem Mac",
            summary: "Ein Artikel ueber macOS-Entwicklung",
            feedTitle: "Mac News"
        )
        // Gruppe 0 (Titel enthaelt "Swift" UND Titel enthaelt "Windows")
        // trifft NICHT zu. Gruppe 1 (Summary enthaelt "macOS") trifft zu --
        // Gesamtergebnis muss dennoch ein Treffer sein (ODER zwischen Gruppen).
        let drafts = [
            RuleConditionDraft(field: .title, conditionOperator: .contains, value: "Swift", groupIndex: 0),
            RuleConditionDraft(field: .title, conditionOperator: .contains, value: "Windows", groupIndex: 0),
            RuleConditionDraft(field: .summary, conditionOperator: .contains, value: "macOS", groupIndex: 1)
        ]

        #expect(RuleEngine.matchingArticleCount(conditionDrafts: drafts, articles: [article]) == 1)
    }

    @Test func matchingArticleCountOhneBedingungenLiefertKeinenTreffer() {
        let article = RuleEngine.ArticleRuleSnapshot(
            id: "article-1",
            title: "Beliebiger Titel",
            summary: nil,
            feedTitle: "Beliebiger Feed"
        )

        #expect(RuleEngine.matchingArticleCount(conditionDrafts: [], articles: [article]) == 0)
    }
}
