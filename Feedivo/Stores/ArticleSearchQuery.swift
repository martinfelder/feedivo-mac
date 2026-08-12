import Foundation

enum ArticleSearchField: String, CaseIterable, Identifiable {
    case all
    case title
    case summary
    case content

    var id: String {
        rawValue
    }
}

enum ArticleSearchScope: String, CaseIterable, Identifiable {
    case currentView
    case allArticles

    var id: String {
        rawValue
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

enum ArticleSearchTagMatchMode: String, CaseIterable, Identifiable {
    case any
    case all

    var id: String {
        rawValue
    }
}

struct ArticleSearchFilters: Equatable {
    var feedID: UUID?
    var tagIDs: Set<UUID>
    var date: ArticleSearchDateFilter
    var status: ArticleSearchStatusFilter

    init(
        feedID: UUID? = nil,
        tagIDs: Set<UUID> = [],
        date: ArticleSearchDateFilter = .anytime,
        status: ArticleSearchStatusFilter = .all
    ) {
        self.feedID = feedID
        self.tagIDs = tagIDs
        self.date = date
        self.status = status
    }

    var isActive: Bool {
        feedID != nil || !tagIDs.isEmpty || date != .anytime || status != .all
    }
}

struct ArticleSearchQuery: Equatable {
    var text: String
    var filters: ArticleSearchFilters

    init(
        text: String = "",
        filters: ArticleSearchFilters = ArticleSearchFilters()
    ) {
        self.text = text
        self.filters = filters
    }

    var normalizedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct ArticleSearchWindowState: Equatable {
    var searchText: String
    var field: ArticleSearchField
    var feedID: UUID?
    var tagIDs: Set<UUID>
    var tagMatchMode: ArticleSearchTagMatchMode
    var dateFilter: ArticleSearchDateFilter
    var statusFilter: ArticleSearchStatusFilter
    var now: Date
    var calendar: Calendar

    init(
        searchText: String = "",
        field: ArticleSearchField = .all,
        feedID: UUID? = nil,
        tagIDs: Set<UUID> = [],
        tagMatchMode: ArticleSearchTagMatchMode = .any,
        dateFilter: ArticleSearchDateFilter = .anytime,
        statusFilter: ArticleSearchStatusFilter = .all,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        self.searchText = searchText
        self.field = field
        self.feedID = feedID
        self.tagIDs = tagIDs
        self.tagMatchMode = tagMatchMode
        self.dateFilter = dateFilter
        self.statusFilter = statusFilter
        self.now = now
        self.calendar = calendar
    }

    var query: ArticleSearchQuery {
        ArticleSearchQuery(
            text: searchText,
            filters: ArticleSearchFilters(
                feedID: feedID,
                tagIDs: tagIDs,
                date: dateFilter,
                status: statusFilter
            )
        )
    }
}
