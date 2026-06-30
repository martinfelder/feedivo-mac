import Foundation

enum ArticleWindowSettings {
    static let restoreOpenArticleWindowsOnLaunchKey = "articleWindows.restoreOpenArticleWindowsOnLaunch"
    static let defaultRestoreOpenArticleWindowsOnLaunch = false
    static let openArticleIDsKey = "articleWindows.openArticleIDs"

    static func openArticleIDs(defaults: UserDefaults = .standard) -> [UUID] {
        defaults.stringArray(forKey: openArticleIDsKey)?
            .compactMap(UUID.init(uuidString:)) ?? []
    }

    static func rememberOpenArticleID(_ articleID: UUID, defaults: UserDefaults = .standard) {
        var articleIDs = openArticleIDs(defaults: defaults)
        guard !articleIDs.contains(articleID) else {
            return
        }

        articleIDs.append(articleID)
        saveOpenArticleIDs(articleIDs, defaults: defaults)
    }

    static func forgetOpenArticleID(_ articleID: UUID, defaults: UserDefaults = .standard) {
        let articleIDs = openArticleIDs(defaults: defaults).filter { $0 != articleID }
        saveOpenArticleIDs(articleIDs, defaults: defaults)
    }

    private static func saveOpenArticleIDs(_ articleIDs: [UUID], defaults: UserDefaults) {
        defaults.set(articleIDs.map(\.uuidString), forKey: openArticleIDsKey)
    }
}
