import Foundation
import SwiftData
import Testing
@testable import Feedivo

struct TagViewModelTests {

    @MainActor
    @Test func normalizedTagNameTrimmtUndVerwirftLeereNamen() {
        #expect(TagViewModel.normalizedTagName("  Swift  ") == "Swift")
        #expect(TagViewModel.normalizedTagName("   ") == nil)
        #expect(TagViewModel.normalizedTagName(nil) == nil)
    }

    @MainActor
    @Test func createTagSpeichertNormalisiertenNamenUndFarbe() throws {
        let context = try testContext()
        let viewModel = TagViewModel()

        let createdTag = viewModel.createTag(
            name: "  Swift  ",
            colorHex: "#3B82F6",
            availableTags: [],
            context: context
        )

        let tags = try context.fetch(FetchDescriptor<Feedivo.Tag>())
        #expect(tags.count == 1)
        #expect(tags.first?.name == "Swift")
        #expect(tags.first?.colorHex == "#3B82F6")
        #expect(createdTag?.persistentModelID == tags.first?.persistentModelID)
        #expect(viewModel.errorMessage == nil)
    }

    @MainActor
    @Test func createTagSpiegeltTagNachSQLite() throws {
        let context = try testContext()
        let database = try FeedivoDatabase.inMemoryForTests()
        let viewModel = TagViewModel()

        let createdTag = try #require(viewModel.createTag(
            name: "  Swift  ",
            colorHex: "#3b82f6",
            availableTags: [],
            context: context,
            sqliteDatabase: database
        ))

        let sqliteTags = try TagStore(database: database).tags()

        #expect(sqliteTags.map(\.id) == [createdTag.id.uuidString])
        #expect(sqliteTags.map(\.name) == ["Swift"])
        #expect(sqliteTags.map(\.colorHex) == ["#3B82F6"])
        #expect(viewModel.errorMessage == nil)
    }

    @MainActor
    @Test func createTagVerhindertLeereUndDoppelteNamen() throws {
        let context = try testContext()
        let existingTag = Tag(name: "Swift", colorHex: "#22C55E")
        context.insert(existingTag)
        try context.save()
        let viewModel = TagViewModel()

        viewModel.createTag(name: " ", colorHex: "#3B82F6", availableTags: [existingTag], context: context)
        #expect(try context.fetch(FetchDescriptor<Feedivo.Tag>()).count == 1)
        #expect(viewModel.errorMessage == L10n.tagManagerEmptyNameError)

        viewModel.createTag(name: "swift", colorHex: "#3B82F6", availableTags: [existingTag], context: context)
        #expect(try context.fetch(FetchDescriptor<Feedivo.Tag>()).count == 1)
        #expect(viewModel.errorMessage == L10n.tagManagerDuplicateNameError)
    }

    @MainActor
    @Test func renameTagAendertNamenUndVerhindertDuplikate() throws {
        let context = try testContext()
        let tag = Tag(name: "Apple", colorHex: "#22C55E")
        let otherTag = Tag(name: "Swift", colorHex: "#3B82F6")
        context.insert(tag)
        context.insert(otherTag)
        try context.save()
        let viewModel = TagViewModel()

        viewModel.renameTag(tag, name: "  Apple News  ", availableTags: [tag, otherTag], context: context)
        #expect(tag.name == "Apple News")
        #expect(tag.colorHex == "#22C55E")
        #expect(viewModel.errorMessage == nil)

        viewModel.renameTag(tag, name: "swift", availableTags: [tag, otherTag], context: context)
        #expect(tag.name == "Apple News")
        #expect(viewModel.errorMessage == L10n.tagManagerDuplicateNameError)
    }

    @MainActor
    @Test func renameTagSpiegeltNamenNachSQLite() throws {
        let context = try testContext()
        let database = try FeedivoDatabase.inMemoryForTests()
        let tag = Tag(name: "Apple", colorHex: "#22C55E")
        context.insert(tag)
        try context.save()
        try TagStore(database: database).save(
            TagRecord(id: tag.id.uuidString, name: tag.name, colorHex: tag.colorHex)
        )
        let viewModel = TagViewModel()

        viewModel.renameTag(
            tag,
            name: "  Apple News  ",
            availableTags: [tag],
            context: context,
            sqliteDatabase: database
        )

        let sqliteTag = try #require(try TagStore(database: database).tags().first)
        #expect(sqliteTag.id == tag.id.uuidString)
        #expect(sqliteTag.name == "Apple News")
        #expect(sqliteTag.colorHex == "#22C55E")
        #expect(viewModel.errorMessage == nil)
    }

    @MainActor
    @Test func updateColorNormalisiertHexFarbe() throws {
        let context = try testContext()
        let tag = Tag(name: "Swift", colorHex: "#22C55E")
        context.insert(tag)
        try context.save()
        let viewModel = TagViewModel()

        viewModel.updateColor(tag, colorHex: "3b82f6", context: context)

        #expect(tag.colorHex == "#3B82F6")
        #expect(tag.name == "Swift")
    }

    @MainActor
    @Test func updateColorSpiegeltFarbeNachSQLite() throws {
        let context = try testContext()
        let database = try FeedivoDatabase.inMemoryForTests()
        let tag = Tag(name: "Swift", colorHex: "#22C55E")
        context.insert(tag)
        try context.save()
        try TagStore(database: database).save(
            TagRecord(id: tag.id.uuidString, name: tag.name, colorHex: tag.colorHex)
        )
        let viewModel = TagViewModel()

        viewModel.updateColor(tag, colorHex: "3b82f6", context: context, sqliteDatabase: database)

        let sqliteTag = try #require(try TagStore(database: database).tags().first)
        #expect(sqliteTag.id == tag.id.uuidString)
        #expect(sqliteTag.name == "Swift")
        #expect(sqliteTag.colorHex == "#3B82F6")
        #expect(viewModel.errorMessage == nil)
    }

    @MainActor
    @Test func normalizedColorHexValidiertUndNormalisiertFarben() {
        #expect(TagViewModel.normalizedColorHex("#22c55e") == "#22C55E")
        #expect(TagViewModel.normalizedColorHex("3B82F6") == "#3B82F6")
        #expect(TagViewModel.normalizedColorHex("not-a-color") == "#888888")
    }

    @MainActor
    @Test func deleteTagEntferntNurTagNichtArtikel() throws {
        let context = try testContext()
        let tag = Tag(name: "Swift", colorHex: "#3B82F6")
        let article = Article(title: "Artikel")
        article.tags = [tag]
        context.insert(tag)
        context.insert(article)
        try context.save()
        let viewModel = TagViewModel()

        viewModel.deleteTag(tag, context: context)

        #expect(try context.fetch(FetchDescriptor<Feedivo.Tag>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Article>()).count == 1)
        #expect((article.tags ?? []).isEmpty)
    }

    @MainActor
    @Test func deleteTagEntferntTagAusSQLite() throws {
        let context = try testContext()
        let database = try FeedivoDatabase.inMemoryForTests()
        let feed = Feed(url: "https://example.com/feed.xml", title: "Example")
        let tag = Tag(name: "Swift", colorHex: "#3B82F6")
        feed.tags = [tag]
        context.insert(feed)
        context.insert(tag)
        try context.save()
        try FeedStore(database: database).save(
            FeedRecord(id: feed.id.uuidString, url: feed.url, title: feed.title)
        )
        try TagStore(database: database).save(
            TagRecord(id: tag.id.uuidString, name: tag.name, colorHex: tag.colorHex)
        )
        try TagStore(database: database).assignTag(
            tagID: tag.id.uuidString,
            toFeedID: feed.id.uuidString,
            at: Date(timeIntervalSince1970: 100)
        )
        let viewModel = TagViewModel()

        viewModel.deleteTag(tag, context: context, sqliteDatabase: database)

        #expect(try TagStore(database: database).tags().isEmpty)
        #expect(try TagStore(database: database).tags(feedID: feed.id.uuidString).isEmpty)
        #expect(viewModel.errorMessage == nil)
    }

    @MainActor
    private func testContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Feed.self,
            FeedFolder.self,
            Article.self,
            Tag.self,
            Rule.self,
            RuleCondition.self,
            FeedLogEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )

        return ModelContext(container)
    }
}
