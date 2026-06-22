import Foundation

enum ReaderOfflineAvailability: Equatable {
    case feedContent
    case summaryOnly
    case empty

    static func resolved(content: String?, summary: String?) -> ReaderOfflineAvailability {
        if hasText(content) {
            return .feedContent
        }

        if hasText(summary) {
            return .summaryOnly
        }

        return .empty
    }

    private static func hasText(_ value: String?) -> Bool {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
}

struct ReaderPreparedArticle {
    let contentBlocks: [ReaderContentBlock]
    let metadataText: String
    let originalURL: URL?
    let offlineAvailability: ReaderOfflineAvailability

    init(article: Article) {
        self.contentBlocks = ReaderContentRenderer.blocks(
            summary: article.summary,
            content: article.content,
            fallbackImageURL: article.imageURL
        )
        self.offlineAvailability = ReaderOfflineAvailability.resolved(
            content: article.content,
            summary: article.summary
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
