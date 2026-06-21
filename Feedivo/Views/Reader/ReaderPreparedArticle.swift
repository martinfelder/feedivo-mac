import Foundation

struct ReaderPreparedArticle {
    let contentBlocks: [ReaderContentBlock]
    let metadataText: String
    let originalURL: URL?

    init(article: Article) {
        self.contentBlocks = ReaderContentRenderer.blocks(
            summary: article.summary,
            content: article.content,
            fallbackImageURL: article.imageURL
        )

        self.metadataText = ReaderMetadataFormatter.metadataParts(
            feedName: article.feed?.title,
            readingTime: ReaderMetadataFormatter.readingTimeText(
                content: article.content,
                summary: article.summary
            ),
            publishedAt: article.publishedAt
        )
        .joined(separator: " · ")

        if let link = article.link, let url = URL(string: link), url.scheme != nil {
            self.originalURL = url
        } else {
            self.originalURL = nil
        }
    }
}
