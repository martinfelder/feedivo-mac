import Foundation
import SwiftData
import Testing
@testable import Feedivo

struct RuleEngineTests {
    @MainActor
    @Test func previewMatchingArticleCountZaehltTrefferOhneTagsZuSetzen() throws {
        let feed = Feed(url: "https://example.com/feed.xml", title: "Mac News")
        let otherFeed = Feed(url: "https://example.com/other.xml", title: "Other News")
        let matchingArticle = Article(
            title: "Swift auf dem Mac",
            summary: "Neue Tools",
            feed: feed
        )
        let nonMatchingArticle = Article(
            title: "Swift auf dem Mac",
            summary: "Neue Tools",
            feed: otherFeed
        )
        let articleWithoutFeed = Article(
            title: "Swift auf dem Mac",
            summary: "Neue Tools"
        )

        let matchingCount = RuleEngine.matchingArticleCount(
            conditionDrafts: [
                RuleConditionDraft(field: .title, conditionOperator: .contains, value: "Swift"),
                RuleConditionDraft(field: .feedTitle, conditionOperator: .contains, value: "Mac")
            ],
            matchMode: .all,
            articles: [matchingArticle, nonMatchingArticle, articleWithoutFeed]
        )

        #expect(matchingCount == 1)
        #expect((matchingArticle.tags ?? []).isEmpty)
        #expect((nonMatchingArticle.tags ?? []).isEmpty)
        #expect((articleWithoutFeed.tags ?? []).isEmpty)
    }

    @MainActor
    @Test func previewMatchingArticleCountUnterstuetztOderBedingungen() throws {
        let feed = Feed(url: "https://example.com/feed.xml", title: "Mac News")
        let titleMatch = Article(title: "Swift Update", feed: feed)
        let feedMatch = Article(title: "Apple News", feed: feed)
        let noMatch = Article(title: "Windows Update", feed: Feed(url: "https://example.com/other.xml", title: "Other"))

        let matchingCount = RuleEngine.matchingArticleCount(
            conditionDrafts: [
                RuleConditionDraft(field: .title, conditionOperator: .contains, value: "Swift"),
                RuleConditionDraft(field: .feedTitle, conditionOperator: .contains, value: "Mac")
            ],
            matchMode: .any,
            articles: [titleMatch, feedMatch, noMatch]
        )

        #expect(matchingCount == 2)
    }

    @MainActor
    @Test func previewMatchingArticleCountUnterstuetztRegexOperator() throws {
        let feed = Feed(url: "https://example.com/feed.xml", title: "Mac News")
        let matchingArticle = Article(title: "Swift 7 erscheint", feed: feed)
        let nonMatchingArticle = Article(title: "Swift erscheint", feed: feed)

        let matchingCount = RuleEngine.matchingArticleCount(
            conditionDrafts: [
                RuleConditionDraft(field: .title, conditionOperator: .regex, value: #"swift\s+\d+"#)
            ],
            matchMode: .all,
            articles: [matchingArticle, nonMatchingArticle]
        )

        #expect(matchingCount == 1)
    }

    @MainActor
    @Test func previewMatchingArticleCountIgnoriertUngueltigeRegexPatterns() throws {
        let feed = Feed(url: "https://example.com/feed.xml", title: "Mac News")
        let article = Article(title: "Swift 7 erscheint", feed: feed)

        let matchingCount = RuleEngine.matchingArticleCount(
            conditionDrafts: [
                RuleConditionDraft(field: .title, conditionOperator: .regex, value: "[")
            ],
            matchMode: .all,
            articles: [article]
        )

        #expect(matchingCount == 0)
    }

    @MainActor
    @Test func applyRulesUnterstuetztMehrereBedingungenMitAND() throws {
        let tag = Tag(name: "Apple", colorHex: "#3B82F6")
        let rule = Rule(name: "Apple Mac")
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

        #expect((matchingArticle.tags ?? []).map(\.name) == ["Apple"])
        #expect((nonMatchingArticle.tags ?? []).isEmpty)
    }

    @MainActor
    @Test func applyRulesUnterstuetztMehrereBedingungenMitOR() throws {
        let tag = Tag(name: "Apple", colorHex: "#3B82F6")
        let rule = Rule(name: "Apple oder Mac")
        rule.conditionMatchMode = RuleMatchMode.any.rawValue
        rule.conditions = [
            RuleCondition(field: "title", conditionOperator: "contains", value: "Apple", sortOrder: 0),
            RuleCondition(field: "feedTitle", conditionOperator: "contains", value: "Mac", sortOrder: 1)
        ]
        rule.assignTag = tag
        let feed = Feed(url: "https://example.com/feed.xml", title: "Mac News")
        let article = Article(title: "Swift Update", feed: feed)

        RuleEngine.applyRules([rule], to: article, feed: feed)

        #expect((article.tags ?? []).map(\.name) == ["Apple"])
    }

    @MainActor
    @Test func applyRulesIgnoriertRegelnOhneGueltigeConditions() throws {
        let tag = Tag(name: "Swift", colorHex: "#3B82F6")
        let rule = Rule(name: "Leer")
        rule.conditions = [
            RuleCondition(field: "title", conditionOperator: "contains", value: "   ", sortOrder: 0),
            RuleCondition(field: "author", conditionOperator: "contains", value: "Swift", sortOrder: 1)
        ]
        rule.assignTag = tag
        let feed = Feed(url: "https://example.com/feed.xml", title: "Feed")
        let article = Article(title: "Swift News", feed: feed)

        RuleEngine.applyRules([rule], to: article, feed: feed)

        #expect((article.tags ?? []).isEmpty)
    }

    @MainActor
    @Test func applyRulesTaggtArtikelBeiTitelSummaryUndFeedTreffern() throws {
        let swiftTag = Tag(name: "Swift", colorHex: "#3B82F6")
        let macTag = Tag(name: "Mac", colorHex: "#22C55E")
        let newsTag = Tag(name: "News", colorHex: "#F59E0B")
        let titleRule = Rule(name: "Swift Titel")
        titleRule.conditions = [
            RuleCondition(field: "title", conditionOperator: "contains", value: "swift")
        ]
        titleRule.assignTag = swiftTag
        let summaryRule = Rule(name: "Summary Start")
        summaryRule.conditions = [
            RuleCondition(field: "summary", conditionOperator: "startsWith", value: "breaking")
        ]
        summaryRule.assignTag = newsTag
        let feedRule = Rule(name: "Feed Ende")
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

        #expect((article.tags ?? []).map(\.name).sorted() == ["Mac", "News", "Swift"])
    }

    @MainActor
    @Test func applyRulesGibtAnzahlNeuGesetzterTagsZurueck() throws {
        let tag = Tag(name: "Swift", colorHex: "#3B82F6")
        let rule = Rule(name: "Swift")
        rule.conditions = [
            RuleCondition(field: "title", conditionOperator: "contains", value: "Swift")
        ]
        rule.assignTag = tag
        let feed = Feed(url: "https://example.com/feed.xml", title: "Feed")
        let article = Article(title: "Swift News", feed: feed)

        let firstAppliedCount = RuleEngine.applyRules([rule], to: article, feed: feed)
        let secondAppliedCount = RuleEngine.applyRules([rule], to: article, feed: feed)

        #expect(firstAppliedCount == 1)
        #expect(secondAppliedCount == 0)
        #expect((article.tags ?? []).map(\.name) == ["Swift"])
    }

    @MainActor
    @Test func applyRulesWertetRegelnNachSortOrderAus() throws {
        let firstTag = Tag(name: "Erste Aktion", colorHex: "#3B82F6")
        let secondTag = Tag(name: "Zweite Aktion", colorHex: "#22C55E")
        let firstRule = Rule(name: "Erste Regel")
        firstRule.sortOrder = 0
        firstRule.conditions = [
            RuleCondition(field: "title", conditionOperator: "contains", value: "Swift")
        ]
        firstRule.assignTag = firstTag
        let secondRule = Rule(name: "Zweite Regel")
        secondRule.sortOrder = 1
        secondRule.conditions = [
            RuleCondition(field: "title", conditionOperator: "contains", value: "Swift")
        ]
        secondRule.assignTag = secondTag
        let feed = Feed(url: "https://example.com/feed.xml", title: "Feed")
        let article = Article(title: "Swift News", feed: feed)

        RuleEngine.applyRules([secondRule, firstRule], to: article, feed: feed)

        #expect((article.tags ?? []).map(\.name) == ["Erste Aktion", "Zweite Aktion"])
    }

    @MainActor
    @Test func applyRulesToExistingArticlesTaggtVorhandeneArtikelRueckwirkend() throws {
        let tag = Tag(name: "Swift", colorHex: "#3B82F6")
        let rule = Rule(name: "Swift")
        rule.conditions = [
            RuleCondition(field: "title", conditionOperator: "contains", value: "Swift")
        ]
        rule.assignTag = tag
        let feed = Feed(url: "https://example.com/feed.xml", title: "Feed")
        let matchingArticle = Article(title: "Swift News", feed: feed)
        let existingTaggedArticle = Article(title: "Swift Tipps", feed: feed)
        existingTaggedArticle.tags = [tag]
        let unmatchedArticle = Article(title: "Mac News", feed: feed)
        let articleWithoutFeed = Article(title: "Swift ohne Feed")

        let appliedCount = RuleEngine.applyRulesToExistingArticles(
            [rule],
            articles: [
                matchingArticle,
                existingTaggedArticle,
                unmatchedArticle,
                articleWithoutFeed
            ]
        )

        #expect(appliedCount == 1)
        #expect((matchingArticle.tags ?? []).map(\.name) == ["Swift"])
        #expect((existingTaggedArticle.tags ?? []).map(\.name) == ["Swift"])
        #expect((unmatchedArticle.tags ?? []).isEmpty)
        #expect((articleWithoutFeed.tags ?? []).isEmpty)
    }

    @MainActor
    @Test func applyRulesBlendetArtikelBeiHideAktionAus() throws {
        let rule = Rule(name: "Spoiler ausblenden")
        rule.actionRaw = RuleAction.hideArticle.rawValue
        rule.conditions = [
            RuleCondition(field: "title", conditionOperator: "contains", value: "Spoiler")
        ]
        let feed = Feed(url: "https://example.com/feed.xml", title: "Feed")
        let article = Article(title: "Spoiler zum Film", feed: feed)

        let appliedCount = RuleEngine.applyRules([rule], to: article, feed: feed)
        let secondAppliedCount = RuleEngine.applyRules([rule], to: article, feed: feed)

        #expect(appliedCount == 1)
        #expect(secondAppliedCount == 0)
        #expect(article.isHidden)
        #expect((article.tags ?? []).isEmpty)
    }

    @MainActor
    @Test func applyRulesToExistingArticlesBlendetPassendeArtikelRueckwirkendAus() throws {
        let rule = Rule(name: "Spoiler ausblenden")
        rule.actionRaw = RuleAction.hideArticle.rawValue
        rule.conditions = [
            RuleCondition(field: "title", conditionOperator: "contains", value: "Spoiler")
        ]
        let feed = Feed(url: "https://example.com/feed.xml", title: "Feed")
        let matchingArticle = Article(title: "Spoiler zum Film", feed: feed)
        let alreadyHiddenArticle = Article(title: "Spoiler alt", isHidden: true, feed: feed)
        let unmatchedArticle = Article(title: "Normale News", feed: feed)
        feed.unreadCount = 2

        let appliedCount = RuleEngine.applyRulesToExistingArticles(
            [rule],
            articles: [matchingArticle, alreadyHiddenArticle, unmatchedArticle]
        )

        #expect(appliedCount == 1)
        #expect(matchingArticle.isHidden)
        #expect(alreadyHiddenArticle.isHidden)
        #expect(!unmatchedArticle.isHidden)
        #expect(feed.unreadCount == 1)
    }

    @MainActor
    @Test func applyRulesIgnoriertUngueltigeRegelnUndVerhindertDoppelteTags() throws {
        let tag = Tag(name: "Swift", colorHex: "#3B82F6")
        let activeRule = Rule(name: "Swift")
        activeRule.conditions = [
            RuleCondition(field: "title", conditionOperator: "contains", value: "Swift")
        ]
        activeRule.assignTag = tag
        let disabledRule = Rule(name: "Aus")
        disabledRule.isEnabled = false
        disabledRule.conditions = [
            RuleCondition(field: "title", conditionOperator: "contains", value: "Swift")
        ]
        disabledRule.assignTag = Tag(name: "Disabled")
        let emptyValueRule = Rule(name: "Leer")
        emptyValueRule.conditions = [
            RuleCondition(field: "title", conditionOperator: "contains", value: "   ")
        ]
        emptyValueRule.assignTag = Tag(name: "Leer")
        let missingTagRule = Rule(name: "Ohne Tag")
        missingTagRule.conditions = [
            RuleCondition(field: "title", conditionOperator: "contains", value: "Swift")
        ]
        let unknownFieldRule = Rule(name: "Feld")
        unknownFieldRule.conditions = [
            RuleCondition(field: "author", conditionOperator: "contains", value: "Swift")
        ]
        unknownFieldRule.assignTag = Tag(name: "Autor")
        let unknownOperatorRule = Rule(name: "Operator")
        unknownOperatorRule.conditions = [
            RuleCondition(field: "title", conditionOperator: "unknown", value: "Swift")
        ]
        unknownOperatorRule.assignTag = Tag(name: "Unbekannt")
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

        #expect((article.tags ?? []).map(\.name) == ["Swift"])
    }

    @MainActor
    @Test func applyRulesErzeugtRegelBenachrichtigungOhneArtikelZuVeraendern() throws {
        let rule = Rule(name: "Breaking")
        rule.actionRaw = RuleAction.notify.rawValue
        rule.notificationTemplate = "Breaking: {Titel} aus {Feed}"
        rule.notificationPriorityRaw = RuleNotificationPriority.critical.rawValue
        rule.conditions = [
            RuleCondition(field: "title", conditionOperator: "contains", value: "Swift")
        ]
        let feed = Feed(url: "https://example.com/feed.xml", title: "Mac News")
        let article = Article(title: "Swift 7 ist da", feed: feed)

        let result = RuleEngine.applyRulesWithNotifications([rule], to: article, feed: feed)

        #expect(result.appliedActionCount == 1)
        #expect((article.tags ?? []).isEmpty)
        #expect(!article.isHidden)
        #expect(result.notifications == [
            RuleNotificationResult(
                ruleID: rule.id,
                ruleName: "Breaking",
                message: "Breaking: Swift 7 ist da aus Mac News",
                articleTitle: "Swift 7 ist da",
                feedTitle: "Mac News",
                priority: .critical
            )
        ])
    }

    @MainActor
    @Test func applyRulesBatchWendetRegelAufAllePassendenArtikelAn() throws {
        let rule = Rule(name: "Swift")
        rule.actionRaw = RuleAction.assignTag.rawValue
        rule.conditions = [
            RuleCondition(field: "title", conditionOperator: "contains", value: "Swift")
        ]
        let feed = Feed(url: "https://example.com/feed.xml", title: "Mac News")
        let tag = Tag(name: "Swift", colorHex: "#FF0000")
        rule.assignTag = tag

        let matching = Article(title: "Swift 7 ist da", feed: feed)
        let nonMatching = Article(title: "Sonstiges", feed: feed)

        let result = RuleEngine.applyRulesWithNotifications([rule], to: [matching, nonMatching], feed: feed)

        #expect(result.appliedActionCount == 1)
        #expect((matching.tags ?? []).map(\.name) == ["Swift"])
        #expect((nonMatching.tags ?? []).isEmpty)
    }

    @MainActor
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
