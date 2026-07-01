import Foundation
import SwiftData

enum FeedUnreadCountBackfillService {
    // v3: nach Fix, dass rückwirkend ausgeblendete ungelesene Artikel den
    // gespeicherten Feed-Zähler neu synchronisieren.
    private static let backfillDoneKey = "feedUnreadCountBackfillDone_v3"

    @MainActor
    @discardableResult
    static func backfillUnreadCounts(
        in context: ModelContext,
        defaults: UserDefaults = .standard
    ) throws -> Int {
        guard !defaults.bool(forKey: backfillDoneKey) else {
            return 0
        }

        let feeds = try context.fetch(FetchDescriptor<Feed>())
        let unreadCounts = try unreadCountsByFeedID(in: context)
        var updatedCount = 0

        for feed in feeds {
            let unreadCount = unreadCounts[feed.id, default: 0]
            guard feed.unreadCount != unreadCount else {
                continue
            }

            feed.unreadCount = unreadCount
            updatedCount += 1
        }

        if updatedCount > 0 {
            try context.save()
        }

        defaults.set(true, forKey: backfillDoneKey)
        return updatedCount
    }

    @MainActor
    private static func unreadCountsByFeedID(in context: ModelContext) throws -> [UUID: Int] {
        var descriptor = FetchDescriptor<Article>()
        descriptor.propertiesToFetch = [
            \.feedID,
            \.isRead,
            \.isHidden
        ]
        let articles = try context.fetch(descriptor)
        var unreadCounts: [UUID: Int] = [:]

        for article in articles where !article.isRead && !article.isHidden {
            if let feedID = article.feedID {
                unreadCounts[feedID, default: 0] += 1
            }
        }

        return unreadCounts
    }
}
