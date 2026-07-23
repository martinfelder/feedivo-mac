import Foundation
import Testing
@testable import Feedivo

struct BackgroundRefreshServiceTests {

    @Test func scheduleNextRefreshPlantNichtsWennDeaktiviert() throws {
        let scheduler = RecordingBackgroundTaskScheduler()

        try BackgroundRefreshService.scheduleNextRefresh(
            isEnabled: false,
            intervalMinutes: 30,
            now: Date(timeIntervalSince1970: 1_000),
            scheduler: scheduler
        )

        #expect(scheduler.submittedRequests.isEmpty)
        #expect(scheduler.cancelledIdentifiers == [BackgroundRefreshService.taskIdentifier])
    }

    @Test func scheduleNextRefreshPlantTaskMitGeklemmtemStartdatum() throws {
        let scheduler = RecordingBackgroundTaskScheduler()
        let defaults = try temporaryUserDefaults()
        let now = Date(timeIntervalSince1970: 1_000)

        try BackgroundRefreshService.scheduleNextRefresh(
            isEnabled: true,
            intervalMinutes: 44,
            now: now,
            scheduler: scheduler,
            userDefaults: defaults
        )

        let request = try #require(scheduler.submittedRequests.first)
        #expect(request.identifier == BackgroundRefreshService.taskIdentifier)
        #expect(request.intervalMinutes == 30)
        #expect(request.earliestBeginDate == now.addingTimeInterval(30 * 60))
        #expect(defaults.double(forKey: BackgroundRefreshSettings.nextAutomaticRefreshDateKey) == now.addingTimeInterval(30 * 60).timeIntervalSince1970)
    }

    @Test func scheduleNextRefreshEntferntNaechstenZeitpunktWennDeaktiviert() throws {
        let scheduler = RecordingBackgroundTaskScheduler()
        let defaults = try temporaryUserDefaults()
        defaults.set(2_000.0, forKey: BackgroundRefreshSettings.nextAutomaticRefreshDateKey)

        try BackgroundRefreshService.scheduleNextRefresh(
            isEnabled: false,
            intervalMinutes: 30,
            now: Date(timeIntervalSince1970: 1_000),
            scheduler: scheduler,
            userDefaults: defaults
        )

        #expect(defaults.object(forKey: BackgroundRefreshSettings.nextAutomaticRefreshDateKey) == nil)
    }

    @Test func scheduleNextRefreshSpeichertPlanungsfehlerOhneNaechstenZeitpunkt() throws {
        let scheduler = RecordingBackgroundTaskScheduler(errorToThrow: TestBackgroundRefreshError())
        let defaults = try temporaryUserDefaults()
        let now = Date(timeIntervalSince1970: 1_000)

        do {
            try BackgroundRefreshService.scheduleNextRefresh(
                isEnabled: true,
                intervalMinutes: 30,
                now: now,
                scheduler: scheduler,
                userDefaults: defaults
            )
            Issue.record("Planung sollte fehlschlagen")
        } catch {
            #expect(defaults.object(forKey: BackgroundRefreshSettings.nextAutomaticRefreshDateKey) == nil)
            #expect(defaults.double(forKey: BackgroundRefreshSettings.lastAutomaticRefreshDateKey) == now.timeIntervalSince1970)
            #expect(defaults.string(forKey: BackgroundRefreshSettings.lastAutomaticRefreshStatusKey) == BackgroundRefreshSettings.statusFailed)
            #expect(defaults.string(forKey: BackgroundRefreshSettings.lastAutomaticRefreshErrorKey) == "Planung fehlgeschlagen")
        }
    }

    @Test func recordRefreshSuccessSpeichertStatusUndNaechstenZeitpunkt() throws {
        let defaults = try temporaryUserDefaults()
        let now = Date(timeIntervalSince1970: 1_000)

        BackgroundRefreshService.recordRefreshSuccess(
            now: now,
            intervalMinutes: 44,
            userDefaults: defaults
        )

        #expect(defaults.double(forKey: BackgroundRefreshSettings.lastAutomaticRefreshDateKey) == now.timeIntervalSince1970)
        #expect(defaults.string(forKey: BackgroundRefreshSettings.lastAutomaticRefreshStatusKey) == BackgroundRefreshSettings.statusSuccess)
        #expect(defaults.string(forKey: BackgroundRefreshSettings.lastAutomaticRefreshErrorKey) == nil)
        #expect(defaults.double(forKey: BackgroundRefreshSettings.nextAutomaticRefreshDateKey) == now.addingTimeInterval(30 * 60).timeIntervalSince1970)
    }

    @Test func recordRefreshFailureSpeichertStatusUndFehlermeldung() throws {
        let defaults = try temporaryUserDefaults()
        let now = Date(timeIntervalSince1970: 1_000)

        BackgroundRefreshService.recordRefreshFailure(
            "Netzwerkfehler",
            now: now,
            intervalMinutes: 30,
            userDefaults: defaults
        )

        #expect(defaults.double(forKey: BackgroundRefreshSettings.lastAutomaticRefreshDateKey) == now.timeIntervalSince1970)
        #expect(defaults.string(forKey: BackgroundRefreshSettings.lastAutomaticRefreshStatusKey) == BackgroundRefreshSettings.statusFailed)
        #expect(defaults.string(forKey: BackgroundRefreshSettings.lastAutomaticRefreshErrorKey) == "Netzwerkfehler")
        #expect(defaults.double(forKey: BackgroundRefreshSettings.nextAutomaticRefreshDateKey) == now.addingTimeInterval(30 * 60).timeIntervalSince1970)
    }

    @Test func recordRefreshPartialSpeichertStatusPartialUndMeldung() throws {
        let defaults = try temporaryUserDefaults()
        let now = Date(timeIntervalSince1970: 1_000)

        BackgroundRefreshService.recordRefreshPartial(
            "2 Feeds nicht erreichbar",
            failedCount: 2,
            now: now,
            intervalMinutes: 30,
            userDefaults: defaults
        )

        #expect(defaults.double(forKey: BackgroundRefreshSettings.lastAutomaticRefreshDateKey) == now.timeIntervalSince1970)
        #expect(defaults.string(forKey: BackgroundRefreshSettings.lastAutomaticRefreshStatusKey) == BackgroundRefreshSettings.statusPartial)
        #expect(defaults.string(forKey: BackgroundRefreshSettings.lastAutomaticRefreshErrorKey) == "2 Feeds nicht erreichbar")
        #expect(defaults.double(forKey: BackgroundRefreshSettings.nextAutomaticRefreshDateKey) == now.addingTimeInterval(30 * 60).timeIntervalSince1970)
    }

    // MARK: - cleanupOnAppStartIfNeeded / cleanupOnScheduleIfDue
    //
    // Regressionstests für den Bugfix vom 2026-07-13 (Nutzer-Report: "Alte Artikel
    // bleiben trotz aktivierter Bereinigung liegen, auch nach Tagen im Hintergrund").
    // Root Cause: ArticleRetentionCleanupService wurde bisher nur beim App-Start und
    // bei Einstellungsänderungen aufgerufen, nie vom periodischen Hintergrund-Refresh.
    // Feature 17.3a spaltet den bisherigen einzelnen `cleanupExpiredArticlesIfNeeded`-
    // Auslöser in einen App-Start-Auslöser und einen Zeitplan-Auslöser auf.

    @MainActor
    @Test func cleanupOnAppStartIfNeededLoeschtAlteArtikelWennAktiviert() throws {
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

        defaults.set(true, forKey: ArticleRetentionSettings.isEnabledKey)
        defaults.set(90, forKey: ArticleRetentionSettings.retentionDaysKey)
        defaults.set(0, forKey: ArticleRetentionSettings.minimumArticlesPerFeedKey)
        defaults.set(false, forKey: ArticleRetentionSettings.includesProtectedArticlesKey)

        BackgroundRefreshService.cleanupOnAppStartIfNeeded(
            database: database,
            userDefaults: defaults,
            now: now
        )

        #expect(try ArticleStatusStore(database: database).status(articleID: expiredID) == nil)
    }

    @MainActor
    @Test func cleanupOnAppStartIfNeededTutNichtsWennKeineEinstellungenGespeichertSind() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let defaults = try temporaryUserDefaults()
        let now = Date(timeIntervalSince1970: 10_000_000)
        let oldDate = now.addingTimeInterval(-400 * 24 * 60 * 60)
        let feedID = UUID().uuidString

        try FeedStore(database: database).save(
            FeedRecord(id: feedID, url: "https://example.com/feed.xml", title: "Feed", unreadCount: 1)
        )
        let expiredID = try ArticleStore(database: database).upsert(
            ArticleUpsertInput(feedID: feedID, title: "Sehr alt", publishedAt: oldDate)
        )

        BackgroundRefreshService.cleanupOnAppStartIfNeeded(
            database: database,
            userDefaults: defaults,
            now: now
        )

        #expect(try ArticleStatusStore(database: database).status(articleID: expiredID) != nil)
    }

    @MainActor
    @Test func cleanupOnAppStartIfNeededNutztStandardAufbewahrungWennNurAktivierungGespeichertIst() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let defaults = try temporaryUserDefaults()
        let now = Date(timeIntervalSince1970: 10_000_000)
        let fortyDaysOld = now.addingTimeInterval(-40 * 24 * 60 * 60)
        let feedID = UUID().uuidString

        try FeedStore(database: database).save(
            FeedRecord(id: feedID, url: "https://example.com/feed.xml", title: "Feed", unreadCount: 1)
        )
        let articleID = try ArticleStore(database: database).upsert(
            ArticleUpsertInput(feedID: feedID, title: "40 Tage alt", publishedAt: fortyDaysOld)
        )

        defaults.set(true, forKey: ArticleRetentionSettings.isEnabledKey)

        BackgroundRefreshService.cleanupOnAppStartIfNeeded(
            database: database,
            userDefaults: defaults,
            now: now
        )

        #expect(try ArticleStatusStore(database: database).status(articleID: articleID) != nil)
    }

    @MainActor
    @Test func cleanupOnAppStartIfNeededTutNichtsWennSchalterAus() throws {
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

        defaults.set(true, forKey: ArticleRetentionSettings.isEnabledKey)
        defaults.set(90, forKey: ArticleRetentionSettings.retentionDaysKey)
        defaults.set(false, forKey: CleanupScheduleSettings.runOnAppStartKey)

        BackgroundRefreshService.cleanupOnAppStartIfNeeded(
            database: database,
            userDefaults: defaults,
            now: now
        )

        #expect(try ArticleStatusStore(database: database).status(articleID: expiredID) != nil)
    }

    @MainActor
    @Test func cleanupOnScheduleIfDueTutNichtsWennZeitplanNichtFaellig() throws {
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

        defaults.set(true, forKey: ArticleRetentionSettings.isEnabledKey)
        defaults.set(90, forKey: ArticleRetentionSettings.retentionDaysKey)
        // CleanupScheduleSettings.runOnWeekdayTimeKey bewusst NICHT gesetzt → Default false.

        BackgroundRefreshService.cleanupOnScheduleIfDue(database: database, userDefaults: defaults, now: now)

        #expect(try ArticleStatusStore(database: database).status(articleID: expiredID) != nil)
    }

    @MainActor
    @Test func cleanupOnScheduleIfDueLoeschtArtikelUndProtokolliertLaufWennFaellig() throws {
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

        defaults.set(true, forKey: ArticleRetentionSettings.isEnabledKey)
        defaults.set(90, forKey: ArticleRetentionSettings.retentionDaysKey)
        // minimumArticlesPerFeedKey explizit auf 0 — sonst würde der Standardwert
        // (defaultMinimumArticlesPerFeed = 20) den einzigen Artikel dieses Feeds
        // vor der Löschung schützen (Mindestanzahl-pro-Feed-Regel).
        defaults.set(0, forKey: ArticleRetentionSettings.minimumArticlesPerFeedKey)
        defaults.set(false, forKey: ArticleRetentionSettings.includesProtectedArticlesKey)
        defaults.set(true, forKey: CleanupScheduleSettings.runOnWeekdayTimeKey)
        // lastScheduleRunAtKey bewusst nie gesetzt → beim ersten Aufruf immer fällig.

        BackgroundRefreshService.cleanupOnScheduleIfDue(database: database, userDefaults: defaults, now: now)

        #expect(try ArticleStatusStore(database: database).status(articleID: expiredID) == nil)
        #expect(defaults.object(forKey: CleanupScheduleSettings.lastScheduleRunAtKey) as? Date == now)
    }

    // Root-Cause-Fund (Nutzer-Report 2026-07-23): `NSBackgroundActivityScheduler`
    // (Foundation) kennt kein `earliestBeginDate` (anders als `BGTaskRequest`
    // aus dem hier bewusst nicht genutzten BackgroundTasks-Framework) — der
    // allererste Tick nach `schedule(...)` konnte dadurch praktisch sofort
    // feuern und kollidierte beim App-Start mit dem separaten "Feeds beim
    // App-Start aktualisieren"-Refresh. `isPrematureTick` ist die daraus
    // extrahierte, direkt testbare Entscheidungslogik, die `submit(_:)`
    // seither im Scheduler-Callback selbst durchsetzt.
    @Test func isPrematureTickIstFalseOhneEarliestBeginDate() {
        #expect(!BackgroundRefreshService.isPrematureTick(
            earliestBeginDate: nil,
            now: Date(timeIntervalSince1970: 1_000)
        ))
    }

    @Test func isPrematureTickIstTrueVorDerEarliestBeginDate() {
        let earliestBeginDate = Date(timeIntervalSince1970: 2_000)
        #expect(BackgroundRefreshService.isPrematureTick(
            earliestBeginDate: earliestBeginDate,
            now: Date(timeIntervalSince1970: 1_000)
        ))
    }

    @Test func isPrematureTickIstFalseAbDerEarliestBeginDate() {
        let earliestBeginDate = Date(timeIntervalSince1970: 2_000)
        #expect(!BackgroundRefreshService.isPrematureTick(
            earliestBeginDate: earliestBeginDate,
            now: earliestBeginDate
        ))
        #expect(!BackgroundRefreshService.isPrematureTick(
            earliestBeginDate: earliestBeginDate,
            now: Date(timeIntervalSince1970: 3_000)
        ))
    }
}

private func temporaryUserDefaults() throws -> UserDefaults {
    let suiteName = "FeedivoTests.BackgroundRefresh.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

private final class RecordingBackgroundTaskScheduler: BackgroundRefreshScheduling {
    let errorToThrow: Error?
    private(set) var submittedRequests: [BackgroundRefreshRequest] = []
    private(set) var cancelledIdentifiers: [String] = []

    init(errorToThrow: Error? = nil) {
        self.errorToThrow = errorToThrow
    }

    func submit(_ request: BackgroundRefreshRequest) throws {
        if let errorToThrow {
            throw errorToThrow
        }

        submittedRequests.append(request)
    }

    func cancel(identifier: String) {
        cancelledIdentifiers.append(identifier)
    }
}

private struct TestBackgroundRefreshError: LocalizedError {
    var errorDescription: String? {
        "Planung fehlgeschlagen"
    }
}
