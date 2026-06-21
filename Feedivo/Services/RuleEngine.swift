import Foundation

enum RuleEngine {
    @discardableResult
    static func applyRules(_ rules: [Rule], to article: Article, feed: Feed) -> Int {
        var appliedTagCount = 0

        for rule in rules where rule.isEnabled {
            guard
                let tag = rule.assignTag,
                matches(rule: rule, article: article, feed: feed),
                !article.tags.contains(where: { $0.id == tag.id })
            else {
                continue
            }

            article.tags.append(tag)
            appliedTagCount += 1
        }

        return appliedTagCount
    }

    static func applyRulesToExistingArticles(_ rules: [Rule], articles: [Article]) -> Int {
        articles.reduce(0) { appliedTagCount, article in
            guard let feed = article.feed else {
                return appliedTagCount
            }

            return appliedTagCount + applyRules(rules, to: article, feed: feed)
        }
    }

    private static func matches(rule: Rule, article: Article, feed: Feed) -> Bool {
        let conditions = normalizedConditions(for: rule)
        guard !conditions.isEmpty else {
            return false
        }

        let mode = RuleMatchMode.normalized(rule.conditionMatchMode)
        switch mode {
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

    private static func normalizedConditions(for rule: Rule) -> [RuleCondition] {
        rule.conditions
            .sorted { $0.sortOrder < $1.sortOrder }
            .filter { condition in
                !condition.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
    }

    private static func matches(condition: RuleCondition, article: Article, feed: Feed) -> Bool {
        let value = condition.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              let fieldValue = fieldValue(for: condition.field, article: article, feed: feed)
        else {
            return false
        }

        let normalizedFieldValue = fieldValue.lowercased()
        let normalizedValue = value.lowercased()

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
