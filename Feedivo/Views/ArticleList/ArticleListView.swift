import SwiftUI
import SwiftData

struct ArticleListView: View {
    private enum Scope {
        case feed(Feed)
        case smartFilter(SmartFilter)
        case tag(Tag)
    }

    private let scope: Scope
    @Binding var selectedArticle: Article?
    @Binding var navigationState: ArticleNavigationState
    private let onRequestCreateRuleFromArticle: (Article) -> Void

    init(
        feed: Feed,
        selectedArticle: Binding<Article?>,
        navigationState: Binding<ArticleNavigationState>,
        onRequestCreateRuleFromArticle: @escaping (Article) -> Void = { _ in }
    ) {
        self.scope = .feed(feed)
        self._selectedArticle = selectedArticle
        self._navigationState = navigationState
        self.onRequestCreateRuleFromArticle = onRequestCreateRuleFromArticle
    }

    init(
        smartFilter: SmartFilter,
        selectedArticle: Binding<Article?>,
        navigationState: Binding<ArticleNavigationState>,
        onRequestCreateRuleFromArticle: @escaping (Article) -> Void = { _ in }
    ) {
        self.scope = .smartFilter(smartFilter)
        self._selectedArticle = selectedArticle
        self._navigationState = navigationState
        self.onRequestCreateRuleFromArticle = onRequestCreateRuleFromArticle
    }

    init(
        tag: Tag,
        selectedArticle: Binding<Article?>,
        navigationState: Binding<ArticleNavigationState>,
        onRequestCreateRuleFromArticle: @escaping (Article) -> Void = { _ in }
    ) {
        self.scope = .tag(tag)
        self._selectedArticle = selectedArticle
        self._navigationState = navigationState
        self.onRequestCreateRuleFromArticle = onRequestCreateRuleFromArticle
    }

    var body: some View {
        switch scope {
        case .feed(let feed):
            FeedArticleListContent(
                feed: feed,
                selectedArticle: $selectedArticle,
                navigationState: $navigationState,
                onRequestCreateRuleFromArticle: onRequestCreateRuleFromArticle
            )
        case .smartFilter(let smartFilter):
            SmartFilterArticleListContent(
                smartFilter: smartFilter,
                selectedArticle: $selectedArticle,
                navigationState: $navigationState,
                onRequestCreateRuleFromArticle: onRequestCreateRuleFromArticle
            )
        case .tag(let tag):
            TagArticleListContent(
                tag: tag,
                selectedArticle: $selectedArticle,
                navigationState: $navigationState,
                onRequestCreateRuleFromArticle: onRequestCreateRuleFromArticle
            )
        }
    }
}

private struct FeedArticleListContent: View {
    let feed: Feed
    let onRequestCreateRuleFromArticle: (Article) -> Void
    @Binding var selectedArticle: Article?
    @Binding var navigationState: ArticleNavigationState
    @Query private var articles: [Article]

    init(
        feed: Feed,
        selectedArticle: Binding<Article?>,
        navigationState: Binding<ArticleNavigationState>,
        onRequestCreateRuleFromArticle: @escaping (Article) -> Void
    ) {
        self.feed = feed
        self.onRequestCreateRuleFromArticle = onRequestCreateRuleFromArticle
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
            sortArticles: false
        )
        .id(feed.id)
    }
}

private struct TagArticleListContent: View {
    let tag: Tag
    let onRequestCreateRuleFromArticle: (Article) -> Void
    @Binding var selectedArticle: Article?
    @Binding var navigationState: ArticleNavigationState
    @Query private var articles: [Article]

    init(
        tag: Tag,
        selectedArticle: Binding<Article?>,
        navigationState: Binding<ArticleNavigationState>,
        onRequestCreateRuleFromArticle: @escaping (Article) -> Void
    ) {
        self.tag = tag
        self.onRequestCreateRuleFromArticle = onRequestCreateRuleFromArticle
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
            sortArticles: false
        )
        .id(tag.id)
    }
}

private struct SmartFilterArticleListContent: View {
    let smartFilter: SmartFilter
    let onRequestCreateRuleFromArticle: (Article) -> Void
    @Binding var selectedArticle: Article?
    @Binding var navigationState: ArticleNavigationState
    @Query private var articles: [Article]

    init(
        smartFilter: SmartFilter,
        selectedArticle: Binding<Article?>,
        navigationState: Binding<ArticleNavigationState>,
        onRequestCreateRuleFromArticle: @escaping (Article) -> Void
    ) {
        self.smartFilter = smartFilter
        self.onRequestCreateRuleFromArticle = onRequestCreateRuleFromArticle
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
        }
    }

    var body: some View {
        ArticleListContent(
            articles: articles,
            navigationTitle: Text(smartFilter.title),
            selectedArticle: $selectedArticle,
            navigationState: $navigationState,
            onRequestCreateRuleFromArticle: onRequestCreateRuleFromArticle,
            sortArticles: false
        )
        .id(smartFilter)
    }
}

private struct ArticleListContent: View {
    @Environment(\.modelContext) private var modelContext
    let articles: [Article]
    let navigationTitle: Text
    let onRequestCreateRuleFromArticle: (Article) -> Void
    let sortArticles: Bool
    @Binding var selectedArticle: Article?
    @Binding var navigationState: ArticleNavigationState
    @Query(sort: \Tag.name) private var tags: [Tag]
    @AppStorage("markArticleReadOnSelection")
    private var markArticleReadOnSelection = true
    @State private var viewModel = ArticleViewModel()
    @State private var offlineDownloadService = OfflineDownloadService()
    @State private var showsReadArticles = false

    init(
        articles: [Article],
        navigationTitle: Text,
        selectedArticle: Binding<Article?>,
        navigationState: Binding<ArticleNavigationState>,
        onRequestCreateRuleFromArticle: @escaping (Article) -> Void,
        sortArticles: Bool = true
    ) {
        self.articles = articles
        self.navigationTitle = navigationTitle
        self.onRequestCreateRuleFromArticle = onRequestCreateRuleFromArticle
        self._selectedArticle = selectedArticle
        self._navigationState = navigationState
        self.sortArticles = sortArticles
    }

    var body: some View {
        let sortedArticles = sortedArticles
        let displayState = ArticleListDisplayState(
            articles: sortedArticles,
            showsReadArticles: showsReadArticles,
            selectedArticle: selectedArticle
        )
        let visibleArticles = displayState.visibleArticles

        List(selection: $selectedArticle) {
            if sortedArticles.isEmpty {
                ContentUnavailableView(
                    L10n.articleListEmptyTitle,
                    systemImage: "doc.text.magnifyingglass",
                    description: Text(L10n.articleListEmptyDescription)
                )
            } else {
                ForEach(visibleArticles) { article in
                    ArticleRowView(
                        article: article,
                        availableTags: ArticleMetadataEditor.availableTagsToAdd(
                            to: article,
                            availableTags: tags
                        ),
                        onToggleRead: {
                            viewModel.toggleRead(article)
                        },
                        onToggleStarred: {
                            viewModel.toggleStarred(article)
                        },
                        onToggleArchived: {
                            viewModel.toggleArchived(article)
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
                    .tag(article)
                }

                if displayState.shouldShowReadArticlesButton {
                    showReadArticlesButton(count: displayState.hiddenReadArticleCount)
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
        .onChange(of: selectedArticle?.persistentModelID) {
            let displayState = ArticleListDisplayState(
                articles: sortedArticles,
                showsReadArticles: showsReadArticles,
                selectedArticle: selectedArticle
            )
            updateNavigationState(in: displayState.visibleArticles)
            viewModel.markReadIfNeeded(
                selectedArticle,
                isEnabled: markArticleReadOnSelection
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

    private var sortedArticles: [Article] {
        guard sortArticles else {
            return articles
        }

        return viewModel.sortedForList(articles)
    }

    private func updateNavigationState(in articles: [Article]) {
        navigationState = ArticleNavigationState(
            articles: articles,
            selectedArticle: selectedArticle,
            sortArticles: { $0 }
        )
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
    private func deleteArticle(_ article: Article) {
        if selectedArticle?.persistentModelID == article.persistentModelID {
            selectedArticle = nil
        }

        viewModel.deleteArticle(article, context: modelContext)
    }

}
