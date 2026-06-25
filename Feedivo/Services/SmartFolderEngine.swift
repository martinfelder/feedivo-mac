import Foundation

enum SmartFolderEngine {
    static func matches(
        folder: SmartFolder,
        article: Article,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        SmartFolderPreparedMatcher(folder: folder).matches(
            article,
            now: now,
            calendar: calendar
        )
    }

    static func matchingArticles(
        folder: SmartFolder,
        articles: [Article],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Article] {
        SmartFolderPreparedMatcher(folder: folder).matchingArticles(
            articles,
            now: now,
            calendar: calendar
        )
    }

    static func matchingArticleCount(
        folder: SmartFolder,
        articles: [Article],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        SmartFolderPreparedMatcher(folder: folder).matchingArticleCount(
            articles,
            now: now,
            calendar: calendar
        )
    }

    fileprivate static func sortedConditions(for folder: SmartFolder) -> [SmartFolderCondition] {
        folder.conditions.sorted { firstCondition, secondCondition in
            firstCondition.sortOrder < secondCondition.sortOrder
        }
    }

    fileprivate static func matches(
        condition: SmartFolderCondition,
        article: Article,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        guard let field = SmartFolderConditionField(rawValue: condition.fieldRaw),
              let conditionOperator = SmartFolderConditionOperator(rawValue: condition.operatorRaw)
        else {
            return false
        }

        switch field {
        case .tag:
            let hasTag = article.tags.contains { tag in
                tag.id.uuidString == condition.value
                    || tag.name.localizedCaseInsensitiveCompare(condition.value) == .orderedSame
            }
            return boolMatch(hasTag, operator: conditionOperator)
        case .feed:
            let feedID = article.feedID?.uuidString
            let feedTitle = article.feed?.title
            let matchesFeed = feedID == condition.value
                || feedTitle?.localizedCaseInsensitiveCompare(condition.value) == .orderedSame
            return boolMatch(matchesFeed, operator: conditionOperator)
        case .feedFolder:
            return stringMatch(article.feed?.folderName, operator: conditionOperator, value: condition.value)
        case .date:
            return dateMatch(article.publishedAt, operator: conditionOperator, value: condition.value, now: now, calendar: calendar)
        case .status:
            return statusMatch(article, operator: conditionOperator, value: condition.value)
        case .title:
            return stringMatch(article.title, operator: conditionOperator, value: condition.value)
        case .text:
            return stringMatch(articleSearchText(article), operator: conditionOperator, value: condition.value)
        case .author:
            return stringMatch(article.author, operator: conditionOperator, value: condition.value)
        }
    }

    private static func boolMatch(_ value: Bool, operator conditionOperator: SmartFolderConditionOperator) -> Bool {
        switch conditionOperator {
        case .is, .contains:
            return value
        case .isNot:
            return !value
        case .olderThanDays:
            return false
        }
    }

    private static func stringMatch(
        _ fieldValue: String?,
        operator conditionOperator: SmartFolderConditionOperator,
        value: String
    ) -> Bool {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty,
              let fieldValue,
              !fieldValue.isEmpty
        else {
            return false
        }

        switch conditionOperator {
        case .is:
            return fieldValue.localizedCaseInsensitiveCompare(trimmedValue) == .orderedSame
        case .isNot:
            return fieldValue.localizedCaseInsensitiveCompare(trimmedValue) != .orderedSame
        case .contains:
            return fieldValue.localizedCaseInsensitiveContains(trimmedValue)
        case .olderThanDays:
            return false
        }
    }

    private static func dateMatch(
        _ publishedAt: Date?,
        operator conditionOperator: SmartFolderConditionOperator,
        value: String,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        guard let publishedAt else {
            return false
        }

        switch conditionOperator {
        case .is:
            guard let dateValue = SmartFolderDateValue(rawValue: value) else {
                return false
            }

            switch dateValue {
            case .today:
                return calendar.isDate(publishedAt, inSameDayAs: now)
            case .thisWeek:
                return calendar.isDate(publishedAt, equalTo: now, toGranularity: .weekOfYear)
            }
        case .isNot:
            guard let dateValue = SmartFolderDateValue(rawValue: value) else {
                return false
            }

            switch dateValue {
            case .today:
                return !calendar.isDate(publishedAt, inSameDayAs: now)
            case .thisWeek:
                return !calendar.isDate(publishedAt, equalTo: now, toGranularity: .weekOfYear)
            }
        case .olderThanDays:
            guard let days = Int(value),
                  let threshold = calendar.date(byAdding: .day, value: -days, to: now)
            else {
                return false
            }

            return publishedAt < threshold
        case .contains:
            return false
        }
    }

    private static func statusMatch(
        _ article: Article,
        operator conditionOperator: SmartFolderConditionOperator,
        value: String
    ) -> Bool {
        guard let statusValue = SmartFolderStatusValue(rawValue: value) else {
            return false
        }

        let matchesStatus: Bool
        switch statusValue {
        case .unread:
            matchesStatus = !article.isRead
        case .read:
            matchesStatus = article.isRead
        case .starred:
            matchesStatus = article.isStarred
        case .archived:
            matchesStatus = article.isArchived
        case .hidden:
            matchesStatus = article.isHidden
        }

        return boolMatch(matchesStatus, operator: conditionOperator)
    }

    private static func articleSearchText(_ article: Article) -> String {
        [
            article.title,
            article.summary,
            article.content,
            article.offlineContent
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }
}

struct SmartFolderPreparedMatcher {
    let conditions: [SmartFolderCondition]
    private let matchMode: RuleMatchMode

    init(folder: SmartFolder) {
        self.conditions = SmartFolderEngine.sortedConditions(for: folder)
        self.matchMode = RuleMatchMode.normalized(folder.matchModeRaw)
    }

    func matchingArticles(
        _ articles: [Article],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Article] {
        articles.filter { article in
            matches(article, now: now, calendar: calendar)
        }
    }

    func matchingArticleCount(
        _ articles: [Article],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        articles.reduce(0) { count, article in
            matches(article, now: now, calendar: calendar) ? count + 1 : count
        }
    }

    func matches(
        _ article: Article,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard !conditions.isEmpty else {
            return true
        }

        let matchesCondition: (SmartFolderCondition) -> Bool = { condition in
            SmartFolderEngine.matches(
                condition: condition,
                article: article,
                now: now,
                calendar: calendar
            )
        }

        switch matchMode {
        case .all:
            return conditions.allSatisfy(matchesCondition)
        case .any:
            return conditions.contains(where: matchesCondition)
        }
    }
}
