import SwiftUI
import SwiftData

struct ArticleListView: View {
    private enum Scope {
        case feed(Feed)
        case smartFilter(SmartFilter)
    }

    private let scope: Scope
    @Binding var selectedArticle: Article?
    @Binding var visibleArticles: [Article]

    init(
        feed: Feed,
        selectedArticle: Binding<Article?>,
        visibleArticles: Binding<[Article]>
    ) {
        self.scope = .feed(feed)
        self._selectedArticle = selectedArticle
        self._visibleArticles = visibleArticles
    }

    init(
        smartFilter: SmartFilter,
        selectedArticle: Binding<Article?>,
        visibleArticles: Binding<[Article]>
    ) {
        self.scope = .smartFilter(smartFilter)
        self._selectedArticle = selectedArticle
        self._visibleArticles = visibleArticles
    }

    var body: some View {
        switch scope {
        case .feed(let feed):
            ArticleListContent(
                articles: feed.articles,
                navigationTitle: Text(feed.title),
                selectedArticle: $selectedArticle,
                visibleArticles: $visibleArticles
            )
        case .smartFilter(let smartFilter):
            SmartFilterArticleListContent(
                smartFilter: smartFilter,
                selectedArticle: $selectedArticle,
                visibleArticles: $visibleArticles
            )
        }
    }
}

private struct SmartFilterArticleListContent: View {
    let smartFilter: SmartFilter
    @Binding var selectedArticle: Article?
    @Binding var visibleArticles: [Article]
    @Query private var articles: [Article]

    init(
        smartFilter: SmartFilter,
        selectedArticle: Binding<Article?>,
        visibleArticles: Binding<[Article]>
    ) {
        self.smartFilter = smartFilter
        self._selectedArticle = selectedArticle
        self._visibleArticles = visibleArticles

        let sortDescriptors = [SortDescriptor(\Article.publishedAt, order: .reverse)]
        switch smartFilter {
        case .allArticles:
            self._articles = Query(sort: sortDescriptors)
        case .unread:
            self._articles = Query(
                filter: #Predicate<Article> { article in
                    !article.isRead
                },
                sort: sortDescriptors
            )
        case .starred:
            self._articles = Query(
                filter: #Predicate<Article> { article in
                    article.isStarred
                },
                sort: sortDescriptors
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
                sort: sortDescriptors
            )
        }
    }

    var body: some View {
        ArticleListContent(
            articles: articles,
            navigationTitle: Text(smartFilter.title),
            selectedArticle: $selectedArticle,
            visibleArticles: $visibleArticles,
            sortArticles: false
        )
    }
}

private struct ArticleListContent: View {
    let articles: [Article]
    let navigationTitle: Text
    let sortArticles: Bool
    @Binding var selectedArticle: Article?
    @Binding var visibleArticles: [Article]
    @AppStorage("markArticleReadOnSelection")
    private var markArticleReadOnSelection = true
    @State private var viewModel = ArticleViewModel()

    init(
        articles: [Article],
        navigationTitle: Text,
        selectedArticle: Binding<Article?>,
        visibleArticles: Binding<[Article]>,
        sortArticles: Bool = true
    ) {
        self.articles = articles
        self.navigationTitle = navigationTitle
        self._selectedArticle = selectedArticle
        self._visibleArticles = visibleArticles
        self.sortArticles = sortArticles
    }

    var body: some View {
        let articles = sortedArticles
        let articleIDs = articles.map(\.id)

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
            visibleArticles = articles
        }
        .onChange(of: articleIDs) {
            visibleArticles = articles
        }
        .onChange(of: selectedArticle?.persistentModelID) {
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

}
