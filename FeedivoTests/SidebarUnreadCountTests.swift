import SwiftData
import Testing
@testable import Feedivo

struct SidebarUnreadCountTests {
    @MainActor
    @Test func feedUnreadCountNutztGespeichertenFeedZaehler() {
        let feed = Feed(url: "https://example.com/feed.xml", title: "Test Feed")
        feed.unreadCount = 2

        #expect(SidebarUnreadCount.unreadArticleCount(for: feed) == 2)
    }

    @Test func badgeTextIstNurFuerPositiveZaehlerSichtbar() {
        #expect(SidebarUnreadCount.badgeText(for: 0) == nil)
        #expect(SidebarUnreadCount.badgeText(for: 7) == "7")
    }

    @MainActor
    @Test func tagBadgeTextZaehltVerknuepfteArtikel() throws {
        let context = try testContext()
        let tag = Tag(name: "Swift")
        let firstArticle = Article(title: "Erster Artikel")
        let secondArticle = Article(title: "Zweiter Artikel")
        firstArticle.tags = [tag]
        secondArticle.tags = [tag]
        context.insert(tag)
        context.insert(firstArticle)
        context.insert(secondArticle)
        try context.save()

        #expect(try SidebarTagCount.articleCount(for: tag, context: context) == 2)
        #expect(try SidebarTagCount.badgeText(for: tag, context: context) == "2")
    }

    @MainActor
    @Test func tagBadgeTextZaehltArtikelAusGetaggtenFeedsOhneDuplikate() throws {
        let context = try testContext()
        let tag = Tag(name: "Apple")
        let feed = Feed(url: "https://example.com/feed.xml", title: "Feed")
        let feedArticle = Article(title: "Feed-Artikel", feed: feed)
        let duplicateArticle = Article(title: "Doppelt", feed: feed)
        let directArticle = Article(title: "Direkt")
        feed.tags = [tag]
        duplicateArticle.tags = [tag]
        directArticle.tags = [tag]
        context.insert(tag)
        context.insert(feed)
        context.insert(feedArticle)
        context.insert(duplicateArticle)
        context.insert(directArticle)
        try context.save()

        #expect(try SidebarTagCount.articleCount(for: tag, context: context) == 3)
        #expect(try SidebarTagCount.badgeText(for: tag, context: context) == "3")
    }

    @MainActor
    @Test func tagBadgeTextZaehltArtikelPerSwiftDataQueryOhneRelationshipTraversal() throws {
        let context = try testContext()
        let tag = Tag(name: "Apple")
        let feed = Feed(url: "https://example.com/feed.xml", title: "Feed")
        let feedArticle = Article(title: "Feed-Artikel", feed: feed)
        let duplicateArticle = Article(title: "Doppelt", feed: feed)
        let directArticle = Article(title: "Direkt")
        let unrelatedArticle = Article(title: "Anderer Artikel")
        feed.tags = [tag]
        tag.feeds = [feed]
        duplicateArticle.tags = [tag]
        directArticle.tags = [tag]

        context.insert(tag)
        context.insert(feed)
        context.insert(feedArticle)
        context.insert(duplicateArticle)
        context.insert(directArticle)
        context.insert(unrelatedArticle)
        try context.save()

        #expect(try SidebarTagCount.articleCount(for: tag, context: context) == 3)
        #expect(try SidebarTagCount.badgeText(for: tag, context: context) == "3")
    }

    @MainActor
    @Test func tagBadgeTextIstNurFuerTagsMitArtikelnSichtbar() throws {
        let context = try testContext()
        let tag = Tag(name: "Leer")
        context.insert(tag)
        try context.save()

        #expect(try SidebarTagCount.articleCount(for: tag, context: context) == 0)
        #expect(try SidebarTagCount.badgeText(for: tag, context: context) == nil)
    }

    @MainActor
    @Test func totalUnreadCountZaehltGespeicherteFeedZaehler() {
        let firstFeed = Feed(url: "https://example.com/first.xml", title: "First")
        let secondFeed = Feed(url: "https://example.com/second.xml", title: "Second")
        firstFeed.unreadCount = 1
        secondFeed.unreadCount = 2

        #expect(SidebarUnreadCount.totalUnreadArticleCount(in: [firstFeed, secondFeed]) == 3)
    }

    @MainActor
    @Test func articleViewModelHaeltFeedZaehlerBeiStatuswechselAktuell() {
        let feed = Feed(url: "https://example.com/feed.xml", title: "Feed")
        let article = Article(title: "Ungelesen", isRead: false, feed: feed)
        feed.unreadCount = 1
        let viewModel = ArticleViewModel()

        viewModel.markReadIfNeeded(article, isEnabled: true)

        #expect(article.isRead)
        #expect(feed.unreadCount == 0)

        viewModel.toggleRead(article)

        #expect(!article.isRead)
        #expect(feed.unreadCount == 1)
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
