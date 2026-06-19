import SwiftUI
import SwiftData

struct ArticleListView: View {
    let feed: Feed
    @Binding var selectedArticle: Article?

    var body: some View {
        List(selection: $selectedArticle) {
            Text("Artikel von \(feed.title) kommen hier hin")
        }
        .navigationTitle(feed.title)
    }
}
