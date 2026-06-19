import SwiftUI

struct ReaderView: View {
    let article: Article

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(article.title)
                    .font(.largeTitle)
                    .fontWeight(.bold)

                if let summary = article.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                if let content = article.content, !content.isEmpty {
                    Text(content)
                        .font(.body)
                        .textSelection(.enabled)
                }

                if let link = article.link, let url = URL(string: link) {
                    Link("Original öffnen", destination: url)
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding()
        }
        .navigationTitle(article.title)
    }
}
