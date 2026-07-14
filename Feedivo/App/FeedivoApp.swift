import SwiftUI
import Observation
import AppKit

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
        let cloudSyncIsEnabled = CloudSyncSettings.isEnabled()
        let database = Self.openSQLiteDatabase()
        self.backgroundRefreshScheduler = SystemBackgroundActivityRefreshScheduler(
            feedivoDatabase: database,
            feedViewModel: feedViewModel
        )
        self.feedivoDatabase = database
        self.localExtensionBridgeServer = LocalExtensionBridgeServer(database: database)
        self.databaseLoadState.initializationError = nil
        self.databaseLoadState.isCloudSyncEnabledAtLaunch = cloudSyncIsEnabled
        // Feature 21.1: `NSStatusItem` darf erst in `applicationDidFinishLaunching` entstehen
        // (siehe `FeedivoAppDelegate`) — hier nur die Abhängigkeiten durchreichen.
        self.appDelegate.configureMenubarController(feedivoDatabase: database, feedViewModel: feedViewModel)
        self.localExtensionBridgeServer.start()
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
            ContentView(feedViewModel: feedViewModel)
                .environment(\.locale, appLanguage.locale)
                .environment(\.interfaceTextSize, interfaceTextSize)
                .environment(\.feedivoDatabase, feedivoDatabase)
                .environment(databaseLoadState)
                .environment(appDelegate.pendingURLSchemeAction)
                .dynamicTypeSize(interfaceTextSize.dynamicTypeSize)
                .preferredColorScheme(appAppearance.colorScheme)
                .toolbarBackground(.ultraThinMaterial, for: .windowToolbar)
                .toolbarBackground(.visible, for: .windowToolbar)
                .task {
                    backfillStoredArticleMetadataIfNeeded()
                    cleanupExpiredArticlesIfNeeded()
                    trimImageCacheToSelectedLimit()
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
        }
        .commands {
            ArticleCommands()
            FeedCommands()
            ViewCommands()
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
        try? BackgroundRefreshService.scheduleNextRefresh(
            isEnabled: backgroundRefreshIsEnabled,
            intervalMinutes: backgroundRefreshIntervalMinutes,
            scheduler: backgroundRefreshScheduler
        )
    }

    private static func openSQLiteDatabase() -> FeedivoDatabase {
        do {
            return try FeedivoDatabase.open(at: FeedivoDatabaseLocation.databaseURL())
        } catch {
            return try! FeedivoDatabase.inMemoryForTests()
        }
    }

    private func trimImageCacheToSelectedLimit() {
        try? ImageCacheService.shared.trimCache(
            toLimitInBytes: ImageCacheSettings.currentLimitInBytes
        )
    }

    @MainActor
    private func cleanupExpiredArticlesIfNeeded() {
        ArticleRetentionCleanupService.runAutomaticCleanup(
            database: feedivoDatabase,
            isEnabled: articleRetentionIsEnabled,
            retentionDays: articleRetentionDays,
            minimumArticlesPerFeed: articleRetentionMinimumArticlesPerFeed,
            includeProtectedArticles: articleRetentionIncludesProtectedArticles
        )
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
// wenn die on-disk-Datenbank normal geöffnet wurde; wird gesetzt, sobald auf
// den In-Memory-Fallback ausgewichen wurde. Über `.environment` an die
// ContentView gereicht, die ihn einmalig als Alarm anzeigt.
@Observable
final class DatabaseLoadState {
    var initializationError: String?
    var isCloudSyncEnabledAtLaunch = false
}
