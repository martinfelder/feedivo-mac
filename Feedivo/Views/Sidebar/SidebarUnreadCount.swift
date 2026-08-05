import Foundation

enum SidebarUnreadCount {
    static func badgeText(for count: Int) -> String? {
        count > 0 ? "\(count)" : nil
    }
}

@MainActor
enum SmartFolderSidebarBadge {
    static func badgeText(for folder: SQLiteSmartFolderSnapshot, snapshot: SmartFolderSidebarBadgeSnapshot) -> String? {
        badgeCount(for: folder, snapshot: snapshot).flatMap(SidebarUnreadCount.badgeText)
    }

    private static func badgeCount(for folder: SQLiteSmartFolderSnapshot, snapshot: SmartFolderSidebarBadgeSnapshot) -> Int? {
        guard let badgeKind = SmartFolderSidebarBadgeKind(folder: folder) else {
            return nil
        }

        switch badgeKind {
        case .unread:
            return snapshot.unread
        case .starred:
            return snapshot.starred
        case .hidden:
            return snapshot.hidden
        case .saved:
            return snapshot.saved
        }
    }
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

/// Ersetzt `SidebarBadgeInvalidation`s `UserDefaults`/`@AppStorage`-
/// Mechanismus durch natives SwiftUI-`@Observable`, analog zu
/// `SQLiteDataInvalidationSignal` (siehe dort für die volle Begründung).
@MainActor
@Observable
final class SidebarBadgeInvalidationSignal {
    static let shared = SidebarBadgeInvalidationSignal()
    private init() {}

    private(set) var directTagVersion = 0

    func bumpDirectTagVersion() {
        directTagVersion += 1
    }

    /// Nur für Tests.
    func reset() {
        directTagVersion = 0
    }
}

enum SmartFolderSidebarBadgeKind: Equatable {
    case unread
    case starred
    case hidden
    case saved

    init?(folder: SQLiteSmartFolderSnapshot) {
        if folder.matchMode == .all,
           folder.conditions.count == 1,
           let condition = folder.conditions.first,
           condition.field == .status,
           condition.conditionOperator == .is,
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

        if folder.matchMode == .any,
           folder.conditions.count == 2,
           folder.conditions.allSatisfy({ condition in
               condition.field == .status
                   && condition.conditionOperator == .is
           }) {
            let values = Set(folder.conditions.map(\.value))
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
