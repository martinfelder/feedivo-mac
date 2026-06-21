import Foundation
import SwiftData
import Testing
@testable import Feedivo

struct RuleEngineTests {
    @MainActor
    @Test func applyRulesUnterstuetztMehrereBedingungenMitAND() throws {
        let tag = Tag(name: "Apple", colorHex: "#3B82F6")
        let rule = Rule(
            name: "Apple Mac",
            conditionField: "title",
            conditionOperator: "contains",
            conditionValue: "Apple"
        )
        rule.conditionMatchMode = RuleMatchMode.all.rawValue
        rule.conditions = [
            RuleCondition(field: "title", conditionOperator: "contains", value: "Apple", sortOrder: 0),
            RuleCondition(field: "feedTitle", conditionOperator: "contains", value: "Mac", sortOrder: 1)
        ]
        rule.assignTag = tag
        let feed = Feed(url: "https://example.com/feed.xml", title: "Mac News")
        let matchingArticle = Article(title: "Apple stellt Swift vor", feed: feed)
        let otherFeed = Feed(url: "https://example.com/other.xml", title: "Other News")
        let nonMatchingArticle = Article(title: "Apple stellt Swift vor", feed: otherFeed)

        RuleEngine.applyRules([rule], to: matchingArticle, feed: feed)
        RuleEngine.applyRules([rule], to: nonMatchingArticle, feed: otherFeed)

        #expect(matchingArticle.tags.map(\.name) == ["Apple"])
        #expect(nonMatchingArticle.tags.isEmpty)
    }

    @MainActor
    @Test func applyRulesUnterstuetztMehrereBedingungenMitOR() throws {
        let tag = Tag(name: "Apple", colorHex: "#3B82F6")
        let rule = Rule(
            name: "Apple oder Mac",
            conditionField: "title",
            conditionOperator: "contains",
            conditionValue: "Apple"
        )
        rule.conditionMatchMode = RuleMatchMode.any.rawValue
        rule.conditions = [
            RuleCondition(field: "title", conditionOperator: "contains", value: "Apple", sortOrder: 0),
            RuleCondition(field: "feedTitle", conditionOperator: "contains", value: "Mac", sortOrder: 1)
        ]
        rule.assignTag = tag
        let feed = Feed(url: "https://example.com/feed.xml", title: "Mac News")
        let article = Article(title: "Swift Update", feed: feed)

        RuleEngine.applyRules([rule], to: article, feed: feed)

        #expect(article.tags.map(\.name) == ["Apple"])
    }

    @MainActor
    @Test func applyRulesIgnoriertRegelnOhneGueltigeConditions() throws {
        let tag = Tag(name: "Swift", colorHex: "#3B82F6")
        let rule = Rule(
            name: "Leer",
            conditionField: "title",
            conditionOperator: "contains",
            conditionValue: "Swift"
        )
        rule.conditions = [
            RuleCondition(field: "title", conditionOperator: "contains", value: "   ", sortOrder: 0),
            RuleCondition(field: "author", conditionOperator: "contains", value: "Swift", sortOrder: 1)
        ]
        rule.assignTag = tag
        let feed = Feed(url: "https://example.com/feed.xml", title: "Feed")
        let article = Article(title: "Swift News", feed: feed)

        RuleEngine.applyRules([rule], to: article, feed: feed)

        #expect(article.tags.isEmpty)
    }

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
        titleRule.conditions = [
            RuleCondition(field: "title", conditionOperator: "contains", value: "swift")
        ]
        titleRule.assignTag = swiftTag
        let summaryRule = Rule(
            name: "Summary Start",
            conditionField: "summary",
            conditionOperator: "startsWith",
            conditionValue: "breaking"
        )
        summaryRule.conditions = [
            RuleCondition(field: "summary", conditionOperator: "startsWith", value: "breaking")
        ]
        summaryRule.assignTag = newsTag
        let feedRule = Rule(
            name: "Feed Ende",
            conditionField: "feedTitle",
            conditionOperator: "endsWith",
            conditionValue: "weekly"
        )
        feedRule.conditions = [
            RuleCondition(field: "feedTitle", conditionOperator: "endsWith", value: "weekly")
        ]
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
        activeRule.conditions = [
            RuleCondition(field: "title", conditionOperator: "contains", value: "Swift")
        ]
        activeRule.assignTag = tag
        let disabledRule = Rule(
            name: "Aus",
            conditionField: "title",
            conditionOperator: "contains",
            conditionValue: "Swift"
        )
        disabledRule.isEnabled = false
        disabledRule.conditions = [
            RuleCondition(field: "title", conditionOperator: "contains", value: "Swift")
        ]
        disabledRule.assignTag = Tag(name: "Disabled")
        let emptyValueRule = Rule(
            name: "Leer",
            conditionField: "title",
            conditionOperator: "contains",
            conditionValue: "   "
        )
        emptyValueRule.conditions = [
            RuleCondition(field: "title", conditionOperator: "contains", value: "   ")
        ]
        emptyValueRule.assignTag = Tag(name: "Leer")
        let missingTagRule = Rule(
            name: "Ohne Tag",
            conditionField: "title",
            conditionOperator: "contains",
            conditionValue: "Swift"
        )
        missingTagRule.conditions = [
            RuleCondition(field: "title", conditionOperator: "contains", value: "Swift")
        ]
        let unknownFieldRule = Rule(
            name: "Feld",
            conditionField: "author",
            conditionOperator: "contains",
            conditionValue: "Swift"
        )
        unknownFieldRule.conditions = [
            RuleCondition(field: "author", conditionOperator: "contains", value: "Swift")
        ]
        unknownFieldRule.assignTag = Tag(name: "Autor")
        let unknownOperatorRule = Rule(
            name: "Operator",
            conditionField: "title",
            conditionOperator: "regex",
            conditionValue: "Swift"
        )
        unknownOperatorRule.conditions = [
            RuleCondition(field: "title", conditionOperator: "regex", value: "Swift")
        ]
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
