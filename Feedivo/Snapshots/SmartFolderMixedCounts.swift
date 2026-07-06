import Foundation
import GRDB

struct SmartFolderMixedCounts: Equatable, Sendable {
    let read: Int
    let unread: Int

    static let empty = SmartFolderMixedCounts(read: 0, unread: 0)
}

extension SmartFolderMixedCounts: FetchableRecord {
    init(row: Row) throws {
        read = row["read"]
        unread = row["unread"]
    }
}
