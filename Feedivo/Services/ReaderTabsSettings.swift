import Foundation

/// UserDefaults-Schema für die optionale Persistenz offener Reader-Tabs.
/// Analog zu `ArticleWindowSettings` (Popout-Fenster), aber mit `String`-
/// statt `UUID`-Artikel-IDs, da Tabs direkt mit den internen GRDB-
/// Primärschlüsseln arbeiten.
enum ReaderTabsSettings {
    static let restoreTabsOnLaunchKey = "readerTabs.restoreOnLaunch"
    static let defaultRestoreTabsOnLaunch = false
    static let openTabArticleIDsKey = "readerTabs.openArticleIDs"
    static let activeTabArticleIDKey = "readerTabs.activeArticleID"

    static func isRestoreOnLaunchEnabled(defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: restoreTabsOnLaunchKey) != nil else {
            return defaultRestoreTabsOnLaunch
        }
        return defaults.bool(forKey: restoreTabsOnLaunchKey)
    }

    static func savedArticleIDs(defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: openTabArticleIDsKey) ?? []
    }

    static func savedActiveArticleID(defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: activeTabArticleIDKey)
    }

    static func save(articleIDs: [String], activeArticleID: String?, defaults: UserDefaults = .standard) {
        defaults.set(articleIDs, forKey: openTabArticleIDsKey)
        if let activeArticleID {
            defaults.set(activeArticleID, forKey: activeTabArticleIDKey)
        } else {
            defaults.removeObject(forKey: activeTabArticleIDKey)
        }
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: openTabArticleIDsKey)
        defaults.removeObject(forKey: activeTabArticleIDKey)
    }
}
