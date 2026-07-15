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

    @Test func removeTagFromArticleDeletesOnlyArticleAssignment() throws {
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

        try tagStore.removeTag(tagID: "tag-1", fromArticleID: articleID)

        #expect(try tagStore.tags(articleID: articleID).isEmpty)
        #expect(try tagStore.tags().map(\.id) == ["tag-1"])
    }

    @Test func deleteTagRemovesTagAndAssignments() throws {
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
        try tagStore.assignTag(tagID: "tag-1", toFeedID: "feed-1", at: Date(timeIntervalSince1970: 100))

        try tagStore.deleteTag(id: "tag-1")

        let tagCount = try database.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM tags") ?? 0
        }
        let articleTagCount = try database.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM article_tags") ?? 0
        }
        let feedTagCount = try database.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM feed_tags") ?? 0
        }

        #expect(tagCount == 0)
        #expect(articleTagCount == 0)
        #expect(feedTagCount == 0)
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

        #expect(sidebarTags.map(\.id) == ["tag-swift", "tag-empty"])
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

    @Test func moveVerschiebtTagAnNeuePosition() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let tagStore = TagStore(database: database)
        try tagStore.save(TagRecord(id: "tag-a", name: "Alpha", sortIndex: 0))
        try tagStore.save(TagRecord(id: "tag-b", name: "Bravo", sortIndex: 1))
        try tagStore.save(TagRecord(id: "tag-c", name: "Charlie", sortIndex: 2))

        try tagStore.move(id: "tag-c", targetIndex: 0)

        let orderedNames = try tagStore.tags()
            .sorted { $0.sortIndex < $1.sortIndex }
            .map(\.name)
        #expect(orderedNames == ["Charlie", "Alpha", "Bravo"])
    }

    @Test func moveKlemmtTargetIndexAufGueltigenBereich() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let tagStore = TagStore(database: database)
        try tagStore.save(TagRecord(id: "tag-a", name: "Alpha", sortIndex: 0))
        try tagStore.save(TagRecord(id: "tag-b", name: "Bravo", sortIndex: 1))

        try tagStore.move(id: "tag-a", targetIndex: 999)

        let orderedNames = try tagStore.tags()
            .sorted { $0.sortIndex < $1.sortIndex }
            .map(\.name)
        #expect(orderedNames == ["Bravo", "Alpha"])
    }

    @Test func neuerTagWirdAmEndeEingefuegtNichtBeiIndexNull() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let tagStore = TagStore(database: database)
        try tagStore.save(TagRecord(id: "tag-a", name: "Alpha", sortIndex: 0))
        try tagStore.save(TagRecord(id: "tag-b", name: "Bravo", sortIndex: 1))

        // Bewusst ohne explizit gesetzten sortIndex gespeichert (Default 0 aus dem
        // Initializer) — save() muss trotzdem ans Ende anhängen, nicht bei den
        // bestehenden Tags mit sortIndex 0 landen.
        try tagStore.save(TagRecord(id: "tag-c", name: "Charlie"))

        let orderedNames = try tagStore.tags()
            .sorted { $0.sortIndex < $1.sortIndex }
            .map(\.name)
        #expect(orderedNames == ["Alpha", "Bravo", "Charlie"])
    }

    @Test func tagsSortiertNachSortIndexNichtNachName() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let tagStore = TagStore(database: database)
        try tagStore.save(TagRecord(id: "tag-z", name: "Zebra", sortIndex: 0))
        try tagStore.save(TagRecord(id: "tag-a", name: "Apfel", sortIndex: 1))

        let orderedNames = try tagStore.tags().map(\.name)
        #expect(orderedNames == ["Zebra", "Apfel"])
    }
}
