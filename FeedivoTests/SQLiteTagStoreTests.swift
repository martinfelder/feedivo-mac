import Foundation
import GRDB
import SwiftData
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

    @Test func assignTagToFeedIsIdempotent() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let tagStore = TagStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))
        try tagStore.save(TagRecord(id: "tag-1", name: "Swift", colorHex: "#ff0000"))

        try tagStore.assignTag(tagID: "tag-1", toFeedID: "feed-1", at: Date(timeIntervalSince1970: 100))
        try tagStore.assignTag(tagID: "tag-1", toFeedID: "feed-1", at: Date(timeIntervalSince1970: 200))

        let feedTags = try tagStore.tags(feedID: "feed-1")
        let assignmentCount = try database.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM feed_tags") ?? 0
        }

        #expect(feedTags.map(\.name) == ["Swift"])
        #expect(assignmentCount == 1)
    }

    @Test func removeTagFromFeedDeletesAssignment() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let tagStore = TagStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))
        try tagStore.save(TagRecord(id: "tag-1", name: "Swift", colorHex: "#ff0000"))
        try tagStore.assignTag(tagID: "tag-1", toFeedID: "feed-1", at: Date(timeIntervalSince1970: 100))

        try tagStore.removeTag(tagID: "tag-1", fromFeedID: "feed-1")

        #expect(try tagStore.tags(feedID: "feed-1").isEmpty)
    }

    @Test func sidebarTagsIncludeDirectArticleCountsFromSQLite() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let tagStore = TagStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))
        let firstArticleID = try articleStore.upsert(
            ArticleUpsertInput(feedID: "feed-1", sourceID: "article-1", title: "Erster Artikel")
        )
        let secondArticleID = try articleStore.upsert(
            ArticleUpsertInput(feedID: "feed-1", sourceID: "article-2", title: "Zweiter Artikel")
        )
        try tagStore.save(TagRecord(id: "tag-swift", name: "Swift", colorHex: "#ff0000"))
        try tagStore.save(TagRecord(id: "tag-empty", name: "Leer", colorHex: "#00ff00"))

        try tagStore.assignTag(tagID: "tag-swift", toArticleID: firstArticleID, at: Date(timeIntervalSince1970: 100))
        try tagStore.assignTag(tagID: "tag-swift", toArticleID: firstArticleID, at: Date(timeIntervalSince1970: 200))
        try tagStore.assignTag(tagID: "tag-swift", toArticleID: secondArticleID, at: Date(timeIntervalSince1970: 300))

        let sidebarTags = try tagStore.sidebarTags()

        #expect(sidebarTags.map(\.id) == ["tag-empty", "tag-swift"])
        #expect(sidebarTags.first { $0.id == "tag-swift" }?.articleCount == 2)
        #expect(sidebarTags.first { $0.id == "tag-empty" }?.articleCount == 0)
    }

    @Test func sidebarTagsCountFeedTaggedArticlesWithoutDuplicates() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let tagStore = TagStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))
        try tagStore.save(TagRecord(id: "tag-swift", name: "Swift", colorHex: "#ff0000"))
        let firstArticleID = try articleStore.upsert(
            ArticleUpsertInput(feedID: "feed-1", sourceID: "article-1", title: "Erster Artikel")
        )
        _ = try articleStore.upsert(
            ArticleUpsertInput(feedID: "feed-1", sourceID: "article-2", title: "Zweiter Artikel")
        )

        try tagStore.assignTag(tagID: "tag-swift", toFeedID: "feed-1", at: Date(timeIntervalSince1970: 100))
        try tagStore.assignTag(tagID: "tag-swift", toArticleID: firstArticleID, at: Date(timeIntervalSince1970: 200))

        let sidebarTags = try tagStore.sidebarTags()

        #expect(sidebarTags.first { $0.id == "tag-swift" }?.articleCount == 2)
    }

    @MainActor
    @Test func feedTagBackfillSpiegeltBestehendeSwiftDataFeedTagsNachSQLite() throws {
        let container = try ModelContainer(
            for: Feed.self,
            FeedFolder.self,
            FeedLogEntry.self,
            Article.self,
            Tag.self,
            Rule.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let database = try FeedivoDatabase.inMemoryForTests()
        let feed = Feed(url: "https://example.com/feed.xml", title: "Example")
        let tag = Tag(name: "Swift", colorHex: "#ff0000")
        feed.tags = [tag]

        context.insert(feed)
        context.insert(tag)
        try context.save()

        let mirroredCount = try FeedTagBackfillService.backfillFeedTags(
            in: context,
            database: database
        )

        let sqliteFeed = try FeedStore(database: database).feed(id: feed.id.uuidString)
        let tagStore = TagStore(database: database)
        let feedTags = try tagStore.tags(feedID: feed.id.uuidString)
        let feedTagRows = try database.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM feed_tags") ?? 0
        }

        #expect(mirroredCount == 1)
        #expect(sqliteFeed?.title == "Example")
        #expect(feedTags.map(\.id) == [tag.id.uuidString])
        #expect(feedTags.map(\.name) == ["Swift"])
        #expect(feedTagRows == 1)
    }
}
