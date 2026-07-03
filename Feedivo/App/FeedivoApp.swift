import SwiftUI
import SwiftData
import Observation

@main
struct FeedivoApp: App {
    @AppStorage("appLanguage")
    private var appLanguageRawValue = AppLanguage.system.rawValue

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

    private let modelContainer: ModelContainer
    private let backgroundRefreshScheduler: SystemBackgroundActivityRefreshScheduler
    private let databaseLoadState = DatabaseLoadState()
    private let feedViewModel = FeedViewModel()
    private let feedivoDatabase: FeedivoDatabase

    // Alle SwiftData-Modelle an einer Stelle — so gibt es genau eine
    // Wahrheitsquelle für den Schema-Bestand, genutzt vom normalen Container
    // wie auch vom In-Memory-Fallback (M11).
    private static let schema = Schema([
        Feed.self,
        FeedFolder.self,
        Article.self,
        Tag.self,
        Rule.self,
        RuleCondition.self,
        SmartFolder.self,
        SmartFolderCondition.self,
        FeedLogEntry.self
    ])

    init() {
        ReaderFontRegistry.registerBundledFonts()

        let loadedContainer: ModelContainer
        var loadError: String?
        let cloudSyncIsEnabled = CloudSyncSettings.isEnabled()

        do {
            loadedContainer = try FeedivoModelContainerFactory.makePersistentContainer(
                schema: Self.schema,
                isCloudSyncEnabled: cloudSyncIsEnabled
            )
        } catch {
            loadError = error.localizedDescription
            do {
                loadedContainer = try FeedivoModelContainerFactory.makeInMemoryFallbackContainer(
                    schema: Self.schema
                )
            } catch {
                fatalError("Feedivo App kann ohne Datenbank nicht starten: \(error.localizedDescription)")
            }
        }

        self.modelContainer = loadedContainer
        self.backgroundRefreshScheduler = SystemBackgroundActivityRefreshScheduler(
            modelContainer: loadedContainer,
            feedViewModel: feedViewModel
        )
        self.feedivoDatabase = Self.openSQLiteDatabase()
        self.databaseLoadState.initializationError = loadError
        self.databaseLoadState.isCloudSyncEnabledAtLaunch = cloudSyncIsEnabled && loadError == nil
    }

    // modelContainer stellt SwiftData für die ganze App zur Verfügung.
    // Alle SwiftData-Modelle werden hier registriert.
    // isCloudKitEnabled: true aktiviert später die iCloud-Synchronisation —
    // dafür brauchen wir noch die iCloud-Capability, aber der Code ist schon bereit.
    var body: some Scene {
        let appLanguage = AppLanguage.resolved(from: appLanguageRawValue)
        let interfaceTextSize = InterfaceTextSize.resolved(from: interfaceTextSizeRawValue)

        WindowGroup {
            ContentView(feedViewModel: feedViewModel, modelContainer: modelContainer)
                .environment(\.locale, appLanguage.locale)
                .environment(\.interfaceTextSize, interfaceTextSize)
                .environment(\.feedivoDatabase, feedivoDatabase)
                .environment(databaseLoadState)
                .dynamicTypeSize(interfaceTextSize.dynamicTypeSize)
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
        .modelContainer(modelContainer)

        Window(L10n.articleSearchCommand, id: ArticleSearchWindowView.windowID) {
            ArticleSearchWindowView()
                .environment(\.locale, appLanguage.locale)
                .environment(\.interfaceTextSize, interfaceTextSize)
                .environment(\.feedivoDatabase, feedivoDatabase)
                .dynamicTypeSize(interfaceTextSize.dynamicTypeSize)
        }
        .defaultSize(width: 760, height: 560)
        .modelContainer(modelContainer)

        WindowGroup(for: ArticleWindowRequest.self) { $request in
            if let request {
                ArticleWindowView(request: request)
                    .environment(\.locale, appLanguage.locale)
                    .environment(\.interfaceTextSize, interfaceTextSize)
                    .environment(\.feedivoDatabase, feedivoDatabase)
                    .dynamicTypeSize(interfaceTextSize.dynamicTypeSize)
            } else {
                ContentUnavailableView(
                    L10n.articleWindowMissingTitle,
                    systemImage: "doc.text.magnifyingglass",
                    description: Text(L10n.articleWindowMissingDescription)
                )
            }
        }
        .defaultSize(width: 900, height: 720)
        .modelContainer(modelContainer)

        Settings {
            NewSettingsView()
                .environment(\.locale, appLanguage.locale)
                .environment(\.interfaceTextSize, interfaceTextSize)
                .environment(\.feedivoDatabase, feedivoDatabase)
                .environment(databaseLoadState)
                .dynamicTypeSize(interfaceTextSize.dynamicTypeSize)
        }
        .defaultSize(width: 1040, height: 640)
        .modelContainer(modelContainer)
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
        _ = try? ArticleRetentionCleanupService.removeExpiredArticles(
            in: modelContainer.mainContext,
            isEnabled: articleRetentionIsEnabled,
            retentionDays: articleRetentionDays,
            minimumArticlesPerFeed: articleRetentionMinimumArticlesPerFeed,
            includeProtectedArticles: articleRetentionIncludesProtectedArticles
        )
        _ = try? ArticleRetentionCleanupService.removeExpiredSQLiteArticles(
            in: modelContainer.mainContext,
            database: feedivoDatabase,
            isEnabled: articleRetentionIsEnabled,
            retentionDays: articleRetentionDays,
            minimumArticlesPerFeed: articleRetentionMinimumArticlesPerFeed,
            includeProtectedArticles: articleRetentionIncludesProtectedArticles
        )
    }

    @MainActor
    private func backfillStoredArticleMetadataIfNeeded() {
        _ = try? ArticleFeedIDBackfillService.backfillMissingFeedIDs(in: modelContainer.mainContext)
        _ = try? OrphanedArticleCleanupService.removeArticlesWithoutExistingFeed(in: modelContainer.mainContext)
        _ = try? FeedUnreadCountBackfillService.backfillUnreadCounts(in: modelContainer.mainContext)
        _ = try? FeedTagBackfillService.backfillFeedTags(
            in: modelContainer.mainContext,
            database: feedivoDatabase
        )
        restoreDefaultSmartFoldersIfNeeded()
        _ = try? SQLiteAdminDefinitionBackfillService.backfill(
            in: modelContainer.mainContext,
            database: feedivoDatabase
        )
    }

    @MainActor
    private func restoreDefaultSmartFoldersIfNeeded() {
        let context = modelContainer.mainContext
        _ = try? SmartFolderDefaultKeyBackfillService.backfillDefaultKeys(in: context)
        let folders = (try? context.fetch(FetchDescriptor<SmartFolder>())) ?? []
        SmartFolderViewModel().restoreDefaultFolders(existingFolders: folders, context: context)
    }
}

// Hält den Status des Datenbank-Ladevorgangs beim App-Start. Bleibt `nil`,
// wenn die on-disk-Datenbank normal geöffnet wurde; wird gesetzt, sobald auf
// den In-Memory-Fallback ausgewichen wurde (M11). Über `.environment` an die
// ContentView gereicht, die ihn einmalig als Alarm anzeigt.
@Observable
final class DatabaseLoadState {
    var initializationError: String?
    var isCloudSyncEnabledAtLaunch = false
}
