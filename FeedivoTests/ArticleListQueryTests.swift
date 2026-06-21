import Foundation
import SwiftData
import Testing
@testable import Feedivo

struct ArticleListQueryTests {
    @MainActor
    @Test func feedFetchDescriptorLaedtNurArtikelDesAusgewaehltenFeedsSortiert() throws {
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
        let selectedFeed = Feed(url: "https://example.com/feed.xml", title: "Ausgewaehlt")
        let otherFeed = Feed(url: "https://example.com/other.xml", title: "Andere")
        let olderArticle = Article(
            title: "Aelter",
            publishedAt: Date(timeIntervalSince1970: 100),
            feed: selectedFeed
        )
        let newerArticle = Article(
            title: "Neuer",
            publishedAt: Date(timeIntervalSince1970: 300),
            feed: selectedFeed
        )
        let unrelatedArticle = Article(
            title: "Fremd",
            publishedAt: Date(timeIntervalSince1970: 500),
            feed: otherFeed
        )

        context.insert(selectedFeed)
        context.insert(otherFeed)
        context.insert(olderArticle)
        context.insert(newerArticle)
        context.insert(unrelatedArticle)
        try context.save()

        let articles = try context.fetch(
            ArticleListQuery.feedFetchDescriptor(for: selectedFeed)
        )

        #expect(articles.map(\.title) == ["Neuer", "Aelter"])
    }
}
