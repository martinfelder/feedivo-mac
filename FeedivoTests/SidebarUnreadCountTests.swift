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
