import Foundation
import GRDB
import Testing
@testable import Feedivo

struct SQLiteTagStoreTests {
    @Test func saveTagUpsertsByIDAndName() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = TagStore(database: database)

        try store.save(TagRecord(id: "tag-1", name: "Swift", colorHex: "#ff0000"))
        try store.save(TagRecord(id: "tag-1", name: "SwiftUI", colorHex: "#00ff00"))

        let tags = try store.tags()

        #expect(tags.map(\.id) == ["tag-1"])
        #expect(tags.first?.name == "SwiftUI")
        #expect(tags.first?.colorHex == "#00ff00")
    }

    @Test func assignTagToArticleIsIdempotent() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let tagStore = TagStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))
        let articleID = try articleStore.upsert(
            ArticleUpsertInput(feedID: "feed-1", sourceID: "article-1", title: "Artikel")
        )
        try tagStore.save(TagRecord(id: "tag-1", name: "Swift", colorHex: "#ff0000"))

        try tagStore.assignTag(tagID: "tag-1", toArticleID: articleID, at: Date(timeIntervalSince1970: 100))
        try tagStore.assignTag(tagID: "tag-1", toArticleID: articleID, at: Date(timeIntervalSince1970: 200))

        let articleTags = try tagStore.tags(articleID: articleID)
        let assignmentCount = try database.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM article_tags") ?? 0
        }

        #expect(articleTags.map(\.name) == ["Swift"])
        #expect(assignmentCount == 1)
    }
}
