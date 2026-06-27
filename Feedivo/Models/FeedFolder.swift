import Foundation
import SwiftData

// FeedFolder speichert leere Ordner, bevor ihnen Feeds zugewiesen sind.
@Model
class FeedFolder {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()

    init(
        name: String,
        createdAt: Date = Date()
    ) {
        self.id = UUID()
        self.name = name
        self.createdAt = createdAt
    }
}
