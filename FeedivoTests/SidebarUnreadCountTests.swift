import Testing
@testable import Feedivo

struct SidebarUnreadCountTests {
    @MainActor
    @Test func feedUnreadCountZaehltNurUngeleseneArtikelUndReagiertAufStatuswechsel() {
        let feed = Feed(url: "https://example.com/feed.xml", title: "Test Feed")
        let firstUnreadArticle = Article(title: "Ungelesen 1", isRead: false)
        let secondUnreadArticle = Article(title: "Ungelesen 2", isRead: false)
        let readArticle = Article(title: "Gelesen", isRead: true)

        feed.articles = [firstUnreadArticle, secondUnreadArticle, readArticle]

        #expect(SidebarUnreadCount.unreadArticleCount(in: feed) == 2)

        firstUnreadArticle.isRead = true

        #expect(SidebarUnreadCount.unreadArticleCount(in: feed) == 1)
    }

    @Test func badgeTextIstNurFuerPositiveZaehlerSichtbar() {
        #expect(SidebarUnreadCount.badgeText(for: 0) == nil)
        #expect(SidebarUnreadCount.badgeText(for: 7) == "7")
    }

    @MainActor
    @Test func totalUnreadCountSummiertAlleFeeds() {
        let firstFeed = Feed(url: "https://example.com/first.xml", title: "First")
        firstFeed.articles = [
            Article(title: "Ungelesen", isRead: false),
            Article(title: "Gelesen", isRead: true)
        ]

        let secondFeed = Feed(url: "https://example.com/second.xml", title: "Second")
        secondFeed.articles = [
            Article(title: "Ungelesen 1", isRead: false),
            Article(title: "Ungelesen 2", isRead: false)
        ]

        #expect(SidebarUnreadCount.totalUnreadArticleCount(in: [firstFeed, secondFeed]) == 3)
    }
}
