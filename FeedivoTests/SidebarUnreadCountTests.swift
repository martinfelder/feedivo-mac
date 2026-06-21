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
    @Test func tagBadgeTextZaehltVerknuepfteArtikel() {
        let tag = Tag(name: "Swift")
        let firstArticle = Article(title: "Erster Artikel")
        let secondArticle = Article(title: "Zweiter Artikel")
        tag.articles = [firstArticle, secondArticle]

        #expect(SidebarTagCount.articleCount(for: tag) == 2)
        #expect(SidebarTagCount.badgeText(for: tag) == "2")
    }

    @MainActor
    @Test func tagBadgeTextZaehltArtikelAusGetaggtenFeedsOhneDuplikate() {
        let tag = Tag(name: "Apple")
        let feed = Feed(url: "https://example.com/feed.xml", title: "Feed")
        let feedArticle = Article(title: "Feed-Artikel", feed: feed)
        let duplicateArticle = Article(title: "Doppelt", feed: feed)
        let directArticle = Article(title: "Direkt")
        feed.articles = [feedArticle, duplicateArticle]
        feed.tags = [tag]
        tag.feeds = [feed]
        tag.articles = [duplicateArticle, directArticle]

        #expect(SidebarTagCount.articleCount(for: tag) == 3)
        #expect(SidebarTagCount.badgeText(for: tag) == "3")
    }

    @MainActor
    @Test func tagBadgeTextIstNurFuerTagsMitArtikelnSichtbar() {
        let tag = Tag(name: "Leer")

        #expect(SidebarTagCount.articleCount(for: tag) == 0)
        #expect(SidebarTagCount.badgeText(for: tag) == nil)
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
}
