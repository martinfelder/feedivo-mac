import Foundation
import SwiftData

enum SidebarUnreadCount {
    static func unreadArticleCount(for feed: Feed) -> Int {
        feed.unreadCount
    }

    static func totalUnreadArticleCount(in feeds: [Feed]) -> Int {
        feeds.reduce(0) { total, feed in
            total + feed.unreadCount
        }
    }

    static func badgeText(for count: Int) -> String? {
        count > 0 ? "\(count)" : nil
    }
}

enum SidebarTagCount {
    @MainActor
    static func articleCount(for tag: Tag, context: ModelContext) throws -> Int {
        let descriptor = FetchDescriptor<Article>(
            predicate: ArticleListQuery.tagPredicate(for: tag, taggedFeeds: tag.feeds)
        )

        return try context.fetchCount(descriptor)
    }

    @MainActor
    static func badgeText(for tag: Tag, context: ModelContext) throws -> String? {
        try SidebarUnreadCount.badgeText(for: articleCount(for: tag, context: context))
    }
}

@MainActor
enum SmartFolderSidebarBadge {
    static func badgeText(for folder: SmartFolder, feeds: [Feed], context: ModelContext) -> String? {
        badgeCount(for: folder, feeds: feeds, context: context).flatMap(SidebarUnreadCount.badgeText)
    }

    /// In-Memory-Variante: statt N `fetchCount`-Queries pro Sidebar-Render werden
    /// die Zähler einmal zentral über alle Artikel gebündelt (Batching) und hier
    /// nur noch zugewiesen. Kein Stale-Risiko, da kein Cache.
    static func badgeText(for folder: SmartFolder, feeds: [Feed], counts: SidebarBadgeCounts) -> String? {
        badgeCount(for: folder, feeds: feeds, counts: counts).flatMap(SidebarUnreadCount.badgeText)
    }

    private static func badgeCount(for folder: SmartFolder, feeds: [Feed], context: ModelContext) -> Int? {
        guard let badgeKind = SmartFolderSidebarBadgeKind(folder: folder) else {
            return nil
        }

        switch badgeKind {
        case .unread:
            return SidebarUnreadCount.totalUnreadArticleCount(in: feeds)
        case .starred:
            return try? context.fetchCount(
                FetchDescriptor<Article>(
                    predicate: #Predicate<Article> { article in
                        article.isStarred
                    }
                )
            )
        case .hidden:
            return try? context.fetchCount(
                FetchDescriptor<Article>(
                    predicate: #Predicate<Article> { article in
                        article.isHidden
                    }
                )
            )
        case .saved:
            return try? context.fetchCount(
                FetchDescriptor<Article>(
                    predicate: #Predicate<Article> { article in
                        article.isStarred || article.isArchived
                    }
                )
            )
        }
    }

    private static func badgeCount(for folder: SmartFolder, feeds: [Feed], counts: SidebarBadgeCounts) -> Int? {
        guard let badgeKind = SmartFolderSidebarBadgeKind(folder: folder) else {
            return nil
        }

        switch badgeKind {
        case .unread:
            return SidebarUnreadCount.totalUnreadArticleCount(in: feeds)
        case .starred:
            return counts.starred
        case .hidden:
            return counts.hidden
        case .saved:
            return counts.saved
        }
    }
}

/// Zentral gebündelte Badge-Zähler der Sidebar. `tagCounts` liefert pro Tag die
/// Artikel-Anzahl (Tag direkt am Artikel ODER am Feed des Artikels), die
/// Status-Zähler decken die SmartFolder-Badges ab.
struct SidebarBadgeCounts: Equatable {
    let tagCounts: [PersistentIdentifier: Int]
    let starred: Int
    let hidden: Int
    let saved: Int

    static let empty = SidebarBadgeCounts(tagCounts: [:], starred: 0, hidden: 0, saved: 0)
}

/// Signatur für das Sidebar-Badge-Caching. Erfasst alle Änderungen, die die
/// Zähler beeinflussen: Artikel-Zahl, Status-Counts (Stern/versteckt/archiviert),
/// Feed→Tag-Zuordnungen, Anzahl Feeds/Tags sowie direkte Artikel→Tag-Zuweisungen
/// (`directTagVersion`). Unverändert → Cache trifft → keine Neuberechnung.
struct SidebarBadgeSignature: Equatable, Hashable {
    let articleCount: Int
    let starredCount: Int
    let hiddenCount: Int
    let archivedCount: Int
    let tagFeedMembershipHash: Int
    let tagCount: Int
    let feedCount: Int
    let directTagVersion: Int
}

/// Invalidierung für das Sidebar-Badge-Caching. Direkte Artikel→Tag-Zuweisungen
/// (nicht über den Feed) werden nicht von den Skalar-Counts oder den beobachteten
/// @Querys erfasst — daher bumpen die Zuweisungs-Stellen diesen Zähler, worauf
/// die Sidebar ihre Badges neu berechnet. UserDefaults ist thread-sicher, daher
/// nonisolated aufrufbar (auch aus dem RuleEngine-Pfad).
enum SidebarBadgeInvalidation {
    static let directTagVersionKey = "sidebarBadgeDirectTagVersion"

    static func bumpDirectTagVersion() {
        let defaults = UserDefaults.standard
        defaults.set(defaults.integer(forKey: directTagVersionKey) + 1, forKey: directTagVersionKey)
    }
}

private enum SmartFolderSidebarBadgeKind {
    case unread
    case starred
    case hidden
    case saved

    init?(folder: SmartFolder) {
        let conditions = folder.conditions.sorted { $0.sortOrder < $1.sortOrder }

        if RuleMatchMode.normalized(folder.matchModeRaw) == .all,
           conditions.count == 1,
           let condition = conditions.first,
           condition.fieldRaw == SmartFolderConditionField.status.rawValue,
           condition.operatorRaw == SmartFolderConditionOperator.is.rawValue,
           let statusValue = SmartFolderStatusValue(rawValue: condition.value) {
            switch statusValue {
            case .unread:
                self = .unread
                return
            case .starred:
                self = .starred
                return
            case .hidden:
                self = .hidden
                return
            case .read, .archived:
                break
            }
        }

        if RuleMatchMode.normalized(folder.matchModeRaw) == .any,
           conditions.count == 2,
           conditions.allSatisfy({ condition in
               condition.fieldRaw == SmartFolderConditionField.status.rawValue
                   && condition.operatorRaw == SmartFolderConditionOperator.is.rawValue
           }) {
            let values = Set(conditions.map(\.value))
            if values == Set([
                SmartFolderStatusValue.starred.rawValue,
                SmartFolderStatusValue.archived.rawValue
            ]) {
                self = .saved
                return
            }
        }

        return nil
    }
}
