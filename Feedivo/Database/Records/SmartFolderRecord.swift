import Foundation
import GRDB

struct SmartFolderRecord: Codable, FetchableRecord, MutablePersistableRecord, Equatable, Sendable {
    static let databaseTableName = "smart_folders"

    var id: String
    var name: String
    var matchMode: String
    var isShownInSidebar: Bool
    var isDefault: Bool
    var sortOrder: Int
    var defaultKey: String?
    var iconName: String?
    var colorHex: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        matchMode: String = RuleMatchMode.all.rawValue,
        isShownInSidebar: Bool = true,
        isDefault: Bool = false,
        sortOrder: Int = 0,
        defaultKey: String? = nil,
        iconName: String? = nil,
        colorHex: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.matchMode = matchMode
        self.isShownInSidebar = isShownInSidebar
        self.isDefault = isDefault
        self.sortOrder = sortOrder
        self.defaultKey = defaultKey
        self.iconName = iconName
        self.colorHex = colorHex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
