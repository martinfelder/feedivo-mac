import SwiftUI
import SwiftData

@main
struct FeedivoApp: App {
    @AppStorage("appLanguage")
    private var appLanguageRawValue = AppLanguage.system.rawValue

    init() {
        ReaderFontRegistry.registerBundledFonts()
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
        }
        .modelContainer(for: [
            Feed.self,
            Article.self,
            Tag.self,
            Rule.self
        ])

        Settings {
            SettingsView()
                .environment(\.locale, appLanguage.locale)
        }
    }
}
