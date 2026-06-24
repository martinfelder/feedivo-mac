import Foundation
import SwiftData
import Testing
@testable import Feedivo

@Suite(.serialized)
struct ArticleListQueryTests {
    @Test func displayStateBlendetGeleseneArtikelStandardmaessigAus() {
        let unreadNewest = Article(
            title: "Ungelesen neu",
            publishedAt: Date(timeIntervalSince1970: 300),
            isRead: false
        )
        let readMiddle = Article(
            title: "Gelesen",
            publishedAt: Date(timeIntervalSince1970: 200),
            isRead: true
        )
        let unreadOldest = Article(
            title: "Ungelesen alt",
            publishedAt: Date(timeIntervalSince1970: 100),
            isRead: false
        )

        let state = ArticleListDisplayState(
            articles: [unreadNewest, readMiddle, unreadOldest],
            showsReadArticles: false
        )

        #expect(state.visibleArticles.map(\.title) == ["Ungelesen neu", "Ungelesen alt"])
        #expect(state.hiddenReadArticleCount == 1)
        #expect(state.shouldShowReadArticlesButton)
    }

    @Test func displayStateZeigtAlleArtikelNachAktivierung() {
        let unreadArticle = Article(title: "Ungelesen", isRead: false)
        let readArticle = Article(title: "Gelesen", isRead: true)

        let state = ArticleListDisplayState(
            articles: [unreadArticle, readArticle],
            showsReadArticles: true
        )

        #expect(state.visibleArticles.map(\.title) == ["Ungelesen", "Gelesen"])
        #expect(state.hiddenReadArticleCount == 0)
        #expect(!state.shouldShowReadArticlesButton)
    }

    @Test func displayStateHaeltAusgewaehltenGelesenenArtikelSichtbar() {
        let unreadArticle = Article(title: "Ungelesen", isRead: false)
        let selectedReadArticle = Article(title: "Ausgewaehlt", isRead: true)
        let hiddenReadArticle = Article(title: "Verborgen", isRead: true)

        let state = ArticleListDisplayState(
            articles: [unreadArticle, selectedReadArticle, hiddenReadArticle],
            showsReadArticles: false,
            selectedArticle: selectedReadArticle
        )

        #expect(state.visibleArticles.map(\.title) == ["Ungelesen", "Ausgewaehlt"])
        #expect(state.hiddenReadArticleCount == 1)
    }

    @Test func displayStateBlendetHiddenArtikelAusNormalenListenAus() {
        let visibleArticle = Article(title: "Sichtbar", isRead: false)
        let hiddenArticle = Article(title: "Ausgeblendet", isRead: false, isHidden: true)

        let state = ArticleListDisplayState(
            articles: [visibleArticle, hiddenArticle],
            showsReadArticles: true
        )

        #expect(state.visibleArticles.map(\.title) == ["Sichtbar"])
        #expect(!state.shouldShowReadArticlesButton)
    }

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
    @Test func tagFetchDescriptorLaedtNurArtikelMitAusgewaehltemTagSortiert() throws {
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
        let selectedTag = Tag(name: "Swift", colorHex: "#3B82F6")
        let otherTag = Tag(name: "Mac", colorHex: "#22C55E")
        let olderArticle = Article(
            title: "Aelter",
            publishedAt: Date(timeIntervalSince1970: 100)
        )
        olderArticle.tags = [selectedTag]
        let newerArticle = Article(
            title: "Neuer",
            publishedAt: Date(timeIntervalSince1970: 300)
        )
        newerArticle.tags = [selectedTag, otherTag]
        let unrelatedArticle = Article(
            title: "Fremd",
            publishedAt: Date(timeIntervalSince1970: 500)
        )
        unrelatedArticle.tags = [otherTag]

        context.insert(selectedTag)
        context.insert(otherTag)
        context.insert(olderArticle)
        context.insert(newerArticle)
        context.insert(unrelatedArticle)
        try context.save()

        let articles = try context.fetch(
            ArticleListQuery.tagFetchDescriptor(for: selectedTag)
        )

        #expect(articles.map(\.title) == ["Neuer", "Aelter"])
    }

    @MainActor
    @Test func tagFetchDescriptorLaedtAuchArtikelAusGetaggtenFeedsOhneDuplikate() throws {
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
        let selectedTag = Tag(name: "Apple", colorHex: "#3B82F6")
        let taggedFeed = Feed(url: "https://example.com/tagged.xml", title: "Apple Feed")
        taggedFeed.tags = [selectedTag]
        let otherFeed = Feed(url: "https://example.com/other.xml", title: "Other Feed")
        let feedTaggedArticle = Article(
            title: "Feed-Tag Treffer",
            publishedAt: Date(timeIntervalSince1970: 300),
            feed: taggedFeed
        )
        let directTaggedArticle = Article(
            title: "Direkter Treffer",
            publishedAt: Date(timeIntervalSince1970: 200),
            feed: otherFeed
        )
        directTaggedArticle.tags = [selectedTag]
        let duplicateArticle = Article(
            title: "Doppelter Treffer",
            publishedAt: Date(timeIntervalSince1970: 100),
            feed: taggedFeed
        )
        duplicateArticle.tags = [selectedTag]
        let unrelatedArticle = Article(
            title: "Fremd",
            publishedAt: Date(timeIntervalSince1970: 500),
            feed: otherFeed
        )

        context.insert(selectedTag)
        context.insert(taggedFeed)
        context.insert(otherFeed)
        context.insert(feedTaggedArticle)
        context.insert(directTaggedArticle)
        context.insert(duplicateArticle)
        context.insert(unrelatedArticle)
        try context.save()

        let articles = try context.fetch(
            ArticleListQuery.tagFetchDescriptor(for: selectedTag)
        )

        #expect(articles.map(\.title) == [
            "Feed-Tag Treffer",
            "Direkter Treffer",
            "Doppelter Treffer"
        ])
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

    @MainActor
    @Test func orphanedArticleCleanupEntferntArtikelOhneExistierendenFeed() throws {
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
        let validArticle = Article(title: "Gueltig", feed: feed)
        let staleArticle = Article(title: "Alter Offline-Rest")
        staleArticle.feedID = UUID()
        staleArticle.offlineState = .feedContent
        let articleWithoutFeed = Article(title: "Ohne Feed")

        context.insert(feed)
        context.insert(validArticle)
        context.insert(staleArticle)
        context.insert(articleWithoutFeed)
        try context.save()

        let removedCount = try OrphanedArticleCleanupService.removeArticlesWithoutExistingFeed(in: context)
        let articles = try context.fetch(FetchDescriptor<Article>())

        #expect(removedCount == 2)
        #expect(articles.map(\.title) == ["Gueltig"])
    }
}
