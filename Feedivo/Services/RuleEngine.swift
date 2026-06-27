import Foundation

enum RuleEngine {
    struct RuleApplicationResult: Equatable {
        var appliedActionCount: Int
        var notifications: [RuleNotificationResult]
    }

    private struct NormalizedCondition {
        var field: String
        var conditionOperator: String
        var lowercasedValue: String
    }

    /// Vorbereitete Regel: Sortierung, Conditions und Match-Modus werden einmalig
    /// vor der Artikel-Schleife berechnet, statt pro Artikel neu aufgebaut zu werden.
    private struct PreparedRule {
        let rule: Rule
        let conditions: [NormalizedCondition]
        let matchMode: RuleMatchMode
    }

    @discardableResult
    @MainActor
    static func applyRules(_ rules: [Rule], to article: Article, feed: Feed) -> Int {
        applyRulesWithNotifications(rules, to: article, feed: feed).appliedActionCount
    }

    @MainActor
    static func applyRulesWithNotifications(_ rules: [Rule], to article: Article, feed: Feed) -> RuleApplicationResult {
        applyPreparedRulesWithNotifications(preparedRules(rules), to: article, feed: feed)
    }

    /// Wendet Regeln auf mehrere Artikel eines Feeds an. `preparedRules` wird nur
    /// einmal berechnet (Sortierung + normalisierte Conditions) statt pro Artikel
    /// neu aufgebaut — das war vorher im Refresh-Pfad pro neuem Artikel der Fall.
    @MainActor
    static func applyRulesWithNotifications(_ rules: [Rule], to articles: [Article], feed: Feed) -> RuleApplicationResult {
        let prepared = preparedRules(rules)
        var appliedActionCount = 0
        var notifications: [RuleNotificationResult] = []

        for article in articles {
            let result = applyPreparedRulesWithNotifications(prepared, to: article, feed: feed)
            appliedActionCount += result.appliedActionCount
            notifications.append(contentsOf: result.notifications)
        }

        return RuleApplicationResult(
            appliedActionCount: appliedActionCount,
            notifications: notifications
        )
    }

    @MainActor
    static func applyRulesToExistingArticles(_ rules: [Rule], articles: [Article]) -> Int {
        // Regeln einmalig vorbereiten (Sortierung + normalisierte Conditions),
        // damit pro Artikel nur noch die vorbereitete Struktur ausgewertet wird.
        let preparedRules = preparedRules(rules)

        return articles.reduce(0) { appliedActionCount, article in
            guard let feed = article.feed else {
                return appliedActionCount
            }

            return appliedActionCount + applyPreparedRulesWithNotifications(
                preparedRules,
                to: article,
                feed: feed
            ).appliedActionCount
        }
    }

    @MainActor
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

    private static func applyPreparedRulesWithNotifications(
        _ preparedRules: [PreparedRule],
        to article: Article,
        feed: Feed
    ) -> RuleApplicationResult {
        var appliedActionCount = 0
        var notifications: [RuleNotificationResult] = []

        for preparedRule in preparedRules {
            let rule = preparedRule.rule
            guard matches(
                conditions: preparedRule.conditions,
                matchMode: preparedRule.matchMode,
                article: article,
                feed: feed
            ) else {
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
                SidebarBadgeInvalidation.bumpDirectTagVersion()
                appliedActionCount += 1
            case .hideArticle:
                guard !article.isHidden else {
                    continue
                }

                article.isHidden = true
                appliedActionCount += 1
            case .notify:
                notifications.append(notificationResult(for: rule, article: article, feed: feed))
                appliedActionCount += 1
            }
        }

        return RuleApplicationResult(
            appliedActionCount: appliedActionCount,
            notifications: notifications
        )
    }

    private static func preparedRules(_ rules: [Rule]) -> [PreparedRule] {
        sortedRules(rules).compactMap { rule in
            guard rule.isEnabled else {
                return nil
            }

            let conditions = normalizedConditions(for: rule)
            guard !conditions.isEmpty else {
                return nil
            }

            return PreparedRule(
                rule: rule,
                conditions: conditions,
                matchMode: RuleMatchMode.normalized(rule.conditionMatchMode)
            )
        }
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
            // Wert einmalig kleinschreiben — er ist statisch zur Laufzeit und
            // wird sonst bei jedem Artikel-Vergleich neu lowercased.
            lowercasedValue: trimmedValue.lowercased()
        )
    }

    private static func matches(condition: NormalizedCondition, article: Article, feed: Feed) -> Bool {
        guard let fieldValue = fieldValue(for: condition.field, article: article, feed: feed) else {
            return false
        }

        let normalizedFieldValue = fieldValue.lowercased()

        switch condition.conditionOperator {
        case RuleConditionOperator.contains.rawValue:
            return normalizedFieldValue.contains(condition.lowercasedValue)
        case RuleConditionOperator.startsWith.rawValue:
            return normalizedFieldValue.hasPrefix(condition.lowercasedValue)
        case RuleConditionOperator.endsWith.rawValue:
            return normalizedFieldValue.hasSuffix(condition.lowercasedValue)
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

    private static func notificationResult(for rule: Rule, article: Article, feed: Feed) -> RuleNotificationResult {
        RuleNotificationResult(
            ruleID: rule.id,
            ruleName: rule.name,
            message: notificationMessage(for: rule, article: article, feed: feed),
            articleTitle: article.title,
            feedTitle: feed.title,
            priority: RuleNotificationPriority.normalized(rule.notificationPriorityRaw)
        )
    }

    private static func notificationMessage(for rule: Rule, article: Article, feed: Feed) -> String {
        let template = rule.notificationTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTemplate = template.isEmpty ? "{Titel}" : template

        return normalizedTemplate
            .replacingOccurrences(of: "{Titel}", with: article.title)
            .replacingOccurrences(of: "{Feed}", with: feed.title)
            .replacingOccurrences(of: "{Regel}", with: rule.name)
    }
}