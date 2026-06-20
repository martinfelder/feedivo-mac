import Foundation
import SwiftData

// FeedLogEntry protokolliert Feed-Abrufe und Fehler fuer die Eigenschaftenansicht.
@Model
class FeedLogEntry {
    var id: UUID
    var createdAt: Date
    var kind: String
    var message: String

    @Relationship
    var feed: Feed?

    init(
        createdAt: Date = Date(),
        kind: String,
        message: String,
        feed: Feed? = nil
    ) {
        self.id = UUID()
        self.createdAt = createdAt
        self.kind = kind
        self.message = message
        self.feed = feed
    }
}
