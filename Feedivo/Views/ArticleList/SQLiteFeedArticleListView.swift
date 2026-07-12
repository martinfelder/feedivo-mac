import AppKit
import GRDB
import SwiftUI

/// Zustand der Feed-Status-Zeile im Artikellisten-Header (nur bei `scope == .feed`).
/// `nil` bedeutet: Feed wurde noch nie aktualisiert (weder erfolgreich noch fehlgeschlagen),
/// Zeile bleibt dann ausgeblendet.
private enum FeedHeaderRefreshStatus: Equatable {
    case success(Date)
    case failure(String)
}

struct SQLiteFeedArticleListView: View {
    @Environment(\.feedivoDatabase) private var database
    @Environment(\.interfaceTextSize) private var interfaceTextSize
    @AppStorage(SidebarBadgeInvalidation.directTagVersionKey)
    private var directTagVersion = 0
    @AppStorage(SQLiteDataInvalidation.statusVersionKey)
    private var sqliteStatusVersion = 0
    @AppStorage("markArticleReadOnSelection")
    private var markArticleReadOnSelection = true

    private enum Scope {
        case feed(feedID: String, title: String)
        case tagID(String)
        case smartFilter(SmartFilter)
        case smartFolder(SQLiteSmartFolderSnapshot)

        var timelineScope: TimelineScope {
            switch self {
            case let .feed(feedID, _):
                .feed(feedID)
            case let .tagID(tagID):
                .tag(tagID)
            case let .smartFilter(smartFilter):
                .smartFilter(smartFilter)
            case let .smartFolder(smartFolder):
                .smartFolder(smartFolder)
            }
        }

        var includeHidden: Bool {
            switch self {
            case .feed, .tagID:
                false
            case let .smartFilter(smartFilter):
                smartFilter == .hidden
            case let .smartFolder(smartFolder):
                smartFolder.includesHiddenArticles
            }
        }
    }

    private let scope: Scope
    let onRetryFeed: (() -> Void)?
    @Binding var selectedArticleID: String?
    @Binding var navigationState: SQLiteArticleNavigationState
    @Binding var searchText: String

    @State private var state = SQLiteFeedArticleListState()
    @State private var feedHasRecentError = false
    @State private var feedHeaderRefreshStatus: FeedHeaderRefreshStatus?
    @State private var debouncedSearchText = ""
    @State private var articleExportRequest: ArticleExportRequest?
    @State private var ruleCreationRequest: ArticleListRuleCreationRequest?
    @State private var articlePendingDeletion: ArticleListSnapshot?
    @State private var isDeleteArticleConfirmationPresented = false
    @State private var showsReadArticles = false
    @State private var temporarilyVisibleReadArticleIDs = Set<String>()
    // Haelt die zuletzt bekannten Zeilendaten fuer Artikel, die gerade als
    // gelesen markiert wurden. Ein Smart Folder wie "Ungelesen" hat "Status
    // ist ungelesen" als eigene SQL-Bedingung - ein Reload (ausgeloest durch
    // jede Statusaenderung ueber sqliteStatusVersion) wuerde den Artikel sonst
    // sofort aus state.rows entfernen, noch bevor der Anzeige-Filter greifen
    // kann. Dieser Cache ueberlebt den Reload, bis der Scope wechselt.
    @State private var stickyRowSnapshots: [String: ArticleListSnapshot] = [:]

    @AppStorage(ArticleSortOption.storageKey)
    private var articleSortRawValue = ArticleSortOption.newestFirst.rawValue

    @AppStorage(ArticleFilterOption.storageKey)
    private var articleFilterRawValue = ArticleFilterOption.all.rawValue

    init(
        feedID: String,
        title: String,
        selectedArticleID: Binding<String?>,
        navigationState: Binding<SQLiteArticleNavigationState>,
        searchText: Binding<String>,
        onRetryFeed: (() -> Void)? = nil
    ) {
        self.scope = .feed(feedID: feedID, title: title)
        self.onRetryFeed = onRetryFeed
        self._selectedArticleID = selectedArticleID
        self._navigationState = navigationState
        self._searchText = searchText
    }

    init(
        tagID: String,
        selectedArticleID: Binding<String?>,
        navigationState: Binding<SQLiteArticleNavigationState>,
        searchText: Binding<String>
    ) {
        self.scope = .tagID(tagID)
        self.onRetryFeed = nil
        self._selectedArticleID = selectedArticleID
        self._navigationState = navigationState
        self._searchText = searchText
    }

    init(
        smartFilter: SmartFilter,
        selectedArticleID: Binding<String?>,
        navigationState: Binding<SQLiteArticleNavigationState>,
        searchText: Binding<String>
    ) {
        self.scope = .smartFilter(smartFilter)
        self.onRetryFeed = nil
        self._selectedArticleID = selectedArticleID
        self._navigationState = navigationState
        self._searchText = searchText
    }

    init(
        smartFolder: SQLiteSmartFolderSnapshot,
        selectedArticleID: Binding<String?>,
        navigationState: Binding<SQLiteArticleNavigationState>,
        searchText: Binding<String>
    ) {
        self.scope = .smartFolder(smartFolder)
        self.onRetryFeed = nil
        self._selectedArticleID = selectedArticleID
        self._navigationState = navigationState
        self._searchText = searchText
    }

    var body: some View {
        articleContent
        .task(id: searchText) {
            await updateDebouncedSearchText()
        }
        .task(id: loadToken) {
            reload()
        }
        .onChange(of: scopeToken) {
            temporarilyVisibleReadArticleIDs.removeAll()
            stickyRowSnapshots.removeAll()
        }
        .onChange(of: selectedArticleID) {
            markSelectedArticleReadIfNeeded()
            navigationState = SQLiteArticleNavigationState(
                articleIDs: state.rows.map(\.id),
                selectedArticleID: selectedArticleID
            )
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
        .confirmationDialog(
            L10n.articleDeleteConfirmationTitle,
            isPresented: $isDeleteArticleConfirmationPresented,
            presenting: articlePendingDeletion
        ) { row in
            Button(L10n.articleDeleteCommand, role: .destructive) {
                deleteArticle(row)
            }

            Button(L10n.commonCancel, role: .cancel) {
                articlePendingDeletion = nil
            }
        } message: { row in
            Text(L10n.articleDeleteConfirmationMessage(articleTitle: row.title))
        }
        .toolbar {
            ToolbarItemGroup {
                markReadMenu(visibleRows: displayState.visibleRows)
                filterMenu
                sortMenu
            }
        }
        .navigationTitle("")
    }

    @ViewBuilder
    private var articleContent: some View {
        Group {
            switch state.loadState {
            case .missingSQLiteDatabase:
                ContentUnavailableView(
                    L10n.dbUnavailableTitle,
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text(L10n.dbUnavailableDescription)
                )
            case .missingFeed:
                ContentUnavailableView(
                    L10n.feedNotInSQLiteTitle,
                    systemImage: "tray",
                    description: Text(L10n.feedNotInSQLiteDescription)
                )
            case .failed(let message):
                ContentUnavailableView {
                    Label(L10n.articleListLoadFailedTitle, systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    if let onRetryFeed {
                        Button(L10n.feedErrorRetryButton, action: onRetryFeed)
                    }
                }
            case .idle where state.rows.isEmpty:
                articleListContainer {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            case .loaded where state.rows.isEmpty:
                articleListContainer {
                    ContentUnavailableView {
                        Label(emptyTitle, systemImage: emptySystemImage)
                    } description: {
                        Text(emptyDescription)
                    } actions: {
                        if case .feed = scope, let onRetryFeed {
                            Button(L10n.feedRefreshCommand, action: onRetryFeed)
                        }
                    }
                }
            case .idle, .loaded:
                articleListContainer {
                    articleList
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func articleListContainer<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            articleListHeader
            if feedHasRecentError, !state.rows.isEmpty, case .feed = scope, let onRetryFeed {
                feedErrorBanner(retry: onRetryFeed)
            }
            Divider()
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func feedErrorBanner(retry: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(L10n.feedErrorBannerMessage)
                .font(interfaceTextSize.font(size: 12))
            Spacer()
            Button(L10n.feedErrorRetryButton, action: retry)
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.12))
    }

    private var articleListHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(navigationTitle)
                .font(interfaceTextSize.font(size: 13, weight: .medium))
                .lineLimit(1)

            Text(unreadArticleCountText)
                .font(interfaceTextSize.font(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if case .feed = scope, let feedHeaderRefreshStatus {
                Text(feedHeaderRefreshStatusText(feedHeaderRefreshStatus))
                    .font(interfaceTextSize.font(size: 13))
                    .foregroundStyle(feedHeaderRefreshStatusColor(feedHeaderRefreshStatus))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private func feedHeaderRefreshStatusText(_ status: FeedHeaderRefreshStatus) -> String {
        switch status {
        case let .success(date):
            // Bewusst immer der konkrete Zeitpunkt (Datum + Uhrzeit), nicht die relative
            // "vor X Stunden"-Formatierung von feedivoDisplay(mode:) — der Nutzer will
            // sehen, WANN aktualisiert wurde, nicht wie lange das her ist (Nutzer-Report
            // 2026-07-12).
            L10n.articleListLastRefreshed(date.formatted(date: .abbreviated, time: .shortened))
        case let .failure(reason):
            L10n.articleListRefreshFailed(reason)
        }
    }

    private func feedHeaderRefreshStatusColor(_ status: FeedHeaderRefreshStatus) -> Color {
        switch status {
        case .success:
            .secondary
        case .failure:
            .orange
        }
    }

    private var unreadArticleCount: Int {
        state.rows.filter { row in
            !row.isRead && !row.isHidden
        }.count
    }

    private var unreadArticleCountText: String {
        if unreadArticleCount == 1 {
            "1 ungelesener Artikel"
        } else {
            "\(unreadArticleCount) ungelesene Artikel"
        }
    }

    private var articleList: some View {
        let currentDisplayState = displayState

        return List(selection: $selectedArticleID) {
            if currentDisplayState.filteredRows.isEmpty {
                articleListEmptyState(isSearching: isSearching)
            } else {
                ForEach(currentDisplayState.visibleRows) { row in
                    articleRow(row, visibleRows: currentDisplayState.visibleRows)
                        .tag(row.id)
                }

                if !showsReadArticles, currentDisplayState.hiddenReadRowCount > 0 {
                    showReadArticlesButton(count: currentDisplayState.hiddenReadRowCount)
                }
            }
        }
    }

    private var effectiveRows: [ArticleListSnapshot] {
        SQLiteArticleListDisplayState.mergingStickyRows(
            into: state.rows,
            stickyRowSnapshots: stickyRowSnapshots
        )
    }

    private var displayState: SQLiteArticleListDisplayState {
        SQLiteArticleListDisplayState(
            rows: effectiveRows.sorted(by: sortRows),
            showsReadArticles: showsReadArticles,
            selectedArticleID: selectedArticleID,
            temporarilyVisibleReadArticleIDs: temporarilyVisibleReadArticleIDs,
            filterOption: articleFilterOption
        )
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
            onDelete: {
                requestDeleteArticle(row)
            },
            onMarkAllRead: {
                markRowsRead(.allVisible)
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

    private var loadToken: String {
        SQLiteFeedArticleListLoadToken.make(
            scopeToken: scopeToken,
            directTagVersion: directTagVersion,
            sqliteStatusVersion: sqliteStatusVersion,
            debouncedSearchText: debouncedSearchText
        )
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
            return L10n.articleListEmptyDescriptionFeed
        case .tagID:
            return L10n.articleListEmptyDescriptionTag
        case .smartFilter:
            return L10n.articleListEmptyDescriptionSmartFilter
        case .smartFolder:
            return L10n.articleListEmptyDescriptionSmartFolder
        }
    }

    private var emptyTitle: String {
        isSearching ? L10n.articleSearchNoResultsTitle : L10n.articleListEmptyTitle
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
            if let database {
                let latestLog = (try? FeedLogStore(database: database).logs(feedID: feedID, limit: 1))?.first
                let isLatestLogAnError = latestLog.map { FeedLogEntryKind(rawValue: $0.level) == .error } ?? false
                feedHasRecentError = isLatestLogAnError

                if isLatestLogAnError, let latestLog {
                    feedHeaderRefreshStatus = .failure(latestLog.message)
                } else if let lastRefreshedAt = (try? FeedStore(database: database).feed(id: feedID))?.lastRefreshedAt {
                    feedHeaderRefreshStatus = .success(lastRefreshedAt)
                } else {
                    feedHeaderRefreshStatus = nil
                }
            } else {
                feedHasRecentError = false
                feedHeaderRefreshStatus = nil
            }
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
                Button {
                    markRowsRead(option)
                } label: {
                    Text(option.label)
                }
            }
        } label: {
            Label(L10n.articleMarkReadMenuTitle, systemImage: "checkmark.circle")
        }
        .help(L10n.articleMarkReadMenuTitle)
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
        temporarilyVisibleReadArticleIDs.insert(articleID)
        if let row = state.rows.first(where: { $0.id == articleID }) {
            stickyRowSnapshots[articleID] = row
        }
    }

    private func markSelectedArticleReadIfNeeded() {
        let articleID = selectedArticleID
        guard state.markReadIfNeeded(
            articleID: articleID,
            database: database,
            isEnabled: markArticleReadOnSelection
        ) else {
            return
        }

        if let articleID {
            temporarilyVisibleReadArticleIDs.insert(articleID)
            if let row = state.rows.first(where: { $0.id == articleID }) {
                stickyRowSnapshots[articleID] = row
            }
        }
    }

    private func markRowsRead(_ option: ArticleMarkReadOption) {
        guard let database else {
            return
        }

        do {
            _ = try TimelineStore(database: database).markRead(
                scope: scope.timelineScope,
                searchText: debouncedSearchText,
                includeHidden: scope.includeHidden,
                option: option
            )
            SQLiteDataInvalidation.bumpStatusVersion()
            reload()
        } catch {
            // Kein reload() hier: das wuerde ueber state.load(...) den
            // gerade gesetzten .failed-Zustand sofort wieder auf .idle/
            // .loaded ueberschreiben (siehe SQLiteFeedArticleListState.
            // deleteArticle fuer denselben, bereits etablierten Grund).
            state.loadState = .failed(error.localizedDescription)
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

        ArticleOriginalBrowserLauncher.open(url)
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

    private func requestDeleteArticle(_ row: ArticleListSnapshot) {
        articlePendingDeletion = row
        isDeleteArticleConfirmationPresented = true
    }

    private func deleteArticle(_ row: ArticleListSnapshot) {
        articlePendingDeletion = nil

        guard let database else {
            return
        }

        guard state.deleteArticle(articleID: row.id, database: database) else {
            return
        }

        if selectedArticleID == row.id {
            selectedArticleID = nil
        }
        SQLiteDataInvalidation.bumpStatusVersion()
    }

    private func updateDebouncedSearchText() async {
        if searchText.isEmpty {
            debouncedSearchText = ""
            return
        }

        guard await SearchDebounce.wait() else {
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

struct SQLiteArticleListDisplayState {
    let rows: [ArticleListSnapshot]
    let showsReadArticles: Bool
    let selectedArticleID: String?
    let temporarilyVisibleReadArticleIDs: Set<String>
    let filterOption: ArticleFilterOption

    // state.rows kommt aus einer frischen Scope-Abfrage und kann einen Artikel
    // bereits vollstaendig ausgeschlossen haben (z. B. Smart Folder "Ungelesen"
    // mit "Status ist ungelesen" als eigener SQL-Bedingung). stickyRowSnapshots
    // haelt solche Artikel bis zum naechsten Scope-Wechsel sichtbar; rows hat
    // aber immer Vorrang, falls der Artikel dort wieder auftaucht.
    static func mergingStickyRows(
        into rows: [ArticleListSnapshot],
        stickyRowSnapshots: [String: ArticleListSnapshot]
    ) -> [ArticleListSnapshot] {
        let presentIDs = Set(rows.map(\.id))
        let missingStickyRows = stickyRowSnapshots.values.filter { !presentIDs.contains($0.id) }
        return rows + missingStickyRows
    }

    var filteredRows: [ArticleListSnapshot] {
        rows.filter(articleFilterIncludes)
    }

    var visibleRows: [ArticleListSnapshot] {
        guard !showsReadArticles else {
            return filteredRows
        }

        return filteredRows.filter { row in
            !row.isRead || isSelected(row) || isTemporarilyVisibleReadRow(row)
        }
    }

    var hiddenReadRowCount: Int {
        filteredRows.filter { row in
            row.isRead && !isSelected(row) && !isTemporarilyVisibleReadRow(row)
        }.count
    }

    private func articleFilterIncludes(_ row: ArticleListSnapshot) -> Bool {
        switch filterOption {
        case .all:
            return true
        case .unread:
            return !row.isRead || isSelected(row) || isTemporarilyVisibleReadRow(row)
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

    private func isSelected(_ row: ArticleListSnapshot) -> Bool {
        row.id == selectedArticleID
    }

    private func isTemporarilyVisibleReadRow(_ row: ArticleListSnapshot) -> Bool {
        row.isRead && temporarilyVisibleReadArticleIDs.contains(row.id)
    }
}
