import Foundation
import SwiftData

// Rule definiert eine Bedingung die automatisch Tags an Artikel vergibt
@Model
class Rule {
    var id: UUID
    var name: String
    var isEnabled: Bool
    var conditionField: String      // "title", "summary", "feedTitle"
    var conditionOperator: String   // "contains", "startsWith", "endsWith"
    var conditionValue: String      // z.B. "Apple", "WWDC"

    @Relationship
    var assignTag: Tag?

    init(name: String, conditionField: String,
         conditionOperator: String, conditionValue: String) {
        self.id = UUID()
        self.name = name
        self.isEnabled = true
        self.conditionField = conditionField
        self.conditionOperator = conditionOperator
        self.conditionValue = conditionValue
    }
}
