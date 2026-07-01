import Foundation
import SwiftData

enum OrphanedArticleCleanupService {
    @MainActor
    @discardableResult
    static func removeArticlesWithoutExistingFeed(in context: ModelContext) throws -> Int {
        let feeds = try context.fetch(FetchDescriptor<Feed>())
        let existingFeedIDs = Set(feeds.map(\.id))
        let articles = try context.fetch(articleCleanupFetchDescriptor())
        var removedCount = 0

        for article in articles where shouldRemove(article, existingFeedIDs: existingFeedIDs) {
            context.delete(article)
            removedCount += 1
        }

        if removedCount > 0 {
            try context.save()
        }

        return removedCount
    }

    private static func articleCleanupFetchDescriptor() -> FetchDescriptor<Article> {
        var descriptor = FetchDescriptor<Article>()
        descriptor.propertiesToFetch = [
            \.id,
            \.feedID
        ]
        return descriptor
    }

    private static func shouldRemove(_ article: Article, existingFeedIDs: Set<UUID>) -> Bool {
        if let feedID = article.feedID {
            return !existingFeedIDs.contains(feedID)
        }

        // Fallback für Altbestand während Migrationen: Wenn die Relationship noch
        // intakt ist, aber feedID fehlt, darf der Artikel nicht gelöscht werden.
        guard let relatedFeedID = article.feed?.id else {
            return true
        }

        return !existingFeedIDs.contains(relatedFeedID)
    }
}
