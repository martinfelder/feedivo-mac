import Foundation
import GRDB
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

    @Test func sqliteCleanupLoeschtAlteArtikelUndKorrigiertFeedZaehler() throws {
        let context = try testContext()
        let database = try FeedivoDatabase.inMemoryForTests()
        let now = Date(timeIntervalSince1970: 10_000_000)
        let oldDate = now.addingTimeInterval(-91 * 24 * 60 * 60)
        let recentDate = now.addingTimeInterval(-10 * 24 * 60 * 60)
        let feed = Feed(url: "https://example.com/feed.xml", title: "Feed")

        context.insert(feed)
        try context.save()

        let feedID = feed.id.uuidString
        try FeedStore(database: database).save(FeedRecord(id: feedID, url: feed.url, title: feed.title, unreadCount: 2))
        let articleStore = ArticleStore(database: database)
        let expiredID = try articleStore.upsert(ArticleUpsertInput(feedID: feedID, title: "Alt", publishedAt: oldDate))
        let keptID = try articleStore.upsert(ArticleUpsertInput(feedID: feedID, title: "Neu", publishedAt: recentDate))

        let removedCount = try ArticleRetentionCleanupService.removeExpiredSQLiteArticles(
            in: context,
            database: database,
            isEnabled: true,
            retentionDays: 90,
            now: now
        )

        let remaining = try TimelineStore(database: database).articles(
            scope: .feed(feedID),
            includeRead: true,
            includeHidden: true,
            limit: 10
        )
        let sqliteFeed = try FeedStore(database: database).feed(id: feedID)

        #expect(removedCount == 1)
        #expect(remaining.map(\.id) == [keptID])
        #expect(sqliteFeed?.unreadCount == 1)
        #expect(try ArticleStatusStore(database: database).status(articleID: expiredID) == nil)
    }

    @Test func sqliteCleanupSichertIdentitaetsHistorieVorDemLoeschen() throws {
        let context = try testContext()
        let database = try FeedivoDatabase.inMemoryForTests()
        let now = Date(timeIntervalSince1970: 10_000_000)
        let oldDate = now.addingTimeInterval(-91 * 24 * 60 * 60)
        let readAt = now.addingTimeInterval(-60)
        let feed = Feed(url: "https://example.com/feed.xml", title: "Feed")

        context.insert(feed)
        try context.save()

        let feedID = feed.id.uuidString
        try FeedStore(database: database).save(FeedRecord(id: feedID, url: feed.url, title: feed.title, unreadCount: 1))
        let articleStore = ArticleStore(database: database)
        let expiredID = try articleStore.upsert(ArticleUpsertInput(
            feedID: feedID,
            sourceID: "old-source",
            link: "https://example.com/old",
            title: "Alter Artikel",
            publishedAt: oldDate,
            arrivedAt: oldDate
        ))
        try ArticleStatusStore(database: database).setRead(true, articleID: expiredID, at: readAt)

        let removedCount = try ArticleRetentionCleanupService.removeExpiredSQLiteArticles(
            in: context,
            database: database,
            isEnabled: true,
            retentionDays: 90,
            now: now
        )

        let history = try database.read { db in
            try ArticleIdentityHistoryRecord.fetchOne(db, sql: """
                SELECT *
                FROM article_identity_history
                WHERE feedID = ? AND sourceID = ?
                LIMIT 1
                """, arguments: [feedID, "old-source"])
        }

        #expect(removedCount == 1)
        #expect(history?.lastArticleID == expiredID)
        #expect(history?.isRead == true)
        #expect(history?.readAt == readAt)
        #expect(history?.firstSeenAt == oldDate)
    }

    @Test func sqliteCleanupSchuetztSternUndArchivStandardmaessig() throws {
        let context = try testContext()
        let database = try FeedivoDatabase.inMemoryForTests()
        let now = Date(timeIntervalSince1970: 10_000_000)
        let oldDate = now.addingTimeInterval(-91 * 24 * 60 * 60)
        let feed = Feed(url: "https://example.com/feed.xml", title: "Feed")

        context.insert(feed)
        try context.save()

        let feedID = feed.id.uuidString
        try FeedStore(database: database).save(FeedRecord(id: feedID, url: feed.url, title: feed.title, unreadCount: 3))
        let articleStore = ArticleStore(database: database)
        let normalID = try articleStore.upsert(ArticleUpsertInput(feedID: feedID, title: "Normal", publishedAt: oldDate))
        let starredID = try articleStore.upsert(ArticleUpsertInput(feedID: feedID, title: "Stern", publishedAt: oldDate))
        let archivedID = try articleStore.upsert(ArticleUpsertInput(feedID: feedID, title: "Archiv", publishedAt: oldDate))
        let statusStore = ArticleStatusStore(database: database)
        try statusStore.setStarred(true, articleID: starredID, at: now)
        try statusStore.setArchived(true, articleID: archivedID, at: now)

        let removedCount = try ArticleRetentionCleanupService.removeExpiredSQLiteArticles(
            in: context,
            database: database,
            isEnabled: true,
            retentionDays: 90,
            now: now
        )

        let remainingIDs = try TimelineStore(database: database).articles(
            scope: .feed(feedID),
            includeRead: true,
            includeHidden: true,
            limit: 10
        ).map(\.id)

        #expect(removedCount == 1)
        #expect(!remainingIDs.contains(normalID))
        #expect(Set(remainingIDs) == [starredID, archivedID])
    }

    @Test func sqliteCleanupBeruecksichtigtFeedEigeneAufbewahrung() throws {
        let context = try testContext()
        let database = try FeedivoDatabase.inMemoryForTests()
        let now = Date(timeIntervalSince1970: 10_000_000)
        let fortyDaysOld = now.addingTimeInterval(-40 * 24 * 60 * 60)
        let customFeed = Feed(url: "https://example.com/custom.xml", title: "Kurz")
        let inheritedFeed = Feed(url: "https://example.com/inherited.xml", title: "Global")

        context.insert(customFeed)
        context.insert(inheritedFeed)
        try context.save()

        let customFeedID = customFeed.id.uuidString
        let inheritedFeedID = inheritedFeed.id.uuidString
        try FeedStore(database: database).save(
            FeedRecord(
                id: customFeedID,
                url: customFeed.url,
                title: customFeed.title,
                articleRetentionOverridesGlobalSetting: true,
                articleRetentionIsEnabled: true,
                articleRetentionDays: 30
            )
        )
        try FeedStore(database: database).save(FeedRecord(id: inheritedFeedID, url: inheritedFeed.url, title: inheritedFeed.title))
        let articleStore = ArticleStore(database: database)
        let customArticleID = try articleStore.upsert(ArticleUpsertInput(feedID: customFeedID, title: "Kurz alt", publishedAt: fortyDaysOld))
        let inheritedArticleID = try articleStore.upsert(ArticleUpsertInput(feedID: inheritedFeedID, title: "Global jung", publishedAt: fortyDaysOld))

        let removedCount = try ArticleRetentionCleanupService.removeExpiredSQLiteArticles(
            in: context,
            database: database,
            isEnabled: true,
            retentionDays: 90,
            now: now
        )

        let allIDs = try TimelineStore(database: database).articles(
            scope: .all,
            includeRead: true,
            includeHidden: true,
            limit: 10
        ).map(\.id)

        #expect(removedCount == 1)
        #expect(!allIDs.contains(customArticleID))
        #expect(allIDs == [inheritedArticleID])
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
