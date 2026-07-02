import Foundation

enum RuleEngine {
    struct RuleApplicationResult: Equatable {
        var appliedActionCount: Int
        var notifications: [RuleNotificationResult]
    }

    struct RuleConditionSnapshot: Equatable, Sendable {
        var field: String
        var conditionOperator: String
        var value: String
        var sortOrder: Int
    }

    struct RuleSnapshot: Equatable, Sendable {
        var id: UUID
        var name: String
        var isEnabled: Bool
        var conditionMatchMode: String
        var actionRaw: String
        var notificationTemplate: String
        var notificationPriorityRaw: String
        var sortOrder: Int
        var conditions: [RuleConditionSnapshot]
        var assignTag: TagSnapshot?
    }

    struct TagSnapshot: Equatable, Sendable {
        var id: String
        var name: String
        var colorHex: String
    }

    struct ArticleRuleSnapshot: Equatable, Sendable {
        var id: String
        var title: String
        var summary: String?
        var feedTitle: String
    }

    struct SQLiteRuleApplicationResult: Equatable, Sendable {
        var appliedActionCount: Int
        var hiddenArticleIDs: [String]
        var tagAssignments: [ArticleTagAssignment]
        var notifications: [RuleNotificationResult]
    }

    struct ArticleTagAssignment: Equatable, Sendable {
        var articleID: String
        var tag: TagSnapshot
    }

    private struct NormalizedCondition {
        var field: String
        var conditionOperator: String
        var lowercasedValue: String
        var regularExpression: NSRegularExpression?
    }

    /// Vorbereitete Regel: Sortierung, Conditions und Match-Modus werden einmalig
    /// vor der Artikel-Schleife berechnet, statt pro Artikel neu aufgebaut zu werden.
    private struct PreparedRule {
        let rule: Rule
        let conditions: [NormalizedCondition]
        let matchMode: RuleMatchMode
    }

    private struct PreparedRuleSnapshot {
        let rule: RuleSnapshot
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

    @MainActor
    static func snapshots(from rules: [Rule]) -> [RuleSnapshot] {
        rules.map { rule in
            RuleSnapshot(
                id: rule.id,
                name: rule.name,
                isEnabled: rule.isEnabled,
                conditionMatchMode: rule.conditionMatchMode,
                actionRaw: rule.actionRaw,
                notificationTemplate: rule.notificationTemplate,
                notificationPriorityRaw: rule.notificationPriorityRaw,
                sortOrder: rule.sortOrder,
                conditions: (rule.conditions ?? []).map { condition in
                    RuleConditionSnapshot(
                        field: condition.field,
                        conditionOperator: condition.conditionOperator,
                        value: condition.value,
                        sortOrder: condition.sortOrder
                    )
                },
                assignTag: rule.assignTag.map { tag in
                    TagSnapshot(
                        id: tag.id.uuidString,
                        name: tag.name,
                        colorHex: tag.colorHex
                    )
                }
            )
        }
    }

    static func applySQLiteRules(
        _ rules: [RuleSnapshot],
        to articles: [ArticleRuleSnapshot]
    ) -> SQLiteRuleApplicationResult {
        let preparedRules = preparedSQLiteRules(rules)
        var appliedActionCount = 0
        var hiddenArticleIDs: [String] = []
        var tagAssignments: [ArticleTagAssignment] = []
        var assignedArticleTagPairs = Set<String>()
        var notifications: [RuleNotificationResult] = []

        for article in articles {
            for preparedRule in preparedRules {
                guard matches(
                    conditions: preparedRule.conditions,
                    matchMode: preparedRule.matchMode,
                    article: article
                ) else {
                    continue
                }

                switch RuleAction.normalized(preparedRule.rule.actionRaw) {
                case .assignTag:
                    guard let tag = preparedRule.rule.assignTag else {
                        continue
                    }

                    let assignmentKey = "\(article.id)|\(tag.id)"
                    guard assignedArticleTagPairs.insert(assignmentKey).inserted else {
                        continue
                    }

                    tagAssignments.append(
                        ArticleTagAssignment(
                            articleID: article.id,
                            tag: tag
                        )
                    )
                    appliedActionCount += 1
                case .hideArticle:
                    if !hiddenArticleIDs.contains(article.id) {
                        hiddenArticleIDs.append(article.id)
                    }
                    appliedActionCount += 1
                case .notify:
                    notifications.append(notificationResult(for: preparedRule.rule, article: article))
                    appliedActionCount += 1
                }
            }
        }

        return SQLiteRuleApplicationResult(
            appliedActionCount: appliedActionCount,
            hiddenArticleIDs: hiddenArticleIDs,
            tagAssignments: tagAssignments,
            notifications: notifications
        )
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
        var appliedActionCount = 0
        var feedsToResync: [UUID: Feed] = [:]

        for article in articles {
            guard let feed = article.feed else {
                continue
            }

            let wasVisibleUnreadArticle = !article.isRead && !article.isHidden
            let result = applyPreparedRulesWithNotifications(
                preparedRules,
                to: article,
                feed: feed
            )
            appliedActionCount += result.appliedActionCount

            if wasVisibleUnreadArticle, article.isHidden {
                feedsToResync[feed.id] = feed
            }
        }

        for feed in feedsToResync.values {
            synchronizeUnreadCount(for: feed, articles: articles)
        }

        return appliedActionCount
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
                      !(article.tags ?? []).contains(where: { $0.id == tag.id })
                else {
                    continue
                }

                var tags = article.tags ?? []
                tags.append(tag)
                article.tags = tags
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

    @MainActor
    private static func synchronizeUnreadCount(for feed: Feed, articles: [Article]) {
        let feedID = feed.id
        feed.unreadCount = articles.reduce(0) { count, article in
            guard article.feedID == feedID || article.feed?.id == feedID,
                  !article.isRead,
                  !article.isHidden
            else {
                return count
            }

            return count + 1
        }
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

    private static func preparedSQLiteRules(_ rules: [RuleSnapshot]) -> [PreparedRuleSnapshot] {
        sortedRules(rules).compactMap { rule in
            guard rule.isEnabled else {
                return nil
            }

            let conditions = normalizedConditions(for: rule)
            guard !conditions.isEmpty else {
                return nil
            }

            return PreparedRuleSnapshot(
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

    private static func matches(
        conditions: [NormalizedCondition],
        matchMode: RuleMatchMode,
        article: ArticleRuleSnapshot
    ) -> Bool {
        switch matchMode {
        case .all:
            return conditions.allSatisfy { condition in
                matches(condition: condition, article: article)
            }
        case .any:
            return conditions.contains { condition in
                matches(condition: condition, article: article)
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

    private static func sortedRules(_ rules: [RuleSnapshot]) -> [RuleSnapshot] {
        rules.sorted { firstRule, secondRule in
            if firstRule.sortOrder == secondRule.sortOrder {
                return firstRule.name.localizedCaseInsensitiveCompare(secondRule.name) == .orderedAscending
            }

            return firstRule.sortOrder < secondRule.sortOrder
        }
    }

    private static func normalizedConditions(for rule: Rule) -> [NormalizedCondition] {
        (rule.conditions ?? [])
            .sorted { $0.sortOrder < $1.sortOrder }
            .compactMap { condition in
                normalizedCondition(
                    field: condition.field,
                    conditionOperator: condition.conditionOperator,
                    value: condition.value
                )
            }
    }

    private static func normalizedConditions(for rule: RuleSnapshot) -> [NormalizedCondition] {
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

        let expression = regularExpression(
            for: conditionOperator,
            pattern: trimmedValue
        )
        if conditionOperator == RuleConditionOperator.regex.rawValue,
           expression == nil {
            return nil
        }

        return NormalizedCondition(
            field: field,
            conditionOperator: conditionOperator,
            // Wert einmalig kleinschreiben — er ist statisch zur Laufzeit und
            // wird sonst bei jedem Artikel-Vergleich neu lowercased.
            lowercasedValue: trimmedValue.lowercased(),
            regularExpression: expression
        )
    }

    private static func matches(condition: NormalizedCondition, article: Article, feed: Feed) -> Bool {
        guard let fieldValue = fieldValue(for: condition.field, article: article, feed: feed) else {
            return false
        }

        if condition.conditionOperator == RuleConditionOperator.regex.rawValue {
            guard let regularExpression = condition.regularExpression else {
                return false
            }

            let range = NSRange(location: 0, length: fieldValue.utf16.count)
            return regularExpression.firstMatch(in: fieldValue, range: range) != nil
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

    private static func matches(condition: NormalizedCondition, article: ArticleRuleSnapshot) -> Bool {
        guard let fieldValue = fieldValue(for: condition.field, article: article) else {
            return false
        }

        if condition.conditionOperator == RuleConditionOperator.regex.rawValue {
            guard let regularExpression = condition.regularExpression else {
                return false
            }

            let range = NSRange(location: 0, length: fieldValue.utf16.count)
            return regularExpression.firstMatch(in: fieldValue, range: range) != nil
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

    private static func regularExpression(
        for conditionOperator: String,
        pattern: String
    ) -> NSRegularExpression? {
        guard conditionOperator == RuleConditionOperator.regex.rawValue else {
            return nil
        }

        return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
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

    private static func fieldValue(for field: String, article: ArticleRuleSnapshot) -> String? {
        switch field {
        case RuleConditionField.title.rawValue:
            return article.title
        case RuleConditionField.summary.rawValue:
            return article.summary
        case RuleConditionField.feedTitle.rawValue:
            return article.feedTitle
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

    private static func notificationResult(for rule: RuleSnapshot, article: ArticleRuleSnapshot) -> RuleNotificationResult {
        RuleNotificationResult(
            ruleID: rule.id,
            ruleName: rule.name,
            message: notificationMessage(for: rule, article: article),
            articleTitle: article.title,
            feedTitle: article.feedTitle,
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

    private static func notificationMessage(for rule: RuleSnapshot, article: ArticleRuleSnapshot) -> String {
        let template = rule.notificationTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTemplate = template.isEmpty ? "{Titel}" : template

        return normalizedTemplate
            .replacingOccurrences(of: "{Titel}", with: article.title)
            .replacingOccurrences(of: "{Feed}", with: article.feedTitle)
            .replacingOccurrences(of: "{Regel}", with: rule.name)
    }
}
