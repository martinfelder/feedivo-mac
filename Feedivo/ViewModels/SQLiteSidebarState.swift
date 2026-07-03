import Foundation
import Observation

@MainActor
@Observable
final class SQLiteSidebarState {
    private(set) var snapshots: [FeedSidebarSnapshot] = []
    private(set) var tagSnapshots: [TagSidebarSnapshot] = []
    private(set) var feedFolders: [FeedFolderRecord] = []
    private(set) var smartFolderSnapshots: [SQLiteSmartFolderSnapshot] = []
    private(set) var smartFolderBadgeSnapshot = SmartFolderSidebarBadgeSnapshot.empty
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
            let smartFolderStore = SQLiteSmartFolderStore(database: database)
            let statusStore = ArticleStatusStore(database: database)
            let loadedSnapshots = try feedStore.sidebarFeeds(showsReadFeeds: showsReadFeeds)
            let loadedTagSnapshots = try tagStore.sidebarTags()
            let loadedFeedFolders = try feedFolderStore.folders()
            let loadedSmartFolderSnapshots = try smartFolderStore.sidebarSnapshots()
            let loadedSmartFolderBadgeSnapshot = try statusStore.sidebarSmartFolderBadgeSnapshot()
            snapshots = loadedSnapshots
            tagSnapshots = loadedTagSnapshots
            feedFolders = loadedFeedFolders
            smartFolderSnapshots = loadedSmartFolderSnapshots
            smartFolderBadgeSnapshot = loadedSmartFolderBadgeSnapshot
            snapshotsByFeedID = Dictionary(uniqueKeysWithValues: loadedSnapshots.map { ($0.id, $0) })
            tagSnapshotsByID = Dictionary(uniqueKeysWithValues: loadedTagSnapshots.map { ($0.id, $0) })
            visibleFeedIDs = Set(loadedSnapshots.map(\.id))
            totalUnreadCount = loadedSnapshots.reduce(0) { total, snapshot in
                total + snapshot.unreadCount
            }
            errorMessage = nil
        } catch {
            snapshots = []
            tagSnapshots = []
            feedFolders = []
            smartFolderSnapshots = []
            smartFolderBadgeSnapshot = .empty
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
