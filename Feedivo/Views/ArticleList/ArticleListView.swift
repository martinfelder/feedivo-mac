import SwiftUI
import SwiftData
import AppKit

struct ArticleListView: View {
    private enum Scope {
        case feed(Feed)
        case smartFilter(SmartFilter)
        case tag(Tag)
        case smartFolder(SmartFolder)
    }

    private let scope: Scope
    @Binding var selectedArticle: Article?
    @Binding var navigationState: ArticleNavigationState
    private let onRequestCreateRuleFromArticle: (Article) -> Void
    private let onRequestExportArticle: (Article) -> Void

    init(
        feed: Feed,
        selectedArticle: Binding<Article?>,
        navigationState: Binding<ArticleNavigationState>,
        onRequestCreateRuleFromArticle: @escaping (Article) -> Void = { _ in },
        onRequestExportArticle: @escaping (Article) -> Void = { _ in }
    ) {
        self.scope = .feed(feed)
        self._selectedArticle = selectedArticle
        self._navigationState = navigationState
        self.onRequestCreateRuleFromArticle = onRequestCreateRuleFromArticle
        self.onRequestExportArticle = onRequestExportArticle
    }

    init(
        smartFilter: SmartFilter,
        selectedArticle: Binding<Article?>,
        navigationState: Binding<ArticleNavigationState>,
        onRequestCreateRuleFromArticle: @escaping (Article) -> Void = { _ in },
        onRequestExportArticle: @escaping (Article) -> Void = { _ in }
    ) {
        self.scope = .smartFilter(smartFilter)
        self._selectedArticle = selectedArticle
        self._navigationState = navigationState
        self.onRequestCreateRuleFromArticle = onRequestCreateRuleFromArticle
        self.onRequestExportArticle = onRequestExportArticle
    }

    init(
        tag: Tag,
        selectedArticle: Binding<Article?>,
        navigationState: Binding<ArticleNavigationState>,
        onRequestCreateRuleFromArticle: @escaping (Article) -> Void = { _ in },
        onRequestExportArticle: @escaping (Article) -> Void = { _ in }
    ) {
        self.scope = .tag(tag)
        self._selectedArticle = selectedArticle
        self._navigationState = navigationState
        self.onRequestCreateRuleFromArticle = onRequestCreateRuleFromArticle
        self.onRequestExportArticle = onRequestExportArticle
    }

    init(
        smartFolder: SmartFolder,
        selectedArticle: Binding<Article?>,
        navigationState: Binding<ArticleNavigationState>,
        onRequestCreateRuleFromArticle: @escaping (Article) -> Void = { _ in },
        onRequestExportArticle: @escaping (Article) -> Void = { _ in }
    ) {
        self.scope = .smartFolder(smartFolder)
        self._selectedArticle = selectedArticle
        self._navigationState = navigationState
        self.onRequestCreateRuleFromArticle = onRequestCreateRuleFromArticle
        self.onRequestExportArticle = onRequestExportArticle
    }

    var body: some View {
        switch scope {
        case .feed(let feed):
            FeedArticleListContent(
                feed: feed,
                selectedArticle: $selectedArticle,
                navigationState: $navigationState,
                onRequestCreateRuleFromArticle: onRequestCreateRuleFromArticle,
                onRequestExportArticle: onRequestExportArticle
            )
            .id(feed.id)
        case .smartFilter(let smartFilter):
            SmartFilterArticleListContent(
                smartFilter: smartFilter,
                selectedArticle: $selectedArticle,
                navigationState: $navigationState,
                onRequestCreateRuleFromArticle: onRequestCreateRuleFromArticle,
                onRequestExportArticle: onRequestExportArticle
            )
            .id(smartFilter)
        case .tag(let tag):
            TagArticleListContent(
                tag: tag,
                selectedArticle: $selectedArticle,
                navigationState: $navigationState,
                onRequestCreateRuleFromArticle: onRequestCreateRuleFromArticle,
                onRequestExportArticle: onRequestExportArticle
            )
            .id(tag.id)
        case .smartFolder(let smartFolder):
            SmartFolderArticleListContent(
                smartFolder: smartFolder,
                selectedArticle: $selectedArticle,
                navigationState: $navigationState,
                onRequestCreateRuleFromArticle: onRequestCreateRuleFromArticle,
                onRequestExportArticle: onRequestExportArticle
            )
            .id(smartFolder.id)
        }
    }
}

private struct FeedArticleListContent: View {
    let feed: Feed
    let onRequestCreateRuleFromArticle: (Article) -> Void
    let onRequestExportArticle: (Article) -> Void
    @Binding var selectedArticle: Article?
    @Binding var navigationState: ArticleNavigationState
    @State private var fetchLimit = ArticleListQuery.initialFetchLimit

    init(
        feed: Feed,
        selectedArticle: Binding<Article?>,
        navigationState: Binding<ArticleNavigationState>,
        onRequestCreateRuleFromArticle: @escaping (Article) -> Void,
        onRequestExportArticle: @escaping (Article) -> Void
    ) {
        self.feed = feed
        self.onRequestCreateRuleFromArticle = onRequestCreateRuleFromArticle
        self.onRequestExportArticle = onRequestExportArticle
        self._selectedArticle = selectedArticle
        self._navigationState = navigationState
    }

    var body: some View {
        FeedArticleListQueryContent(
            feed: feed,
            fetchLimit: fetchLimit,
            selectedArticle: $selectedArticle,
            navigationState: $navigationState,
            onRequestCreateRuleFromArticle: onRequestCreateRuleFromArticle,
            onRequestExportArticle: onRequestExportArticle,
            onLoadMoreArticles: loadMoreArticles
        )
    }

    private func loadMoreArticles() {
        fetchLimit += ArticleListQuery.fetchBatchSize
    }
}

private struct FeedArticleListQueryContent: View {
    let feed: Feed
    let fetchLimit: Int
    let onRequestCreateRuleFromArticle: (Article) -> Void
    let onRequestExportArticle: (Article) -> Void
    let onLoadMoreArticles: () -> Void
    @Binding var selectedArticle: Article?
    @Binding var navigationState: ArticleNavigationState
    @Query private var articles: [Article]

    init(
        feed: Feed,
        fetchLimit: Int,
        selectedArticle: Binding<Article?>,
        navigationState: Binding<ArticleNavigationState>,
        onRequestCreateRuleFromArticle: @escaping (Article) -> Void,
        onRequestExportArticle: @escaping (Article) -> Void,
        onLoadMoreArticles: @escaping () -> Void
    ) {
        self.feed = feed
        self.fetchLimit = fetchLimit
        self.onRequestCreateRuleFromArticle = onRequestCreateRuleFromArticle
        self.onRequestExportArticle = onRequestExportArticle
        self.onLoadMoreArticles = onLoadMoreArticles
        self._selectedArticle = selectedArticle
        self._navigationState = navigationState
        self._articles = Query(
            ArticleListQuery.feedFetchDescriptor(
                for: feed,
                fetchLimit: fetchLimit
            )
        )
    }

    var body: some View {
        ArticleListContent(
            articles: articles,
            navigationTitle: Text(feed.title),
            selectedArticle: $selectedArticle,
            navigationState: $navigationState,
            onRequestCreateRuleFromArticle: onRequestCreateRuleFromArticle,
            onRequestExportArticle: onRequestExportArticle,
            showsHiddenArticles: false,
            canLoadMoreArticles: canLoadMoreArticles,
            onLoadMoreArticles: onLoadMoreArticles
        )
    }

    private var canLoadMoreArticles: Bool {
        articles.count >= fetchLimit
    }
}

private struct TagArticleListContent: View {
    let tag: Tag
    let onRequestCreateRuleFromArticle: (Article) -> Void
    let onRequestExportArticle: (Article) -> Void
    @Binding var selectedArticle: Article?
    @Binding var navigationState: ArticleNavigationState
    @State private var fetchLimit = ArticleListQuery.initialFetchLimit

    init(
        tag: Tag,
        selectedArticle: Binding<Article?>,
        navigationState: Binding<ArticleNavigationState>,
        onRequestCreateRuleFromArticle: @escaping (Article) -> Void,
        onRequestExportArticle: @escaping (Article) -> Void
    ) {
        self.tag = tag
        self.onRequestCreateRuleFromArticle = onRequestCreateRuleFromArticle
        self.onRequestExportArticle = onRequestExportArticle
        self._selectedArticle = selectedArticle
        self._navigationState = navigationState
    }

    var body: some View {
        TagArticleListQueryContent(
            tag: tag,
            fetchLimit: fetchLimit,
            selectedArticle: $selectedArticle,
            navigationState: $navigationState,
            onRequestCreateRuleFromArticle: onRequestCreateRuleFromArticle,
            onRequestExportArticle: onRequestExportArticle,
            onLoadMoreArticles: loadMoreArticles
        )
    }

    private func loadMoreArticles() {
        fetchLimit += ArticleListQuery.fetchBatchSize
    }
}

private struct TagArticleListQueryContent: View {
    let tag: Tag
    let fetchLimit: Int
    let onRequestCreateRuleFromArticle: (Article) -> Void
    let onRequestExportArticle: (Article) -> Void
    let onLoadMoreArticles: () -> Void
    @Binding var selectedArticle: Article?
    @Binding var navigationState: ArticleNavigationState
    @Query private var articles: [Article]

    init(
        tag: Tag,
        fetchLimit: Int,
        selectedArticle: Binding<Article?>,
        navigationState: Binding<ArticleNavigationState>,
        onRequestCreateRuleFromArticle: @escaping (Article) -> Void,
        onRequestExportArticle: @escaping (Article) -> Void,
        onLoadMoreArticles: @escaping () -> Void
    ) {
        self.tag = tag
        self.fetchLimit = fetchLimit
        self.onRequestCreateRuleFromArticle = onRequestCreateRuleFromArticle
        self.onRequestExportArticle = onRequestExportArticle
        self.onLoadMoreArticles = onLoadMoreArticles
        self._selectedArticle = selectedArticle
        self._navigationState = navigationState
        self._articles = Query(
            ArticleListQuery.tagFetchDescriptor(
                for: tag,
                fetchLimit: fetchLimit
            )
        )
    }

    var body: some View {
        ArticleListContent(
            articles: articles,
            navigationTitle: Text(tag.name),
            selectedArticle: $selectedArticle,
            navigationState: $navigationState,
            onRequestCreateRuleFromArticle: onRequestCreateRuleFromArticle,
            onRequestExportArticle: onRequestExportArticle,
            showsHiddenArticles: false,
            canLoadMoreArticles: canLoadMoreArticles,
            onLoadMoreArticles: onLoadMoreArticles
        )
    }

    private var canLoadMoreArticles: Bool {
        articles.count >= fetchLimit
    }
}

private struct SmartFilterArticleListContent: View {
    let smartFilter: SmartFilter
    let onRequestCreateRuleFromArticle: (Article) -> Void
    let onRequestExportArticle: (Article) -> Void
    @Binding var selectedArticle: Article?
    @Binding var navigationState: ArticleNavigationState
    @State private var fetchLimit = ArticleListQuery.initialFetchLimit

    init(
        smartFilter: SmartFilter,
        selectedArticle: Binding<Article?>,
        navigationState: Binding<ArticleNavigationState>,
        onRequestCreateRuleFromArticle: @escaping (Article) -> Void,
        onRequestExportArticle: @escaping (Article) -> Void
    ) {
        self.smartFilter = smartFilter
        self.onRequestCreateRuleFromArticle = onRequestCreateRuleFromArticle
        self.onRequestExportArticle = onRequestExportArticle
        self._selectedArticle = selectedArticle
        self._navigationState = navigationState
    }

    var body: some View {
        SmartFilterArticleListQueryContent(
            smartFilter: smartFilter,
            fetchLimit: fetchLimit,
            selectedArticle: $selectedArticle,
            navigationState: $navigationState,
            onRequestCreateRuleFromArticle: onRequestCreateRuleFromArticle,
            onRequestExportArticle: onRequestExportArticle,
            onLoadMoreArticles: loadMoreArticles
        )
    }

    private func loadMoreArticles() {
        fetchLimit += ArticleListQuery.fetchBatchSize
    }
}

private struct SmartFilterArticleListQueryContent: View {
    let smartFilter: SmartFilter
    let fetchLimit: Int
    let onRequestCreateRuleFromArticle: (Article) -> Void
    let onRequestExportArticle: (Article) -> Void
    let onLoadMoreArticles: () -> Void
    @Binding var selectedArticle: Article?
    @Binding var navigationState: ArticleNavigationState
    @Query private var articles: [Article]

    init(
        smartFilter: SmartFilter,
        fetchLimit: Int,
        selectedArticle: Binding<Article?>,
        navigationState: Binding<ArticleNavigationState>,
        onRequestCreateRuleFromArticle: @escaping (Article) -> Void,
        onRequestExportArticle: @escaping (Article) -> Void,
        onLoadMoreArticles: @escaping () -> Void
    ) {
        self.smartFilter = smartFilter
        self.fetchLimit = fetchLimit
        self.onRequestCreateRuleFromArticle = onRequestCreateRuleFromArticle
        self.onRequestExportArticle = onRequestExportArticle
        self.onLoadMoreArticles = onLoadMoreArticles
        self._selectedArticle = selectedArticle
        self._navigationState = navigationState
        self._articles = Query(
            ArticleListQuery.smartFilterFetchDescriptor(
                for: smartFilter,
                fetchLimit: fetchLimit
            )
        )
    }

    var body: some View {
        ArticleListContent(
            articles: displayedArticles,
            navigationTitle: Text(smartFilter.title),
            selectedArticle: $selectedArticle,
            navigationState: $navigationState,
            onRequestCreateRuleFromArticle: onRequestCreateRuleFromArticle,
            onRequestExportArticle: onRequestExportArticle,
            showsHiddenArticles: smartFilter == .hidden,
            canLoadMoreArticles: canLoadMoreArticles,
            onLoadMoreArticles: onLoadMoreArticles
        )
    }

    private var displayedArticles: [Article] {
        guard smartFilter == .today else {
            return articles
        }
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let startOfTomorrow = Calendar.current.date(
            byAdding: .day,
            value: 1,
            to: startOfToday
        ) ?? startOfToday
        return articles.filter { article in
            guard let publishedAt = article.publishedAt else { return false }
            return publishedAt >= startOfToday && publishedAt < startOfTomorrow
        }
    }

    private var canLoadMoreArticles: Bool {
        articles.count >= fetchLimit
    }
}

private struct SmartFolderArticleListContent: View {
    let smartFolder: SmartFolder
    let onRequestCreateRuleFromArticle: (Article) -> Void
    let onRequestExportArticle: (Article) -> Void
    @Binding var selectedArticle: Article?
    @Binding var navigationState: ArticleNavigationState
    @State private var fetchLimit = ArticleListQuery.initialFetchLimit

    init(
        smartFolder: SmartFolder,
        selectedArticle: Binding<Article?>,
        navigationState: Binding<ArticleNavigationState>,
        onRequestCreateRuleFromArticle: @escaping (Article) -> Void,
        onRequestExportArticle: @escaping (Article) -> Void
    ) {
        self.smartFolder = smartFolder
        self.onRequestCreateRuleFromArticle = onRequestCreateRuleFromArticle
        self.onRequestExportArticle = onRequestExportArticle
        self._selectedArticle = selectedArticle
        self._navigationState = navigationState
    }

    var body: some View {
        SmartFolderArticleListQueryContent(
            smartFolder: smartFolder,
            fetchLimit: fetchLimit,
            selectedArticle: $selectedArticle,
            navigationState: $navigationState,
            onRequestCreateRuleFromArticle: onRequestCreateRuleFromArticle,
            onRequestExportArticle: onRequestExportArticle,
            onLoadMoreArticles: loadMoreArticles
        )
    }

    private func loadMoreArticles() {
        fetchLimit += ArticleListQuery.fetchBatchSize
    }
}

private struct SmartFolderArticleListQueryContent: View {
    let smartFolder: SmartFolder
    let onRequestCreateRuleFromArticle: (Article) -> Void
    let onRequestExportArticle: (Article) -> Void
    let onLoadMoreArticles: () -> Void
    private let fetchLimit: Int
    private let usesOptimizedQuery: Bool
    @Binding var selectedArticle: Article?
    @Binding var navigationState: ArticleNavigationState
    @Query private var articles: [Article]

    init(
        smartFolder: SmartFolder,
        fetchLimit: Int,
        selectedArticle: Binding<Article?>,
        navigationState: Binding<ArticleNavigationState>,
        onRequestCreateRuleFromArticle: @escaping (Article) -> Void,
        onRequestExportArticle: @escaping (Article) -> Void,
        onLoadMoreArticles: @escaping () -> Void
    ) {
        self.smartFolder = smartFolder
        self.fetchLimit = fetchLimit
        self.onRequestCreateRuleFromArticle = onRequestCreateRuleFromArticle
        self.onRequestExportArticle = onRequestExportArticle
        self.onLoadMoreArticles = onLoadMoreArticles
        self._selectedArticle = selectedArticle
        self._navigationState = navigationState

        if let descriptor = ArticleListQuery.smartFolderFetchDescriptor(
            for: smartFolder,
            fetchLimit: fetchLimit
        ) {
            self.usesOptimizedQuery = true
            self._articles = Query(descriptor)
        } else {
            self.usesOptimizedQuery = false
            self._articles = Query(ArticleListQuery.allFetchDescriptor(fetchLimit: fetchLimit))
        }
    }

    var body: some View {
        ArticleListContent(
            articles: displayedArticles,
            navigationTitle: Text(smartFolder.name),
            selectedArticle: $selectedArticle,
            navigationState: $navigationState,
            onRequestCreateRuleFromArticle: onRequestCreateRuleFromArticle,
            onRequestExportArticle: onRequestExportArticle,
            showsHiddenArticles: SmartFolderFormatter.includesHiddenStatus(smartFolder),
            showsReadArticlesInitially: SmartFolderFormatter.showsReadArticlesByDefault(smartFolder),
            canLoadMoreArticles: canLoadMoreArticles,
            onLoadMoreArticles: onLoadMoreArticles
        )
    }

    private var displayedArticles: [Article] {
        usesOptimizedQuery
            ? articles
            : SmartFolderEngine.matchingArticles(folder: smartFolder, articles: articles)
    }

    private var canLoadMoreArticles: Bool {
        articles.count >= fetchLimit
    }
}

private struct ArticleListContent: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    let articles: [Article]
    let navigationTitle: Text
    let onRequestCreateRuleFromArticle: (Article) -> Void
    let onRequestExportArticle: (Article) -> Void
    let sortArticles: Bool
    let showsHiddenArticles: Bool
    let canLoadMoreArticles: Bool
    let onLoadMoreArticles: () -> Void
    @Binding var selectedArticle: Article?
    @Binding var navigationState: ArticleNavigationState
    @Query(sort: \Tag.name) private var tags: [Tag]
    @AppStorage("markArticleReadOnSelection")
    private var markArticleReadOnSelection = true
    @AppStorage(OfflineReadingSettings.automaticallySaveStarredArticlesKey)
    private var automaticallySaveStarredArticles = OfflineReadingSettings.defaultAutomaticallySaveStarredArticles
    @State private var viewModel = ArticleViewModel()
    @State private var offlineDownloadService = OfflineDownloadService()
    @State private var showsReadArticles = false
    // Entbunden: markReadIfNeeded sichert nicht sofort pro Auswahl, sondern
    // debounced. Schnelles Weiter-/Zurück-Navigieren löst so nicht jede
    // Auswahl eine @Query-Refetch-Kaskade aus; UI-Updates kommen über
    // @Model-Beobachtung der In-Memory-Mutation (kein Save nötig).
    @State private var pendingReadPersistenceTask: Task<Void, Never>?
    @State private var pendingUnreadCountSyncFeedIDs = Set<UUID>()
    @State private var searchText = ""
    @State private var temporarilyVisibleReadArticleIDs = Set<PersistentIdentifier>()
    @State private var feedTitleByFeedID: [UUID: String] = [:]
    @AppStorage(ArticleSortOption.storageKey)
    private var articleSortRawValue = ArticleSortOption.newestFirst.rawValue
    @AppStorage(ArticleFilterOption.storageKey)
    private var articleFilterRawValue = ArticleFilterOption.all.rawValue
    // Cache für makePreparedArticles(): reiner Selektionswechsel soll keine
    // O(n log n)-Sortierung auslösen. Befüllt ausschließlich asynchron via .task(id:),
    // niemals direkt im Body (sonst "modifying state during view update").
    @State private var cachedPreparedArticles: ArticleListPreparedArticles?
    @State private var cachedPreparedKey: PreparedArticlesCacheKey?
    @State private var readerPrefetchTask: Task<Void, Never>?
    @State private var readerPrefetchKey: ReaderArticlePrefetchKey?
    @State private var offlineArchiveError: OfflineArchiveErrorAlert?

    init(
        articles: [Article],
        navigationTitle: Text,
        selectedArticle: Binding<Article?>,
        navigationState: Binding<ArticleNavigationState>,
        onRequestCreateRuleFromArticle: @escaping (Article) -> Void,
        onRequestExportArticle: @escaping (Article) -> Void,
        sortArticles: Bool = true,
        showsHiddenArticles: Bool = false,
        showsReadArticlesInitially: Bool = false,
        canLoadMoreArticles: Bool = false,
        onLoadMoreArticles: @escaping () -> Void = {}
    ) {
        self.articles = articles
        self.navigationTitle = navigationTitle
        self.onRequestCreateRuleFromArticle = onRequestCreateRuleFromArticle
        self.onRequestExportArticle = onRequestExportArticle
        self.canLoadMoreArticles = canLoadMoreArticles
        self.onLoadMoreArticles = onLoadMoreArticles
        self._selectedArticle = selectedArticle
        self._navigationState = navigationState
        self.sortArticles = sortArticles
        self.showsHiddenArticles = showsHiddenArticles
        self._showsReadArticles = State(initialValue: showsReadArticlesInitially)
    }

    var body: some View {
        let preparedArticlesKey = makePreparedArticlesKey()
        let preparedArticles = preparedArticles(for: preparedArticlesKey)
        let filteredArticles = preparedArticles.filtered
        let displayState = ArticleListDisplayState(
            articles: filteredArticles,
            showsReadArticles: showsReadArticles,
            selectedArticle: selectedArticle,
            showsHiddenArticles: showsHiddenArticles,
            temporarilyVisibleReadArticleIDs: temporarilyVisibleReadArticleIDs
        )
        let displaySnapshot = displayState.snapshot
        let visibleArticles = displaySnapshot.visibleArticles
        let feedTitleByFeedID = self.feedTitleByFeedID

        VStack(spacing: 0) {
            articleSearchBar
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.bar)

            List(selection: $selectedArticle) {
                if filteredArticles.isEmpty {
                    articleListEmptyState(isSearching: activeSearchQuery.isActive)
                    if canLoadMoreArticles {
                        loadMoreArticlesRow
                    }
                } else {
                    ForEach(visibleArticles) { article in
                        articleRow(
                            article,
                            visibleArticles: visibleArticles,
                            feedTitleByFeedID: feedTitleByFeedID
                        )
                            .tag(article)
                    }

                    if displaySnapshot.shouldShowReadArticlesButton {
                        showReadArticlesButton(count: displaySnapshot.hiddenReadArticleCount)
                    }

                    if canLoadMoreArticles {
                        loadMoreArticlesRow
                    }
                }
            }
        }
        .navigationTitle(navigationTitle)
        .onAppear {
            updateNavigationState(in: visibleArticles)
        }
        .onDisappear {
            // Ausstehende Lese-Markierungen sofort persistieren, bevor die
            // Liste verlassen wird (kein Datenverlust beim Wechsel/App-Quit).
            flushPendingReadPersistenceSave()
            readerPrefetchTask?.cancel()
        }
        .onChange(of: visibleArticles) {
            updateNavigationState(in: visibleArticles)
        }
        // Sortier-/Filterwechsel: keine separaten Handler mehr — der Body
        // berechnet `visibleArticles` neu (Cache-Miss wegen geändertem Key),
        // und `.onChange(of: visibleArticles)` aktualisiert den NavigationState.
        // Früher wurde makePreparedArticles() hier bis zu 2× redundant
        // (zusätzlich zum Body + .task) berechnet.
        .onChange(of: selectedArticle?.persistentModelID) {
            rememberAutoReadArticleIfNeeded(selectedArticle)

            updateNavigationState(in: visibleArticles)
            // Hebel 4: Nur sichern, wenn tatsächlich ein ungelesener Artikel
            // als gelesen markiert wurde. Navigieren zwischen bereits gelesenen
            // Artikeln löst so keine Save-Kaskade (Feed.unreadCount-
            // Änderung -> @Query-Refetch -> Re-Render) mehr aus.
            let didMarkRead = viewModel.markReadIfNeeded(
                selectedArticle,
                isEnabled: markArticleReadOnSelection,
                updatesUnreadCount: false,
                context: modelContext
            )
            if didMarkRead {
                rememberPendingUnreadCountSyncFeedID(for: selectedArticle)
                // Save entbunden: In-Memory-Mutation reicht für die UI; erst
                // nach einer kurzen Pause Feed-Zähler synchronisieren und
                // sichern, damit @Query-Invalidierungen nicht pro Auswahl
                // feuern.
                scheduleReadPersistenceSave()
            }
        }
        .toolbar {
            ToolbarItemGroup {
                markReadMenu(visibleArticles: visibleArticles)
                filterMenu
                sortMenu
            }
        }
        .alert(item: $offlineArchiveError) { alert in
            Alert(
                title: Text(L10n.offlineArchiveErrorTitle),
                message: Text(alert.message),
                dismissButton: .default(Text(L10n.commonDone))
            )
        }
        .task(id: preparedArticlesKey) {
            // Cache asynchron befüllen, nachdem der Body mit dem neuen Key
            // gerendert wurde. Bei Cache-Treffer (gleicher Key) startet die
            // Task nicht neu → reiner Selektionswechsel kostet keine Sortierung.
            guard let preparedArticlesKey else { return }
            cachedPreparedArticles = makePreparedArticles()
            cachedPreparedKey = preparedArticlesKey
        }
        .task {
            loadFeedTitleLookup()
        }
        .onChange(of: articles.count) {
            loadFeedTitleLookup()
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
                    clearArticleSearch()
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

    private func articleListEmptyState(isSearching: Bool) -> some View {
        if isSearching {
            ContentUnavailableView(
                L10n.articleSearchNoResultsTitle,
                systemImage: "magnifyingglass",
                description: Text(L10n.articleSearchNoResultsDescription(activeSearchQuery.normalizedText))
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

    private var loadMoreArticlesRow: some View {
        HStack(spacing: 8) {
            Spacer()

            ProgressView()
                .controlSize(.small)

            Text(L10n.articleListLoadingMore)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.vertical, 10)
        .onAppear {
            onLoadMoreArticles()
        }
    }

    private func articleRow(
        _ article: Article,
        visibleArticles: [Article],
        feedTitleByFeedID: [UUID: String]
    ) -> ArticleRowView {
        ArticleRowView(
            article: article,
            feedTitle: feedTitle(for: article, in: feedTitleByFeedID),
            availableTags: tags,
            onToggleRead: {
                viewModel.toggleRead(article, context: modelContext)
                try? modelContext.save()
            },
            onToggleStarred: {
                Task {
                    await viewModel.toggleStarred(
                        article,
                        automaticallySaveForOffline: automaticallySaveStarredArticles,
                        context: modelContext,
                        offlineSaver: offlineDownloadService
                    )
                }
            },
            onToggleArchived: {
                Task {
                    await archiveOrRemoveArchive(article)
                }
            },
            onAssignTag: { tag in
                ArticleMetadataEditor.addTag(
                    named: tag.name,
                    to: article,
                    availableTags: tags,
                    context: modelContext
                )
            },
            onCreateRule: {
                onRequestCreateRuleFromArticle(article)
            },
            onCopyLink: {
                _ = viewModel.copyLink(article)
            },
            onOpenOriginal: {
                _ = viewModel.openOriginal(article)
            },
            onShareOriginal: {
                _ = viewModel.shareOriginal(article)
            },
            onOpenInWindow: {
                openArticleInWindow(article)
            },
            onExport: {
                onRequestExportArticle(article)
            },
            onSaveOrRemoveOffline: {
                Task {
                    await saveOrRemoveOffline(article)
                }
            },
            onDelete: {
                deleteArticle(article)
            },
            onMarkAllRead: {
                viewModel.markAllRead(visibleArticles, context: modelContext)
                try? modelContext.save()
            }
        )
    }

    private func openArticleInWindow(_ article: Article) {
        openWindow(value: ArticleWindowRequest(articleID: article.id))
    }

    private func feedTitle(for article: Article, in feedTitleByFeedID: [UUID: String]) -> String? {
        guard let feedID = article.feedID else {
            return nil
        }

        return feedTitleByFeedID[feedID]
    }

    private func loadFeedTitleLookup() {
        var descriptor = FetchDescriptor<Feed>(sortBy: [SortDescriptor(\.title)])
        descriptor.propertiesToFetch = [\.id, \.title]

        let snapshots = ((try? modelContext.fetch(descriptor)) ?? []).map { feed in
            ArticleListFeedTitleSnapshot(feedID: feed.id, title: feed.title)
        }
        let lookup = ArticleListFeedTitleLookup.make(from: snapshots)

        if feedTitleByFeedID != lookup {
            feedTitleByFeedID = lookup
        }
    }

    private func makePreparedArticles() -> ArticleListPreparedArticles {
        ArticleListPreparedArticles.prepare(
            articles: articles,
            sortArticles: sortArticles,
            filterOption: articleFilterOption,
            searchQuery: activeSearchQuery,
            sorter: articleSortOption.sorted
        )
    }

    /// Baut den Cache-Key für makePreparedArticles(). Liefert nil für Pfade
    /// ohne sicheres Invalidierungssignal (Suche, "heute"-Filter, kurze
    /// Lesezeit-Sortierung); diese werden immer frisch berechnet.
    ///
    /// Wichtig: In den Key wird nur die Status-Zählung aufgenommen, die das
    /// Filterergebnis tatsächlich beeinflusst. Für `.all` hängt das Ergebnis
    /// ausschließlich von Sortierung + Artikelzahl ab — ein Selektionswechsel
    /// (Artikel wird als gelesen markiert, unreadCount sinkt) invalisiert den
    /// Cache dann nicht mehr. Ohne diesen Schutz würde jede Auswahl bei
    /// `markArticleReadOnSelection` einen Cache-Miss auslösen und die komplette
    /// Liste im Body synchron neu sortieren — genau in dem Moment, in dem die
    /// Liste zum neu ausgewählten Artikel scrollt. Das äußerte sich als kurzes
    /// Flackern, sobald der nächste Artikel unterhalb des sichtbaren Bereichs
    /// lag.
    private func makePreparedArticlesKey() -> PreparedArticlesCacheKey? {
        if activeSearchQuery.isActive
            || articleFilterOption == .today
            || articleSortOption == .shortReadingTimeFirst {
            return nil
        }

        var unreadCount = 0
        var starredCount = 0
        var archivedCount = 0
        switch articleFilterOption {
        case .all:
            // Filterergebnis ist unabhängig vom Lese-/Stern-/Archiv-Status.
            break
        case .unread:
            for article in articles where !article.isRead { unreadCount += 1 }
        case .starred:
            for article in articles where article.isStarred { starredCount += 1 }
        case .archived:
            for article in articles where article.isArchived { archivedCount += 1 }
        case .today:
            return nil
        }

        return PreparedArticlesCacheKey(
            articleCount: articles.count,
            unreadCount: unreadCount,
            starredCount: starredCount,
            archivedCount: archivedCount,
            sortRawValue: articleSortRawValue,
            filterRawValue: articleFilterRawValue,
            sortArticles: sortArticles
        )
    }

    /// Liefert vorbereitete Artikel — aus dem Cache wenn der Key trifft, sonst
    /// frisch berechnet. Key nil (Bypass) wird immer frisch berechnet.
    private func preparedArticles(for key: PreparedArticlesCacheKey?) -> ArticleListPreparedArticles {
        guard let key else {
            return makePreparedArticles()
        }

        if cachedPreparedKey == key, let cached = cachedPreparedArticles {
            return cached
        }

        return makePreparedArticles()
    }

    private var activeSearchQuery: ArticleSearchQuery {
        ArticleSearchQuery(
            text: searchText,
            field: .all,
            scope: .currentView,
            includesHeavyContent: false
        )
    }

    private var articleSortOption: ArticleSortOption {
        ArticleSortOption.resolved(from: articleSortRawValue)
    }

    private var articleFilterOption: ArticleFilterOption {
        ArticleFilterOption.resolved(from: articleFilterRawValue)
    }

    private func markReadMenu(visibleArticles: [Article]) -> some View {
        Menu {
            ForEach(ArticleMarkReadOption.allCases) { option in
                let candidateArticles = visibleArticles.filter { article in
                    option.includes(article)
                }

                Button {
                    markRead(visibleArticles, matching: option)
                } label: {
                    Text(option.label)
                }
                .disabled(candidateArticles.isEmpty)
            }
        } label: {
            Label(L10n.articleMarkReadMenuTitle, systemImage: "checkmark.circle")
        }
        .help(L10n.articleMarkReadMenuTitle)
    }

    private func markRead(_ articles: [Article], matching option: ArticleMarkReadOption) {
        viewModel.markRead(articles, matching: option, context: modelContext)
        try? modelContext.save()
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

    private func clearArticleSearch() {
        searchText = ""
    }

    private func updateNavigationState(in articles: [Article]) {
        let newNavigationState = ArticleNavigationState(
            articles: articles,
            selectedArticle: selectedArticle,
            sortArticles: { $0 }
        )
        navigationState = newNavigationState
        scheduleReaderPrefetch(for: newNavigationState)
    }

    private func scheduleReaderPrefetch(for navigationState: ArticleNavigationState) {
        let articlesToPrefetch = ReaderArticlePrefetchPlan.articles(
            previousArticle: navigationState.previousArticle,
            nextArticle: navigationState.nextArticle
        )
        let nextKey = ReaderArticlePrefetchKey(articles: articlesToPrefetch)

        guard !articlesToPrefetch.isEmpty, nextKey != readerPrefetchKey else {
            return
        }

        readerPrefetchKey = nextKey
        readerPrefetchTask?.cancel()
        readerPrefetchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            await ReaderArticlePrefetchPlan.prefetchReaderFields(for: articlesToPrefetch)
        }
    }

    private func rememberAutoReadArticleIfNeeded(_ article: Article?) {
        guard markArticleReadOnSelection,
              let article,
              !article.isRead
        else {
            return
        }

        temporarilyVisibleReadArticleIDs.insert(article.persistentModelID)
    }

    private func rememberPendingUnreadCountSyncFeedID(for article: Article?) {
        guard let feedID = article?.feedID else {
            return
        }

        pendingUnreadCountSyncFeedIDs.insert(feedID)
    }

    /// Sichert ausstehende Lese-Status-Änderungen entbunden: nach kurzer Pause
    /// ohne weitere Auswahl. Schnelles Navigieren koalesziert viele
    /// Einzelmarkierungen zu einem Feed-Zähler-Sync und einem Save.
    private func scheduleReadPersistenceSave() {
        pendingReadPersistenceTask?.cancel()
        pendingReadPersistenceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            persistPendingReadChanges()
        }
    }

    /// Flusht ausstehende Lese-Markierungen sofort (z. B. beim Verlassen der
    /// Liste), damit beim App-Wechsel nichts verloren geht.
    private func flushPendingReadPersistenceSave() {
        pendingReadPersistenceTask?.cancel()
        pendingReadPersistenceTask = nil
        persistPendingReadChanges()
    }

    private func persistPendingReadChanges() {
        if !pendingUnreadCountSyncFeedIDs.isEmpty {
            viewModel.synchronizeUnreadCounts(
                forFeedIDs: pendingUnreadCountSyncFeedIDs,
                context: modelContext
            )
            pendingUnreadCountSyncFeedIDs.removeAll()
        }

        try? modelContext.save()
    }

    @MainActor
    private func saveOrRemoveOffline(_ article: Article) async {
        if article.offlineState.isAvailable {
            offlineDownloadService.removeOfflineContent(from: article)
        } else {
            await offlineDownloadService.saveForOffline(article)
        }

        try? modelContext.save()
    }

    @MainActor
    private func archiveOrRemoveArchive(_ article: Article) async {
        if article.isArchived {
            offlineDownloadService.removeArchive(from: article)
        } else {
            let success = await offlineDownloadService.archiveForOffline(article)
            if !success {
                // Speichern fehlgeschlagen — vorher lautlos (isArchived false,
                // kein Hinweis). Fehlerdetails stehen in article.offlineErrorMessage.
                offlineArchiveError = OfflineArchiveErrorAlert(
                    message: article.offlineErrorMessage ?? L10n.offlineArchiveErrorMessage
                )
            }
        }

        try? modelContext.save()
    }

    @MainActor
    private func deleteArticle(_ article: Article) {
        if selectedArticle?.persistentModelID == article.persistentModelID {
            selectedArticle = nil
        }

        viewModel.deleteArticle(article, context: modelContext)
    }

}

/// Cache-Key für vorbereitete Artikel. Erfasst alle Status-Änderungen, die das
/// Sortier-/Filterergebnis beeinflussen (Lese-/Stern-/Archiv-Status, Anzahl,
/// Sortierung, Filter). Statusunabhängige Pfade (Suche, "heute", kurze Lesezeit)
/// werden über nil umgangen und nicht gecacht.
private struct PreparedArticlesCacheKey: Equatable, Hashable {
    let articleCount: Int
    let unreadCount: Int
    let starredCount: Int
    let archivedCount: Int
    let sortRawValue: String
    let filterRawValue: String
    let sortArticles: Bool
}

struct ReaderArticlePrefetchPlan {
    static func articles(previousArticle: Article?, nextArticle: Article?) -> [Article] {
        [previousArticle, nextArticle].compactMap { $0 }
    }

    @MainActor
    static func prefetchReaderFields(for articles: [Article]) async {
        for article in articles {
            // Absichtlich leichtgewichtig: Der Reader lädt und parst große
            // Textfelder asynchron erst für den wirklich geöffneten Artikel.
            // Prefetching darf beim schnellen Lesen nicht nebenbei Volltexte
            // Bilder oder Feed-Relationships faulten/decodieren.
            _ = article.feedID
        }
    }
}

struct ReaderArticlePrefetchKey: Equatable {
    let articleIDs: [PersistentIdentifier]

    init(articles: [Article]) {
        self.articleIDs = articles.map(\.persistentModelID)
    }
}

// Identifiable-Wrapper für den Alert bei fehlgeschlagenem Offline-Archivieren.
private struct OfflineArchiveErrorAlert: Identifiable {
    let id = UUID()
    let message: String
}
