import Foundation

enum ReaderContentAvailability: Equatable {
    case fullText
    case feedContent
    case summaryOnly
    case empty

    static func resolved(
        offlineState: ArticleOfflineState,
        offlineContent: String?,
        content: String?,
        summary: String?
    ) -> ReaderContentAvailability {
        if offlineState == .fullText, hasText(offlineContent) {
            return .fullText
        }

        if offlineState == .feedContent, hasText(offlineContent) {
            return .feedContent
        }

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
    let contentAvailability: ReaderContentAvailability
    let shouldShowSummaryOnlyNotice: Bool

    init(article: Article) {
        let preferredContent = ReaderPreparedArticle.preferredContent(for: article)

        self.contentBlocks = ReaderContentRenderer.blocks(
            summary: article.summary,
            content: preferredContent,
            fallbackImageURL: article.imageURL
        )
        self.contentAvailability = ReaderContentAvailability.resolved(
            offlineState: article.offlineState,
            offlineContent: article.offlineContent,
            content: article.content,
            summary: article.summary
        )
        self.shouldShowSummaryOnlyNotice = false

        self.metadataText = ReaderMetadataFormatter.metadataParts(
            feedName: article.feed?.title,
            readingTime: ReaderMetadataFormatter.readingTimeText(
                content: preferredContent,
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

    private static func preferredContent(for article: Article) -> String? {
        if article.offlineState.isAvailable,
           let offlineContent = normalizedText(article.offlineContent) {
            return offlineContent
        }

        return article.content
    }

    private static func normalizedText(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }
}
