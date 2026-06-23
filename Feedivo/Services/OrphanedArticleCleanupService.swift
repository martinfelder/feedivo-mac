import Foundation
import SwiftData

enum OrphanedArticleCleanupService {
    @MainActor
    @discardableResult
    static func removeArticlesWithoutExistingFeed(in context: ModelContext) throws -> Int {
        let feeds = try context.fetch(FetchDescriptor<Feed>())
        let existingFeedIDs = Set(feeds.map(\.id))
        let articles = try context.fetch(FetchDescriptor<Article>())
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

    private static func shouldRemove(_ article: Article, existingFeedIDs: Set<UUID>) -> Bool {
        guard
            let feedID = article.feedID,
            existingFeedIDs.contains(feedID)
        else {
            return true
        }

        return false
    }
}
