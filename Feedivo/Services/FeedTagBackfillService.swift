import Foundation
import SwiftData

enum FeedTagBackfillService {
    @MainActor
    @discardableResult
    static func backfillFeedTags(
        in context: ModelContext,
        database: FeedivoDatabase
    ) throws -> Int {
        var descriptor = FetchDescriptor<Feed>()
        descriptor.propertiesToFetch = [
            \.id,
            \.url,
            \.title,
            \.siteURL,
            \.faviconURL,
            \.folderName,
            \.refreshIntervalMinutes,
            \.lastRefreshed,
            \.httpETag,
            \.httpLastModified,
            \.httpContentHash,
            \.lastHTTPStatusCode,
            \.unreadCount
        ]

        let feeds = try context.fetch(descriptor)
        let feedStore = FeedStore(database: database)
        let tagStore = TagStore(database: database)
        var mirroredCount = 0

        for feed in feeds {
            let feedID = feed.id.uuidString
            try feedStore.save(
                FeedRecord(
                    id: feedID,
                    url: feed.url,
                    title: feed.title,
                    websiteURL: feed.siteURL,
                    faviconURL: feed.faviconURL,
                    folderName: feed.folderName,
                    refreshIntervalMinutes: feed.refreshIntervalMinutes,
                    lastRefreshedAt: feed.lastRefreshed,
                    lastETag: feed.httpETag,
                    lastModified: feed.httpLastModified,
                    lastBodyHash: feed.httpContentHash,
                    lastHTTPStatusCode: feed.lastHTTPStatusCode,
                    unreadCount: feed.unreadCount
                )
            )

            for tag in feed.tags ?? [] {
                let tagID = tag.id.uuidString
                try tagStore.save(
                    TagRecord(
                        id: tagID,
                        name: tag.name,
                        colorHex: tag.colorHex
                    )
                )
                try tagStore.assignTag(tagID: tagID, toFeedID: feedID, at: Date())
                mirroredCount += 1
            }
        }

        if mirroredCount > 0 {
            SidebarBadgeInvalidation.bumpDirectTagVersion()
        }

        return mirroredCount
    }
}
