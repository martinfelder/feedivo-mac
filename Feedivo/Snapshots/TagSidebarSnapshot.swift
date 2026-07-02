import Foundation
import GRDB

struct TagSidebarSnapshot: Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let colorHex: String
    let articleCount: Int
}

extension TagSidebarSnapshot: FetchableRecord {
    init(row: Row) throws {
        id = row["id"]
        name = row["name"]
        colorHex = row["colorHex"]
        articleCount = row["articleCount"]
    }
}
