import Foundation
import GRDB
import Testing
@testable import Feedivo

@MainActor
struct ArticleRetentionCleanupServiceTests {
    @Test func retentionSettingsKlemmenUnbekannteWerte() {
        #expect(ArticleRetentionSettings.clampedRetentionDays(100) == 90)
        #expect(ArticleRetentionSettings.clampedRetentionDays(400) == 365)
    }

    @Test func retentionSettingsKlemmenMindestartikelProFeed() {
        #expect(ArticleRetentionSettings.clampedMinimumArticlesPerFeed(-5) == 0)
        #expect(ArticleRetentionSettings.clampedMinimumArticlesPerFeed(17) == 20)
        #expect(ArticleRetentionSettings.clampedMinimumArticlesPerFeed(80) == 100)
    }

    @Test func sqliteCleanupLoeschtAlteArtikelUndKorrigiertFeedZaehler() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let now = Date(timeIntervalSince1970: 10_000_000)
        let oldDate = now.addingTimeInterval(-91 * 24 * 60 * 60)
        let recentDate = now.addingTimeInterval(-10 * 24 * 60 * 60)
        let feedID = UUID().uuidString
        let feedURL = "https://example.com/feed.xml"
        let feedTitle = "Feed"

        try FeedStore(database: database).save(FeedRecord(id: feedID, url: feedURL, title: feedTitle, unreadCount: 2))
        let articleStore = ArticleStore(database: database)
        let expiredID = try articleStore.upsert(ArticleUpsertInput(feedID: feedID, title: "Alt", publishedAt: oldDate))
        let keptID = try articleStore.upsert(ArticleUpsertInput(feedID: feedID, title: "Neu", publishedAt: recentDate))

        let removedCount = try ArticleRetentionCleanupService.removeExpiredSQLiteArticles(
            database: database,
            isEnabled: true,
            retentionDays: 90,
            minimumArticlesPerFeed: 0,
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
        let database = try FeedivoDatabase.inMemoryForTests()
        let now = Date(timeIntervalSince1970: 10_000_000)
        let oldDate = now.addingTimeInterval(-91 * 24 * 60 * 60)
        let readAt = now.addingTimeInterval(-60)
        let feedID = UUID().uuidString
        let feedURL = "https://example.com/feed.xml"
        let feedTitle = "Feed"

        try FeedStore(database: database).save(FeedRecord(id: feedID, url: feedURL, title: feedTitle, unreadCount: 1))
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
            database: database,
            isEnabled: true,
            retentionDays: 90,
            minimumArticlesPerFeed: 0,
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
        let database = try FeedivoDatabase.inMemoryForTests()
        let now = Date(timeIntervalSince1970: 10_000_000)
        let oldDate = now.addingTimeInterval(-91 * 24 * 60 * 60)
        let feedID = UUID().uuidString
        let feedURL = "https://example.com/feed.xml"
        let feedTitle = "Feed"

        try FeedStore(database: database).save(FeedRecord(id: feedID, url: feedURL, title: feedTitle, unreadCount: 3))
        let articleStore = ArticleStore(database: database)
        let normalID = try articleStore.upsert(ArticleUpsertInput(feedID: feedID, title: "Normal", publishedAt: oldDate))
        let starredID = try articleStore.upsert(ArticleUpsertInput(feedID: feedID, title: "Stern", publishedAt: oldDate))
        let archivedID = try articleStore.upsert(ArticleUpsertInput(feedID: feedID, title: "Archiv", publishedAt: oldDate))
        let statusStore = ArticleStatusStore(database: database)
        try statusStore.setStarred(true, articleID: starredID, at: now)
        try statusStore.setArchived(true, articleID: archivedID, at: now)

        let removedCount = try ArticleRetentionCleanupService.removeExpiredSQLiteArticles(
            database: database,
            isEnabled: true,
            retentionDays: 90,
            minimumArticlesPerFeed: 0,
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
        let database = try FeedivoDatabase.inMemoryForTests()
        let now = Date(timeIntervalSince1970: 10_000_000)
        let fortyDaysOld = now.addingTimeInterval(-40 * 24 * 60 * 60)
        let customFeedID = UUID().uuidString
        let customFeedURL = "https://example.com/custom.xml"
        let customFeedTitle = "Kurz"
        let inheritedFeedID = UUID().uuidString
        let inheritedFeedURL = "https://example.com/inherited.xml"
        let inheritedFeedTitle = "Global"

        try FeedStore(database: database).save(
            FeedRecord(
                id: customFeedID,
                url: customFeedURL,
                title: customFeedTitle,
                articleRetentionOverridesGlobalSetting: true,
                articleRetentionIsEnabled: true,
                articleRetentionDays: 30,
                articleRetentionMinimumArticles: 0
            )
        )
        try FeedStore(database: database).save(FeedRecord(id: inheritedFeedID, url: inheritedFeedURL, title: inheritedFeedTitle))
        let articleStore = ArticleStore(database: database)
        let customArticleID = try articleStore.upsert(ArticleUpsertInput(feedID: customFeedID, title: "Kurz alt", publishedAt: fortyDaysOld))
        let inheritedArticleID = try articleStore.upsert(ArticleUpsertInput(feedID: inheritedFeedID, title: "Global jung", publishedAt: fortyDaysOld))

        let removedCount = try ArticleRetentionCleanupService.removeExpiredSQLiteArticles(
            database: database,
            isEnabled: true,
            retentionDays: 90,
            minimumArticlesPerFeed: 0,
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

    @Test func sqliteCleanupBehaeltMindestanzahlProFeed() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let now = Date(timeIntervalSince1970: 10_000_000)
        let feedID = UUID().uuidString
        let feedURL = "https://example.com/feed.xml"
        let feedTitle = "Feed"

        try FeedStore(database: database).save(FeedRecord(id: feedID, url: feedURL, title: feedTitle))
        let articleStore = ArticleStore(database: database)
        var articleIDs: [String] = []
        for index in 0..<12 {
            let publishedAt = now.addingTimeInterval(-TimeInterval((100 + index) * 24 * 60 * 60))
            articleIDs.append(try articleStore.upsert(ArticleUpsertInput(
                feedID: feedID,
                sourceID: "article-\(index)",
                title: "Artikel \(index)",
                publishedAt: publishedAt,
                arrivedAt: publishedAt
            )))
        }

        let removedCount = try ArticleRetentionCleanupService.removeExpiredSQLiteArticles(
            database: database,
            isEnabled: true,
            retentionDays: 90,
            minimumArticlesPerFeed: 10,
            now: now
        )

        let remainingIDs = try TimelineStore(database: database).articles(
            scope: .feed(feedID),
            includeRead: true,
            includeHidden: true,
            limit: 10
        ).map(\.id)

        #expect(removedCount == 2)
        #expect(Set(remainingIDs) == Set(articleIDs.prefix(10)))
    }
}
