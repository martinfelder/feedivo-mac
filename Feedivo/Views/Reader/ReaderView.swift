import SwiftUI

struct ReaderView: View {
    let article: Article

    private var contentBlocks: [ReaderContentBlock] {
        ReaderContentRenderer.blocks(
            summary: article.summary,
            content: article.content,
            fallbackImageURL: article.imageURL
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(article.title)
                    .font(.largeTitle)
                    .fontWeight(.bold)

                ForEach(Array(contentBlocks.enumerated()), id: \.offset) { _, block in
                    switch block {
                    case .paragraph(let text):
                        Text(text)
                            .font(.body)
                            .lineSpacing(4)
                            .textSelection(.enabled)
                    case .image(let urlString):
                        readerImage(urlString: urlString)
                    }
                }

                if let link = article.link, let url = URL(string: link) {
                    Link(L10n.readerOpenOriginal, destination: url)
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding()
        }
        .navigationTitle(article.title)
    }

    @ViewBuilder
    private func readerImage(urlString: String) -> some View {
        if let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                case .failure:
                    EmptyView()
                case .empty:
                    ProgressView()
                @unknown default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}
