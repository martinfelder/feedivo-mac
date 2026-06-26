import SwiftUI
import SwiftData

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

    @AppStorage(ArticleRetentionSettings.includesProtectedArticlesKey)
    private var articleRetentionIncludesProtectedArticles = ArticleRetentionSettings.defaultIncludesProtectedArticles

    private let modelContainer: ModelContainer
    private let backgroundRefreshScheduler: SystemBackgroundActivityRefreshScheduler

    init() {
        ReaderFontRegistry.registerBundledFonts()

        let modelContainer = try! ModelContainer(
            for: Feed.self,
            FeedFolder.self,
            Article.self,
            Tag.self,
            Rule.self,
            RuleCondition.self,
            SmartFolder.self,
            SmartFolderCondition.self,
            FeedLogEntry.self
        )
        self.modelContainer = modelContainer
        self.backgroundRefreshScheduler = SystemBackgroundActivityRefreshScheduler(
            modelContainer: modelContainer
        )
    }

    // modelContainer stellt SwiftData für die ganze App zur Verfügung.
    // Alle SwiftData-Modelle werden hier registriert.
    // isCloudKitEnabled: true aktiviert später die iCloud-Synchronisation —
    // dafür brauchen wir noch die iCloud-Capability, aber der Code ist schon bereit.
    var body: some Scene {
        let appLanguage = AppLanguage.resolved(from: appLanguageRawValue)
        let interfaceTextSize = InterfaceTextSize.resolved(from: interfaceTextSizeRawValue)

        WindowGroup {
            ContentView()
                .environment(\.locale, appLanguage.locale)
                .environment(\.interfaceTextSize, interfaceTextSize)
                .dynamicTypeSize(interfaceTextSize.dynamicTypeSize)
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

        Settings {
            SettingsView()
                .environment(\.locale, appLanguage.locale)
                .environment(\.interfaceTextSize, interfaceTextSize)
                .dynamicTypeSize(interfaceTextSize.dynamicTypeSize)
        }
        .modelContainer(modelContainer)
    }

    private func scheduleBackgroundRefresh() {
        try? BackgroundRefreshService.scheduleNextRefresh(
            isEnabled: backgroundRefreshIsEnabled,
            intervalMinutes: backgroundRefreshIntervalMinutes,
            scheduler: backgroundRefreshScheduler
        )
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
            includeProtectedArticles: articleRetentionIncludesProtectedArticles
        )
    }

    @MainActor
    private func backfillStoredArticleMetadataIfNeeded() {
        _ = try? ArticleFeedIDBackfillService.backfillMissingFeedIDs(in: modelContainer.mainContext)
        _ = try? OrphanedArticleCleanupService.removeArticlesWithoutExistingFeed(in: modelContainer.mainContext)
        _ = try? FeedUnreadCountBackfillService.backfillUnreadCounts(in: modelContainer.mainContext)
        _ = try? RuleConditionBackfillService.backfillMissingConditions(context: modelContainer.mainContext)
        restoreDefaultSmartFoldersIfNeeded()
    }

    @MainActor
    private func restoreDefaultSmartFoldersIfNeeded() {
        let context = modelContainer.mainContext
        let folders = (try? context.fetch(FetchDescriptor<SmartFolder>())) ?? []
        SmartFolderViewModel().restoreDefaultFolders(existingFolders: folders, context: context)
    }
}
