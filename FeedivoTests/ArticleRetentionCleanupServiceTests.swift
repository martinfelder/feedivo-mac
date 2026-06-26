import Foundation
import SwiftData
import Testing
@testable import Feedivo

@MainActor
struct ArticleRetentionCleanupServiceTests {
    @Test func cleanupIstStandardmaessigDeaktiviert() throws {
        let context = try testContext()
        let article = Article(
            title: "Alt",
            publishedAt: Date(timeIntervalSince1970: 0)
        )
        context.insert(article)
        try context.save()

        let removedCount = try ArticleRetentionCleanupService.removeExpiredArticles(
            in: context,
            isEnabled: ArticleRetentionSettings.defaultIsEnabled,
            retentionDays: ArticleRetentionSettings.defaultRetentionDays,
            now: Date(timeIntervalSince1970: 100_000_000)
        )

        let articles = try context.fetch(FetchDescriptor<Article>())
        #expect(removedCount == 0)
        #expect(articles.map(\.title) == ["Alt"])
    }

    @Test func cleanupLoeschtNurAlteArtikelOhneSternOderArchiv() throws {
        let context = try testContext()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let oldDate = now.addingTimeInterval(-91 * 24 * 60 * 60)
        let recentDate = now.addingTimeInterval(-10 * 24 * 60 * 60)

        let oldArticle = Article(title: "Alt", publishedAt: oldDate)
        let recentArticle = Article(title: "Neu", publishedAt: recentDate)
        let starredArticle = Article(title: "Stern", publishedAt: oldDate, isStarred: true)
        let archivedArticle = Article(title: "Archiv", publishedAt: oldDate, isArchived: true)
        let undatedArticle = Article(title: "Ohne Datum")

        [oldArticle, recentArticle, starredArticle, archivedArticle, undatedArticle].forEach {
            context.insert($0)
        }
        try context.save()

        let removedCount = try ArticleRetentionCleanupService.removeExpiredArticles(
            in: context,
            isEnabled: true,
            retentionDays: 90,
            now: now
        )

        let articles = try context.fetch(FetchDescriptor<Article>())
        #expect(removedCount == 1)
        #expect(Set(articles.map(\.title)) == ["Neu", "Stern", "Archiv", "Ohne Datum"])
    }

    @Test func cleanupKorrigiertFeedZaehlerNachGeloeschtenUngelesenenArtikeln() throws {
        let context = try testContext()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let oldDate = now.addingTimeInterval(-91 * 24 * 60 * 60)
        let feed = Feed(url: "https://example.com/feed.xml", title: "Feed")
        let expiredUnreadArticle = Article(
            title: "Alt ungelesen",
            publishedAt: oldDate,
            isRead: false,
            feed: feed
        )
        let keptUnreadArticle = Article(
            title: "Neu ungelesen",
            publishedAt: now,
            isRead: false,
            feed: feed
        )
        feed.articles = [expiredUnreadArticle, keptUnreadArticle]
        feed.unreadCount = 2

        context.insert(feed)
        try context.save()

        let removedCount = try ArticleRetentionCleanupService.removeExpiredArticles(
            in: context,
            isEnabled: true,
            retentionDays: 90,
            now: now
        )

        #expect(removedCount == 1)
        #expect(feed.unreadCount == 1)
    }

    @Test func cleanupKannSternUndArchivArtikelOptionalMitLoeschen() throws {
        let context = try testContext()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let oldDate = now.addingTimeInterval(-91 * 24 * 60 * 60)
        let starredArticle = Article(title: "Stern", publishedAt: oldDate, isStarred: true)
        let archivedArticle = Article(title: "Archiv", publishedAt: oldDate, isArchived: true)
        let normalArticle = Article(title: "Normal", publishedAt: oldDate)

        [starredArticle, archivedArticle, normalArticle].forEach {
            context.insert($0)
        }
        try context.save()

        let removedCount = try ArticleRetentionCleanupService.removeExpiredArticles(
            in: context,
            isEnabled: true,
            retentionDays: 90,
            includeProtectedArticles: true,
            now: now
        )

        let articles = try context.fetch(FetchDescriptor<Article>())
        #expect(removedCount == 3)
        #expect(articles.isEmpty)
    }

    @Test func cleanupBeruecksichtigtFeedEigeneAufbewahrung() throws {
        let context = try testContext()
        let now = Date(timeIntervalSince1970: 10_000_000)
        let fortyDaysOld = now.addingTimeInterval(-40 * 24 * 60 * 60)
        let customFeed = Feed(url: "https://example.com/custom.xml", title: "Kurz")
        let inheritedFeed = Feed(url: "https://example.com/inherited.xml", title: "Global")
        let customArticle = Article(title: "Kurz alt", publishedAt: fortyDaysOld, feed: customFeed)
        let inheritedArticle = Article(title: "Global jung", publishedAt: fortyDaysOld, feed: inheritedFeed)

        customFeed.articleRetentionOverridesGlobalSetting = true
        customFeed.articleRetentionIsEnabled = true
        customFeed.articleRetentionDays = 30
        customFeed.articles = [customArticle]
        inheritedFeed.articles = [inheritedArticle]

        context.insert(customFeed)
        context.insert(inheritedFeed)
        try context.save()

        let removedCount = try ArticleRetentionCleanupService.removeExpiredArticles(
            in: context,
            isEnabled: true,
            retentionDays: 90,
            now: now
        )

        let articles = try context.fetch(FetchDescriptor<Article>())
        #expect(removedCount == 1)
        #expect(articles.map(\.title) == ["Global jung"])
    }

    @Test func feedEigeneAufbewahrungKannAuchBeiGlobalAusAktivSein() throws {
        let context = try testContext()
        let now = Date(timeIntervalSince1970: 10_000_000)
        let oldDate = now.addingTimeInterval(-40 * 24 * 60 * 60)
        let feed = Feed(url: "https://example.com/custom.xml", title: "Kurz")
        let article = Article(title: "Feed alt", publishedAt: oldDate, feed: feed)

        feed.articleRetentionOverridesGlobalSetting = true
        feed.articleRetentionIsEnabled = true
        feed.articleRetentionDays = 30
        feed.articles = [article]

        context.insert(feed)
        try context.save()

        let removedCount = try ArticleRetentionCleanupService.removeExpiredArticles(
            in: context,
            isEnabled: false,
            retentionDays: 90,
            now: now
        )

        let articles = try context.fetch(FetchDescriptor<Article>())
        #expect(removedCount == 1)
        #expect(articles.isEmpty)
    }

    @Test func retentionSettingsKlemmenUnbekannteWerte() {
        #expect(ArticleRetentionSettings.clampedRetentionDays(100) == 90)
        #expect(ArticleRetentionSettings.clampedRetentionDays(400) == 365)
    }

    private func testContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Feed.self,
            FeedFolder.self,
            FeedLogEntry.self,
            Article.self,
            Tag.self,
            Rule.self,
            RuleCondition.self,
            SmartFolder.self,
            SmartFolderCondition.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }
}
