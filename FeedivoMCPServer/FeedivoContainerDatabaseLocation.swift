import Foundation

/// Löst den Pfad zur Feedivo-Datenbank innerhalb des App-Sandbox-Containers auf.
///
/// Feedivo selbst (Target `Feedivo`) läuft mit `com.apple.security.app-sandbox`,
/// weshalb `FileManager.default.urls(for: .applicationSupportDirectory, ...)`
/// von INNERHALB der App auf den Container-Pfad umgeleitet wird. Ein separater,
/// unsandboxed Prozess wie `FeedivoMCPServer` bekommt diese Umleitung nicht
/// automatisch — der Pfad wird deshalb hier explizit nachgebaut, statt
/// `FileManager`s Standard-API zu verwenden (die von einem unsandboxed Prozess
/// aus fälschlich den NICHT-Container-Pfad liefern würde).
enum FeedivoContainerDatabaseLocation {
    static let bundleIdentifier = "ch.martin.Feedivo"

    static func databaseURL(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Containers", isDirectory: true)
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("Data", isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("Feedivo", isDirectory: true)
            .appendingPathComponent("feedivo.sqlite")
    }
}
