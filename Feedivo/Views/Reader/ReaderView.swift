import SwiftUI

struct ReaderView: View {
    let article: Article

    var body: some View {
        ScrollView {
            Text(article.title)
                .font(.title)
                .padding()
        }
        .navigationTitle(article.title)
    }
}
