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
    @Test func badgeTagSignatureBleibtBeiReinemStatuswechselStabil() {
        let feed = Feed(url: "https://example.com/feed.xml", title: "Feed")
        let tag = Tag(name: "Swift")
        feed.tags = [tag]
        let initialTagSignature = SidebarBadgeSignatureBuilder.tagSignature(
            feeds: [feed],
            tags: [tag],
            directTagVersion: 0
        )
        let initialStatusSignature = SidebarBadgeSignatureBuilder.statusSignature(
            articles: []
        )

        let article = Article(title: "Artikel", feed: feed)
        article.isStarred = true
        article.isArchived = true

        let changedTagSignature = SidebarBadgeSignatureBuilder.tagSignature(
            feeds: [feed],
            tags: [tag],
            directTagVersion: 0
        )
        let changedStatusSignature = SidebarBadgeSignatureBuilder.statusSignature(
            articles: [article]
        )

        #expect(changedTagSignature == initialTagSignature)
        #expect(changedStatusSignature != initialStatusSignature)
    }

    @MainActor
    @Test func badgeTagSignatureAendertSichBeiFeedTagWechselMitGleicherAnzahl() {
        let firstTag = Tag(name: "Swift")
        let secondTag = Tag(name: "Apple")
        let feed = Feed(url: "https://example.com/feed.xml", title: "Feed")
        feed.tags = [firstTag]
        let initialSignature = SidebarBadgeSignatureBuilder.tagSignature(
            feeds: [feed],
            tags: [firstTag, secondTag],
            directTagVersion: 0
        )

        feed.tags = [secondTag]

        let changedSignature = SidebarBadgeSignatureBuilder.tagSignature(
            feeds: [feed],
            tags: [firstTag, secondTag],
            directTagVersion: 0
        )

        #expect(changedSignature != initialSignature)
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
    @Test func smartFolderBadgeZaehltSternArtikelGelesenUndUngelesen() throws {
        let context = try testContext()
        let readStarredArticle = Article(title: "Gelesener Stern", isRead: true, isStarred: true)
        let unreadStarredArticle = Article(title: "Ungelesener Stern", isRead: false, isStarred: true)
        let regularArticle = Article(title: "Normal", isRead: false)
        let folder = SmartFolder(
            name: "Mit Stern",
            matchMode: .all,
            conditions: [
                SmartFolderCondition(
                    field: .status,
                    conditionOperator: .is,
                    value: SmartFolderStatusValue.starred.rawValue
                )
            ]
        )

        context.insert(readStarredArticle)
        context.insert(unreadStarredArticle)
        context.insert(regularArticle)
        try context.save()

        #expect(SmartFolderSidebarBadge.badgeText(for: folder, feeds: [], context: context) == "2")
    }

    @MainActor
    @Test func smartFolderBadgeZaehltAusgeblendeteArtikelGelesenUndUngelesen() throws {
        let context = try testContext()
        let readHiddenArticle = Article(title: "Gelesen ausgeblendet", isRead: true, isHidden: true)
        let unreadHiddenArticle = Article(title: "Ungelesen ausgeblendet", isRead: false, isHidden: true)
        let visibleArticle = Article(title: "Sichtbar", isRead: false)
        let folder = SmartFolder(
            name: "Ausgeblendet",
            matchMode: .all,
            conditions: [
                SmartFolderCondition(
                    field: .status,
                    conditionOperator: .is,
                    value: SmartFolderStatusValue.hidden.rawValue
                )
            ]
        )

        context.insert(readHiddenArticle)
        context.insert(unreadHiddenArticle)
        context.insert(visibleArticle)
        try context.save()

        #expect(SmartFolderSidebarBadge.badgeText(for: folder, feeds: [], context: context) == "2")
    }

    @MainActor
    @Test func smartFolderBadgeZaehltGespeicherteArtikelOhneDoppelteTreffer() throws {
        let context = try testContext()
        let starredArticle = Article(title: "Stern", isRead: true, isStarred: true)
        let archivedArticle = Article(title: "Archiv", isRead: false, isArchived: true)
        let starredArchivedArticle = Article(
            title: "Stern und Archiv",
            isRead: true,
            isStarred: true,
            isArchived: true
        )
        let regularArticle = Article(title: "Normal", isRead: false)
        let folder = SmartFolder(
            name: "Gespeichert",
            matchMode: .any,
            conditions: [
                SmartFolderCondition(
                    field: .status,
                    conditionOperator: .is,
                    value: SmartFolderStatusValue.starred.rawValue
                ),
                SmartFolderCondition(
                    field: .status,
                    conditionOperator: .is,
                    value: SmartFolderStatusValue.archived.rawValue
                )
            ]
        )

        context.insert(starredArticle)
        context.insert(archivedArticle)
        context.insert(starredArchivedArticle)
        context.insert(regularArticle)
        try context.save()

        #expect(SmartFolderSidebarBadge.badgeText(for: folder, feeds: [], context: context) == "3")
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
