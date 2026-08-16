import Foundation

/// Wie viele Werkzeuge der MCP-Server bei welchem Schalterstand anbietet.
///
/// **Die Wahrheit steht in `FeedivoMCPServer/main.swift`**, wo `availableTools` tatsächlich
/// aufgebaut wird — diese Konstante ist nur ihr Spiegel für die App, die den Serverprozess nicht
/// befragen kann. Kommt dort ein Werkzeug dazu, MUSS die passende Zahl hier mitwachsen;
/// `main.swift` meldet eine Abweichung beim Start auf stderr.
///
/// Ein automatisierter Test dieser Übereinstimmung ist nicht möglich: `FeedivoMCPServerTests` läuft
/// in diesem Projekt strukturell nie, und kein `xcodebuild`-Aufruf kompiliert auch nur eine Datei
/// dieses Testziels.
enum MCPToolInventory {
    /// `list_feeds`, `list_folders`, `list_tags`, `search_articles`, `get_article`,
    /// `list_smart_folders`, `get_smart_folder_articles`.
    static let readOnlyToolCount = 7

    /// `update_article_status`, `assign_tag`, `remove_tag` — nur bei aktivem Schreibzugriff.
    static let writeToolCount = 3

    static func expectedToolCount(isWriteAccessEnabled: Bool) -> Int {
        isWriteAccessEnabled ? readOnlyToolCount + writeToolCount : readOnlyToolCount
    }
}
