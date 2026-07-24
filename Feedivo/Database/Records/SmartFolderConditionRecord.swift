import Foundation
import GRDB

struct SmartFolderConditionRecord: Codable, FetchableRecord, MutablePersistableRecord, Equatable, Sendable {
    static let databaseTableName = "smart_folder_conditions"

    var id: String
    var smartFolderID: String
    var field: String
    var conditionOperator: String
    var value: String
    var sortOrder: Int
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        smartFolderID: String,
        field: String,
        conditionOperator: String,
        value: String,
        sortOrder: Int = 0,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.smartFolderID = smartFolderID
        self.field = field
        self.conditionOperator = conditionOperator
        self.value = value
        self.sortOrder = sortOrder
        self.updatedAt = updatedAt
    }
}
