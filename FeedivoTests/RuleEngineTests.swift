import Foundation
import SwiftData
import Testing
@testable import Feedivo

struct RuleEngineTests {
    @MainActor
    @Test func applyRulesTaggtArtikelBeiTitelSummaryUndFeedTreffern() throws {
        let swiftTag = Tag(name: "Swift", colorHex: "#3B82F6")
        let macTag = Tag(name: "Mac", colorHex: "#22C55E")
        let newsTag = Tag(name: "News", colorHex: "#F59E0B")
        let titleRule = Rule(
            name: "Swift Titel",
            conditionField: "title",
            conditionOperator: "contains",
            conditionValue: "swift"
        )
        titleRule.assignTag = swiftTag
        let summaryRule = Rule(
            name: "Summary Start",
            conditionField: "summary",
            conditionOperator: "startsWith",
            conditionValue: "breaking"
        )
        summaryRule.assignTag = newsTag
        let feedRule = Rule(
            name: "Feed Ende",
            conditionField: "feedTitle",
            conditionOperator: "endsWith",
            conditionValue: "weekly"
        )
        feedRule.assignTag = macTag
        let feed = Feed(url: "https://example.com/feed.xml", title: "Mac Weekly")
        let article = Article(
            title: "Swift 6.3 ist da",
            summary: "Breaking changes im Detail",
            feed: feed
        )

        RuleEngine.applyRules([titleRule, summaryRule, feedRule], to: article, feed: feed)

        #expect(article.tags.map(\.name).sorted() == ["Mac", "News", "Swift"])
    }

    @MainActor
    @Test func applyRulesIgnoriertUngueltigeRegelnUndVerhindertDoppelteTags() throws {
        let tag = Tag(name: "Swift", colorHex: "#3B82F6")
        let activeRule = Rule(
            name: "Swift",
            conditionField: "title",
            conditionOperator: "contains",
            conditionValue: "Swift"
        )
        activeRule.assignTag = tag
        let disabledRule = Rule(
            name: "Aus",
            conditionField: "title",
            conditionOperator: "contains",
            conditionValue: "Swift"
        )
        disabledRule.isEnabled = false
        disabledRule.assignTag = Tag(name: "Disabled")
        let emptyValueRule = Rule(
            name: "Leer",
            conditionField: "title",
            conditionOperator: "contains",
            conditionValue: "   "
        )
        emptyValueRule.assignTag = Tag(name: "Leer")
        let missingTagRule = Rule(
            name: "Ohne Tag",
            conditionField: "title",
            conditionOperator: "contains",
            conditionValue: "Swift"
        )
        let unknownFieldRule = Rule(
            name: "Feld",
            conditionField: "author",
            conditionOperator: "contains",
            conditionValue: "Swift"
        )
        unknownFieldRule.assignTag = Tag(name: "Autor")
        let unknownOperatorRule = Rule(
            name: "Operator",
            conditionField: "title",
            conditionOperator: "regex",
            conditionValue: "Swift"
        )
        unknownOperatorRule.assignTag = Tag(name: "Regex")
        let feed = Feed(url: "https://example.com/feed.xml", title: "Feed")
        let article = Article(title: "Swift News", feed: feed)
        article.tags = [tag]

        RuleEngine.applyRules(
            [
                activeRule,
                disabledRule,
                emptyValueRule,
                missingTagRule,
                unknownFieldRule,
                unknownOperatorRule
            ],
            to: article,
            feed: feed
        )

        #expect(article.tags.map(\.name) == ["Swift"])
    }
}
