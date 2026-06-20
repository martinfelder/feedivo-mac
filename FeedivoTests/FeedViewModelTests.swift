import SwiftData
import Testing
@testable import Feedivo

struct FeedViewModelTests {

    @MainActor
    @Test func deleteFeedEntferntFeedAusSwiftData() throws {
        let container = try ModelContainer(
            for: Feed.self,
            Article.self,
            Tag.self,
            Rule.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let feed = Feed(url: "https://example.com/feed.xml", title: "Test Feed")
        let viewModel = FeedViewModel()

        context.insert(feed)
        try context.save()

        viewModel.deleteFeed(feed, context: context)

        let feeds = try context.fetch(FetchDescriptor<Feed>())
        #expect(feeds.isEmpty)
        #expect(viewModel.errorMessage == nil)
    }

    @MainActor
    @Test func deleteFeedIgnoriertFehlendeAuswahl() throws {
        let container = try ModelContainer(
            for: Feed.self,
            Article.self,
            Tag.self,
            Rule.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let viewModel = FeedViewModel()

        viewModel.deleteFeed(nil, context: context)

        let feeds = try context.fetch(FetchDescriptor<Feed>())
        #expect(feeds.isEmpty)
        #expect(viewModel.errorMessage == nil)
    }
}
