import SwiftUI
import SwiftData

struct ArticleListView: View {
    let feed: Feed
    @Binding var selectedArticle: Article?
    @AppStorage("markArticleReadOnSelection")
    private var markArticleReadOnSelection = true
    @State private var viewModel = ArticleViewModel()

    var body: some View {
        List(selection: $selectedArticle) {
            if sortedArticles.isEmpty {
                ContentUnavailableView(
                    "Keine Artikel",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Dieser Feed hat noch keine gespeicherten Artikel.")
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
        .navigationTitle(feed.title)
        .onChange(of: selectedArticle?.persistentModelID) {
            viewModel.markReadIfNeeded(
                selectedArticle,
                isEnabled: markArticleReadOnSelection
            )
        }
    }

    private var sortedArticles: [Article] {
        feed.articles.sorted {
            ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast)
        }
    }
}
