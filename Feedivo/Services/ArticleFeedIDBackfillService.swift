import Foundation
import SwiftData

enum ArticleFeedIDBackfillService {
    @MainActor
    @discardableResult
    static func backfillMissingFeedIDs(in context: ModelContext) throws -> Int {
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { article in
                article.feedID == nil
            }
        )
        let articles = try context.fetch(descriptor)
        var updatedCount = 0

        for article in articles {
            guard let feedID = article.feed?.id else {
                continue
            }

            article.feedID = feedID
            updatedCount += 1
        }

        if updatedCount > 0 {
            try context.save()
        }

        return updatedCount
    }
}
