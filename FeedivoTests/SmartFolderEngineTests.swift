import Foundation
import Testing
@testable import Feedivo

struct SmartFolderEngineTests {
    @MainActor
    @Test func ordnerOhneBedingungenZeigtAlleArtikel() {
        let firstArticle = Article(title: "Erster Artikel")
        let secondArticle = Article(title: "Zweiter Artikel", isRead: true)
        let folder = SmartFolder(name: "Alle Artikel", matchMode: .all)

        let articles = SmartFolderEngine.matchingArticles(
            folder: folder,
            articles: [firstArticle, secondArticle]
        )

        #expect(articles.map(\.title) == ["Erster Artikel", "Zweiter Artikel"])
    }

    @MainActor
    @Test func matchesFolderUnterstuetztGlobaleUNDVerknuepfung() {
        let tag = Tag(name: "Swift", colorHex: "#3B82F6")
        let feed = Feed(url: "https://example.com/feed.xml", title: "Swift Feed", folderName: "Entwicklung")
        let article = Article(
            title: "Swift 6.2",
            summary: "Neue Async Verbesserungen",
            publishedAt: Date(),
            isRead: false,
            feed: feed
        )
        article.tags = [tag]
        let folder = SmartFolder(
            name: "Swift ungelesen",
            matchMode: .all,
            conditions: [
                SmartFolderCondition(field: .tag, conditionOperator: .is, value: tag.id.uuidString),
                SmartFolderCondition(field: .status, conditionOperator: .is, value: SmartFolderStatusValue.unread.rawValue),
                SmartFolderCondition(field: .feedFolder, conditionOperator: .is, value: "Entwicklung")
            ]
        )

        #expect(SmartFolderEngine.matches(folder: folder, article: article, now: Date()))
    }

    @MainActor
    @Test func matchesFolderUnterstuetztGlobaleODERVerknuepfung() {
        let feed = Feed(url: "https://example.com/feed.xml", title: "Apple")
        let article = Article(title: "macOS News", isStarred: true, feed: feed)
        let folder = SmartFolder(
            name: "Gespeichert",
            matchMode: .any,
            conditions: [
                SmartFolderCondition(field: .status, conditionOperator: .is, value: SmartFolderStatusValue.starred.rawValue),
                SmartFolderCondition(field: .status, conditionOperator: .is, value: SmartFolderStatusValue.archived.rawValue)
            ]
        )

        #expect(SmartFolderEngine.matches(folder: folder, article: article, now: Date()))
    }

    @MainActor
    @Test func matchingArticleCountUnterstuetztDatumTextUndAutor() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let calendar = Calendar(identifier: .gregorian)
        let feed = Feed(url: "https://example.com/feed.xml", title: "Feed")
        let matchingArticle = Article(
            title: "Swift Concurrency",
            summary: "Actor Isolation",
            content: "Structured concurrency on macOS",
            publishedAt: now,
            feed: feed
        )
        matchingArticle.author = "Apple Developer"
        let oldArticle = Article(
            title: "Swift",
            summary: "Archiv",
            publishedAt: calendar.date(byAdding: .day, value: -10, to: now),
            feed: feed
        )
        oldArticle.author = "Other"
        let folder = SmartFolder(
            name: "Heute Apple Text",
            matchMode: .all,
            conditions: [
                SmartFolderCondition(field: .date, conditionOperator: .is, value: SmartFolderDateValue.today.rawValue),
                SmartFolderCondition(field: .text, conditionOperator: .contains, value: "concurrency"),
                SmartFolderCondition(field: .author, conditionOperator: .contains, value: "apple")
            ]
        )

        let count = SmartFolderEngine.matchingArticleCount(
            folder: folder,
            articles: [matchingArticle, oldArticle],
            now: now,
            calendar: calendar
        )

        #expect(count == 1)
    }

    @MainActor
    @Test func vorbereiteterMatcherSortiertBedingungenVorDemArtikelLoop() {
        let feed = Feed(url: "https://example.com/feed.xml", title: "Feed", folderName: "Entwicklung")
        let matchingArticle = Article(title: "Swift 6.2", isRead: false, feed: feed)
        let readArticle = Article(title: "Swift 6.2 gelesen", isRead: true, feed: feed)
        let folder = SmartFolder(
            name: "Ungelesene Entwicklung",
            matchMode: .all,
            conditions: [
                SmartFolderCondition(
                    field: .status,
                    conditionOperator: .is,
                    value: SmartFolderStatusValue.unread.rawValue,
                    sortOrder: 2
                ),
                SmartFolderCondition(
                    field: .feedFolder,
                    conditionOperator: .is,
                    value: "Entwicklung",
                    sortOrder: 1
                )
            ]
        )

        let matcher = SmartFolderPreparedMatcher(folder: folder)
        let matches = matcher.matchingArticles([matchingArticle, readArticle])

        #expect(matcher.conditions.map(\.sortOrder) == [1, 2])
        #expect(matches.map(\.title) == ["Swift 6.2"])
    }

    @MainActor
    @Test func sidebarBadgeCountNutztFeedUnreadCountFuerUngelesenOrdner() {
        let firstFeed = Feed(url: "https://example.com/1.xml", title: "Feed 1")
        firstFeed.unreadCount = 3
        let secondFeed = Feed(url: "https://example.com/2.xml", title: "Feed 2")
        secondFeed.unreadCount = 4
        let unreadFolder = SmartFolder(
            name: "Ungelesen",
            matchMode: .all,
            conditions: [
                SmartFolderCondition(
                    field: .status,
                    conditionOperator: .is,
                    value: SmartFolderStatusValue.unread.rawValue
                )
            ]
        )

        let badgeText = SmartFolderSidebarBadge.badgeText(
            for: unreadFolder,
            feeds: [firstFeed, secondFeed]
        )

        #expect(badgeText == "7")
    }
}
