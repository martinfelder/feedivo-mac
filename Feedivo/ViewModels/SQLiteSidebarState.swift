import Foundation
import Observation

enum SmartFolderDefaultDisplayPolicy {
    /// Standardordner mit getrennten Gelesen-/Ungelesen-Badges (Sidebar-
    /// Zähler). Unabhängig von der pro Ordner änderbaren
    /// `defaultShowsReadArticles`-Einstellung (siehe SmartFolderEditorView) —
    /// diese Menge bleibt bewusst auf die vier eingebauten Standard-Ordner
    /// beschränkt.
    static let mixedCountKeys: Set<String> = [
        "all", "today", "starred", "thisWeek", "hidden", "saved"
    ]
}

@MainActor
@Observable
final class SQLiteSidebarState {
    private(set) var snapshots: [FeedSidebarSnapshot] = []
    private(set) var tagSnapshots: [TagSidebarSnapshot] = []
    private(set) var feedFolders: [FeedFolderRecord] = []
    private(set) var smartFolderSnapshots: [SQLiteSmartFolderSnapshot] = []
    private(set) var smartFolderBadgeSnapshot = SmartFolderSidebarBadgeSnapshot.empty
    private(set) var mixedCountsByDefaultKey: [String: SmartFolderMixedCounts] = [:]
    private(set) var totalUnreadCount = 0
    private(set) var errorMessage: String?

    private var snapshotsByFeedID: [String: FeedSidebarSnapshot] = [:]
    private var tagSnapshotsByID: [String: TagSidebarSnapshot] = [:]
    private var visibleFeedIDs: Set<String> = []

    func load(database: FeedivoDatabase?, showsReadFeeds: Bool) {
        guard let database else {
            snapshots = []
            tagSnapshots = []
            feedFolders = []
            smartFolderSnapshots = []
            smartFolderBadgeSnapshot = .empty
            mixedCountsByDefaultKey = [:]
            snapshotsByFeedID = [:]
            tagSnapshotsByID = [:]
            visibleFeedIDs = []
            totalUnreadCount = 0
            errorMessage = nil
            return
        }

        do {
            let feedStore = FeedStore(database: database)
            let tagStore = TagStore(database: database)
            let feedFolderStore = FeedFolderStore(database: database)
            try feedFolderStore.materializeImplicitFolders()
            let smartFolderStore = SQLiteSmartFolderStore(database: database)
            let unreadCountService = SQLiteUnreadCountService(database: database)
            let loadedSnapshots = try feedStore.sidebarFeeds(showsReadFeeds: showsReadFeeds)
            let loadedTagSnapshots = try tagStore.sidebarTags()
            let loadedFeedFolders = try feedFolderStore.folders()
            let loadedSmartFolderSnapshots = try smartFolderStore.sidebarSnapshots()
            let loadedSmartFolderBadgeSnapshot = try unreadCountService.sidebarSmartFolderBadgeSnapshot()
            let timelineStore = TimelineStore(database: database)
            var loadedMixedCounts: [String: SmartFolderMixedCounts] = [:]
            for defaultKey in SmartFolderDefaultDisplayPolicy.mixedCountKeys {
                guard let folder = loadedSmartFolderSnapshots.first(where: { $0.defaultKey == defaultKey }) else {
                    continue
                }

                loadedMixedCounts[defaultKey] = try timelineStore.readUnreadCounts(
                    scope: .smartFolder(folder),
                    includeHidden: folder.includesHiddenArticles
                )
            }
            snapshots = loadedSnapshots
            tagSnapshots = loadedTagSnapshots
            feedFolders = loadedFeedFolders
            smartFolderSnapshots = loadedSmartFolderSnapshots
            smartFolderBadgeSnapshot = loadedSmartFolderBadgeSnapshot
            mixedCountsByDefaultKey = loadedMixedCounts
            snapshotsByFeedID = Dictionary(uniqueKeysWithValues: loadedSnapshots.map { ($0.id, $0) })
            tagSnapshotsByID = Dictionary(uniqueKeysWithValues: loadedTagSnapshots.map { ($0.id, $0) })
            visibleFeedIDs = Set(loadedSnapshots.map(\.id))
            totalUnreadCount = try unreadCountService.totalUnreadCount()
            errorMessage = nil
        } catch {
            snapshots = []
            tagSnapshots = []
            feedFolders = []
            smartFolderSnapshots = []
            smartFolderBadgeSnapshot = .empty
            mixedCountsByDefaultKey = [:]
            snapshotsByFeedID = [:]
            tagSnapshotsByID = [:]
            visibleFeedIDs = []
            totalUnreadCount = 0
            errorMessage = error.localizedDescription
        }
    }

    func snapshot(forFeedID feedID: String) -> FeedSidebarSnapshot? {
        snapshotsByFeedID[feedID]
    }

    func tagSnapshot(id: String) -> TagSidebarSnapshot? {
        tagSnapshotsByID[id]
    }
}
