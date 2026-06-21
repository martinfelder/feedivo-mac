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
