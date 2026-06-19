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

    init(url: String, title: String) {
        self.id = UUID()
        self.url = url
        self.title = title
        self.refreshIntervalMinutes = 60
        self.articles = []
        self.tags = []
    }
}
