import Foundation
import SwiftData

// FeedPropertiesQuery liefert die für die Eigenschaftenansicht benötigten
// "neuesten" Artikel- bzw. Log-Einträge eines Feeds über gezielte
// ModelContext-Fetches mit fetchLimit — statt die vollen `feed.articles`- 
// und `feed.logEntries`-Arrays in den Speicher zu faulten (P7).
//
// Verhalten entspricht FeedPropertiesFormatter (pure Funktionen auf Arrays),
// nur dass SwiftData bereits auf Datenbankebene sortiert/begrenzt. Die
// Formatter-Logik bleibt als Referenz erhalten; diese Query ist die
// speicherschonende Variante für die View.
@available(*, deprecated, message: "Legacy SwiftData-Query-Helfer. Produktive Feed-Eigenschaften greifen über SQLite-Trajektorie.")
enum FeedPropertiesQuery {

    /// Neuesten Artikel eines Feeds liefern. Es wird nur eine einzige Zeile
    /// (ohne content/offlineContent-Blobs) geladen.
    ///
    /// Sortierung nach publishedAt desc. Undatierte Artikel werden wie im
    /// Formatter als älteste behandelt (`.distantPast`): daher zuerst nach
    /// datierten Artikeln suchen; nur wenn der Feed gar keine datierten
    /// Artikel hat, fällt die Query auf einen beliebigen (undatierten)
    /// Artikel zurück. So bleibt `latestArticle` bei gemischten Feeds
    /// konsistent zum Formatter-Verhalten.
    static func latestArticle(in context: ModelContext, for feed: Feed) -> Article? {
        let feedID = feed.id

        // 1. Neuester datierter Artikel.
        var datedDescriptor = Article.lightFetchDescriptor(
            sortBy: [SortDescriptor<Article>(\.publishedAt, order: .reverse)]
        )
        datedDescriptor.predicate = #Predicate<Article> { article in
            article.feedID == feedID && article.publishedAt != nil
        }
        datedDescriptor.fetchLimit = 1
        if let dated = try? context.fetch(datedDescriptor).first {
            return dated
        }

        // 2. Fallback: Feed hat ausschließlich undatierte Artikel.
        var fallbackDescriptor = Article.lightFetchDescriptor()
        fallbackDescriptor.predicate = #Predicate<Article> { article in
            article.feedID == feedID
        }
        fallbackDescriptor.fetchLimit = 1
        return try? context.fetch(fallbackDescriptor).first
    }

    /// Neueste Log-Einträge eines Feeds, maximal `limit` Stück, absteigend
    /// nach createdAt sortiert. `FeedLogEntry` besitzt keinen `feedID`-Skalar,
    /// daher wird per Relationship-Prädikat auf `feed` gefiltert.
    static func latestLogEntries(
        in context: ModelContext,
        for feed: Feed,
        limit: Int = 20
    ) -> [FeedLogEntry] {
        let feedID = feed.id
        var descriptor = FetchDescriptor<FeedLogEntry>(
            sortBy: [SortDescriptor<FeedLogEntry>(\.createdAt, order: .reverse)]
        )
        // `FeedLogEntry` besitzt keinen `feedID`-Skalar (nur die `feed`-
        // Relationship). Ein direkter Relationship-Vergleich `entry.feed == feed`
        // kompiliert in #Predicate nicht — daher Traversierung auf den
        // skalaren `id` des verbundenen Feeds (SwiftData erzeugt einen Join).
        descriptor.predicate = #Predicate<FeedLogEntry> { entry in
            entry.feed?.id == feedID
        }
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Anzahl sichtbarer Log-Einträge = min(gesamt, limit). Nutzt fetchCount,
    /// lädt also keine Zeilen in den Speicher.
    static func latestLogEntryCount(
        in context: ModelContext,
        for feed: Feed,
        limit: Int = 20
    ) -> Int {
        let feedID = feed.id
        var descriptor = FetchDescriptor<FeedLogEntry>()
        descriptor.predicate = #Predicate<FeedLogEntry> { entry in
            entry.feed?.id == feedID
        }
        let total = (try? context.fetchCount(descriptor)) ?? 0
        return min(total, limit)
    }

    /// Anzahl Artikel dieses Feeds seit einem Grenzdatum. Undatierte Artikel
    /// zählen nicht, weil "veröffentlicht in der letzten Woche" ein Datum
    /// voraussetzt.
    static func recentArticleCount(
        in context: ModelContext,
        for feed: Feed,
        since cutoffDate: Date,
        until endDate: Date = Date()
    ) -> Int {
        let feedID = feed.id
        var descriptor = FetchDescriptor<Article>()
        descriptor.predicate = #Predicate<Article> { article in
            if let publishedAt = article.publishedAt {
                article.feedID == feedID && publishedAt >= cutoffDate && publishedAt <= endDate
            } else {
                false
            }
        }
        return (try? context.fetchCount(descriptor)) ?? 0
    }
}
