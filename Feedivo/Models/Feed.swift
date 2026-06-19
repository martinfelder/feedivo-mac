import Foundation
import SwiftData

// Feed repräsentiert einen abonnierten RSS-Kanal
@Model
class Feed {
    var id: UUID
    var url: String
    var title: String
    var feedDescription: String?
    var faviconURL: String?
    var lastRefreshed: Date?
    var refreshIntervalMinutes: Int

    @Relationship(deleteRule: .cascade)
    var articles: [Article]

    @Relationship
    var tags: [Tag]

    init(
        url: String,
        title: String,
        feedDescription: String? = nil,
        faviconURL: String? = nil,
        lastRefreshed: Date? = nil,
        refreshIntervalMinutes: Int = 60
    ) {
        self.id = UUID()
        self.url = url
        self.title = title
        self.feedDescription = feedDescription
        self.faviconURL = faviconURL
        self.lastRefreshed = lastRefreshed
        self.refreshIntervalMinutes = refreshIntervalMinutes
        self.articles = []
        self.tags = []
    }
}
