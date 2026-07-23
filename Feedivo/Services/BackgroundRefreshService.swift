import Foundation
struct BackgroundRefreshRequest {
    let identifier: String
    let intervalMinutes: Int
    let earliestBeginDate: Date?
}

protocol BackgroundRefreshScheduling {
    func submit(_ request: BackgroundRefreshRequest) throws
    func cancel(identifier: String)
}

extension BackgroundRefreshScheduling {
    func cancel(identifier: String) {}
}

@MainActor
final class SystemBackgroundActivityRefreshScheduler: BackgroundRefreshScheduling {
    private let feedivoDatabase: FeedivoDatabase
    private let feedViewModel: FeedViewModel
    private var scheduler: NSBackgroundActivityScheduler?

    init(feedivoDatabase: FeedivoDatabase, feedViewModel: FeedViewModel) {
        self.feedivoDatabase = feedivoDatabase
        self.feedViewModel = feedViewModel
    }

    func submit(_ request: BackgroundRefreshRequest) throws {
        scheduler?.invalidate()

        let scheduler = NSBackgroundActivityScheduler(identifier: request.identifier)
        scheduler.repeats = true
        scheduler.interval = TimeInterval(request.intervalMinutes * 60)
        scheduler.tolerance = TimeInterval(max(60, request.intervalMinutes * 60 / 4))
        scheduler.schedule { [feedivoDatabase, feedViewModel] completionHandler in
            // `NSBackgroundActivityScheduler` (Foundation) kennt anders als
            // `BGTaskRequest` (das hier bewusst nicht genutzte, iOS-fokussierte
            // BackgroundTasks-Framework) KEIN `earliestBeginDate` — der eigene
            // Apple-Header dokumentiert für den allerersten Tick nur "run by
            // the OS at a time that best accommodates system-wide factors",
            // ohne untere Zeitschranke. In der Praxis feuerte dieser erste Tick
            // teils fast sofort nach `schedule(...)`, wodurch er beim App-Start
            // mit dem separaten "Feeds beim App-Start aktualisieren"-Refresh
            // kollidierte (Root-Cause-Fund 2026-07-23, Nutzer-Report: "Feed-
            // Fehler: Aktualisierung läuft bereits" bei praktisch jedem
            // App-Start). Fix: die bereits berechnete `earliestBeginDate`
            // selbst durchsetzen, statt sie einer nicht existierenden
            // System-API anzuvertrauen — ein zu frueher Tick wird ohne
            // Refresh sofort abgeschlossen, der naechste natuerliche Tick
            // (nach `interval`) uebernimmt dann.
            guard !BackgroundRefreshService.isPrematureTick(
                earliestBeginDate: request.earliestBeginDate,
                now: Date()
            ) else {
                completionHandler(.finished)
                return
            }

            Task { @MainActor in
                await BackgroundRefreshService.refreshAllFeeds(
                    database: feedivoDatabase,
                    intervalMinutes: request.intervalMinutes,
                    feedViewModel: feedViewModel
                )
                completionHandler(.finished)
            }
        }

        self.scheduler = scheduler
    }

    func cancel(identifier: String) {
        guard scheduler != nil else {
            return
        }

        scheduler?.invalidate()
        scheduler = nil
    }
}

enum BackgroundRefreshService {
    static let taskIdentifier = "ch.martin.Feedivo.refresh"

    /// Reine Entscheidungslogik dafür, ob ein `NSBackgroundActivityScheduler`-
    /// Tick übersprungen werden soll, weil er vor der geplanten
    /// `earliestBeginDate` liegt. Ausgelagert, damit die Logik selbst (anders
    /// als die reine Berechnung von `earliestBeginDate` in
    /// `BackgroundRefreshSettings`, die schon vorher getestet war) direkt
    /// unit-getestet werden kann, statt nur innerhalb des ungetesteten
    /// `NSBackgroundActivityScheduler`-Callbacks zu leben — genau diese Lücke
    /// war der Root-Cause-Fund vom 2026-07-23.
    static func isPrematureTick(earliestBeginDate: Date?, now: Date) -> Bool {
        guard let earliestBeginDate else {
            return false
        }
        return now < earliestBeginDate
    }

    static func scheduleNextRefresh(
        isEnabled: Bool,
        intervalMinutes: Int,
        now: Date = Date(),
        scheduler: BackgroundRefreshScheduling,
        userDefaults: UserDefaults = .standard
    ) throws {
        let clampedIntervalMinutes = BackgroundRefreshSettings.clampedIntervalMinutes(intervalMinutes)
        guard let earliestBeginDate = BackgroundRefreshSettings.earliestBeginDate(
            isEnabled: isEnabled,
            intervalMinutes: clampedIntervalMinutes,
            now: now
        ) else {
            scheduler.cancel(identifier: taskIdentifier)
            userDefaults.removeObject(forKey: BackgroundRefreshSettings.nextAutomaticRefreshDateKey)
            return
        }

        do {
            try scheduler.submit(
                BackgroundRefreshRequest(
                    identifier: taskIdentifier,
                    intervalMinutes: clampedIntervalMinutes,
                    earliestBeginDate: earliestBeginDate
                )
            )
            userDefaults.set(
                earliestBeginDate.timeIntervalSince1970,
                forKey: BackgroundRefreshSettings.nextAutomaticRefreshDateKey
            )
        } catch {
            userDefaults.removeObject(forKey: BackgroundRefreshSettings.nextAutomaticRefreshDateKey)
            userDefaults.set(now.timeIntervalSince1970, forKey: BackgroundRefreshSettings.lastAutomaticRefreshDateKey)
            userDefaults.set(BackgroundRefreshSettings.statusFailed, forKey: BackgroundRefreshSettings.lastAutomaticRefreshStatusKey)
            userDefaults.set(error.localizedDescription, forKey: BackgroundRefreshSettings.lastAutomaticRefreshErrorKey)
            throw error
        }
    }

    @MainActor
    static func refreshAllFeeds(
        database: FeedivoDatabase,
        intervalMinutes: Int = 60,
        userDefaults: UserDefaults = .standard,
        feedViewModel: FeedViewModel
    ) async {
        await feedViewModel.refreshAllFeeds(sqliteDatabase: database, isAutomatic: true)

        recordRefreshOutcome(
            from: feedViewModel,
            intervalMinutes: intervalMinutes,
            userDefaults: userDefaults
        )

        cleanupOnScheduleIfDue(database: database, userDefaults: userDefaults)
    }

    /// App-Start-Auslöser der Bereinigung (Feature 17.3a) — läuft nur, wenn der
    /// Zeitplan-Schalter "Bei App-Start" aktiv ist (Standard: an, bewahrt das bisherige
    /// Verhalten für Bestandsnutzer).
    ///
    /// Liest die Retention-Einstellungen direkt aus `UserDefaults`, da diese Funktion
    /// außerhalb einer SwiftUI-View läuft und kein `@AppStorage` zur Verfügung hat —
    /// bewusst `object(forKey:) as? T ?? default` statt `bool(forKey:)`/`integer(forKey:)`,
    /// da Letztere bei einem noch nie gespeicherten Wert `false`/`0` liefern (bei
    /// `retentionDays` würde `0` auf den kleinsten erlaubten Wert `30` statt auf den
    /// korrekten 90-Tage-Standard geklemmt).
    @MainActor
    static func cleanupOnAppStartIfNeeded(
        database: FeedivoDatabase,
        userDefaults: UserDefaults = .standard,
        now: Date = Date()
    ) {
        guard CleanupScheduleSettings.runOnAppStart(in: userDefaults) else {
            return
        }

        ArticleRetentionCleanupService.runAutomaticCleanup(
            database: database,
            isEnabled: userDefaults.object(forKey: ArticleRetentionSettings.isEnabledKey) as? Bool
                ?? ArticleRetentionSettings.defaultIsEnabled,
            retentionDays: userDefaults.object(forKey: ArticleRetentionSettings.retentionDaysKey) as? Int
                ?? ArticleRetentionSettings.defaultRetentionDays,
            minimumArticlesPerFeed: userDefaults.object(forKey: ArticleRetentionSettings.minimumArticlesPerFeedKey) as? Int
                ?? ArticleRetentionSettings.defaultMinimumArticlesPerFeed,
            includeProtectedArticles: userDefaults.object(forKey: ArticleRetentionSettings.includesProtectedArticlesKey) as? Bool
                ?? ArticleRetentionSettings.defaultIncludesProtectedArticles,
            triggerSource: .appStart,
            userDefaults: userDefaults,
            now: now
        )
    }

    /// Zeitplan-Auslöser der Bereinigung (Feature 17.3a) — ersetzt den bisherigen
    /// unbedingten Trigger bei jedem Hintergrund-Refresh-Zyklus (Befund A, 2026-07-14).
    /// Läuft bei jedem periodischen `NSBackgroundActivityScheduler`-Tick, prüft aber
    /// zuerst per Nachhol-Logik, ob der konfigurierte Wochentag+Uhrzeit tatsächlich
    /// fällig ist (Standard: Schalter aus, nie fällig).
    @MainActor
    static func cleanupOnScheduleIfDue(
        database: FeedivoDatabase,
        userDefaults: UserDefaults = .standard,
        now: Date = Date()
    ) {
        guard CleanupScheduleSettings.isWeekdayTimeScheduleDue(now: now, defaults: userDefaults) else {
            return
        }

        // Zeitplan-Lauf wird nur bei Erfolg als "erledigt" markiert — schlägt die
        // Bereinigung fehl (z. B. transienter DB-Fehler), bleibt der Wochenslot
        // unerfüllt und der nächste Refresh-Zyklus versucht es erneut.
        switch ArticleRetentionCleanupService.runAutomaticCleanup(
            database: database,
            isEnabled: userDefaults.object(forKey: ArticleRetentionSettings.isEnabledKey) as? Bool
                ?? ArticleRetentionSettings.defaultIsEnabled,
            retentionDays: userDefaults.object(forKey: ArticleRetentionSettings.retentionDaysKey) as? Int
                ?? ArticleRetentionSettings.defaultRetentionDays,
            minimumArticlesPerFeed: userDefaults.object(forKey: ArticleRetentionSettings.minimumArticlesPerFeedKey) as? Int
                ?? ArticleRetentionSettings.defaultMinimumArticlesPerFeed,
            includeProtectedArticles: userDefaults.object(forKey: ArticleRetentionSettings.includesProtectedArticlesKey) as? Bool
                ?? ArticleRetentionSettings.defaultIncludesProtectedArticles,
            triggerSource: .schedule,
            userDefaults: userDefaults,
            now: now
        ) {
        case .success:
            CleanupScheduleSettings.recordScheduleRun(now: now, in: userDefaults)
        case .failure:
            break
        }
    }

    static func recordRefreshOutcome(
        from viewModel: FeedViewModel,
        intervalMinutes: Int,
        userDefaults: UserDefaults = .standard
    ) {
        // Unterscheidung zwischen Erfolg / Teilfehler / totaler Misserfolg statt
        // zuvor pauschal „errorMessage != nil → failed". Ein Teilfehler (ein paar
        // Feeds nicht erreichbar, der Rest aktualisiert) ist kein Gesamtversagen.
        switch viewModel.lastRefreshOutcome {
        case .failure:
            recordRefreshFailure(
                viewModel.errorMessage ?? "",
                intervalMinutes: intervalMinutes,
                userDefaults: userDefaults
            )
        case .partial(let failedCount):
            recordRefreshPartial(
                viewModel.errorMessage ?? "",
                failedCount: failedCount,
                intervalMinutes: intervalMinutes,
                userDefaults: userDefaults
            )
        case .success, nil:
            recordRefreshSuccess(
                intervalMinutes: intervalMinutes,
                userDefaults: userDefaults
            )
        }
    }

    static func recordRefreshSuccess(
        now: Date = Date(),
        intervalMinutes: Int,
        userDefaults: UserDefaults = .standard
    ) {
        userDefaults.set(now.timeIntervalSince1970, forKey: BackgroundRefreshSettings.lastAutomaticRefreshDateKey)
        userDefaults.set(BackgroundRefreshSettings.statusSuccess, forKey: BackgroundRefreshSettings.lastAutomaticRefreshStatusKey)
        userDefaults.removeObject(forKey: BackgroundRefreshSettings.lastAutomaticRefreshErrorKey)
        userDefaults.set(
            BackgroundRefreshSettings.nextScheduledRefreshDate(intervalMinutes: intervalMinutes, now: now).timeIntervalSince1970,
            forKey: BackgroundRefreshSettings.nextAutomaticRefreshDateKey
        )
    }

    static func recordRefreshFailure(
        _ message: String,
        now: Date = Date(),
        intervalMinutes: Int,
        userDefaults: UserDefaults = .standard
    ) {
        userDefaults.set(now.timeIntervalSince1970, forKey: BackgroundRefreshSettings.lastAutomaticRefreshDateKey)
        userDefaults.set(BackgroundRefreshSettings.statusFailed, forKey: BackgroundRefreshSettings.lastAutomaticRefreshStatusKey)
        userDefaults.set(message, forKey: BackgroundRefreshSettings.lastAutomaticRefreshErrorKey)
        userDefaults.set(
            BackgroundRefreshSettings.nextScheduledRefreshDate(intervalMinutes: intervalMinutes, now: now).timeIntervalSince1970,
            forKey: BackgroundRefreshSettings.nextAutomaticRefreshDateKey
        )
    }

    /// Teilfehler: der Refresh ist gelaufen, einige Feeds konnten aber nicht
    /// aktualisiert werden. Status „partial" statt „failed" — die meisten Feeds
    /// wurden erfolgreich aktualisiert, nur eine Teilmenge ist fehlgeschlagen.
    static func recordRefreshPartial(
        _ message: String,
        failedCount: Int,
        now: Date = Date(),
        intervalMinutes: Int,
        userDefaults: UserDefaults = .standard
    ) {
        userDefaults.set(now.timeIntervalSince1970, forKey: BackgroundRefreshSettings.lastAutomaticRefreshDateKey)
        userDefaults.set(BackgroundRefreshSettings.statusPartial, forKey: BackgroundRefreshSettings.lastAutomaticRefreshStatusKey)
        userDefaults.set(message, forKey: BackgroundRefreshSettings.lastAutomaticRefreshErrorKey)
        userDefaults.set(
            BackgroundRefreshSettings.nextScheduledRefreshDate(intervalMinutes: intervalMinutes, now: now).timeIntervalSince1970,
            forKey: BackgroundRefreshSettings.nextAutomaticRefreshDateKey
        )
    }
}
