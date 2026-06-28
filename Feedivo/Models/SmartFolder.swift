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
    // Lokalisierung der 8 Default-Ordner: nil = Custom (Name unangetastet),
    // gesetzt = Default (Anzeige via localizedDisplayName, Restore matcht hierauf).
    // Optional+Default nil -> CloudKit-safe (CLAUDE.md).
    var defaultKey: String? = nil
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

    @Relationship(deleteRule: .nullify, inverse: \SmartFolderCondition.smartFolder)
    var conditions: [SmartFolderCondition] = []

    init(
        name: String,
        matchMode: RuleMatchMode = .all,
        isShownInSidebar: Bool = true,
        isDefault: Bool = false,
        sortOrder: Int = 0,
        iconName: String = "folder.badge.gearshape",
        colorHex: String = "#6B7280",
        defaultKey: String? = nil,
        conditions: [SmartFolderCondition] = []
    ) {
        self.id = UUID()
        self.name = name
        self.matchModeRaw = matchMode.rawValue
        self.isShownInSidebar = isShownInSidebar
        self.isDefault = isDefault
        self.sortOrder = sortOrder
        self.defaultKey = defaultKey
        self.iconNameRaw = SmartFolderAppearance.normalizedIconName(iconName)
        self.colorHexRaw = SmartFolderAppearance.normalizedColorHex(colorHex)
        self.conditions = conditions
    }

    // Anzeige-Name: Defaults lokalisiert, Custom = gespeicherter Name.
    var localizedDisplayName: String {
        guard let defaultKey else { return name }
        switch defaultKey {
        case "all":       return String(localized: "smartFolder.default.all")
        case "unread":    return String(localized: "smartFolder.default.unread")
        case "starred":   return String(localized: "smartFolder.default.starred")
        case "today":     return String(localized: "smartFolder.default.today")
        case "hidden":    return String(localized: "smartFolder.default.hidden")
        case "archived":  return String(localized: "smartFolder.default.archived")
        case "thisWeek":  return String(localized: "smartFolder.default.thisWeek")
        case "saved":     return String(localized: "smartFolder.default.saved")
        default:          return name
        }
    }
}
