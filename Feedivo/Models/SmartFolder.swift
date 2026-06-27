import Foundation
import SwiftData

@Model
class SmartFolder {
    var id: UUID = UUID()
    var name: String = ""
    var matchModeRaw: String = RuleMatchMode.all.rawValue
    var isShownInSidebar: Bool = true
    var isDefault: Bool = false
    var sortOrder: Int = 0
    var iconNameRaw: String?
    var colorHexRaw: String?

    var iconName: String {
        get { SmartFolderAppearance.normalizedIconName(iconNameRaw ?? SmartFolderAppearance.defaultIconName) }
        set { iconNameRaw = SmartFolderAppearance.normalizedIconName(newValue) }
    }

    var colorHex: String {
        get { SmartFolderAppearance.normalizedColorHex(colorHexRaw ?? SmartFolderAppearance.defaultColorHex) }
        set { colorHexRaw = SmartFolderAppearance.normalizedColorHex(newValue) }
    }

    @Relationship(deleteRule: .cascade, inverse: \SmartFolderCondition.smartFolder)
    var conditions: [SmartFolderCondition] = []

    init(
        name: String,
        matchMode: RuleMatchMode = .all,
        isShownInSidebar: Bool = true,
        isDefault: Bool = false,
        sortOrder: Int = 0,
        iconName: String = "folder.badge.gearshape",
        colorHex: String = "#6B7280",
        conditions: [SmartFolderCondition] = []
    ) {
        self.id = UUID()
        self.name = name
        self.matchModeRaw = matchMode.rawValue
        self.isShownInSidebar = isShownInSidebar
        self.isDefault = isDefault
        self.sortOrder = sortOrder
        self.iconNameRaw = SmartFolderAppearance.normalizedIconName(iconName)
        self.colorHexRaw = SmartFolderAppearance.normalizedColorHex(colorHex)
        self.conditions = conditions
    }
}
