import Testing
@testable import Feedivo

struct SidebarUnreadCountTests {
    @MainActor
    @Test func feedUnreadCountNutztVorberechneteUngelesenMapUndReagiertAufStatuswechsel() {
        let feed = Feed(url: "https://example.com/feed.xml", title: "Test Feed")
        let firstUnreadArticle = Article(title: "Ungelesen 1", isRead: false, feed: feed)
        let secondUnreadArticle = Article(title: "Ungelesen 2", isRead: false, feed: feed)

        var unreadArticles = [firstUnreadArticle, secondUnreadArticle]
        var unreadCountsByFeed = SidebarUnreadCount.unreadCountsByFeed(in: unreadArticles)

        #expect(SidebarUnreadCount.unreadArticleCount(for: feed, in: unreadCountsByFeed) == 2)

        firstUnreadArticle.isRead = true
        unreadArticles = [secondUnreadArticle]
        unreadCountsByFeed = SidebarUnreadCount.unreadCountsByFeed(in: unreadArticles)

        #expect(SidebarUnreadCount.unreadArticleCount(for: feed, in: unreadCountsByFeed) == 1)
    }

    @Test func badgeTextIstNurFuerPositiveZaehlerSichtbar() {
        #expect(SidebarUnreadCount.badgeText(for: 0) == nil)
        #expect(SidebarUnreadCount.badgeText(for: 7) == "7")
    }

    @MainActor
    @Test func totalUnreadCountZaehltUngeleseneArtikelDirekt() {
        let firstFeed = Feed(url: "https://example.com/first.xml", title: "First")
        let secondFeed = Feed(url: "https://example.com/second.xml", title: "Second")
        let unreadArticles = [
            Article(title: "Ungelesen", isRead: false, feed: firstFeed),
            Article(title: "Ungelesen 1", isRead: false, feed: secondFeed),
            Article(title: "Ungelesen 2", isRead: false, feed: secondFeed)
        ]

        #expect(SidebarUnreadCount.totalUnreadArticleCount(in: unreadArticles) == 3)
    }
}
