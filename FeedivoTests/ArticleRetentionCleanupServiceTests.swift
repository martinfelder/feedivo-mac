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

    @Test func sqliteCleanupDeindexiertGeloeschteArtikelAusSpotlight() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let now = Date(timeIntervalSince1970: 10_000_000)
        let oldDate = now.addingTimeInterval(-91 * 24 * 60 * 60)
        let feedID = UUID().uuidString

        try FeedStore(database: database).save(FeedRecord(id: feedID, url: "https://example.com/feed.xml", title: "Feed", unreadCount: 1))
        let expiredID = try ArticleStore(database: database).upsert(
            ArticleUpsertInput(feedID: feedID, title: "Alt", publishedAt: oldDate)
        )
        var deindexedIDs: [String] = []

        _ = try ArticleRetentionCleanupService.removeExpiredSQLiteArticles(
            database: database,
            isEnabled: true,
            retentionDays: 90,
            minimumArticlesPerFeed: 0,
            now: now,
            deindexForSpotlight: { deindexedIDs.append(contentsOf: $0) }
        )

        #expect(deindexedIDs == [expiredID])
    }

    @Test func sqliteCleanupRuftDeindexNichtAufWennNichtsGeloeschtWurde() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let now = Date(timeIntervalSince1970: 10_000_000)
        let feedID = UUID().uuidString

        try FeedStore(database: database).save(FeedRecord(id: feedID, url: "https://example.com/feed.xml", title: "Feed"))
        _ = try ArticleStore(database: database).upsert(
            ArticleUpsertInput(feedID: feedID, title: "Neu", publishedAt: now)
        )
        var deindexCallCount = 0

        _ = try ArticleRetentionCleanupService.removeExpiredSQLiteArticles(
            database: database,
            isEnabled: true,
            retentionDays: 90,
            minimumArticlesPerFeed: 0,
            now: now,
            deindexForSpotlight: { _ in deindexCallCount += 1 }
        )

        #expect(deindexCallCount == 0)
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
        #expect(history?.wasRemovedByRetention == true)
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

    // MARK: - Fallback auf arrivedAt bei fehlendem publishedAt
    //
    // Regressionstests für Befund B aus der Bereinigungs-Analyse vom 2026-07-13:
    // Artikel ohne parsbares Veröffentlichungsdatum (publishedAt == nil, z. B. bei
    // Feeds ohne pubDate) waren zuvor DAUERHAFT von der Bereinigung ausgenommen,
    // unabhängig vom tatsächlichen Alter. Fix: Fallback auf articles.arrivedAt
    // (NOT NULL, immer vorhanden) — dieselbe COALESCE(publishedAt, arrivedAt)-Logik,
    // die an anderer Stelle im Projekt (ArticleStore.swift Sortierung) bereits
    // etabliert ist.

    @Test func sqliteCleanupNutztArrivedAtAlsFallbackWennPublishedAtFehlt() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let now = Date(timeIntervalSince1970: 10_000_000)
        let oldArrivedAt = now.addingTimeInterval(-91 * 24 * 60 * 60)
        let feedID = UUID().uuidString

        try FeedStore(database: database).save(FeedRecord(id: feedID, url: "https://example.com/feed.xml", title: "Feed", unreadCount: 1))
        let expiredID = try ArticleStore(database: database).upsert(ArticleUpsertInput(
            feedID: feedID,
            title: "Ohne Datum, alt angekommen",
            arrivedAt: oldArrivedAt
        ))

        let removedCount = try ArticleRetentionCleanupService.removeExpiredSQLiteArticles(
            database: database,
            isEnabled: true,
            retentionDays: 90,
            minimumArticlesPerFeed: 0,
            now: now
        )

        #expect(removedCount == 1)
        #expect(try ArticleStatusStore(database: database).status(articleID: expiredID) == nil)
    }

    @Test func sqliteCleanupBehaeltArtikelOhnePublishedAtWennArrivedAtAktuellIst() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let now = Date(timeIntervalSince1970: 10_000_000)
        let recentArrivedAt = now.addingTimeInterval(-10 * 24 * 60 * 60)
        let feedID = UUID().uuidString

        try FeedStore(database: database).save(FeedRecord(id: feedID, url: "https://example.com/feed.xml", title: "Feed", unreadCount: 1))
        let keptID = try ArticleStore(database: database).upsert(ArticleUpsertInput(
            feedID: feedID,
            title: "Ohne Datum, frisch angekommen",
            arrivedAt: recentArrivedAt
        ))

        let removedCount = try ArticleRetentionCleanupService.removeExpiredSQLiteArticles(
            database: database,
            isEnabled: true,
            retentionDays: 90,
            minimumArticlesPerFeed: 0,
            now: now
        )

        #expect(removedCount == 0)
        #expect(try ArticleStatusStore(database: database).status(articleID: keptID) != nil)
    }

    @Test func sqliteCleanupSchuetztMindestanzahlAuchOhnePublishedAt() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let now = Date(timeIntervalSince1970: 10_000_000)
        let feedID = UUID().uuidString

        try FeedStore(database: database).save(FeedRecord(id: feedID, url: "https://example.com/feed.xml", title: "Feed"))
        let articleStore = ArticleStore(database: database)
        var articleIDs: [String] = []
        for index in 0..<12 {
            let arrivedAt = now.addingTimeInterval(-TimeInterval((100 + index) * 24 * 60 * 60))
            articleIDs.append(try articleStore.upsert(ArticleUpsertInput(
                feedID: feedID,
                sourceID: "article-\(index)",
                title: "Artikel \(index) ohne Datum",
                arrivedAt: arrivedAt
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

    // MARK: - Persistenter Status für automatische Bereinigung (Befund C)

    @Test func recordAutomaticCleanupSuccessSpeichertStatusUndAnzahl() throws {
        let defaults = try temporaryUserDefaults()
        let now = Date(timeIntervalSince1970: 5_000)

        ArticleRetentionCleanupService.recordAutomaticCleanupSuccess(
            removedCount: 7,
            now: now,
            userDefaults: defaults
        )

        #expect(defaults.double(forKey: ArticleRetentionSettings.lastAutomaticCleanupDateKey) == now.timeIntervalSince1970)
        #expect(defaults.string(forKey: ArticleRetentionSettings.lastAutomaticCleanupStatusKey) == ArticleRetentionSettings.statusSuccess)
        #expect(defaults.integer(forKey: ArticleRetentionSettings.lastAutomaticCleanupRemovedCountKey) == 7)
        #expect(defaults.string(forKey: ArticleRetentionSettings.lastAutomaticCleanupErrorKey) == nil)
    }

    @Test func recordAutomaticCleanupFailureSpeichertStatusUndFehlermeldung() throws {
        let defaults = try temporaryUserDefaults()
        let now = Date(timeIntervalSince1970: 5_000)

        ArticleRetentionCleanupService.recordAutomaticCleanupFailure(
            "DB-Fehler",
            now: now,
            userDefaults: defaults
        )

        #expect(defaults.double(forKey: ArticleRetentionSettings.lastAutomaticCleanupDateKey) == now.timeIntervalSince1970)
        #expect(defaults.string(forKey: ArticleRetentionSettings.lastAutomaticCleanupStatusKey) == ArticleRetentionSettings.statusFailed)
        #expect(defaults.string(forKey: ArticleRetentionSettings.lastAutomaticCleanupErrorKey) == "DB-Fehler")
    }

    @Test func runAutomaticCleanupLoeschtArtikelUndSpeichertErfolgsstatus() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let defaults = try temporaryUserDefaults()
        let now = Date(timeIntervalSince1970: 10_000_000)
        let oldDate = now.addingTimeInterval(-91 * 24 * 60 * 60)
        let feedID = UUID().uuidString

        try FeedStore(database: database).save(
            FeedRecord(id: feedID, url: "https://example.com/feed.xml", title: "Feed", unreadCount: 1)
        )
        let expiredID = try ArticleStore(database: database).upsert(
            ArticleUpsertInput(feedID: feedID, title: "Alt", publishedAt: oldDate)
        )

        ArticleRetentionCleanupService.runAutomaticCleanup(
            database: database,
            isEnabled: true,
            retentionDays: 90,
            minimumArticlesPerFeed: 0,
            triggerSource: .manual,
            userDefaults: defaults,
            now: now
        )

        #expect(try ArticleStatusStore(database: database).status(articleID: expiredID) == nil)
        #expect(defaults.string(forKey: ArticleRetentionSettings.lastAutomaticCleanupStatusKey) == ArticleRetentionSettings.statusSuccess)
        #expect(defaults.integer(forKey: ArticleRetentionSettings.lastAutomaticCleanupRemovedCountKey) == 1)
    }

    @Test func runAutomaticCleanupSchreibtHistoryEintragBeiErfolg() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let defaults = try temporaryUserDefaults()
        let now = Date(timeIntervalSince1970: 10_000_000)
        let oldDate = now.addingTimeInterval(-91 * 24 * 60 * 60)
        let feedID = UUID().uuidString

        try FeedStore(database: database).save(
            FeedRecord(id: feedID, url: "https://example.com/feed.xml", title: "Feed", unreadCount: 1)
        )
        _ = try ArticleStore(database: database).upsert(
            ArticleUpsertInput(feedID: feedID, title: "Alt", publishedAt: oldDate)
        )

        ArticleRetentionCleanupService.runAutomaticCleanup(
            database: database,
            isEnabled: true,
            retentionDays: 90,
            minimumArticlesPerFeed: 0,
            triggerSource: .schedule,
            userDefaults: defaults,
            now: now
        )

        let history = try CleanupRunHistoryStore(database: database).recentRuns()
        #expect(history.count == 1)
        #expect(history[0].deletedCount == 1)
        #expect(history[0].succeeded == true)
        #expect(history[0].triggerSource == CleanupRunTrigger.schedule.rawValue)
    }

    @Test func runAutomaticCleanupSetztToastSignalNurBeiTatsaechlichGeloeschtenArtikeln() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let defaults = try temporaryUserDefaults()
        let now = Date(timeIntervalSince1970: 10_000_000)

        ArticleRetentionCleanupService.runAutomaticCleanup(
            database: database,
            isEnabled: true,
            retentionDays: 90,
            minimumArticlesPerFeed: 0,
            triggerSource: .manual,
            userDefaults: defaults,
            now: now
        )

        #expect(defaults.integer(forKey: CleanupToastSignal.versionKey) == 0)

        let feedID = UUID().uuidString
        try FeedStore(database: database).save(
            FeedRecord(id: feedID, url: "https://example.com/feed.xml", title: "Feed", unreadCount: 1)
        )
        _ = try ArticleStore(database: database).upsert(
            ArticleUpsertInput(feedID: feedID, title: "Alt", publishedAt: now.addingTimeInterval(-91 * 24 * 60 * 60))
        )

        ArticleRetentionCleanupService.runAutomaticCleanup(
            database: database,
            isEnabled: true,
            retentionDays: 90,
            minimumArticlesPerFeed: 0,
            triggerSource: .manual,
            userDefaults: defaults,
            now: now
        )

        #expect(defaults.integer(forKey: CleanupToastSignal.versionKey) == 1)
        #expect(defaults.integer(forKey: CleanupToastSignal.deletedCountKey) == 1)
    }
}

private func temporaryUserDefaults() throws -> UserDefaults {
    let suiteName = "FeedivoTests.ArticleRetentionCleanup.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
