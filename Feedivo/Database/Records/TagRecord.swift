import Foundation
import GRDB

struct TagRecord: Codable, FetchableRecord, Identifiable, MutablePersistableRecord, Equatable, Sendable {
    static let databaseTableName = "tags"

    var id: String
    var name: String
    var colorHex: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        colorHex: String = "#888888",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
