import SwiftUI
import SwiftData

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
        case .smartFilter(let smartFilter):
            SmartFilterArticleListContent(
                smartFilter: smartFilter,
                selectedArticle: $selectedArticle,
                navigationState: $navigationState,
                onRequestCreateRuleFromArticle: onRequestCreateRuleFromArticle,
                onRequestExportArticle: onRequestExportArticle
            )
        case .tag(let tag):
            TagArticleListContent(
                tag: tag,
                selectedArticle: $selectedArticle,
                navigationState: $navigationState,
                onRequestCreateRuleFromArticle: onRequestCreateRuleFromArticle,
                onRequestExportArticle: onRequestExportArticle
            )
        case .smartFolder(let smartFolder):
            SmartFolderArticleListContent(
                smartFolder: smartFolder,
                selectedArticle: $selectedArticle,
                navigationState: $navigationState,
                onRequestCreateRuleFromArticle: onRequestCreateRuleFromArticle,
                onRequestExportArticle: onRequestExportArticle
            )
        }
    }
}

private struct FeedArticleListContent: View {
    let feed: Feed
    let onRequestCreateRuleFromArticle: (Article) -> Void
    let onRequestExportArticle: (Article) -> Void
    @Binding var selectedArticle: Article?
    @Binding var navigationState: ArticleNavigationState
    @Query private var articles: [Article]

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
        self._articles = Query(
            filter: ArticleListQuery.feedPredicate(for: feed),
            sort: ArticleListQuery.sortDescriptors
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
            showsHiddenArticles: false
        )
        .id(feed.id)
    }
}

private struct TagArticleListContent: View {
    let tag: Tag
    let onRequestCreateRuleFromArticle: (Article) -> Void
    let onRequestExportArticle: (Article) -> Void
    @Binding var selectedArticle: Article?
    @Binding var navigationState: ArticleNavigationState
    @Query private var articles: [Article]

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
        self._articles = Query(
            filter: ArticleListQuery.tagPredicate(for: tag, taggedFeeds: tag.feeds),
            sort: ArticleListQuery.sortDescriptors
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
            showsHiddenArticles: false
        )
        .id(tag.id)
    }
}

private struct SmartFilterArticleListContent: View {
    let smartFilter: SmartFilter
    let onRequestCreateRuleFromArticle: (Article) -> Void
    let onRequestExportArticle: (Article) -> Void
    @Binding var selectedArticle: Article?
    @Binding var navigationState: ArticleNavigationState
    @Query private var articles: [Article]

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

        switch smartFilter {
        case .allArticles:
            self._articles = Query(sort: ArticleListQuery.sortDescriptors)
        case .unread:
            self._articles = Query(
                filter: #Predicate<Article> { article in
                    !article.isRead
                },
                sort: ArticleListQuery.sortDescriptors
            )
        case .starred:
            self._articles = Query(
                filter: #Predicate<Article> { article in
                    article.isStarred
                },
                sort: ArticleListQuery.sortDescriptors
            )
        case .today:
            let startOfToday = Calendar.current.startOfDay(for: Date())
            let startOfTomorrow = Calendar.current.date(
                byAdding: .day,
                value: 1,
                to: startOfToday
            ) ?? startOfToday
            self._articles = Query(
                filter: #Predicate<Article> { article in
                    article.publishedAt != nil
                        && article.publishedAt! >= startOfToday
                        && article.publishedAt! < startOfTomorrow
                },
                sort: ArticleListQuery.sortDescriptors
            )
        case .hidden:
            self._articles = Query(
                filter: #Predicate<Article> { article in
                    article.isHidden
                },
                sort: ArticleListQuery.sortDescriptors
            )
        }
    }

    var body: some View {
        ArticleListContent(
            articles: articles,
            navigationTitle: Text(smartFilter.title),
            selectedArticle: $selectedArticle,
            navigationState: $navigationState,
            onRequestCreateRuleFromArticle: onRequestCreateRuleFromArticle,
            onRequestExportArticle: onRequestExportArticle,
            showsHiddenArticles: smartFilter == .hidden
        )
        .id(smartFilter)
    }
}

private struct SmartFolderArticleListContent: View {
    let smartFolder: SmartFolder
    let onRequestCreateRuleFromArticle: (Article) -> Void
    let onRequestExportArticle: (Article) -> Void
    private let usesOptimizedQuery: Bool
    @Binding var selectedArticle: Article?
    @Binding var navigationState: ArticleNavigationState
    @Query private var articles: [Article]

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

        if let descriptor = ArticleListQuery.smartFolderFetchDescriptor(for: smartFolder) {
            self.usesOptimizedQuery = true
            self._articles = Query(descriptor)
        } else {
            self.usesOptimizedQuery = false
            self._articles = Query(sort: ArticleListQuery.sortDescriptors)
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
            showsHiddenArticles: SmartFolderFormatter.includesHiddenStatus(smartFolder)
        )
        .id(smartFolder.id)
    }

    private var displayedArticles: [Article] {
        usesOptimizedQuery
            ? articles
            : SmartFolderEngine.matchingArticles(folder: smartFolder, articles: articles)
    }
}

private struct ArticleListContent: View {
    @Environment(\.modelContext) private var modelContext
    let articles: [Article]
    let navigationTitle: Text
    let onRequestCreateRuleFromArticle: (Article) -> Void
    let onRequestExportArticle: (Article) -> Void
    let sortArticles: Bool
    let showsHiddenArticles: Bool
    @Binding var selectedArticle: Article?
    @Binding var navigationState: ArticleNavigationState
    @Query(sort: \Tag.name) private var tags: [Tag]
    @AppStorage("markArticleReadOnSelection")
    private var markArticleReadOnSelection = true
    @State private var viewModel = ArticleViewModel()
    @State private var offlineDownloadService = OfflineDownloadService()
    @State private var showsReadArticles = false
    @State private var temporarilyVisibleReadArticleIDs = Set<PersistentIdentifier>()
    @AppStorage(ArticleSortOption.storageKey)
    private var articleSortRawValue = ArticleSortOption.newestFirst.rawValue
    @AppStorage(ArticleFilterOption.storageKey)
    private var articleFilterRawValue = ArticleFilterOption.all.rawValue

    init(
        articles: [Article],
        navigationTitle: Text,
        selectedArticle: Binding<Article?>,
        navigationState: Binding<ArticleNavigationState>,
        onRequestCreateRuleFromArticle: @escaping (Article) -> Void,
        onRequestExportArticle: @escaping (Article) -> Void,
        sortArticles: Bool = true,
        showsHiddenArticles: Bool = false
    ) {
        self.articles = articles
        self.navigationTitle = navigationTitle
        self.onRequestCreateRuleFromArticle = onRequestCreateRuleFromArticle
        self.onRequestExportArticle = onRequestExportArticle
        self._selectedArticle = selectedArticle
        self._navigationState = navigationState
        self.sortArticles = sortArticles
        self.showsHiddenArticles = showsHiddenArticles
    }

    var body: some View {
        let preparedArticles = makePreparedArticles()
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

        List(selection: $selectedArticle) {
            if filteredArticles.isEmpty {
                ContentUnavailableView(
                    L10n.articleListEmptyTitle,
                    systemImage: "doc.text.magnifyingglass",
                    description: Text(L10n.articleListEmptyDescription)
                )
            } else {
                ForEach(visibleArticles) { article in
                    articleRow(article, visibleArticles: visibleArticles)
                        .tag(article)
                }

                if displaySnapshot.shouldShowReadArticlesButton {
                    showReadArticlesButton(count: displaySnapshot.hiddenReadArticleCount)
                }
            }
        }
        .navigationTitle(navigationTitle)
        .onAppear {
            updateNavigationState(in: visibleArticles)
        }
        .onChange(of: visibleArticles) {
            updateNavigationState(in: visibleArticles)
        }
        .onChange(of: articleSortRawValue) {
            let preparedArticles = makePreparedArticles()
            let displayState = ArticleListDisplayState(
                articles: preparedArticles.filtered,
                showsReadArticles: showsReadArticles,
                selectedArticle: selectedArticle,
                showsHiddenArticles: showsHiddenArticles,
                temporarilyVisibleReadArticleIDs: temporarilyVisibleReadArticleIDs
            )
            updateNavigationState(in: displayState.visibleArticles)
        }
        .onChange(of: articleFilterRawValue) {
            let preparedArticles = makePreparedArticles()
            let displayState = ArticleListDisplayState(
                articles: preparedArticles.filtered,
                showsReadArticles: showsReadArticles,
                selectedArticle: selectedArticle,
                showsHiddenArticles: showsHiddenArticles,
                temporarilyVisibleReadArticleIDs: temporarilyVisibleReadArticleIDs
            )
            updateNavigationState(in: displayState.visibleArticles)
        }
        .onChange(of: selectedArticle?.persistentModelID) {
            rememberAutoReadArticleIfNeeded(selectedArticle)

            updateNavigationState(in: visibleArticles)
            viewModel.markReadIfNeeded(
                selectedArticle,
                isEnabled: markArticleReadOnSelection
            )
        }
        .toolbar {
            ToolbarItemGroup {
                markReadMenu(visibleArticles: visibleArticles)
                filterMenu
                sortMenu
            }
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

    private func articleRow(_ article: Article, visibleArticles: [Article]) -> ArticleRowView {
        ArticleRowView(
            article: article,
            availableTags: tags,
            onToggleRead: {
                viewModel.toggleRead(article)
            },
            onToggleStarred: {
                viewModel.toggleStarred(article)
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
                viewModel.markAllRead(visibleArticles)
                try? modelContext.save()
            }
        )
    }

    private func makePreparedArticles() -> ArticleListPreparedArticles {
        ArticleListPreparedArticles.prepare(
            articles: articles,
            sortArticles: sortArticles,
            filterOption: articleFilterOption,
            sorter: articleSortOption.sorted
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
                let matchingArticles = option.matchingArticles(in: visibleArticles)

                Button {
                    markRead(visibleArticles, matching: option)
                } label: {
                    Text(option.label)
                }
                .disabled(matchingArticles.isEmpty)
            }
        } label: {
            Label(L10n.articleMarkReadMenuTitle, systemImage: "checkmark.circle")
        }
        .help(L10n.articleMarkReadMenuTitle)
    }

    private func markRead(_ articles: [Article], matching option: ArticleMarkReadOption) {
        viewModel.markRead(articles, matching: option)
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

    private func updateNavigationState(in articles: [Article]) {
        navigationState = ArticleNavigationState(
            articles: articles,
            selectedArticle: selectedArticle,
            sortArticles: { $0 }
        )
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
            await offlineDownloadService.archiveForOffline(article)
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
