import Foundation

enum RuleEngine {
    private struct NormalizedCondition {
        var field: String
        var conditionOperator: String
        var value: String
    }

    @discardableResult
    static func applyRules(_ rules: [Rule], to article: Article, feed: Feed) -> Int {
        var appliedActionCount = 0

        for rule in sortedRules(rules) where rule.isEnabled {
            guard matches(rule: rule, article: article, feed: feed) else {
                continue
            }

            switch RuleAction.normalized(rule.actionRaw) {
            case .assignTag:
                guard let tag = rule.assignTag,
                      !article.tags.contains(where: { $0.id == tag.id })
                else {
                    continue
                }

                article.tags.append(tag)
                appliedActionCount += 1
            case .hideArticle:
                guard !article.isHidden else {
                    continue
                }

                article.isHidden = true
                appliedActionCount += 1
            }
        }

        return appliedActionCount
    }

    static func applyRulesToExistingArticles(_ rules: [Rule], articles: [Article]) -> Int {
        articles.reduce(0) { appliedActionCount, article in
            guard let feed = article.feed else {
                return appliedActionCount
            }

            return appliedActionCount + applyRules(rules, to: article, feed: feed)
        }
    }

    static func matchingArticleCount(
        conditionDrafts: [RuleConditionDraft],
        matchMode: RuleMatchMode,
        articles: [Article]
    ) -> Int {
        let conditions = normalizedConditions(from: conditionDrafts)
        guard !conditions.isEmpty else {
            return 0
        }

        return articles.reduce(0) { count, article in
            guard let feed = article.feed,
                  matches(conditions: conditions, matchMode: matchMode, article: article, feed: feed)
            else {
                return count
            }

            return count + 1
        }
    }

    private static func matches(rule: Rule, article: Article, feed: Feed) -> Bool {
        let conditions = normalizedConditions(for: rule)
        guard !conditions.isEmpty else {
            return false
        }

        let mode = RuleMatchMode.normalized(rule.conditionMatchMode)
        return matches(conditions: conditions, matchMode: mode, article: article, feed: feed)
    }

    private static func matches(
        conditions: [NormalizedCondition],
        matchMode: RuleMatchMode,
        article: Article,
        feed: Feed
    ) -> Bool {
        switch matchMode {
        case .all:
            return conditions.allSatisfy { condition in
                matches(condition: condition, article: article, feed: feed)
            }
        case .any:
            return conditions.contains { condition in
                matches(condition: condition, article: article, feed: feed)
            }
        }
    }

    private static func sortedRules(_ rules: [Rule]) -> [Rule] {
        rules.sorted { firstRule, secondRule in
            if firstRule.sortOrder == secondRule.sortOrder {
                return firstRule.name.localizedCaseInsensitiveCompare(secondRule.name) == .orderedAscending
            }

            return firstRule.sortOrder < secondRule.sortOrder
        }
    }

    private static func normalizedConditions(for rule: Rule) -> [NormalizedCondition] {
        rule.conditions
            .sorted { $0.sortOrder < $1.sortOrder }
            .compactMap { condition in
                normalizedCondition(
                    field: condition.field,
                    conditionOperator: condition.conditionOperator,
                    value: condition.value
                )
            }
    }

    private static func normalizedConditions(from drafts: [RuleConditionDraft]) -> [NormalizedCondition] {
        drafts.compactMap { draft in
            normalizedCondition(
                field: draft.field.rawValue,
                conditionOperator: draft.conditionOperator.rawValue,
                value: draft.value
            )
        }
    }

    private static func normalizedCondition(
        field: String,
        conditionOperator: String,
        value: String
    ) -> NormalizedCondition? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return nil
        }

        return NormalizedCondition(
            field: field,
            conditionOperator: conditionOperator,
            value: trimmedValue
        )
    }

    private static func matches(condition: NormalizedCondition, article: Article, feed: Feed) -> Bool {
        guard let fieldValue = fieldValue(for: condition.field, article: article, feed: feed) else {
            return false
        }

        let normalizedFieldValue = fieldValue.lowercased()
        let normalizedValue = condition.value.lowercased()

        switch condition.conditionOperator {
        case RuleConditionOperator.contains.rawValue:
            return normalizedFieldValue.contains(normalizedValue)
        case RuleConditionOperator.startsWith.rawValue:
            return normalizedFieldValue.hasPrefix(normalizedValue)
        case RuleConditionOperator.endsWith.rawValue:
            return normalizedFieldValue.hasSuffix(normalizedValue)
        default:
            return false
        }
    }

    private static func fieldValue(for field: String, article: Article, feed: Feed) -> String? {
        switch field {
        case RuleConditionField.title.rawValue:
            return article.title
        case RuleConditionField.summary.rawValue:
            return article.summary
        case RuleConditionField.feedTitle.rawValue:
            return feed.title
        default:
            return nil
        }
    }
}
