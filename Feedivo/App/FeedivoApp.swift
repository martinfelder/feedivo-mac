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
                    trimImageCacheToSelectedLimit()
                    scheduleBackgroundRefresh()
                }
                .onChange(of: backgroundRefreshIsEnabled) {
                    scheduleBackgroundRefresh()
                }
                .onChange(of: backgroundRefreshIntervalMinutes) {
                    scheduleBackgroundRefresh()
                }
        }
        .commands {
            ArticleCommands()
            FeedCommands()
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
    private func backfillStoredArticleMetadataIfNeeded() {
        _ = try? ArticleFeedIDBackfillService.backfillMissingFeedIDs(in: modelContainer.mainContext)
        _ = try? OrphanedArticleCleanupService.removeArticlesWithoutExistingFeed(in: modelContainer.mainContext)
        _ = try? FeedUnreadCountBackfillService.backfillUnreadCounts(in: modelContainer.mainContext)
        _ = try? RuleConditionBackfillService.backfillMissingConditions(context: modelContainer.mainContext)
    }
}
