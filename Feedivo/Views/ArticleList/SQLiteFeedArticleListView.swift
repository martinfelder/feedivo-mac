import AppKit
import GRDB
import SwiftData
import SwiftUI

struct SQLiteFeedArticleListView: View {
    @Environment(\.feedivoDatabase) private var database
    @AppStorage(SidebarBadgeInvalidation.directTagVersionKey)
    private var directTagVersion = 0
    @AppStorage(SQLiteDataInvalidation.statusVersionKey)
    private var sqliteStatusVersion = 0

    private enum Scope {
        case feed(feedID: String, title: String)
        case tagID(String)
        case smartFilter(SmartFilter)
        case smartFolder(SQLiteSmartFolderSnapshot)
    }

    private let scope: Scope
    @Binding var selectedArticleID: String?
    @Binding var navigationState: SQLiteArticleNavigationState

    @State private var state = SQLiteFeedArticleListState()
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var offlineDownloadService = SQLiteOfflineDownloadService()
    @State private var articleExportRequest: ArticleExportRequest?
    @State private var ruleCreationRequest: ArticleListRuleCreationRequest?
    @State private var showsReadArticles = false

    @AppStorage(ArticleSortOption.storageKey)
    private var articleSortRawValue = ArticleSortOption.newestFirst.rawValue

    @AppStorage(ArticleFilterOption.storageKey)
    private var articleFilterRawValue = ArticleFilterOption.all.rawValue

    init(
        feed: Feed,
        selectedArticleID: Binding<String?>,
        navigationState: Binding<SQLiteArticleNavigationState>
    ) {
        self.scope = .feed(feedID: feed.id.uuidString, title: feed.title)
        self._selectedArticleID = selectedArticleID
        self._navigationState = navigationState
    }

    init(
        feedID: String,
        title: String,
        selectedArticleID: Binding<String?>,
        navigationState: Binding<SQLiteArticleNavigationState>
    ) {
        self.scope = .feed(feedID: feedID, title: title)
        self._selectedArticleID = selectedArticleID
        self._navigationState = navigationState
    }

    init(
        tag: Tag,
        selectedArticleID: Binding<String?>,
        navigationState: Binding<SQLiteArticleNavigationState>
    ) {
        self.scope = .tagID(tag.id.uuidString)
        self._selectedArticleID = selectedArticleID
        self._navigationState = navigationState
    }

    init(
        tagID: String,
        selectedArticleID: Binding<String?>,
        navigationState: Binding<SQLiteArticleNavigationState>
    ) {
        self.scope = .tagID(tagID)
        self._selectedArticleID = selectedArticleID
        self._navigationState = navigationState
    }

    init(
        smartFilter: SmartFilter,
        selectedArticleID: Binding<String?>,
        navigationState: Binding<SQLiteArticleNavigationState>
    ) {
        self.scope = .smartFilter(smartFilter)
        self._selectedArticleID = selectedArticleID
        self._navigationState = navigationState
    }

    init(
        smartFolder: SmartFolder,
        selectedArticleID: Binding<String?>,
        navigationState: Binding<SQLiteArticleNavigationState>
    ) {
        self.scope = .smartFolder(SQLiteSmartFolderSnapshot(folder: smartFolder))
        self._selectedArticleID = selectedArticleID
        self._navigationState = navigationState
    }

    init(
        smartFolder: SQLiteSmartFolderSnapshot,
        selectedArticleID: Binding<String?>,
        navigationState: Binding<SQLiteArticleNavigationState>
    ) {
        self.scope = .smartFolder(smartFolder)
        self._selectedArticleID = selectedArticleID
        self._navigationState = navigationState
    }

    var body: some View {
        VStack(spacing: 0) {
            articleSearchBar
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.bar)

            articleContent
        }
        .task(id: searchText) {
            await updateDebouncedSearchText()
        }
        .task(id: loadToken) {
            reload()
        }
        .onChange(of: selectedArticleID) {
            reload()
        }
        .onChange(of: state.navigationState) {
            navigationState = state.navigationState
        }
        .sheet(item: $articleExportRequest) { request in
            ArticleExportSheet(request: request) {
                articleExportRequest = nil
            }
        }
        .sheet(item: $ruleCreationRequest) { request in
            RuleWizardView(
                existingRules: sqliteRulesForRuleCreation(),
                seed: request.seed
            )
        }
        .toolbar {
            ToolbarItemGroup {
                markReadMenu(visibleRows: visibleRows)
                filterMenu
                sortMenu
            }
        }
        .navigationTitle(navigationTitle)
    }

    @ViewBuilder
    private var articleContent: some View {
        Group {
            switch state.loadState {
            case .missingSQLiteDatabase:
                ContentUnavailableView(
                    "SQLite nicht verfügbar",
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text("Die lokale Artikeldatenbank konnte nicht geöffnet werden.")
                )
            case .missingFeed:
                ContentUnavailableView(
                    "Feed noch nicht in SQLite",
                    systemImage: "tray",
                    description: Text("Dieser Feed ist noch nicht in der lokalen Artikeldatenbank vorhanden.")
                )
            case .failed(let message):
                ContentUnavailableView(
                    "Artikel konnten nicht geladen werden",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
            case .idle where state.rows.isEmpty:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded where state.rows.isEmpty:
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: emptySystemImage,
                    description: Text(emptyDescription)
                )
            case .idle, .loaded:
                articleList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var articleList: some View {
        List(selection: $selectedArticleID) {
            if filteredRows.isEmpty {
                articleListEmptyState(isSearching: isSearching)
            } else {
                ForEach(visibleRows) { row in
                    articleRow(row, visibleRows: visibleRows)
                        .tag(row.id)
                }

                if shouldShowReadArticlesButton {
                    showReadArticlesButton(count: hiddenReadRowCount)
                }
            }
        }
    }

    private var filteredRows: [ArticleListSnapshot] {
        state.rows
            .filter(articleFilterIncludes)
            .sorted(by: sortRows)
    }

    private var visibleRows: [ArticleListSnapshot] {
        guard !showsReadArticles else {
            return filteredRows
        }

        return filteredRows.filter { row in
            !row.isRead || row.id == selectedArticleID
        }
    }

    private var hiddenReadRowCount: Int {
        filteredRows.filter(\.isRead).count
    }

    private var shouldShowReadArticlesButton: Bool {
        !showsReadArticles && hiddenReadRowCount > 0
    }

    private func articleRow(
        _ row: ArticleListSnapshot,
        visibleRows: [ArticleListSnapshot]
    ) -> ArticleRowView {
        ArticleRowView(
            snapshot: ArticleListItemSnapshot(sqliteSnapshot: row),
            hasAvailableTags: false,
            onToggleRead: {
                toggleRead(row.id)
            },
            onToggleStarred: {
                toggleStarred(row.id)
            },
            onToggleArchived: {
                toggleArchived(row.id)
            },
            onRequestAssignTag: {},
            onCreateRule: {
                requestRuleCreation(from: row)
            },
            onCopyLink: {
                copyLink(row)
            },
            onOpenOriginal: {
                openOriginal(row)
            },
            onShareOriginal: {
                shareOriginal(row)
            },
            onOpenInWindow: {},
            onExport: {
                requestExportArticle(row.id)
            },
            onSaveOrRemoveOffline: {
                Task {
                    await saveOrRemoveOffline(row)
                }
            },
            onDelete: {
                deleteArticle(row.id)
            },
            onMarkAllRead: {
                markRowsRead(visibleRows)
            }
        )
    }

    private func articleListEmptyState(isSearching: Bool) -> some View {
        if isSearching {
            ContentUnavailableView(
                L10n.articleSearchNoResultsTitle,
                systemImage: "magnifyingglass",
                description: Text(L10n.articleSearchNoResultsDescription(debouncedSearchText))
            )
        } else {
            ContentUnavailableView(
                L10n.articleListEmptyTitle,
                systemImage: "doc.text.magnifyingglass",
                description: Text(L10n.articleListEmptyDescription)
            )
        }
    }

    private func showReadArticlesButton(count: Int) -> some View {
        HStack {
            Spacer()

            Button {
                showsReadArticles = true
            } label: {
                Label(
                    String.localizedStringWithFormat(
                        L10n.articleListShowReadButtonFormat,
                        count
                    ),
                    systemImage: "eye"
                )
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.vertical, 10)
    }

    private var articleSearchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField(L10n.articleSearchPlaceholder, text: $searchText)
                .textFieldStyle(.plain)
                .font(.body)

            if !searchText.isEmpty {
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
        .controlSize(.small)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
        .overlay {
            Capsule()
                .stroke(.separator.opacity(0.5), lineWidth: 1)
        }
    }

    private var loadToken: String {
        "\(scopeToken)#\(directTagVersion)#\(sqliteStatusVersion)#\(selectedArticleID ?? "nil")#\(debouncedSearchText)"
    }

    private var scopeToken: String {
        switch scope {
        case let .feed(feedID, _):
            return "feed:\(feedID)"
        case let .tagID(tagID):
            return "tag:\(tagID)"
        case let .smartFilter(smartFilter):
            return "smartFilter:\(smartFilter.rawValue)"
        case let .smartFolder(smartFolder):
            let conditionToken = smartFolder.conditions
                .map { "\($0.field.rawValue):\($0.conditionOperator.rawValue):\($0.value)" }
                .joined(separator: "|")
            return "smartFolder:\(smartFolder.id):\(smartFolder.matchMode.rawValue):\(conditionToken)"
        }
    }

    private var navigationTitle: String {
        switch scope {
        case let .feed(_, title):
            return title
        case .tagID:
            return String(localized: "sidebar.tags.section")
        case let .smartFilter(smartFilter):
            return navigationTitle(for: smartFilter)
        case let .smartFolder(smartFolder):
            return smartFolder.name
        }
    }

    private func navigationTitle(for smartFilter: SmartFilter) -> String {
        switch smartFilter {
        case .allArticles:
            return String(localized: "smartFilter.allArticles")
        case .unread:
            return String(localized: "smartFilter.unread")
        case .starred:
            return String(localized: "smartFilter.starred")
        case .today:
            return String(localized: "smartFilter.today")
        case .hidden:
            return String(localized: "smartFilter.hidden")
        }
    }

    private var emptyDescription: String {
        if isSearching {
            return L10n.articleSearchNoResultsDescription(debouncedSearchText)
        }

        switch scope {
        case .feed:
            return "Für diesen Feed sind noch keine SQLite-Artikel gespeichert."
        case .tagID:
            return "Für dieses Tag sind noch keine SQLite-Artikel gespeichert."
        case .smartFilter:
            return "Für diesen Filter sind noch keine SQLite-Artikel gespeichert."
        case .smartFolder:
            return "Für diesen intelligenten Ordner sind noch keine SQLite-Artikel gespeichert."
        }
    }

    private var emptyTitle: String {
        isSearching ? L10n.articleSearchNoResultsTitle : "Keine Artikel"
    }

    private var emptySystemImage: String {
        isSearching ? "magnifyingglass" : "doc.text"
    }

    private var isSearching: Bool {
        !debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func reload() {
        switch scope {
        case let .feed(feedID, _):
            state.load(
                feedID: feedID,
                searchText: debouncedSearchText,
                database: database,
                selectedArticleID: selectedArticleID
            )
        case let .tagID(tagID):
            state.load(
                tagID: tagID,
                searchText: debouncedSearchText,
                database: database,
                selectedArticleID: selectedArticleID
            )
        case let .smartFilter(smartFilter):
            state.load(
                smartFilter: smartFilter,
                searchText: debouncedSearchText,
                database: database,
                selectedArticleID: selectedArticleID
            )
        case let .smartFolder(smartFolder):
            state.load(
                smartFolder: smartFolder,
                searchText: debouncedSearchText,
                database: database,
                selectedArticleID: selectedArticleID
            )
        }
        navigationState = state.navigationState
    }

    private func articleFilterIncludes(_ row: ArticleListSnapshot) -> Bool {
        switch articleFilterOption {
        case .all:
            return true
        case .unread:
            return !row.isRead
        case .starred:
            return row.isStarred
        case .archived:
            return row.isArchived
        case .today:
            guard let publishedAt = row.publishedAt else {
                return false
            }

            return Calendar.current.isDateInToday(publishedAt)
        }
    }

    private func sortRows(_ first: ArticleListSnapshot, _ second: ArticleListSnapshot) -> Bool {
        switch articleSortOption {
        case .newestFirst:
            compareOptionalDate(first.publishedAt, second.publishedAt, newestFirst: true)
                ?? compareText(first.title, second.title)
                ?? (first.id < second.id)
        case .oldestFirst:
            compareOptionalDate(first.publishedAt, second.publishedAt, newestFirst: false)
                ?? compareText(first.title, second.title)
                ?? (first.id < second.id)
        case .feed:
            compareText(first.feedTitle, second.feedTitle)
                ?? compareOptionalDate(first.publishedAt, second.publishedAt, newestFirst: true)
                ?? (first.id < second.id)
        case .title:
            compareText(first.title, second.title)
                ?? compareOptionalDate(first.publishedAt, second.publishedAt, newestFirst: true)
                ?? (first.id < second.id)
        case .shortReadingTimeFirst:
            compareNumber(first.estimatedReadingMinutes ?? Int.max, second.estimatedReadingMinutes ?? Int.max)
                ?? compareOptionalDate(first.publishedAt, second.publishedAt, newestFirst: true)
                ?? (first.id < second.id)
        }
    }

    private func compareOptionalDate(_ first: Date?, _ second: Date?, newestFirst: Bool) -> Bool? {
        guard first != second else {
            return nil
        }

        guard let first else {
            return false
        }

        guard let second else {
            return true
        }

        return newestFirst ? first > second : first < second
    }

    private func compareText(_ first: String?, _ second: String?) -> Bool? {
        let normalizedFirst = normalizedText(first)
        let normalizedSecond = normalizedText(second)

        guard normalizedFirst != normalizedSecond else {
            return nil
        }

        guard let normalizedFirst else {
            return false
        }

        guard let normalizedSecond else {
            return true
        }

        return normalizedFirst.localizedStandardCompare(normalizedSecond) == .orderedAscending
    }

    private func compareNumber(_ first: Int, _ second: Int) -> Bool? {
        guard first != second else {
            return nil
        }

        return first < second
    }

    private func normalizedText(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    private var articleSortOption: ArticleSortOption {
        ArticleSortOption.resolved(from: articleSortRawValue)
    }

    private var articleFilterOption: ArticleFilterOption {
        ArticleFilterOption.resolved(from: articleFilterRawValue)
    }

    private func markReadMenu(visibleRows: [ArticleListSnapshot]) -> some View {
        Menu {
            ForEach(ArticleMarkReadOption.allCases) { option in
                let candidateRows = visibleRows.filter { row in
                    !row.isRead && markReadOption(option, includes: row)
                }

                Button {
                    markRowsRead(candidateRows)
                } label: {
                    Text(option.label)
                }
                .disabled(candidateRows.isEmpty)
            }
        } label: {
            Label(L10n.articleMarkReadMenuTitle, systemImage: "checkmark.circle")
        }
        .help(L10n.articleMarkReadMenuTitle)
    }

    private func markReadOption(_ option: ArticleMarkReadOption, includes row: ArticleListSnapshot) -> Bool {
        switch option {
        case .allVisible:
            return true
        case .olderThanOneDay:
            return isRow(row, olderThan: .day, value: 1)
        case .olderThanTwoDays:
            return isRow(row, olderThan: .day, value: 2)
        case .olderThanThreeDays:
            return isRow(row, olderThan: .day, value: 3)
        case .olderThanFourDays:
            return isRow(row, olderThan: .day, value: 4)
        case .olderThanOneWeek:
            return isRow(row, olderThan: .weekOfYear, value: 1)
        case .olderThanTwoWeeks:
            return isRow(row, olderThan: .weekOfYear, value: 2)
        }
    }

    private func isRow(_ row: ArticleListSnapshot, olderThan component: Calendar.Component, value: Int) -> Bool {
        guard
            let publishedAt = row.publishedAt,
            let cutoffDate = Calendar.current.date(byAdding: component, value: -value, to: Date())
        else {
            return false
        }

        return publishedAt < cutoffDate
    }

    private var filterMenu: some View {
        Menu {
            Section(L10n.articleListReadDisplayTitle) {
                Button {
                    showsReadArticles = false
                } label: {
                    if showsReadArticles {
                        Text(L10n.articleListReadDisplayUnreadOnly)
                    } else {
                        Label(L10n.articleListReadDisplayUnreadOnly, systemImage: "checkmark")
                    }
                }

                Button {
                    showsReadArticles = true
                } label: {
                    if showsReadArticles {
                        Label(L10n.articleListReadDisplayAll, systemImage: "checkmark")
                    } else {
                        Text(L10n.articleListReadDisplayAll)
                    }
                }
            }

            Divider()

            ForEach(ArticleFilterOption.allCases) { filterOption in
                Button {
                    articleFilterRawValue = filterOption.rawValue
                } label: {
                    if filterOption == articleFilterOption {
                        Label(filterOption.label, systemImage: "checkmark")
                    } else {
                        Label(filterOption.label, systemImage: filterOption.systemImage)
                    }
                }
            }
        } label: {
            Label(L10n.articleFilterMenuTitle, systemImage: "line.3.horizontal.decrease.circle")
        }
        .help(L10n.articleFilterMenuTitle)
    }

    private var sortMenu: some View {
        Menu {
            ForEach(ArticleSortOption.allCases) { sortOption in
                Button {
                    articleSortRawValue = sortOption.rawValue
                } label: {
                    if sortOption == articleSortOption {
                        Label(sortOption.label, systemImage: "checkmark")
                    } else {
                        Text(sortOption.label)
                    }
                }
            }
        } label: {
            Label(L10n.articleSortMenuTitle, systemImage: "arrow.up.arrow.down")
        }
        .help(L10n.articleSortMenuTitle)
    }

    private func toggleRead(_ articleID: String) {
        guard let database else {
            return
        }

        state.toggleRead(articleID: articleID, database: database)
        navigationState = state.navigationState
    }

    private func markRowsRead(_ rows: [ArticleListSnapshot]) {
        guard let database else {
            return
        }

        do {
            let store = ArticleStatusStore(database: database)
            for row in rows where !row.isRead {
                try store.setRead(true, articleID: row.id, at: Date())
            }
            reload()
        } catch {
            reload()
        }
    }

    private func toggleStarred(_ articleID: String) {
        guard let database else {
            return
        }

        state.toggleStarred(articleID: articleID, database: database)
        navigationState = state.navigationState
    }

    private func toggleArchived(_ articleID: String) {
        guard let database else {
            return
        }

        state.toggleArchived(articleID: articleID, database: database)
        navigationState = state.navigationState
    }

    @MainActor
    private func saveOrRemoveOffline(_ row: ArticleListSnapshot) async {
        guard let database else {
            return
        }

        if row.offlineState.isAvailable {
            offlineDownloadService.removeOfflineContent(articleID: row.id, database: database)
        } else {
            await offlineDownloadService.saveForOffline(articleID: row.id, database: database)
        }

        reload()
        navigationState = state.navigationState
    }

    private func requestExportArticle(_ articleID: String) {
        guard let database else {
            return
        }

        do {
            guard let snapshot = try ArticleStore(database: database).readerArticle(id: articleID) else {
                return
            }
            let tagNames = try TagStore(database: database).exportTagNames(
                articleID: snapshot.id,
                feedID: snapshot.feedID
            )
            let request = ArticleExportRequest(
                snapshot: ArticleExportSnapshot(sqliteSnapshot: snapshot, tagNames: tagNames)
            )

            DispatchQueue.main.async {
                articleExportRequest = request
            }
        } catch {
            state.loadState = .failed(error.localizedDescription)
        }
    }

    private func requestRuleCreation(from row: ArticleListSnapshot) {
        ruleCreationRequest = ArticleListRuleCreationRequest(snapshot: row)
    }

    private func sqliteRulesForRuleCreation() -> [RuleRecord] {
        guard let database else {
            return []
        }

        return (try? SQLiteRuleStore(database: database).rules()) ?? []
    }

    private func copyLink(_ row: ArticleListSnapshot) {
        guard let link = row.link?.trimmingCharacters(in: .whitespacesAndNewlines),
              !link.isEmpty
        else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link, forType: .string)
    }

    private func openOriginal(_ row: ArticleListSnapshot) {
        guard let link = row.link,
              let url = URL(string: link)
        else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func shareOriginal(_ row: ArticleListSnapshot) {
        guard let link = row.link?.trimmingCharacters(in: .whitespacesAndNewlines),
              !link.isEmpty
        else {
            return
        }

        let picker = NSSharingServicePicker(items: [row.title, link])
        let sourceView = NSApp.keyWindow?.contentView ?? NSView()
        picker.show(relativeTo: .zero, of: sourceView, preferredEdge: .minY)
    }

    private func deleteArticle(_ articleID: String) {
        guard let database else {
            return
        }

        do {
            try database.write { db in
                try db.execute(sql: "DELETE FROM articles WHERE id = ?", arguments: [articleID])
            }
            if selectedArticleID == articleID {
                selectedArticleID = nil
            }
            SQLiteDataInvalidation.bumpStatusVersion()
            reload()
        } catch {
            reload()
        }
    }

    private func clearSearch() {
        searchText = ""
        debouncedSearchText = ""
    }

    private func updateDebouncedSearchText() async {
        if searchText.isEmpty {
            debouncedSearchText = ""
            return
        }

        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else {
            return
        }

        debouncedSearchText = searchText
    }
}

private struct ArticleListRuleCreationRequest: Identifiable {
    let id = UUID()
    let seed: RuleWizardSeed

    init(snapshot: ArticleListSnapshot) {
        self.seed = RuleWizardSeed(snapshot: snapshot)
    }
}
