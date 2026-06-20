import Foundation
import SwiftData
import Testing
@testable import Feedivo

struct FeedViewModelTests {

    @MainActor
    @Test func refreshAllFeedsAktualisiertWeiterWennEinFeedFehlschlaegt() async throws {
        let container = try ModelContainer(
            for: Feed.self,
            Article.self,
            Tag.self,
            Rule.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let failingFeed = Feed(url: "https://example.com/fail.xml", title: "Fehler Feed")
        let successfulFeed = Feed(url: "https://example.com/success.xml", title: "Erfolgreicher Feed")
        let viewModel = FeedViewModel { urlString in
            if urlString == failingFeed.url {
                throw TestFeedRefreshError()
            }

            return ParsedFeed(
                sourceURL: urlString,
                title: "Aktualisierter Feed",
                description: "Neue Beschreibung",
                articles: [
                    ParsedArticle(
                        title: "Neuer Artikel",
                        link: "https://example.com/new",
                        summary: "Neu",
                        content: nil,
                        publishedAt: Date(timeIntervalSince1970: 300),
                        imageURL: nil
                    )
                ]
            )
        }

        context.insert(failingFeed)
        context.insert(successfulFeed)
        try context.save()

        await viewModel.refreshAllFeeds([failingFeed, successfulFeed], context: context)

        #expect(failingFeed.articles.isEmpty)
        #expect(successfulFeed.title == "Aktualisierter Feed")
        #expect(successfulFeed.articles.contains { $0.link == "https://example.com/new" })
        #expect(viewModel.errorMessage?.contains("Fehler Feed") == true)
        #expect(!viewModel.isLoading)
    }

    @MainActor
    @Test func refreshFeedFuegtNurNeueArtikelHinzuUndAktualisiertMetadaten() async throws {
        let container = try ModelContainer(
            for: Feed.self,
            Article.self,
            Tag.self,
            Rule.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let oldRefreshDate = Date(timeIntervalSince1970: 1)
        let existingPublishedAt = Date(timeIntervalSince1970: 100)
        let newPublishedAt = Date(timeIntervalSince1970: 200)
        let feed = Feed(
            url: "https://example.com/feed.xml",
            title: "Alter Titel",
            feedDescription: "Alte Beschreibung",
            lastRefreshed: oldRefreshDate
        )
        let existingArticle = Article(
            title: "Vorhandener Artikel",
            link: "https://example.com/1",
            summary: "Bleibt lokal erhalten",
            publishedAt: existingPublishedAt,
            isRead: true,
            feed: feed
        )
        feed.articles = [existingArticle]
        let viewModel = FeedViewModel { urlString in
            #expect(urlString == feed.url)
            return ParsedFeed(
                sourceURL: urlString,
                title: "Neuer Titel",
                description: "Neue Beschreibung",
                articles: [
                    ParsedArticle(
                        title: "Vorhandener Artikel aus Feed",
                        link: "https://example.com/1",
                        summary: "Soll nicht dupliziert werden",
                        content: nil,
                        publishedAt: existingPublishedAt,
                        imageURL: nil
                    ),
                    ParsedArticle(
                        title: "Neuer Artikel",
                        link: "https://example.com/2",
                        summary: "Neu",
                        content: "Inhalt",
                        publishedAt: newPublishedAt,
                        imageURL: "https://example.com/image.jpg"
                    )
                ]
            )
        }

        context.insert(feed)
        try context.save()

        await viewModel.refreshFeed(feed, context: context)

        #expect(feed.title == "Neuer Titel")
        #expect(feed.feedDescription == "Neue Beschreibung")
        #expect(feed.lastRefreshed ?? .distantPast > oldRefreshDate)
        #expect(feed.articles.count == 2)
        #expect(existingArticle.isRead)
        #expect(feed.articles.contains { $0.link == "https://example.com/2" })
        #expect(viewModel.errorMessage == nil)
        #expect(!viewModel.isLoading)
    }

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

private struct TestFeedRefreshError: LocalizedError {
    var errorDescription: String? {
        "Test refresh failed"
    }
}
