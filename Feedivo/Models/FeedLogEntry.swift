import Foundation
import SwiftData

// Art eines Feed-Logeintrags. Wird als String gespeichert (CloudKit-kompatibel,
// kein Migrationsaufwand), an den Aufrufstellen aber typsicher als enum
// übergeben — keine Magic-Strings mehr verstreut im Code.
enum FeedLogEntryKind: String {
    case info
    case error
}

// FeedLogEntry protokolliert Feed-Abrufe und Fehler fuer die Eigenschaftenansicht.
@Model
class FeedLogEntry {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var kind: String = FeedLogEntryKind.info.rawValue
    var message: String = ""

    @Relationship
    var feed: Feed?

    init(
        createdAt: Date = Date(),
        kind: FeedLogEntryKind,
        message: String,
        feed: Feed? = nil
    ) {
        self.id = UUID()
        self.createdAt = createdAt
        self.kind = kind.rawValue
        self.message = message
        self.feed = feed
    }

    /// Typsicherer Zugriff auf den gespeicherten `kind`-String. `nil`, falls
    /// ein älterer Wert gespeichert wurde, der nicht zum enum passt.
    var kindEnum: FeedLogEntryKind? {
        FeedLogEntryKind(rawValue: kind)
    }
}