import Foundation
import SwiftData

enum ReaderContentAvailability: Equatable {
    case fullText
    case feedContent
    case summaryOnly
    case empty

    static func resolved(
        content: String?,
        summary: String?
    ) -> ReaderContentAvailability {
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
    let contentFingerprint: ReaderArticleTextFingerprint?
    let imageURL: String?
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
            contentFingerprint: ReaderArticleTextFingerprint.make(from: article.content),
            imageURL: article.imageURL,
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
            contentFingerprint: nil,
            imageURL: article.imageURL,
            link: article.link,
            feedTitle: article.feed?.title,
            publishedAt: article.publishedAt
        )
    }

    static func make(from snapshot: ArticleReaderSnapshot) -> ReaderArticleInput {
        ReaderArticleInput(
            summary: snapshot.summary,
            content: snapshot.content,
            contentFingerprint: ReaderArticleTextFingerprint.make(from: snapshot.content),
            imageURL: snapshot.imageURL,
            link: snapshot.link,
            feedTitle: snapshot.feedTitle,
            publishedAt: snapshot.publishedAt
        )
    }
}

enum ReaderArticleContentLoader {
    static func loadInput(
        articleID: UUID,
        modelContainer: ModelContainer
    ) async -> ReaderArticleInput? {
        await Task.detached(priority: .userInitiated) {
            let context = ModelContext(modelContainer)
            var descriptor = FetchDescriptor<Article>(
                predicate: #Predicate<Article> { article in
                    article.id == articleID
                }
            )
            descriptor.fetchLimit = 1

            guard let article = try? context.fetch(descriptor).first else {
                return nil
            }

            let content = article.content
            return ReaderArticleInput(
                summary: article.summary,
                content: content,
                contentFingerprint: ReaderArticleTextFingerprint.make(from: content),
                imageURL: article.imageURL,
                link: article.link,
                feedTitle: article.feed?.title,
                publishedAt: article.publishedAt
            )
        }.value
    }
}

/// Leichte Signatur für Reader-Updates. Sie fasst nur Felder an, die in den
/// Listen-Fetches ohnehin geladen sind. Das große Textfeld `content` bleibt
/// bewusst draußen, damit ein Artikelwechsel nicht schon beim SwiftUI-View-
/// Aufbau schwere SwiftData-Faults auslöst.
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
    let readingTimeText: String?
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
            contentFingerprint: nil,
            imageURL: nil,
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
        let readingTimeText = ReaderMetadataFormatter.readingTimeText(
            content: input.content,
            summary: input.summary
        )

        self.contentBlocks = ReaderContentRenderer.blocks(
            summary: input.summary,
            content: input.content,
            fallbackImageURL: input.imageURL
        )
        self.contentAvailability = ReaderContentAvailability.resolved(
            content: input.content,
            summary: input.summary
        )
        self.shouldShowSummaryOnlyNotice = false
        self.readingTimeText = readingTimeText

        self.metadataText = ReaderMetadataFormatter.metadataParts(
            feedName: input.feedTitle,
            readingTime: readingTimeText,
            publishedAt: input.publishedAt
        )
        .joined(separator: " · ")

        if let link = input.link, let url = URL(string: link), url.scheme != nil {
            self.originalURL = url
        } else {
            self.originalURL = nil
        }
    }

}

struct ReaderArticleTextFingerprint: Hashable, Sendable {
    let count: Int
    let hashValue: Int

    static func make(from text: String?) -> ReaderArticleTextFingerprint? {
        guard let text else {
            return nil
        }

        return ReaderArticleTextFingerprint(
            count: text.count,
            hashValue: text.hashValue
        )
    }
}

/// Cache-Schlüssel aus den inhaltsbestimmenden Feldern. Große Feed-Texte werden
/// nicht direkt im Key gespeichert; nur kompakte Fingerprints. Dadurch hält der
/// Cache keine zusätzlichen Kopien langer Artikeltexte.
struct ReaderArticleCacheKey: Hashable, Sendable {
    let summary: String?
    let contentFingerprint: ReaderArticleTextFingerprint?
    let imageURL: String?
    let link: String?
    let feedTitle: String?
    let publishedAt: Date?
}

extension ReaderArticleInput {
    var cacheKey: ReaderArticleCacheKey {
        ReaderArticleCacheKey(
            summary: summary,
            contentFingerprint: contentFingerprint,
            imageURL: imageURL,
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
