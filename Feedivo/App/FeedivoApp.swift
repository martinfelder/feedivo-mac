import SwiftUI
import Observation
import AppKit
import OSLog

@main
struct FeedivoApp: App {
    @AppStorage("appLanguage")
    private var appLanguageRawValue = AppLanguage.system.rawValue

    @AppStorage(AppAppearance.storageKey)
    private var appAppearanceRawValue = AppAppearance.defaultMode.rawValue

    @AppStorage(InterfaceTextSize.storageKey)
    private var interfaceTextSizeRawValue = InterfaceTextSize.defaultSize.rawValue

    @AppStorage(BackgroundRefreshSettings.isEnabledKey)
    private var backgroundRefreshIsEnabled = BackgroundRefreshSettings.defaultIsEnabled

    @AppStorage(BackgroundRefreshSettings.intervalMinutesKey)
    private var backgroundRefreshIntervalMinutes = BackgroundRefreshSettings.defaultIntervalMinutes

    @AppStorage(ArticleRetentionSettings.isEnabledKey)
    private var articleRetentionIsEnabled = ArticleRetentionSettings.defaultIsEnabled

    @AppStorage(ArticleRetentionSettings.retentionDaysKey)
    private var articleRetentionDays = ArticleRetentionSettings.defaultRetentionDays

    @AppStorage(ArticleRetentionSettings.minimumArticlesPerFeedKey)
    private var articleRetentionMinimumArticlesPerFeed = ArticleRetentionSettings.defaultMinimumArticlesPerFeed

    @AppStorage(ArticleRetentionSettings.includesProtectedArticlesKey)
    private var articleRetentionIncludesProtectedArticles = ArticleRetentionSettings.defaultIncludesProtectedArticles

    @AppStorage(SpotlightIndexingSettings.isEnabledKey)
    private var spotlightIndexingIsEnabled = SpotlightIndexingSettings.defaultIsEnabled

    // Feature 23.2: AppKit-Delegate fängt feedivo://-URLs zuverlässig ab —
    // auch beim Kaltstart, bevor die SwiftUI-View-Hierarchie existiert (siehe
    // FeedivoAppDelegate). Die geparste Aktion wird in dessen
    // PendingURLSchemeAction abgelegt und unten an ContentView weitergereicht.
    @NSApplicationDelegateAdaptor(FeedivoAppDelegate.self) private var appDelegate

    private let backgroundRefreshScheduler: SystemBackgroundActivityRefreshScheduler
    private let databaseLoadState = DatabaseLoadState()
    private let feedViewModel = FeedViewModel()
    private let feedivoDatabase: FeedivoDatabase
    private let localExtensionBridgeServer: LocalExtensionBridgeServer

    init() {
        ReaderFontRegistry.registerBundledFonts()
        let databaseOpenResult = Self.openSQLiteDatabase()
        let database = databaseOpenResult.database
        self.backgroundRefreshScheduler = SystemBackgroundActivityRefreshScheduler(
            feedivoDatabase: database,
            feedViewModel: feedViewModel
        )
        self.feedivoDatabase = database
        self.localExtensionBridgeServer = LocalExtensionBridgeServer(database: database)
        self.databaseLoadState.initializationError = databaseOpenResult.errorDescription
        self.databaseLoadState.isCloudSyncEnabledAtLaunch = false
        // Feature 21.1: `NSStatusItem` darf erst in `applicationDidFinishLaunching` entstehen
        // (siehe `FeedivoAppDelegate`) — hier nur die Abhängigkeiten durchreichen.
        if databaseOpenResult.errorDescription == nil {
            self.appDelegate.configureMenubarController(feedivoDatabase: database, feedViewModel: feedViewModel)
            self.localExtensionBridgeServer.start()
        }
    }

    var body: some Scene {
        let appLanguage = AppLanguage.resolved(from: appLanguageRawValue)
        let interfaceTextSize = InterfaceTextSize.resolved(from: interfaceTextSizeRawValue)
        let appAppearance = AppAppearance.resolved(from: appAppearanceRawValue)

        // `Window` (nicht `WindowGroup`) ist hier bewusst: eine WindowGroup erlaubt
        // laut SwiftUI-Design mehrere gleichzeitige Instanzen — jeder Aufruf von
        // `openWindow(id: "main")` (Menubar-Popover-Button "Feedivo öffnen") hätte
        // damit eine NEUE Instanz erzeugt statt die bestehende zu fokussieren
        // (gefunden 2026-07-11, Nutzer-Report). `Window` ist der echte
        // Singleton-Szenentyp, den die anderen Einzelfenster der App (Suche,
        // Organizer, Statistik) bereits korrekt verwenden.
        Window("Feedivo", id: "main") {
            Group {
                if let initializationError = databaseLoadState.initializationError {
                    ContentUnavailableView {
                        Label(L10n.databaseInitErrorTitle, systemImage: "externaldrive.badge.exclamationmark")
                    } description: {
                        Text(verbatim: "\(L10n.databaseInitErrorMessage)\n\n\(initializationError)")
                    }
                } else {
                    ContentView(feedViewModel: feedViewModel)
                }
            }
                .environment(\.locale, appLanguage.locale)
                .environment(\.interfaceTextSize, interfaceTextSize)
                .environment(\.feedivoDatabase, feedivoDatabase)
                .environment(databaseLoadState)
                .environment(appDelegate.pendingURLSchemeAction)
                .dynamicTypeSize(interfaceTextSize.dynamicTypeSize)
                .preferredColorScheme(appAppearance.colorScheme)
                .toolbarBackground(.hidden, for: .windowToolbar)
                .task {
                    guard databaseLoadState.initializationError == nil else {
                        return
                    }
                    backfillStoredArticleMetadataIfNeeded()
                    trimImageCacheToSelectedLimit()
                    ensureSpotlightBackfillIfNeeded()
                    scheduleBackgroundRefresh()
                }
                .onChange(of: backgroundRefreshIsEnabled) {
                    scheduleBackgroundRefresh()
                }
                .onChange(of: backgroundRefreshIntervalMinutes) {
                    scheduleBackgroundRefresh()
                }
                .onChange(of: articleRetentionIsEnabled) {
                    cleanupExpiredArticlesIfNeeded()
                }
                .onChange(of: articleRetentionDays) {
                    cleanupExpiredArticlesIfNeeded()
                }
                .onChange(of: articleRetentionMinimumArticlesPerFeed) {
                    articleRetentionMinimumArticlesPerFeed = ArticleRetentionSettings.clampedMinimumArticlesPerFeed(
                        articleRetentionMinimumArticlesPerFeed
                    )
                    cleanupExpiredArticlesIfNeeded()
                }
                .onChange(of: articleRetentionIncludesProtectedArticles) {
                    cleanupExpiredArticlesIfNeeded()
                }
                .onChange(of: spotlightIndexingIsEnabled) {
                    handleSpotlightIndexingToggleChange()
                }
        }
        .commands {
            ArticleCommands()
            FeedCommands()
            ViewCommands()
            // Entfernt den von SwiftUI automatisch bereitgestellten, aber funktionslosen
            // "Drucken..."-Menuepunkt (Datei-Menue, Standard-Tastenkombination Cmd+P).
            // Ohne diese Entfernung kollidiert er mit dem neuen Drucken-Button in
            // SQLiteReaderView.swift (Feature 25.1), der ebenfalls Cmd+P beansprucht —
            // das Standard-NSMenuItem gewinnt den Tastenkombinations-Konflikt und zeigt
            // beim Ausloesen den generischen AppKit-Fallback-Alert "Diese App
            // unterstuetzt Drucken nicht", statt dass unser Drucken-Button reagiert
            // (Live-Bug-Fund 2026-07-17, Nutzer-Report).
            CommandGroup(replacing: .printItem) {}
        }
        Window(L10n.articleSearchCommand, id: ArticleSearchWindowView.windowID) {
            ArticleSearchWindowView()
                .environment(\.locale, appLanguage.locale)
                .environment(\.interfaceTextSize, interfaceTextSize)
                .environment(\.feedivoDatabase, feedivoDatabase)
                .dynamicTypeSize(interfaceTextSize.dynamicTypeSize)
                .preferredColorScheme(appAppearance.colorScheme)
        }
        .defaultSize(width: 760, height: 560)

        Window(OrganizerWindowView.windowTitle, id: OrganizerWindowView.windowID) {
            OrganizerWindowView()
                .environment(\.locale, appLanguage.locale)
                .environment(\.interfaceTextSize, interfaceTextSize)
                .environment(\.feedivoDatabase, feedivoDatabase)
                .dynamicTypeSize(interfaceTextSize.dynamicTypeSize)
                .preferredColorScheme(appAppearance.colorScheme)
        }

        Window(L10n.statisticsWindowTitle, id: StatisticsWindowView.windowID) {
            StatisticsWindowView()
                .environment(\.locale, appLanguage.locale)
                .environment(\.interfaceTextSize, interfaceTextSize)
                .environment(\.feedivoDatabase, feedivoDatabase)
                .dynamicTypeSize(interfaceTextSize.dynamicTypeSize)
                .preferredColorScheme(appAppearance.colorScheme)
        }
        .defaultSize(width: 820, height: 640)
        .defaultSize(width: 920, height: 620)

        Window(L10n.cleanupHistoryTitle, id: CleanupHistoryWindowView.windowID) {
            CleanupHistoryWindowView()
                .environment(\.locale, appLanguage.locale)
                .environment(\.interfaceTextSize, interfaceTextSize)
                .environment(\.feedivoDatabase, feedivoDatabase)
                .dynamicTypeSize(interfaceTextSize.dynamicTypeSize)
                .preferredColorScheme(appAppearance.colorScheme)
        }
        .defaultSize(width: 420, height: 480)

        WindowGroup(for: ArticleWindowRequest.self) { $request in
            // Gemeinsame Modifier auf einem umschließenden Group, damit auch der
            // else-Zweig (fehlende Anfrage) Sprache/Textgröße/Darstellung erbt,
            // statt nur der Erfolgsfall.
            Group {
                if let request {
                    ArticleWindowView(request: request)
                } else {
                    ContentUnavailableView(
                        L10n.articleWindowMissingTitle,
                        systemImage: "doc.text.magnifyingglass",
                        description: Text(L10n.articleWindowMissingDescription)
                    )
                }
            }
            .environment(\.locale, appLanguage.locale)
            .environment(\.interfaceTextSize, interfaceTextSize)
            .environment(\.feedivoDatabase, feedivoDatabase)
            .dynamicTypeSize(interfaceTextSize.dynamicTypeSize)
            .preferredColorScheme(appAppearance.colorScheme)
        }
        .defaultSize(width: 900, height: 720)

        Settings {
            SettingsView()
                .environment(\.locale, appLanguage.locale)
                .environment(\.interfaceTextSize, interfaceTextSize)
                .environment(\.feedivoDatabase, feedivoDatabase)
                .environment(databaseLoadState)
                .dynamicTypeSize(interfaceTextSize.dynamicTypeSize)
                .preferredColorScheme(appAppearance.colorScheme)
        }
        .windowResizability(.contentSize)

        // Feature 21.1: Kein `MenuBarExtra`-Scene-Eintrag hier — das Menubar-Icon läuft
        // komplett selbstständig über `menubarStatusItemController` (AppKit `NSStatusItem`/
        // `NSPopover`, per UserDefaults-KVO reaktiv statt an eine SwiftUI-View gebunden),
        // siehe dessen Doc-Comment für die vollständige Begründung.
    }

    private func scheduleBackgroundRefresh() {
        guard databaseLoadState.initializationError == nil else {
            return
        }
        try? BackgroundRefreshService.scheduleNextRefresh(
            isEnabled: backgroundRefreshIsEnabled,
            intervalMinutes: backgroundRefreshIntervalMinutes,
            scheduler: backgroundRefreshScheduler
        )
    }

    private struct DatabaseOpenResult {
        var database: FeedivoDatabase
        var errorDescription: String?
    }

    private static func openSQLiteDatabase() -> DatabaseOpenResult {
        do {
            return DatabaseOpenResult(
                database: try FeedivoDatabase.open(at: FeedivoDatabaseLocation.databaseURL()),
                errorDescription: nil
            )
        } catch {
            // Die Ersatzdatenbank hält die Scene technisch konstruierbar. Der
            // Hauptinhalt bleibt jedoch blockiert, damit die flüchtige Datenbank
            // niemals wie ein erfolgreicher, leerer Produktivstart aussieht.
            return DatabaseOpenResult(
                database: try! FeedivoDatabase.inMemoryForTests(),
                errorDescription: error.localizedDescription
            )
        }
    }

    private func trimImageCacheToSelectedLimit() {
        try? ImageCacheService.shared.trimCache(
            toLimitInBytes: ImageCacheSettings.currentLimitInBytes
        )
    }

    @MainActor
    private func cleanupExpiredArticlesIfNeeded() {
        guard databaseLoadState.initializationError == nil else {
            return
        }
        ArticleRetentionCleanupService.runAutomaticCleanup(
            database: feedivoDatabase,
            isEnabled: articleRetentionIsEnabled,
            retentionDays: articleRetentionDays,
            minimumArticlesPerFeed: articleRetentionMinimumArticlesPerFeed,
            includeProtectedArticles: articleRetentionIncludesProtectedArticles,
            triggerSource: .settingsChange
        )
    }

    @MainActor
    private func ensureSpotlightBackfillIfNeeded() {
        guard databaseLoadState.initializationError == nil else {
            return
        }
        // Läuft als eigener Task statt inline `await` im aufrufenden
        // `.task { }`-Block (Whole-Branch-Review-Fund, Feature 9.3): Ein
        // sehr großer Artikel-Bestand könnte den Backfill mehrere Sekunden
        // dauern lassen — inline würde das den nachfolgenden
        // `scheduleBackgroundRefresh()`-Aufruf im selben Block verzögern.
        // `SpotlightIndexingService.ensureBackfillIfNeeded` liest inzwischen
        // komplett über `FeedivoDatabase.readAsync` (GRDBs eigene
        // Hintergrund-Queue) statt der vorherigen blockierenden
        // Sync-Variante, blockiert also auch während der Laufzeit dieses
        // Tasks nicht mehr den MainActor/App-Start.
        let database = feedivoDatabase
        Task {
            do {
                try await SpotlightIndexingService.ensureBackfillIfNeeded(database: database)
            } catch {
                AppLogger.dataAccess.error("Spotlight-Backfill: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    @MainActor
    private func handleSpotlightIndexingToggleChange() {
        if spotlightIndexingIsEnabled {
            ensureSpotlightBackfillIfNeeded()
        } else {
            SpotlightIndexingService.deindexAll()
        }
    }

    @MainActor
    private func backfillStoredArticleMetadataIfNeeded() {
        restoreDefaultSmartFoldersIfNeeded()
    }

    @MainActor
    private func restoreDefaultSmartFoldersIfNeeded() {
        try? SQLiteSmartFolderStore(database: feedivoDatabase).restoreDefaultFolders()
    }
}

// Hält den Status des Datenbank-Ladevorgangs beim App-Start. Bleibt `nil`,
// wenn die on-disk-Datenbank normal geöffnet wurde. Bei einem Fehler bleibt
// die Meldung für die gesamte Sitzung erhalten und blockiert den Hauptinhalt;
// die technische Ersatzdatenbank darf nicht als leerer Produktivstand wirken.
@Observable
final class DatabaseLoadState {
    var initializationError: String?
    var isCloudSyncEnabledAtLaunch = false
}
