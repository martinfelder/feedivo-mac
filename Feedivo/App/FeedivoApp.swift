import SwiftUI
import SwiftData

@main
struct FeedivoApp: App {

    // modelContainer stellt SwiftData für die ganze App zur Verfügung.
    // Alle 4 Modelle werden hier registriert.
    // isCloudKitEnabled: true aktiviert später die iCloud-Synchronisation —
    // dafür brauchen wir noch die iCloud-Capability, aber der Code ist schon bereit.
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [
            Feed.self,
            Article.self,
            Tag.self,
            Rule.self
        ])
    }
}
