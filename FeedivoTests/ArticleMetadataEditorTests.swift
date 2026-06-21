import SwiftData
import Testing
@testable import Feedivo

struct ArticleMetadataEditorTests {

    @MainActor
    @Test func addTagTrimmtNamenUndVerwendetVorhandenenTag() throws {
        let context = try testContext()
        let article = Article(title: "Artikel")
        let existingTag = Tag(name: "Wearables")
        context.insert(article)
        context.insert(existingTag)
        try context.save()

        ArticleMetadataEditor.addTag(named: " wearables ", to: article, availableTags: [existingTag], context: context)

        let tags = try context.fetch(FetchDescriptor<Feedivo.Tag>())
        #expect(tags.count == 1)
        #expect(article.tags.map(\.name) == ["Wearables"])
        #expect(article.tags.first?.colorHex == "#888888")
    }

    @MainActor
    @Test func addTagBewahrtFarbeVorhandenerTags() throws {
        let context = try testContext()
        let article = Article(title: "Artikel")
        let existingTag = Tag(name: "Swift", colorHex: "#3B82F6")
        context.insert(article)
        context.insert(existingTag)
        try context.save()

        ArticleMetadataEditor.addTag(named: "swift", to: article, availableTags: [existingTag], context: context)

        #expect(article.tags.first?.name == "Swift")
        #expect(article.tags.first?.colorHex == "#3B82F6")
    }

    @MainActor
    @Test func addTagIgnoriertLeereUndDoppelteTags() throws {
        let context = try testContext()
        let article = Article(title: "Artikel")
        let tag = Tag(name: "Smartwatch")
        article.tags = [tag]
        context.insert(article)
        context.insert(tag)
        try context.save()

        ArticleMetadataEditor.addTag(named: " ", to: article, availableTags: [tag], context: context)
        ArticleMetadataEditor.addTag(named: "smartwatch", to: article, availableTags: [tag], context: context)

        #expect(article.tags.map(\.name) == ["Smartwatch"])
    }

    @MainActor
    @Test func removeTagEntferntTagVomArtikel() throws {
        let context = try testContext()
        let article = Article(title: "Artikel")
        let firstTag = Tag(name: "Wearables")
        let secondTag = Tag(name: "Smartwatch")
        article.tags = [firstTag, secondTag]
        context.insert(article)
        context.insert(firstTag)
        context.insert(secondTag)
        try context.save()

        ArticleMetadataEditor.removeTag(firstTag, from: article, context: context)

        #expect(article.tags.map(\.name) == ["Smartwatch"])
    }

    @MainActor
    @Test func availableTagsToAddZeigtNurNochNichtZugewieseneTagsSortiert() throws {
        let article = Article(title: "Artikel")
        let swiftTag = Tag(name: "Swift")
        let appleTag = Tag(name: "Apple")
        let newsTag = Tag(name: "News")
        article.tags = [swiftTag]

        let availableTags = ArticleMetadataEditor.availableTagsToAdd(
            to: article,
            availableTags: [swiftTag, newsTag, appleTag]
        )

        #expect(availableTags.map(\.name) == ["Apple", "News"])
    }

    @MainActor
    @Test func setFolderNameSpeichertGetrimmtenFeedOrdner() throws {
        let context = try testContext()
        let feed = Feed(url: "https://example.com/feed.xml", title: "Feed")
        let article = Article(title: "Artikel", feed: feed)
        context.insert(feed)
        context.insert(article)
        try context.save()

        ArticleMetadataEditor.setFolderName(" Technik ", for: article, context: context)
        #expect(feed.folderName == "Technik")

        ArticleMetadataEditor.setFolderName(" ", for: article, context: context)
        #expect(feed.folderName == nil)
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
