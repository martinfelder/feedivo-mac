import Foundation
import SwiftData

@Model
class SmartFolderCondition {
    var id: UUID = UUID()
    var fieldRaw: String = ""
    var operatorRaw: String = ""
    var value: String = ""
    var sortOrder: Int = 0

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

    // Typsicherer Zugriff — ungültige Raw-Values (z.B. nach Refactor verwaist)
    // fallen hier früh auf nil statt still zu matchen.
    var fieldEnum: SmartFolderConditionField? { SmartFolderConditionField(rawValue: fieldRaw) }
    var operatorEnum: SmartFolderConditionOperator? { SmartFolderConditionOperator(rawValue: operatorRaw) }
}
