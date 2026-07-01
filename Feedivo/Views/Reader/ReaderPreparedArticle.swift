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

/// Reine, Sendable-faehige Eingabewerte fuer den Reader. Werden einmal auf dem
/// MainActor aus dem SwiftData-Modell extrahiert, damit das teure Parsing
/// (`ReaderContentRenderer.blocks`, Lesezeit-Berechnung) unabhaengig vom
/// MainActor — typischerweise in einem `Task.detached` — laufen kann, ohne das
/// UI-Thread zu blockieren.
struct ReaderArticleInput: Sendable {
    let summary: String?
    let content: String?
    let imageURL: String?
    let offlineContent: String?
    let offlineState: ArticleOfflineState
    let offlineStateRaw: String?
    let link: String?
    let feedTitle: String?
    let publishedAt: Date?
}

extension ReaderArticleInput {
    @MainActor
    static func make(from article: Article) -> ReaderArticleInput {
        ReaderArticleInput(
            summary: article.summary,
            content: article.content,
            imageURL: article.imageURL,
            offlineContent: article.offlineContent,
            offlineState: article.offlineState,
            offlineStateRaw: article.offlineStateRaw,
            link: article.link,
            feedTitle: article.feed?.title,
            publishedAt: article.publishedAt
        )
    }

    @MainActor
    static func makePreview(from article: Article) -> ReaderArticleInput {
        ReaderArticleInput(
            summary: article.summary,
            content: nil,
            imageURL: article.imageURL,
            offlineContent: nil,
            offlineState: .none,
            offlineStateRaw: ArticleOfflineState.none.rawValue,
            link: article.link,
            feedTitle: nil,
            publishedAt: article.publishedAt
        )
    }
}

/// Leichte Signatur für Reader-Updates. Sie fasst nur Felder an, die in den
/// Listen-Fetches ohnehin geladen sind. Die großen Textfelder `content` und
/// `offlineContent` bleiben bewusst draußen, damit ein Artikelwechsel nicht
/// schon beim SwiftUI-View-Aufbau schwere SwiftData-Faults auslöst.
struct ReaderArticleObservationSignature: Equatable {
    let summary: String?
    let imageURL: String?
    let offlineStateRaw: String
    let offlineRequestedAt: Date?
    let offlineSavedAt: Date?
    let offlineErrorMessage: String?

    static func make(from article: Article) -> ReaderArticleObservationSignature {
        ReaderArticleObservationSignature(
            summary: article.summary,
            imageURL: article.imageURL,
            offlineStateRaw: article.offlineStateRaw,
            offlineRequestedAt: article.offlineRequestedAt,
            offlineSavedAt: article.offlineSavedAt,
            offlineErrorMessage: article.offlineErrorMessage
        )
    }
}

struct ReaderPreparedArticle: Sendable {
    let contentBlocks: [ReaderContentBlock]
    let metadataText: String
    let originalURL: URL?
    let contentAvailability: ReaderContentAvailability
    let shouldShowSummaryOnlyNotice: Bool

    /// Leerer Platzhalter fuer den ersten Render, bevor die asynchrone
    /// Vorbereitung fertig ist. Vermeidet, dass der teure Parse schon im
    /// `ReaderView.init` synchron laufen muss.
    static let empty = ReaderPreparedArticle(
        input: ReaderArticleInput(
            summary: nil,
            content: nil,
            imageURL: nil,
            offlineContent: nil,
            offlineState: .none,
            offlineStateRaw: nil,
            link: nil,
            feedTitle: nil,
            publishedAt: nil
        )
    )

    init(article: Article) {
        // Synchroner Pfad fuer Tests und Diagnose; extrahiert die Werte aus dem
        // Modell und parst danach ueber den reinen Eingabe-Initializer.
        self.init(input: ReaderArticleInput.make(from: article))
    }

    /// Reiner, thread-sicherer Build aus bereits extrahierten Eingabewerten.
    /// Hier laeuft das HTML-Parsing und die Lesezeit-Berechnung — darf vom
    /// MainActor entkoppelt ausgefuehrt werden.
    init(input: ReaderArticleInput) {
        let preferredContent = ReaderPreparedArticle.preferredContent(for: input)

        self.contentBlocks = ReaderContentRenderer.blocks(
            summary: input.summary,
            content: preferredContent,
            fallbackImageURL: input.imageURL
        )
        self.contentAvailability = ReaderContentAvailability.resolved(
            offlineState: input.offlineState,
            offlineContent: input.offlineContent,
            content: input.content,
            summary: input.summary
        )
        self.shouldShowSummaryOnlyNotice = false

        self.metadataText = ReaderMetadataFormatter.metadataParts(
            feedName: input.feedTitle,
            readingTime: ReaderMetadataFormatter.readingTimeText(
                content: preferredContent,
                summary: input.summary
            ),
            publishedAt: input.publishedAt
        )
        .joined(separator: " · ")

        if let link = input.link, let url = URL(string: link), url.scheme != nil {
            self.originalURL = url
        } else {
            self.originalURL = nil
        }
    }

    private static func preferredContent(for input: ReaderArticleInput) -> String? {
        if input.offlineState.isAvailable,
           let offlineContent = normalizedText(input.offlineContent) {
            return offlineContent
        }

        return input.content
    }

    private static func normalizedText(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }
}

/// Cache-Schlüssel aus den inhaltsbestimmenden Feldern. Sind alle Felder
/// identisch, liefert der Reader dasselbe Ergebnis — dann kann der Parse
/// übersprungen werden (Hebel 5). Content-Änderungen durch Refresh führen zu
/// einem anderen Schlüssel -> Cache-Miss -> neu parsen.
struct ReaderArticleCacheKey: Hashable, Sendable {
    let summary: String?
    let content: String?
    let imageURL: String?
    let offlineContent: String?
    let offlineStateRaw: String?
    let link: String?
    let feedTitle: String?
    let publishedAt: Date?
}

extension ReaderArticleInput {
    var cacheKey: ReaderArticleCacheKey {
        ReaderArticleCacheKey(
            summary: summary,
            content: content,
            imageURL: imageURL,
            offlineContent: offlineContent,
            offlineStateRaw: offlineStateRaw,
            link: link,
            feedTitle: feedTitle,
            publishedAt: publishedAt
        )
    }
}

/// MainActor-isolierter, grössenbegrenzter Cache für bereits geparste
/// Reader-Artikel. Hält die letzten ~24 Einträge, damit Vor-/Zurück-
/// Navigation zwischen kürzlich gelesenen Artikeln ohne erneutes Parsen
/// sofort anzeigt.
@MainActor
final class ReaderPreparedArticleCache {
    static let shared = ReaderPreparedArticleCache()

    private let limit = 24
    private var entries: [ReaderArticleCacheKey: ReaderPreparedArticle] = [:]
    private var insertionOrder: [ReaderArticleCacheKey] = []

    func prepared(for input: ReaderArticleInput) -> ReaderPreparedArticle? {
        entries[input.cacheKey]
    }

    func store(_ prepared: ReaderPreparedArticle, for input: ReaderArticleInput) {
        let key = input.cacheKey

        if entries[key] == nil {
            if insertionOrder.count >= limit, let oldest = insertionOrder.first {
                entries.removeValue(forKey: oldest)
                insertionOrder.removeFirst()
            }
            insertionOrder.append(key)
        }

        entries[key] = prepared
    }
}
