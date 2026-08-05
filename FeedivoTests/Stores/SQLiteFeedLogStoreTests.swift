import Foundation
import Testing
@testable import Feedivo

struct SQLiteFeedLogStoreTests {
    @Test func appendLogPersistsNewestFirst() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let logStore = FeedLogStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))
        try logStore.append(FeedLogRecord(
            id: "old",
            feedID: "feed-1",
            createdAt: Date(timeIntervalSince1970: 1_000),
            level: "info",
            message: "Old",
            newArticleCount: 1
        ))
        try logStore.append(FeedLogRecord(
            id: "new",
            feedID: "feed-1",
            createdAt: Date(timeIntervalSince1970: 2_000),
            level: "error",
            message: "New",
            httpStatusCode: 500,
            newArticleCount: 0
        ))

        let logs = try logStore.logs(feedID: "feed-1", limit: 10)

        #expect(logs.map(\.id) == ["new", "old"])
        #expect(logs.first?.level == "error")
        #expect(logs.first?.httpStatusCode == 500)
    }

    @Test func deleteOlderThanEntferntNurAeltereEintraege() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let logStore = FeedLogStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))
        try logStore.append(FeedLogRecord(
            id: "old",
            feedID: "feed-1",
            createdAt: Date(timeIntervalSince1970: 1_000),
            level: "info",
            message: "Old"
        ))
        try logStore.append(FeedLogRecord(
            id: "new",
            feedID: "feed-1",
            createdAt: Date(timeIntervalSince1970: 5_000),
            level: "info",
            message: "New"
        ))

        let deletedCount = try logStore.deleteOlderThan(Date(timeIntervalSince1970: 3_000))

        #expect(deletedCount == 1)
        let remaining = try logStore.logs(feedID: "feed-1", limit: 10)
        #expect(remaining.map(\.id) == ["new"])
    }

    @Test func deleteOlderThanFunktioniertBeiLeererTabelle() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let logStore = FeedLogStore(database: database)

        let deletedCount = try logStore.deleteOlderThan(Date())

        #expect(deletedCount == 0)
    }

    @Test func latestAttemptTimesLiefertNeuestenZeitstempelJeFeed() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let logStore = FeedLogStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://one.example/feed.xml", title: "One"))
        try feedStore.save(FeedRecord(id: "feed-2", url: "https://two.example/feed.xml", title: "Two"))
        try feedStore.save(FeedRecord(id: "feed-3", url: "https://three.example/feed.xml", title: "Three"))

        try logStore.append(FeedLogRecord(
            feedID: "feed-1",
            createdAt: Date(timeIntervalSince1970: 1_000),
            level: "info",
            message: "Alt"
        ))
        try logStore.append(FeedLogRecord(
            feedID: "feed-1",
            createdAt: Date(timeIntervalSince1970: 2_000),
            level: "error",
            message: "Neu, aber fehlgeschlagen"
        ))
        try logStore.append(FeedLogRecord(
            feedID: "feed-2",
            createdAt: Date(timeIntervalSince1970: 500),
            level: "info",
            message: "Einziger Versuch"
        ))

        let attemptTimes = try logStore.latestAttemptTimes()

        #expect(attemptTimes["feed-1"] == Date(timeIntervalSince1970: 2_000))
        #expect(attemptTimes["feed-2"] == Date(timeIntervalSince1970: 500))
        #expect(attemptTimes["feed-3"] == nil)
    }

    @Test func failureDiagnosticsIstLeerOhneFehlgeschlageneFeeds() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let logStore = FeedLogStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))
        try logStore.append(FeedLogRecord(
            feedID: "feed-1",
            createdAt: Date(timeIntervalSince1970: 1_000),
            level: "info",
            message: "Aktualisiert"
        ))

        let diagnostics = try logStore.failureDiagnostics()

        #expect(diagnostics.isEmpty)
    }

    @Test func failureDiagnosticsLiefertFeedMitEinzelnemFehlschlag() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let logStore = FeedLogStore(database: database)

        try feedStore.save(FeedRecord(
            id: "feed-1",
            url: "https://example.com/feed.xml",
            title: "Example",
            websiteURL: "https://example.com",
            faviconURL: "https://example.com/favicon.ico"
        ))
        try logStore.append(FeedLogRecord(
            feedID: "feed-1",
            createdAt: Date(timeIntervalSince1970: 1_000),
            level: "info",
            message: "Aktualisiert"
        ))
        try logStore.append(FeedLogRecord(
            feedID: "feed-1",
            createdAt: Date(timeIntervalSince1970: 2_000),
            level: "error",
            message: "Zeitüberschreitung",
            httpStatusCode: nil,
            newArticleCount: 0
        ))

        let diagnostics = try logStore.failureDiagnostics()

        #expect(diagnostics.count == 1)
        let diagnostic = diagnostics[0]
        #expect(diagnostic.feedID == "feed-1")
        #expect(diagnostic.feedTitle == "Example")
        #expect(diagnostic.feedURL == "https://example.com/feed.xml")
        #expect(diagnostic.feedWebsiteURL == "https://example.com")
        #expect(diagnostic.feedFaviconURL == "https://example.com/favicon.ico")
        #expect(diagnostic.errorMessage == "Zeitüberschreitung")
        #expect(diagnostic.httpStatusCode == nil)
        #expect(diagnostic.lastAttemptAt == Date(timeIntervalSince1970: 2_000))
        #expect(diagnostic.consecutiveFailureCount == 1)
    }

    @Test func failureDiagnosticsZaehltErstenJemalsProtokolliertenFehlerAlsSerieEins() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let logStore = FeedLogStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))
        try logStore.append(FeedLogRecord(
            feedID: "feed-1",
            createdAt: Date(timeIntervalSince1970: 1_000),
            level: "error",
            message: "Erster Versuch schlägt fehl"
        ))

        let diagnostics = try logStore.failureDiagnostics()

        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].consecutiveFailureCount == 1)
    }

    @Test func failureDiagnosticsBrichtGleichstandBeiIdentischemZeitstempelDeterministischAuf() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let logStore = FeedLogStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))
        let sharedTimestamp = Date(timeIntervalSince1970: 2_000)
        try logStore.append(FeedLogRecord(
            id: "aaa-first",
            feedID: "feed-1",
            createdAt: sharedTimestamp,
            level: "error",
            message: "Erster Fehler am selben Zeitstempel"
        ))
        try logStore.append(FeedLogRecord(
            id: "zzz-second",
            feedID: "feed-1",
            createdAt: sharedTimestamp,
            level: "error",
            message: "Zweiter Fehler am selben Zeitstempel"
        ))

        let diagnostics = try logStore.failureDiagnostics()

        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].consecutiveFailureCount == 2)
        #expect(diagnostics[0].errorMessage == "Zweiter Fehler am selben Zeitstempel")
    }

    @Test func failureDiagnosticsZaehltAufeinanderfolgendeFehlschlaegeKorrekt() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let logStore = FeedLogStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))
        try logStore.append(FeedLogRecord(
            feedID: "feed-1",
            createdAt: Date(timeIntervalSince1970: 1_000),
            level: "info",
            message: "Aktualisiert"
        ))
        try logStore.append(FeedLogRecord(
            feedID: "feed-1",
            createdAt: Date(timeIntervalSince1970: 2_000),
            level: "error",
            message: "Erster Fehler",
            httpStatusCode: 500
        ))
        try logStore.append(FeedLogRecord(
            feedID: "feed-1",
            createdAt: Date(timeIntervalSince1970: 3_000),
            level: "error",
            message: "Zweiter Fehler",
            httpStatusCode: 500
        ))
        try logStore.append(FeedLogRecord(
            feedID: "feed-1",
            createdAt: Date(timeIntervalSince1970: 4_000),
            level: "error",
            message: "Dritter Fehler",
            httpStatusCode: 404
        ))

        let diagnostics = try logStore.failureDiagnostics()

        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].consecutiveFailureCount == 3)
        #expect(diagnostics[0].errorMessage == "Dritter Fehler")
        #expect(diagnostics[0].httpStatusCode == 404)
    }

    @Test func failureDiagnosticsIgnoriertFeedNachErneutErfolgreichemVersuch() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let logStore = FeedLogStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))
        try logStore.append(FeedLogRecord(
            feedID: "feed-1",
            createdAt: Date(timeIntervalSince1970: 1_000),
            level: "error",
            message: "Alter Fehler"
        ))
        try logStore.append(FeedLogRecord(
            feedID: "feed-1",
            createdAt: Date(timeIntervalSince1970: 2_000),
            level: "info",
            message: "Wieder aktualisiert"
        ))

        let diagnostics = try logStore.failureDiagnostics()

        #expect(diagnostics.isEmpty)
    }

    @Test func failureDiagnosticsSortiertNachNeuestemVersuchZuerst() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let logStore = FeedLogStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://one.example/feed.xml", title: "One"))
        try feedStore.save(FeedRecord(id: "feed-2", url: "https://two.example/feed.xml", title: "Two"))
        try logStore.append(FeedLogRecord(
            feedID: "feed-1",
            createdAt: Date(timeIntervalSince1970: 1_000),
            level: "error",
            message: "Älterer Fehler"
        ))
        try logStore.append(FeedLogRecord(
            feedID: "feed-2",
            createdAt: Date(timeIntervalSince1970: 5_000),
            level: "error",
            message: "Neuerer Fehler"
        ))

        let diagnostics = try logStore.failureDiagnostics()

        #expect(diagnostics.map(\.feedID) == ["feed-2", "feed-1"])
    }
}
