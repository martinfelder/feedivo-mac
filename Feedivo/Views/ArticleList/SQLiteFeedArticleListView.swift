import SwiftData
import SwiftUI

struct SQLiteFeedArticleListView: View {
    @Environment(\.feedivoDatabase) private var database
    @AppStorage(SidebarBadgeInvalidation.directTagVersionKey)
    private var directTagVersion = 0
    @AppStorage(SQLiteDataInvalidation.statusVersionKey)
    private var sqliteStatusVersion = 0

    private enum Scope {
        case feed(Feed)
        case tagID(String)
        case smartFilter(SmartFilter)
        case smartFolder(SmartFolder)
    }

    private let scope: Scope
    @Binding var selectedArticleID: String?
    @Binding var navigationState: SQLiteArticleNavigationState

    @State private var state = SQLiteFeedArticleListState()
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var offlineDownloadService = SQLiteOfflineDownloadService()
    @State private var articleExportRequest: ArticleExportRequest?

    init(
        feed: Feed,
        selectedArticleID: Binding<String?>,
        navigationState: Binding<SQLiteArticleNavigationState>
    ) {
        self.scope = .feed(feed)
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
        self.scope = .smartFolder(smartFolder)
        self._selectedArticleID = selectedArticleID
        self._navigationState = navigationState
    }

    var body: some View {
        VStack(spacing: 0) {
            articleSearchBar
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()

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
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(state.rows) { row in
                        Button {
                            selectedArticleID = row.id
                        } label: {
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
                                onCreateRule: {},
                                onCopyLink: {},
                                onOpenOriginal: {},
                                onShareOriginal: {},
                                onOpenInWindow: {},
                                onExport: {
                                    requestExportArticle(row.id)
                                },
                                onSaveOrRemoveOffline: {
                                    Task {
                                        await saveOrRemoveOffline(row)
                                    }
                                },
                                onDelete: {},
                                onMarkAllRead: {}
                            )
                            .padding(.horizontal, 12)
                            .background(rowBackground(for: row))
                        }
                        .buttonStyle(.plain)
                        .id(row.id)

                        Divider()
                    }
                }
            }
            .onChange(of: selectedArticleID) { _, newValue in
                if let newValue {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
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
        case let .feed(feed):
            return "feed:\(feed.url)"
        case let .tagID(tagID):
            return "tag:\(tagID)"
        case let .smartFilter(smartFilter):
            return "smartFilter:\(smartFilter.rawValue)"
        case let .smartFolder(smartFolder):
            let snapshot = SQLiteSmartFolderSnapshot(folder: smartFolder)
            let conditionToken = snapshot.conditions
                .map { "\($0.field.rawValue):\($0.conditionOperator.rawValue):\($0.value)" }
                .joined(separator: "|")
            return "smartFolder:\(snapshot.id):\(snapshot.matchMode.rawValue):\(conditionToken)"
        }
    }

    private var navigationTitle: String {
        switch scope {
        case let .feed(feed):
            return feed.title
        case .tagID:
            return String(localized: "sidebar.tags.section")
        case let .smartFilter(smartFilter):
            return navigationTitle(for: smartFilter)
        case let .smartFolder(smartFolder):
            return smartFolder.localizedDisplayName
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

    private func rowBackground(for row: ArticleListSnapshot) -> Color {
        row.id == selectedArticleID
            ? Color.accentColor.opacity(0.14)
            : Color.clear
    }

    private func reload() {
        switch scope {
        case let .feed(feed):
            state.load(
                swiftDataFeedURL: feed.url,
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
                smartFolder: SQLiteSmartFolderSnapshot(folder: smartFolder),
                searchText: debouncedSearchText,
                database: database,
                selectedArticleID: selectedArticleID
            )
        }
        navigationState = state.navigationState
    }

    private func toggleRead(_ articleID: String) {
        guard let database else {
            return
        }

        state.toggleRead(articleID: articleID, database: database)
        navigationState = state.navigationState
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
