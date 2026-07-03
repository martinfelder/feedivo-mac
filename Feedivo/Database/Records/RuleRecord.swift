import Foundation
import GRDB

struct RuleRecord: Codable, FetchableRecord, MutablePersistableRecord, Equatable, Sendable {
    static let databaseTableName = "rules"

    var id: String
    var name: String
    var isEnabled: Bool
    var matchMode: String
    var action: String
    var assignTagID: String?
    var notificationTemplate: String
    var notificationPriority: String
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        isEnabled: Bool = true,
        matchMode: String = RuleMatchMode.all.rawValue,
        action: String = RuleAction.assignTag.rawValue,
        assignTagID: String? = nil,
        notificationTemplate: String = "{Titel}",
        notificationPriority: String = RuleNotificationPriority.normal.rawValue,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.matchMode = matchMode
        self.action = action
        self.assignTagID = assignTagID
        self.notificationTemplate = notificationTemplate
        self.notificationPriority = notificationPriority
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
