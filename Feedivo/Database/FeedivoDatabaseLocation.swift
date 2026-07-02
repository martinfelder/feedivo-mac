import Foundation

enum FeedivoDatabaseLocation {
    static func databaseURL(
        applicationSupportDirectory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0],
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "Feedivo"
    ) -> URL {
        applicationSupportDirectory
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("Feedivo", isDirectory: true)
            .appendingPathComponent("feedivo.sqlite")
    }
}
