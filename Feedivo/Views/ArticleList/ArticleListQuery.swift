import Foundation
import SwiftData

enum ArticleListQuery {
    static let sortDescriptors = [
        SortDescriptor<Article>(\.publishedAt, order: .reverse)
    ]

    static let listPropertiesToFetch = Article.lightPropertiesToFetch

    static func allFetchDescriptor() -> FetchDescriptor<Article> {
        listFetchDescriptor()
    }

    static func feedPredicate(for feed: Feed) -> Predicate<Article> {
        let feedID = feed.id
        return #Predicate<Article> { article in
            article.feedID == feedID
        }
    }

    static func feedFetchDescriptor(for feed: Feed) -> FetchDescriptor<Article> {
        listFetchDescriptor(predicate: feedPredicate(for: feed))
    }

    // Kein Default für `taggedFeeds`: ohne die Feed-Liste matcht der Predicate
    // nur Artikel mit direkter Tag-Zuweisung, nicht aber Artikel, deren Feed
    // getaggt ist — das wäre ein stiller Fehler. Aufrufer müssen die Feeds
    // explizit übergeben (i.d.R. `tag.feeds`).
    static func tagPredicate(for tag: Tag, taggedFeeds: [Feed]) -> Predicate<Article> {
        let tagID = tag.id
        let feedIDs = taggedFeeds.map(\.id)
        return #Predicate<Article> { article in
            (article.tags?.contains { articleTag in
                articleTag.id == tagID
            } ?? false) || (article.feedID.flatMap { feedID in
                feedIDs.contains(feedID)
            } ?? false)
        }
    }

    static func tagFetchDescriptor(for tag: Tag) -> FetchDescriptor<Article> {
        listFetchDescriptor(predicate: tagPredicate(for: tag, taggedFeeds: tag.feeds ?? []))
    }

    static func smartFilterFetchDescriptor(for smartFilter: SmartFilter) -> FetchDescriptor<Article> {
        switch smartFilter {
        case .allArticles:
            return listFetchDescriptor()
        case .unread:
            return listFetchDescriptor(
                predicate: #Predicate<Article> { article in
                    !article.isRead
                }
            )
        case .starred:
            return listFetchDescriptor(
                predicate: #Predicate<Article> { article in
                    article.isStarred
                }
            )
        case .today:
            // Datum-Filter bleibt in-memory: SwiftData unterstützt hier keinen
            // stabilen optionalen Date-Vergleich. Der Fetch bleibt trotzdem leicht.
            return listFetchDescriptor()
        case .hidden:
            return listFetchDescriptor(
                predicate: #Predicate<Article> { article in
                    article.isHidden
                }
            )
        }
    }

    static func smartFolderFetchDescriptor(
        for folder: SmartFolder,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> FetchDescriptor<Article>? {
        guard let queryKind = SmartFolderOptimizedQueryKind(folder: folder) else {
            return nil
        }

        switch queryKind {
        case .all:
            return listFetchDescriptor()
        case .unread:
            // Ungelesen lädt wie ein Feed alle Artikel. Die Anzeigeebene blendet
            // gelesene Artikel aus und hält gerade geöffnete Artikel sichtbar.
            return listFetchDescriptor()
        case .read:
            return listFetchDescriptor(
                predicate: #Predicate<Article> { article in
                    article.isRead
                }
            )
        case .starred:
            return listFetchDescriptor(
                predicate: #Predicate<Article> { article in
                    article.isStarred
                }
            )
        case .archived:
            return listFetchDescriptor(
                predicate: #Predicate<Article> { article in
                    article.isArchived
                }
            )
        case .hidden:
            return listFetchDescriptor(
                predicate: #Predicate<Article> { article in
                    article.isHidden
                }
            )
        case .saved:
            return listFetchDescriptor(
                predicate: #Predicate<Article> { article in
                    article.isStarred || article.isArchived
                }
            )
        case .today, .thisWeek:
            // Kein optimierter Predicate: SwiftData unterstützt keinen Force-Unwrap
            // von `publishedAt!` (Runtime-Fault), und `Date? >= Date` kompiliert
            // nicht. Datum-Filter wird in-memory via SmartFolderEngine gelöst
            // (Fallback-Pfad in SmartFolderArticleListContent).
            return nil
        }
    }

    private static func listFetchDescriptor(
        predicate: Predicate<Article>? = nil
    ) -> FetchDescriptor<Article> {
        var descriptor = FetchDescriptor(
            predicate: predicate,
            sortBy: sortDescriptors
        )
        descriptor.propertiesToFetch = listPropertiesToFetch
        return descriptor
    }
}

private enum SmartFolderOptimizedQueryKind {
    case all
    case unread
    case read
    case starred
    case archived
    case hidden
    case saved
    case today
    case thisWeek

    init?(folder: SmartFolder) {
        let conditions = (folder.conditions ?? []).sorted { firstCondition, secondCondition in
            firstCondition.sortOrder < secondCondition.sortOrder
        }

        guard !conditions.isEmpty else {
            self = .all
            return
        }

        if let singleCondition = conditions.first,
           conditions.count == 1,
           let queryKind = Self.singleConditionKind(singleCondition) {
            self = queryKind
            return
        }

        if RuleMatchMode.normalized(folder.matchModeRaw) == .any,
           conditions.count == 2,
           conditions.allSatisfy({ condition in
               condition.fieldRaw == SmartFolderConditionField.status.rawValue
                   && condition.operatorRaw == SmartFolderConditionOperator.is.rawValue
           }) {
            let values = Set(conditions.map(\.value))
            if values == Set([
                SmartFolderStatusValue.starred.rawValue,
                SmartFolderStatusValue.archived.rawValue
            ]) {
                self = .saved
                return
            }
        }

        return nil
    }

    private static func singleConditionKind(_ condition: SmartFolderCondition) -> Self? {
        guard condition.operatorRaw == SmartFolderConditionOperator.is.rawValue else {
            return nil
        }

        if condition.fieldRaw == SmartFolderConditionField.status.rawValue,
           let statusValue = SmartFolderStatusValue(rawValue: condition.value) {
            switch statusValue {
            case .unread:
                return .unread
            case .read:
                return .read
            case .starred:
                return .starred
            case .archived:
                return .archived
            case .hidden:
                return .hidden
            }
        }

        if condition.fieldRaw == SmartFolderConditionField.date.rawValue,
           let dateValue = SmartFolderDateValue(rawValue: condition.value) {
            switch dateValue {
            case .today:
                return .today
            case .thisWeek:
                return .thisWeek
            }
        }

        return nil
    }
}

struct ArticleListDisplayState {
    let articles: [Article]
    let showsReadArticles: Bool
    let selectedArticle: Article?
    let showsHiddenArticles: Bool
    let temporarilyVisibleReadArticleIDs: Set<PersistentIdentifier>

    init(
        articles: [Article],
        showsReadArticles: Bool,
        selectedArticle: Article? = nil,
        showsHiddenArticles: Bool = false,
        temporarilyVisibleReadArticleIDs: Set<PersistentIdentifier> = []
    ) {
        self.articles = articles
        self.showsReadArticles = showsReadArticles
        self.selectedArticle = selectedArticle
        self.showsHiddenArticles = showsHiddenArticles
        self.temporarilyVisibleReadArticleIDs = temporarilyVisibleReadArticleIDs
    }

    var visibleArticles: [Article] {
        snapshot.visibleArticles
    }

    var hiddenReadArticleCount: Int {
        snapshot.hiddenReadArticleCount
    }

    var shouldShowReadArticlesButton: Bool {
        snapshot.shouldShowReadArticlesButton
    }

    var snapshot: ArticleListDisplaySnapshot {
        var visibleArticles: [Article] = []
        var hiddenReadArticleCount = 0

        for article in articles {
            guard showsHiddenArticles || !article.isHidden else {
                continue
            }

            if showsReadArticles || !article.isRead || isSelected(article) || isTemporarilyVisibleReadArticle(article) {
                visibleArticles.append(article)
            } else {
                hiddenReadArticleCount += 1
            }
        }

        return ArticleListDisplaySnapshot(
            visibleArticles: visibleArticles,
            hiddenReadArticleCount: hiddenReadArticleCount
        )
    }

    private func isSelected(_ article: Article) -> Bool {
        selectedArticle?.persistentModelID == article.persistentModelID
    }

    private func isTemporarilyVisibleReadArticle(_ article: Article) -> Bool {
        article.isRead && temporarilyVisibleReadArticleIDs.contains(article.persistentModelID)
    }
}

struct ArticleListDisplaySnapshot {
    let visibleArticles: [Article]
    let hiddenReadArticleCount: Int

    var shouldShowReadArticlesButton: Bool {
        hiddenReadArticleCount > 0
    }
}

enum ArticleSearchField: String, CaseIterable, Identifiable {
    case all
    case title
    case summary
    case content

    var id: String {
        rawValue
    }

    static func resolved(from rawValue: String) -> ArticleSearchField {
        ArticleSearchField(rawValue: rawValue) ?? .all
    }
}

enum ArticleSearchScope: String, CaseIterable, Identifiable {
    case currentView
    case allArticles

    var id: String {
        rawValue
    }

    static func resolved(from rawValue: String) -> ArticleSearchScope {
        ArticleSearchScope(rawValue: rawValue) ?? .currentView
    }
}

enum ArticleSearchDateFilter: String, CaseIterable, Identifiable {
    case anytime
    case today
    case thisWeek

    var id: String {
        rawValue
    }
}

enum ArticleSearchStatusFilter: String, CaseIterable, Identifiable {
    case all
    case unread
    case read
    case starred
    case archived

    var id: String {
        rawValue
    }
}

struct ArticleSearchFilters: Equatable {
    var feedID: UUID?
    var tagID: UUID?
    var date: ArticleSearchDateFilter
    var status: ArticleSearchStatusFilter

    init(
        feedID: UUID? = nil,
        tagID: UUID? = nil,
        date: ArticleSearchDateFilter = .anytime,
        status: ArticleSearchStatusFilter = .all
    ) {
        self.feedID = feedID
        self.tagID = tagID
        self.date = date
        self.status = status
    }

    var isActive: Bool {
        feedID != nil || tagID != nil || date != .anytime || status != .all
    }

    func includes(
        _ article: Article,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        matchesFeed(article)
            && matchesTag(article)
            && matchesDate(article, now: now, calendar: calendar)
            && matchesStatus(article)
    }

    private func matchesFeed(_ article: Article) -> Bool {
        guard let feedID else {
            return true
        }

        return article.feedID == feedID || article.feed?.id == feedID
    }

    private func matchesTag(_ article: Article) -> Bool {
        guard let tagID else {
            return true
        }

        if (article.tags ?? []).contains(where: { $0.id == tagID }) {
            return true
        }

        return article.feed?.tags?.contains(where: { $0.id == tagID }) ?? false
    }

    private func matchesDate(
        _ article: Article,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        guard date != .anytime else {
            return true
        }

        guard let publishedAt = article.publishedAt else {
            return false
        }

        switch date {
        case .anytime:
            return true
        case .today:
            return calendar.isDate(publishedAt, inSameDayAs: now)
        case .thisWeek:
            return calendar.isDate(
                publishedAt,
                equalTo: now,
                toGranularity: .weekOfYear
            )
        }
    }

    private func matchesStatus(_ article: Article) -> Bool {
        switch status {
        case .all:
            return true
        case .unread:
            return !article.isRead
        case .read:
            return article.isRead
        case .starred:
            return article.isStarred
        case .archived:
            return article.isArchived
        }
    }
}

struct ArticleSearchQuery: Equatable {
    var text: String
    var field: ArticleSearchField
    var scope: ArticleSearchScope
    var filters: ArticleSearchFilters
    var now: Date
    var calendar: Calendar

    init(
        text: String = "",
        field: ArticleSearchField = .all,
        scope: ArticleSearchScope = .currentView,
        filters: ArticleSearchFilters = ArticleSearchFilters(),
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        self.text = text
        self.field = field
        self.scope = scope
        self.filters = filters
        self.now = now
        self.calendar = calendar
    }

    var normalizedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isActive: Bool {
        !normalizedText.isEmpty || filters.isActive
    }

    func includes(_ article: Article) -> Bool {
        guard isActive else {
            return true
        }

        guard textIncludes(article) else {
            return false
        }

        return filters.includes(article, now: now, calendar: calendar)
    }

    func filtered(_ articles: [Article]) -> [Article] {
        guard isActive else {
            return articles
        }

        return articles.filter { article in
            includes(article)
        }
    }

    private func textIncludes(_ article: Article) -> Bool {
        guard !normalizedText.isEmpty else {
            return true
        }

        let needle = normalizedText
        switch field {
        case .all:
            return contains(needle, in: article.title)
                || contains(needle, in: article.summary)
                || contains(needle, in: article.content)
                || contains(needle, in: article.offlineContent)
        case .title:
            return contains(needle, in: article.title)
        case .summary:
            return contains(needle, in: article.summary)
        case .content:
            return contains(needle, in: article.content)
                || contains(needle, in: article.offlineContent)
        }
    }

    private func contains(_ needle: String, in haystack: String?) -> Bool {
        guard let haystack else {
            return false
        }

        return haystack.range(
            of: needle,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) != nil
    }
}

struct ArticleSearchWindowState: Equatable {
    var searchText: String
    var field: ArticleSearchField
    var feedID: UUID?
    var tagID: UUID?
    var dateFilter: ArticleSearchDateFilter
    var statusFilter: ArticleSearchStatusFilter
    var now: Date
    var calendar: Calendar

    init(
        searchText: String = "",
        field: ArticleSearchField = .all,
        feedID: UUID? = nil,
        tagID: UUID? = nil,
        dateFilter: ArticleSearchDateFilter = .anytime,
        statusFilter: ArticleSearchStatusFilter = .all,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        self.searchText = searchText
        self.field = field
        self.feedID = feedID
        self.tagID = tagID
        self.dateFilter = dateFilter
        self.statusFilter = statusFilter
        self.now = now
        self.calendar = calendar
    }

    var query: ArticleSearchQuery {
        ArticleSearchQuery(
            text: searchText,
            field: field,
            scope: .allArticles,
            filters: ArticleSearchFilters(
                feedID: feedID,
                tagID: tagID,
                date: dateFilter,
                status: statusFilter
            ),
            now: now,
            calendar: calendar
        )
    }

    func filteredArticles(from articles: [Article]) -> [Article] {
        ArticleSortOption.newestFirst.sorted(query.filtered(articles))
    }
}

struct ArticleListPreparedArticles {
    let sorted: [Article]
    let filtered: [Article]

    static func prepare(
        articles: [Article],
        sortArticles: Bool,
        filterOption: ArticleFilterOption,
        searchQuery: ArticleSearchQuery = ArticleSearchQuery(),
        sorter: ([Article]) -> [Article]
    ) -> ArticleListPreparedArticles {
        let sortedArticles = sortArticles ? sorter(articles) : articles
        let filteredArticles = searchQuery.filtered(filterOption.filtered(sortedArticles))
        return ArticleListPreparedArticles(
            sorted: sortedArticles,
            filtered: filteredArticles
        )
    }
}
