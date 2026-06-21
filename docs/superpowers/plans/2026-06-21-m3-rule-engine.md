# M3 Rule Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Automatically assign tags to newly fetched articles using stored rules.

**Architecture:** Add a stateless `RuleEngine` service that evaluates `Rule` models against `Article` and `Feed`. Integrate it into `FeedViewModel.refreshFeedContents` only for newly inserted articles, while keeping existing articles untouched.

**Tech Stack:** Swift, SwiftData, Swift Testing, Feedivo MVVM/service structure.

---

### Task 1: Rule Engine Service

**Files:**
- Create: `Feedivo/Services/RuleEngine.swift`
- Create: `FeedivoTests/RuleEngineTests.swift`

- [ ] **Step 1: Add failing RuleEngine tests**

Create `FeedivoTests/RuleEngineTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests and expect failure**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/RuleEngineTests -derivedDataPath /private/tmp/feedivo-m3-rule-engine-derived-data
```

Expected: FAIL because `RuleEngine` does not exist.

- [ ] **Step 3: Add RuleEngine implementation**

Create `Feedivo/Services/RuleEngine.swift`:

```swift
import Foundation

enum RuleEngine {
    static func applyRules(_ rules: [Rule], to article: Article, feed: Feed) {
        for rule in rules where rule.isEnabled {
            guard
                let tag = rule.assignTag,
                matches(rule: rule, article: article, feed: feed),
                !article.tags.contains(where: { $0.id == tag.id })
            else {
                continue
            }

            article.tags.append(tag)
        }
    }

    private static func matches(rule: Rule, article: Article, feed: Feed) -> Bool {
        let value = rule.conditionValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, let fieldValue = fieldValue(for: rule, article: article, feed: feed) else {
            return false
        }

        let normalizedFieldValue = fieldValue.lowercased()
        let normalizedValue = value.lowercased()

        switch rule.conditionOperator {
        case "contains":
            return normalizedFieldValue.contains(normalizedValue)
        case "startsWith":
            return normalizedFieldValue.hasPrefix(normalizedValue)
        case "endsWith":
            return normalizedFieldValue.hasSuffix(normalizedValue)
        default:
            return false
        }
    }

    private static func fieldValue(for rule: Rule, article: Article, feed: Feed) -> String? {
        switch rule.conditionField {
        case "title":
            return article.title
        case "summary":
            return article.summary
        case "feedTitle":
            return feed.title
        default:
            return nil
        }
    }
}
```

- [ ] **Step 4: Run RuleEngine tests and expect pass**

Run the same `xcodebuild ... -only-testing:FeedivoTests/RuleEngineTests ...` command.

Expected: PASS.

### Task 2: Feed Refresh Integration

**Files:**
- Modify: `Feedivo/ViewModels/FeedViewModel.swift`
- Modify: `FeedivoTests/FeedViewModelTests.swift`

- [ ] **Step 1: Add failing refresh integration test**

Add this test to `FeedViewModelTests`:

```swift
@MainActor
@Test func refreshFeedWendetRegelnAufNeueArtikelAn() async throws {
    let container = try ModelContainer(
        for: Feed.self,
        Article.self,
        Tag.self,
        Rule.self,
        FeedLogEntry.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = ModelContext(container)
    let feed = Feed(url: "https://example.com/feed.xml", title: "Alter Feed")
    let existingArticle = Article(
        title: "Swift Altbestand",
        link: "https://example.com/old",
        feed: feed
    )
    feed.articles = [existingArticle]
    let tag = Tag(name: "Swift", colorHex: "#3B82F6")
    let rule = Rule(
        name: "Swift Titel",
        conditionField: "title",
        conditionOperator: "contains",
        conditionValue: "swift"
    )
    rule.assignTag = tag
    context.insert(feed)
    context.insert(tag)
    context.insert(rule)
    try context.save()

    let viewModel = FeedViewModel(
        fetchFeed: { urlString in
            ParsedFeed(
                sourceURL: urlString,
                title: "Neuer Feed",
                description: nil,
                siteURL: nil,
                articles: [
                    ParsedArticle(
                        title: "Swift Altbestand",
                        link: "https://example.com/old",
                        summary: nil,
                        content: nil,
                        publishedAt: nil,
                        imageURL: nil
                    ),
                    ParsedArticle(
                        title: "Swift Neuer Artikel",
                        link: "https://example.com/new",
                        summary: nil,
                        content: nil,
                        publishedAt: nil,
                        imageURL: nil
                    )
                ]
            )
        },
        discoverFaviconURL: { _ in nil }
    )

    await viewModel.refreshFeed(feed, context: context)

    let newArticle = try #require(feed.articles.first { $0.link == "https://example.com/new" })
    #expect(newArticle.tags.map(\.name) == ["Swift"])
    #expect(existingArticle.tags.isEmpty)
}
```

- [ ] **Step 2: Run integration test and expect failure**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedViewModelTests/refreshFeedWendetRegelnAufNeueArtikelAn -derivedDataPath /private/tmp/feedivo-m3-rule-engine-derived-data
```

Expected: FAIL because refresh does not apply rules yet.

- [ ] **Step 3: Fetch rules and apply to new articles**

In `refreshFeedContents`, fetch rules before the loop:

```swift
let rules = try context.fetch(FetchDescriptor<Rule>())
```

Inside the new-article loop, create the article in a local variable, apply rules, then append:

```swift
let article = Article(
    title: articleToInsert.title,
    link: articleToInsert.link,
    summary: articleToInsert.summary,
    content: articleToInsert.content,
    publishedAt: articleToInsert.publishedAt,
    imageURL: articleToInsert.imageURL,
    feed: feed
)
RuleEngine.applyRules(rules, to: article, feed: feed)
feed.articles.append(article)
```

- [ ] **Step 4: Run integration test and expect pass**

Run the same `xcodebuild ... -only-testing:FeedivoTests/FeedViewModelTests/refreshFeedWendetRegelnAufNeueArtikelAn ...` command.

Expected: PASS.

### Task 3: Documentation and Full Verification

**Files:**
- Modify: `AGENTS.md`
- Modify: `docs/FEATURES.md`

- [ ] **Step 1: Update project memory**

Document:

- `RuleEngine.swift` exists and applies simple rules.
- M3 Rule Engine basis is complete.
- Rule UI, regex, multi-condition rules, and retroactive application remain open.

- [ ] **Step 2: Run full unit verification**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -skip-testing:FeedivoUITests -derivedDataPath /private/tmp/feedivo-m3-rule-engine-derived-data
```

Expected: `TEST SUCCEEDED`.

- [ ] **Step 3: Commit implementation**

Stage only implementation, tests, docs, spec, and plan files. Do not stage Xcode `UserInterfaceState.xcuserstate`.

Commit:

```bash
git commit -m "feat: apply simple tag rules on refresh"
```
