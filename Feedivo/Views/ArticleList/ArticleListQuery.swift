import Foundation
import SwiftData

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
}

struct ArticleSearchQuery: Equatable {
    var text: String
    var field: ArticleSearchField
    var scope: ArticleSearchScope
    var filters: ArticleSearchFilters
    var includesHeavyContent: Bool
    var now: Date
    var calendar: Calendar

    init(
        text: String = "",
        field: ArticleSearchField = .all,
        scope: ArticleSearchScope = .currentView,
        filters: ArticleSearchFilters = ArticleSearchFilters(),
        includesHeavyContent: Bool = true,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        self.text = text
        self.field = field
        self.scope = scope
        self.filters = filters
        self.includesHeavyContent = includesHeavyContent
        self.now = now
        self.calendar = calendar
    }

    var normalizedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isActive: Bool {
        !normalizedText.isEmpty || filters.isActive
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
}
