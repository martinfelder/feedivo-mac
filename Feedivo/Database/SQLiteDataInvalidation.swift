import Foundation

enum SQLiteDataInvalidation {
    static let statusVersionKey = "sqliteData.statusVersion"

    static func bumpStatusVersion(defaults: UserDefaults = .standard) {
        defaults.set(
            defaults.integer(forKey: statusVersionKey) + 1,
            forKey: statusVersionKey
        )
    }
}
