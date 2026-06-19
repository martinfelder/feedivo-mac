import SwiftUI
import SwiftData

struct ArticleListView: View {
    let feed: Feed
    @Binding var selectedArticle: Article?

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
                    VStack(alignment: .leading, spacing: 4) {
                        Text(article.title)
                            .font(.headline)
                            .lineLimit(2)

                        if let summary = article.summary, !summary.isEmpty {
                            Text(summary)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 4)
                    .tag(article)
                }
            }
        }
        .navigationTitle(feed.title)
    }

    private var sortedArticles: [Article] {
        feed.articles.sorted {
            ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast)
        }
    }
}
