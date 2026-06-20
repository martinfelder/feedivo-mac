import SwiftUI
import SwiftData

struct ArticleListView: View {
    private enum Scope {
        case feed(Feed)
        case smartFilter(SmartFilter)
    }

    private let scope: Scope
    @Binding var selectedArticle: Article?
    @Query private var allArticles: [Article]
    @AppStorage("markArticleReadOnSelection")
    private var markArticleReadOnSelection = true
    @State private var viewModel = ArticleViewModel()

    init(feed: Feed, selectedArticle: Binding<Article?>) {
        self.scope = .feed(feed)
        self._selectedArticle = selectedArticle
    }

    init(smartFilter: SmartFilter, selectedArticle: Binding<Article?>) {
        self.scope = .smartFilter(smartFilter)
        self._selectedArticle = selectedArticle
    }

    var body: some View {
        List(selection: $selectedArticle) {
            if sortedArticles.isEmpty {
                ContentUnavailableView(
                    L10n.articleListEmptyTitle,
                    systemImage: "doc.text.magnifyingglass",
                    description: Text(L10n.articleListEmptyDescription)
                )
            } else {
                ForEach(sortedArticles) { article in
                    ArticleRowView(
                        article: article,
                        onToggleRead: {
                            viewModel.toggleRead(article)
                        },
                        onToggleStarred: {
                            viewModel.toggleStarred(article)
                        }
                    )
                    .tag(article)
                }
            }
        }
        .navigationTitle(navigationTitle)
        .onChange(of: selectedArticle?.persistentModelID) {
            viewModel.markReadIfNeeded(
                selectedArticle,
                isEnabled: markArticleReadOnSelection
            )
        }
    }

    private var sortedArticles: [Article] {
        scopedArticles.sorted {
            ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast)
        }
    }

    private var scopedArticles: [Article] {
        switch scope {
        case .feed(let feed):
            return feed.articles
        case .smartFilter(let smartFilter):
            return allArticles.filter { smartFilter.includes($0) }
        }
    }

    private var navigationTitle: Text {
        switch scope {
        case .feed(let feed):
            return Text(feed.title)
        case .smartFilter(let smartFilter):
            return Text(smartFilter.title)
        }
    }
}
