import SwiftUI
import SwiftData

struct ArticleSearchWindowView: View {
    static let windowID = "article-search-window"

    @Query(sort: \Article.publishedAt, order: .reverse)
    private var articles: [Article]
    @Query(sort: \Feed.title)
    private var feeds: [Feed]
    @Query(sort: \Tag.name)
    private var tags: [Tag]

    @State private var searchState = ArticleSearchWindowState()
    @State private var viewModel = ArticleViewModel()

    /// P4: Debounced Suchtext — das TextField bleibt an `searchState.searchText`
    /// gebunden (so tippt der Nutzer flüssig), aber Filterung/Sortierung laufen
    /// erst nach einer kurzen Typ-Pause (250 ms) über den committeten Text statt
    /// bei jedem Tastendruck über alle Artikel. Picker (Feed/Tag/Datum/Status)
    /// ändern `searchState` direkt und bleiben sofort wirksam.
    @State private var debouncedSearchText: String = ""

    /// Such-State mit committetem (debounced) Text — die Filter-Picker kommen
    /// weiter live aus `searchState`, nur der Text ist debounced.
    private var committedState: ArticleSearchWindowState {
        var state = searchState
        state.searchText = debouncedSearchText
        return state
    }

    private var filteredArticles: [Article] {
        committedState.filteredArticles(from: articles)
    }

    var body: some View {
        VStack(spacing: 0) {
            searchHeader

            Divider()

            if filteredArticles.isEmpty {
                emptyState
            } else {
                resultList
            }
        }
        .frame(minWidth: 620, minHeight: 460)
        // P4: Debounce des Suchtextes. `.task(id:)` bricht die vorherige Aufgabe
        // ab, sobald sich der Text ändert — committet nur nach 250 ms ohne
        // weiteren Tastendruck. Leeres Feld wird sofort committet (kein Lag beim
        // Löschen/Freimachen).
        .task(id: searchState.searchText) {
            if searchState.searchText.isEmpty {
                debouncedSearchText = ""
                return
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
            if !Task.isCancelled {
                debouncedSearchText = searchState.searchText
            }
        }
    }

    private var searchHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.blue)
                    .frame(width: 34, height: 34)
                    .background(.blue.opacity(0.13), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.articleSearchCommand)
                        .font(.headline)

                    Text(L10n.articleSearchWindowDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Text(L10n.articleSearchMatchCount(filteredArticles.count))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.blue.opacity(0.13), in: Capsule())
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField(L10n.articleSearchPlaceholder, text: $searchState.searchText)
                    .textFieldStyle(.plain)

                if !searchState.searchText.isEmpty || searchState.query.filters.isActive {
                    Button {
                        clearSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help(L10n.articleSearchClear)
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(.background, in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(.separator.opacity(0.5), lineWidth: 1)
            }

            HStack(spacing: 8) {
                searchFieldPicker
                searchFeedPicker
                searchTagPicker
                searchDatePicker
                searchStatusPicker
                Spacer(minLength: 0)
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background(Color.blue.opacity(0.08))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var searchFieldPicker: some View {
        Picker("", selection: $searchState.field) {
            ForEach(ArticleSearchField.allCases) { field in
                Text(label(for: field)).tag(field)
            }
        }
        .labelsHidden()
        .frame(width: 130)
    }

    private var searchFeedPicker: some View {
        Picker("", selection: $searchState.feedID) {
            Text(L10n.articleSearchFeedAll).tag(UUID?.none)

            ForEach(feeds) { feed in
                Text(feed.title).tag(Optional(feed.id))
            }
        }
        .labelsHidden()
        .frame(width: 150)
    }

    private var searchTagPicker: some View {
        Picker("", selection: $searchState.tagID) {
            Text(L10n.articleSearchTagAll).tag(UUID?.none)

            ForEach(tags) { tag in
                Text(tag.name).tag(Optional(tag.id))
            }
        }
        .labelsHidden()
        .frame(width: 136)
    }

    private var searchDatePicker: some View {
        Picker("", selection: $searchState.dateFilter) {
            ForEach(ArticleSearchDateFilter.allCases) { dateFilter in
                Text(label(for: dateFilter)).tag(dateFilter)
            }
        }
        .labelsHidden()
        .frame(width: 118)
    }

    private var searchStatusPicker: some View {
        Picker("", selection: $searchState.statusFilter) {
            ForEach(ArticleSearchStatusFilter.allCases) { statusFilter in
                Text(label(for: statusFilter)).tag(statusFilter)
            }
        }
        .labelsHidden()
        .frame(width: 122)
    }

    private var resultList: some View {
        List(filteredArticles) { article in
            ArticleSearchResultRow(article: article) {
                _ = viewModel.openOriginal(article)
            }
        }
        .listStyle(.inset)
    }

    private var emptyState: some View {
        Group {
            if committedState.query.normalizedText.isEmpty {
                ContentUnavailableView(
                    L10n.articleSearchNoResultsTitle,
                    systemImage: "magnifyingglass",
                    description: Text(L10n.articleListEmptyDescription)
                )
            } else {
                ContentUnavailableView(
                    L10n.articleSearchNoResultsTitle,
                    systemImage: "magnifyingglass",
                    description: Text(L10n.articleSearchNoResultsDescription(committedState.query.normalizedText))
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func clearSearch() {
        searchState = ArticleSearchWindowState()
        // P4: debounced Text sofort zurücksetzen, damit Treffer/Leer-Zustand ohne
        // 250 ms Lag folgen.
        debouncedSearchText = ""
    }

    private func label(for field: ArticleSearchField) -> String {
        switch field {
        case .all:
            return L10n.articleSearchFieldAll
        case .title:
            return L10n.articleSearchFieldTitle
        case .summary:
            return L10n.articleSearchFieldSummary
        case .content:
            return L10n.articleSearchFieldContent
        }
    }

    private func label(for dateFilter: ArticleSearchDateFilter) -> String {
        switch dateFilter {
        case .anytime:
            return L10n.articleSearchDateAnytime
        case .today:
            return L10n.articleSearchDateToday
        case .thisWeek:
            return L10n.articleSearchDateThisWeek
        }
    }

    private func label(for statusFilter: ArticleSearchStatusFilter) -> String {
        switch statusFilter {
        case .all:
            return L10n.articleSearchStatusAll
        case .unread:
            return L10n.articleSearchStatusUnread
        case .read:
            return L10n.articleSearchStatusRead
        case .starred:
            return L10n.articleSearchStatusStarred
        case .archived:
            return L10n.articleSearchStatusArchived
        }
    }
}

private struct ArticleSearchResultRow: View {
    let article: Article
    let onOpenOriginal: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(article.title)
                    .font(.headline)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(article.feed?.title ?? "")
                    Text("·")
                    Text(formattedDate)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let summary = article.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 12)

            Button {
                onOpenOriginal()
            } label: {
                Image(systemName: "safari")
            }
            .buttonStyle(.borderless)
            .help(L10n.articleOpenOriginalCommand)
        }
        .padding(.vertical, 6)
    }

    private var formattedDate: String {
        guard let publishedAt = article.publishedAt else {
            return "Unbekannt"
        }

        return publishedAt.formatted(date: .abbreviated, time: .omitted)
    }
}
