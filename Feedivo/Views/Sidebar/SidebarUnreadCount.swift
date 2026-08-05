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

/// Ersetzt einen vormaligen `UserDefaults`/`@AppStorage`-Mechanismus durch
/// natives SwiftUI-`@Observable`, analog zu `SQLiteDataInvalidation` (siehe
/// dort für die volle Begründung).
@MainActor
@Observable
final class SidebarBadgeInvalidation {
    static let shared = SidebarBadgeInvalidation()
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
