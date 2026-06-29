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
        var updatedCount = 0

        for feed in feeds {
            let unreadCount = feed.articles.filter { !$0.isRead && !$0.isHidden }.count
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
}
