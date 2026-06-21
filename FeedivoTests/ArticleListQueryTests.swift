import Foundation
import SwiftData
import Testing
@testable import Feedivo

struct ArticleListQueryTests {
    @Test func articleInitialisiertDirekteFeedIDFuerSchnelleListenQueries() throws {
        let feed = Feed(url: "https://example.com/feed.xml", title: "Feed")
        let article = Article(title: "Artikel", feed: feed)

        #expect(article.feedID == feed.id)
    }

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

    @MainActor
    @Test func feedFetchDescriptorNutztDirekteFeedIDOhneRelationshipFallback() throws {
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
        let matchingArticle = Article(
            title: "Direkter Treffer",
            publishedAt: Date(timeIntervalSince1970: 300),
            feed: selectedFeed
        )
        let staleRelationshipArticle = Article(
            title: "Alte Relationship",
            publishedAt: Date(timeIntervalSince1970: 200),
            feed: selectedFeed
        )
        staleRelationshipArticle.feedID = otherFeed.id

        context.insert(selectedFeed)
        context.insert(otherFeed)
        context.insert(matchingArticle)
        context.insert(staleRelationshipArticle)
        try context.save()

        let articles = try context.fetch(
            ArticleListQuery.feedFetchDescriptor(for: selectedFeed)
        )

        #expect(articles.map(\.title) == ["Direkter Treffer"])
    }

    @MainActor
    @Test func backfillSetztFehlendeDirekteFeedIDsAusDerRelationship() throws {
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
        let feed = Feed(url: "https://example.com/feed.xml", title: "Feed")
        let article = Article(title: "Altbestand", feed: feed)
        article.feedID = nil

        context.insert(feed)
        context.insert(article)
        try context.save()

        let updatedCount = try ArticleFeedIDBackfillService.backfillMissingFeedIDs(in: context)

        #expect(updatedCount == 1)
        #expect(article.feedID == feed.id)
    }

    @MainActor
    @Test func unreadCountBackfillSetztFeedZaehlerAusGespeichertenArtikeln() throws {
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
        let feed = Feed(url: "https://example.com/feed.xml", title: "Feed")
        feed.articles = [
            Article(title: "Ungelesen", isRead: false, feed: feed),
            Article(title: "Gelesen", isRead: true, feed: feed)
        ]
        feed.unreadCount = 0

        context.insert(feed)
        try context.save()

        let testDefaults = UserDefaults(suiteName: "test-unread-backfill-\(UUID())")!
        let updatedCount = try FeedUnreadCountBackfillService.backfillUnreadCounts(
            in: context,
            defaults: testDefaults
        )

        #expect(updatedCount == 1)
        #expect(feed.unreadCount == 1)
    }
}
