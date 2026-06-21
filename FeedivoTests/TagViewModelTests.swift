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

        viewModel.createTag(
            name: "  Swift  ",
            colorHex: "#3B82F6",
            availableTags: [],
            context: context
        )

        let tags = try context.fetch(FetchDescriptor<Feedivo.Tag>())
        #expect(tags.count == 1)
        #expect(tags.first?.name == "Swift")
        #expect(tags.first?.colorHex == "#3B82F6")
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
        #expect(article.tags.isEmpty)
    }

    @MainActor
    private func testContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Feed.self,
            FeedFolder.self,
            Article.self,
            Tag.self,
            Rule.self,
            FeedLogEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )

        return ModelContext(container)
    }
}
