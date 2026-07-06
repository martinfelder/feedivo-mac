import Foundation

struct SmartFolderConditionDraft: Identifiable, Equatable {
    var id = UUID()
    var field: SmartFolderConditionField
    var conditionOperator: SmartFolderConditionOperator
    var value: String
}
