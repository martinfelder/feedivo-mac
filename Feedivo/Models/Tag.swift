import Foundation
import SwiftData

// Tag ist ein Label das Feeds und Artikeln zugewiesen werden kann
@Model
class Tag {
    var id: UUID
    var name: String
    var colorHex: String

    @Relationship(inverse: \Feed.tags)
    var feeds: [Feed]

    @Relationship(inverse: \Article.tags)
    var articles: [Article]

    init(name: String, colorHex: String = "#888888") {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
        self.feeds = []
        self.articles = []
    }
}
