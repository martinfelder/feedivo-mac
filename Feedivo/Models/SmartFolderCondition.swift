import Foundation
import SwiftData

@Model
class SmartFolderCondition {
    var id: UUID
    var fieldRaw: String
    var operatorRaw: String
    var value: String
    var sortOrder: Int

    @Relationship
    var smartFolder: SmartFolder?

    init(
        field: SmartFolderConditionField,
        conditionOperator: SmartFolderConditionOperator,
        value: String,
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.fieldRaw = field.rawValue
        self.operatorRaw = conditionOperator.rawValue
        self.value = value
        self.sortOrder = sortOrder
    }
}
