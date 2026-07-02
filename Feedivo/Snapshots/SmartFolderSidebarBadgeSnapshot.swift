import Foundation
import GRDB

struct SmartFolderSidebarBadgeSnapshot: Equatable, Sendable {
    let unread: Int
    let starred: Int
    let hidden: Int
    let saved: Int

    static let empty = SmartFolderSidebarBadgeSnapshot(
        unread: 0,
        starred: 0,
        hidden: 0,
        saved: 0
    )
}

extension SmartFolderSidebarBadgeSnapshot: FetchableRecord {
    init(row: Row) throws {
        unread = row["unread"]
        starred = row["starred"]
        hidden = row["hidden"]
        saved = row["saved"]
    }
}
