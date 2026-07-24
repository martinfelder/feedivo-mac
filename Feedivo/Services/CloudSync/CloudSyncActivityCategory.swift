import SwiftUI

/// Fasst die 7 rohen `CloudSyncRecordMapping.recordType`-Werte zu 5 nutzerverständlichen
/// Kategorien für die Sync-Status-Übersicht zusammen — die Bedingungs-Tabellen (`RuleCondition`,
/// `SmartFolderCondition`) haben für den Nutzer keine eigene Identität. Siehe Design-Spec
/// `docs/superpowers/specs/2026-07-24-icloud-sync-status-uebersicht-design.md`.
enum CloudSyncActivityCategory: CaseIterable, Hashable {
    case tags
    case feeds
    case folders
    case rules
    case smartFolders

    var recordTypes: [String] {
        switch self {
        case .tags: ["Tag"]
        case .feeds: ["Feed"]
        case .folders: ["FeedFolder"]
        case .rules: ["Rule", "RuleCondition"]
        case .smartFolders: ["SmartFolder", "SmartFolderCondition"]
        }
    }

    var localizedTitle: LocalizedStringKey {
        switch self {
        case .tags: L10n.settingsSyncActivityCategoryTags
        case .feeds: L10n.settingsSyncActivityCategoryFeeds
        case .folders: L10n.settingsSyncActivityCategoryFolders
        case .rules: L10n.settingsSyncActivityCategoryRules
        case .smartFolders: L10n.settingsSyncActivityCategorySmartFolders
        }
    }

    func pendingCount(in counts: [String: Int]) -> Int {
        recordTypes.reduce(0) { $0 + (counts[$1] ?? 0) }
    }
}
