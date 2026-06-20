import SwiftUI
import SwiftData

@main
struct FeedivoApp: App {
    @AppStorage("appLanguage")
    private var appLanguageRawValue = AppLanguage.system.rawValue

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
            Article.self,
            Tag.self,
            Rule.self,
            FeedLogEntry.self
        )
        self.modelContainer = modelContainer
        self.backgroundRefreshScheduler = SystemBackgroundActivityRefreshScheduler(
            modelContainer: modelContainer
        )
    }

    // modelContainer stellt SwiftData für die ganze App zur Verfügung.
    // Alle 4 Modelle werden hier registriert.
    // isCloudKitEnabled: true aktiviert später die iCloud-Synchronisation —
    // dafür brauchen wir noch die iCloud-Capability, aber der Code ist schon bereit.
    var body: some Scene {
        let appLanguage = AppLanguage.resolved(from: appLanguageRawValue)

        WindowGroup {
            ContentView()
                .environment(\.locale, appLanguage.locale)
                .task {
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
        }
    }

    private func scheduleBackgroundRefresh() {
        try? BackgroundRefreshService.scheduleNextRefresh(
            isEnabled: backgroundRefreshIsEnabled,
            intervalMinutes: backgroundRefreshIntervalMinutes,
            scheduler: backgroundRefreshScheduler
        )
    }
}
