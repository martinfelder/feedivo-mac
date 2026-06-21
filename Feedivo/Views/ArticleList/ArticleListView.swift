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

    init(
        feed: Feed,
        selectedArticle: Binding<Article?>,
        navigationState: Binding<ArticleNavigationState>
    ) {
        self.scope = .feed(feed)
        self._selectedArticle = selectedArticle
        self._navigationState = navigationState
    }

    init(
        smartFilter: SmartFilter,
        selectedArticle: Binding<Article?>,
        navigationState: Binding<ArticleNavigationState>
    ) {
        self.scope = .smartFilter(smartFilter)
        self._selectedArticle = selectedArticle
        self._navigationState = navigationState
    }

    init(
        tag: Tag,
        selectedArticle: Binding<Article?>,
        navigationState: Binding<ArticleNavigationState>
    ) {
        self.scope = .tag(tag)
        self._selectedArticle = selectedArticle
        self._navigationState = navigationState
    }

    var body: some View {
        switch scope {
        case .feed(let feed):
            FeedArticleListContent(
                feed: feed,
                selectedArticle: $selectedArticle,
                navigationState: $navigationState
            )
        case .smartFilter(let smartFilter):
            SmartFilterArticleListContent(
                smartFilter: smartFilter,
                selectedArticle: $selectedArticle,
                navigationState: $navigationState
            )
        case .tag(let tag):
            TagArticleListContent(
                tag: tag,
                selectedArticle: $selectedArticle,
                navigationState: $navigationState
            )
        }
    }
}

private struct FeedArticleListContent: View {
    let feed: Feed
    @Binding var selectedArticle: Article?
    @Binding var navigationState: ArticleNavigationState
    @Query private var articles: [Article]

    init(
        feed: Feed,
        selectedArticle: Binding<Article?>,
        navigationState: Binding<ArticleNavigationState>
    ) {
        self.feed = feed
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
            sortArticles: false
        )
    }
}

private struct TagArticleListContent: View {
    let tag: Tag
    @Binding var selectedArticle: Article?
    @Binding var navigationState: ArticleNavigationState
    @Query private var articles: [Article]

    init(
        tag: Tag,
        selectedArticle: Binding<Article?>,
        navigationState: Binding<ArticleNavigationState>
    ) {
        self.tag = tag
        self._selectedArticle = selectedArticle
        self._navigationState = navigationState
        self._articles = Query(
            filter: ArticleListQuery.tagPredicate(for: tag),
            sort: ArticleListQuery.sortDescriptors
        )
    }

    var body: some View {
        ArticleListContent(
            articles: articles,
            navigationTitle: Text(tag.name),
            selectedArticle: $selectedArticle,
            navigationState: $navigationState,
            sortArticles: false
        )
    }
}

private struct SmartFilterArticleListContent: View {
    let smartFilter: SmartFilter
    @Binding var selectedArticle: Article?
    @Binding var navigationState: ArticleNavigationState
    @Query private var articles: [Article]

    init(
        smartFilter: SmartFilter,
        selectedArticle: Binding<Article?>,
        navigationState: Binding<ArticleNavigationState>
    ) {
        self.smartFilter = smartFilter
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
            sortArticles: false
        )
    }
}

private struct ArticleListContent: View {
    let articles: [Article]
    let navigationTitle: Text
    let sortArticles: Bool
    @Binding var selectedArticle: Article?
    @Binding var navigationState: ArticleNavigationState
    @AppStorage("markArticleReadOnSelection")
    private var markArticleReadOnSelection = true
    @State private var viewModel = ArticleViewModel()

    init(
        articles: [Article],
        navigationTitle: Text,
        selectedArticle: Binding<Article?>,
        navigationState: Binding<ArticleNavigationState>,
        sortArticles: Bool = true
    ) {
        self.articles = articles
        self.navigationTitle = navigationTitle
        self._selectedArticle = selectedArticle
        self._navigationState = navigationState
        self.sortArticles = sortArticles
    }

    var body: some View {
        let articles = sortedArticles

        List(selection: $selectedArticle) {
            if articles.isEmpty {
                ContentUnavailableView(
                    L10n.articleListEmptyTitle,
                    systemImage: "doc.text.magnifyingglass",
                    description: Text(L10n.articleListEmptyDescription)
                )
            } else {
                ForEach(articles) { article in
                    ArticleRowView(
                        article: article,
                        onToggleRead: {
                            viewModel.toggleRead(article)
                        },
                        onToggleStarred: {
                            viewModel.toggleStarred(article)
                        },
                        onCopyLink: {
                            _ = viewModel.copyLink(article)
                        },
                        onOpenOriginal: {
                            _ = viewModel.openOriginal(article)
                        }
                    )
                    .tag(article)
                }
            }
        }
        .navigationTitle(navigationTitle)
        .onAppear {
            updateNavigationState(in: articles)
        }
        .onChange(of: articles) {
            updateNavigationState(in: articles)
        }
        .onChange(of: selectedArticle?.persistentModelID) {
            updateNavigationState(in: articles)
            viewModel.markReadIfNeeded(
                selectedArticle,
                isEnabled: markArticleReadOnSelection
            )
        }
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

}
