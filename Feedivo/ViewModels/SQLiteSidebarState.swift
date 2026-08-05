import Foundation
import Observation

/// Traegt das Ergebnis von `SQLiteSidebarState.load(...)`s ausgelagerter
/// `Task.detached`-Lese-Kaskade zurueck zum MainActor (siehe Kommentar dort).
private struct LoadedSidebarData: Sendable {
    let snapshots: [FeedSidebarSnapshot]
    let tagSnapshots: [TagSidebarSnapshot]
    let feedFolders: [FeedFolderRecord]
    let smartFolderSnapshots: [SQLiteSmartFolderSnapshot]
    let smartFolderBadgeSnapshot: SmartFolderSidebarBadgeSnapshot
    let mixedCounts: [String: SmartFolderMixedCounts]
    let totalUnreadCount: Int
}

@MainActor
@Observable
final class SQLiteSidebarState {
    private(set) var snapshots: [FeedSidebarSnapshot] = []
    private(set) var tagSnapshots: [TagSidebarSnapshot] = []
    private(set) var feedFolders: [FeedFolderRecord] = []
    private(set) var smartFolderSnapshots: [SQLiteSmartFolderSnapshot] = []
    private(set) var smartFolderBadgeSnapshot = SmartFolderSidebarBadgeSnapshot.empty
    private(set) var mixedCountsByFolderID: [String: SmartFolderMixedCounts] = [:]
    private(set) var totalUnreadCount = 0
    private(set) var errorMessage: String?

    private var snapshotsByFeedID: [String: FeedSidebarSnapshot] = [:]
    private var tagSnapshotsByID: [String: TagSidebarSnapshot] = [:]
    private var visibleFeedIDs: Set<String> = []

    /// TEMP-DEBUG-Fund (2026-08-05, @Observable-Migration-Folgesitzung): diese
    /// Methode fuehrte bislang 6-7 SQL-Abfragen (inkl. einer Schleife mit
    /// einer weiteren Abfrage PRO Smart Folder) komplett SYNCHRON auf dem
    /// MainActor aus — ausgeloest von `.task(id: sqliteSidebarReloadToken)`
    /// in SidebarView.swift, das bei JEDER SQLiteDataInvalidation/
    /// SidebarBadgeInvalidation-Aenderung feuert (jedes Gelesen-Markieren,
    /// Stern setzen, Tag-Aenderung, ...). Per Live-OSLog-Messung (log stream)
    /// verifiziert: diese Kaskade blockierte den MainActor konstant fuer
    /// ~180-230ms, wodurch ALLES andere auf dem MainActor (u. a. der
    /// Readers `.onChange(of: statusVersion)`) so lange warten musste — DAS
    /// war die tatsaechliche Ursache der ~220-250ms-Latenz, die die
    /// @AppStorage->@Observable-Migration (siehe CLAUDE.md) faelschlich der
    /// UserDefaults-Notification zuschrieb; die Migration selbst aenderte
    /// daran nichts, weil das Problem nie beim Signalmechanismus lag.
    /// Fix: die komplette Lese-Kaskade in `Task.detached` auslagern (exakt
    /// dasselbe, bereits etablierte Muster wie SQLiteReaderState.load()) —
    /// nur die finale Ergebnisuebernahme bleibt auf dem MainActor.
    func load(database: FeedivoDatabase?, showsReadFeeds: Bool) async {
        guard let database else {
            snapshots = []
            tagSnapshots = []
            feedFolders = []
            smartFolderSnapshots = []
            smartFolderBadgeSnapshot = .empty
            mixedCountsByFolderID = [:]
            snapshotsByFeedID = [:]
            tagSnapshotsByID = [:]
            visibleFeedIDs = []
            totalUnreadCount = 0
            errorMessage = nil
            return
        }

        do {
            let result = try await Task.detached(priority: .userInitiated) {
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
                for folder in loadedSmartFolderSnapshots {
                    loadedMixedCounts[folder.id] = try timelineStore.readUnreadCounts(
                        scope: .smartFolder(folder),
                        includeHidden: folder.includesHiddenArticles
                    )
                }
                let loadedTotalUnreadCount = try unreadCountService.totalUnreadCount()
                return LoadedSidebarData(
                    snapshots: loadedSnapshots,
                    tagSnapshots: loadedTagSnapshots,
                    feedFolders: loadedFeedFolders,
                    smartFolderSnapshots: loadedSmartFolderSnapshots,
                    smartFolderBadgeSnapshot: loadedSmartFolderBadgeSnapshot,
                    mixedCounts: loadedMixedCounts,
                    totalUnreadCount: loadedTotalUnreadCount
                )
            }.value

            snapshots = result.snapshots
            tagSnapshots = result.tagSnapshots
            feedFolders = result.feedFolders
            smartFolderSnapshots = result.smartFolderSnapshots
            smartFolderBadgeSnapshot = result.smartFolderBadgeSnapshot
            mixedCountsByFolderID = result.mixedCounts
            snapshotsByFeedID = Dictionary(uniqueKeysWithValues: result.snapshots.map { ($0.id, $0) })
            tagSnapshotsByID = Dictionary(uniqueKeysWithValues: result.tagSnapshots.map { ($0.id, $0) })
            visibleFeedIDs = Set(result.snapshots.map(\.id))
            totalUnreadCount = result.totalUnreadCount
            errorMessage = nil
        } catch {
            snapshots = []
            tagSnapshots = []
            feedFolders = []
            smartFolderSnapshots = []
            smartFolderBadgeSnapshot = .empty
            mixedCountsByFolderID = [:]
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
