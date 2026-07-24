import Foundation
import Observation

/// Hält den aktuellen iCloud-Sync-Status für die Settings-UI. Eigene, CloudKit-freie Datei,
/// damit `CloudSyncSettings.swift` (liest u. a. `state` für den Status-Text) nicht `CloudKit`
/// importieren muss.
@Observable
final class CloudSyncStatus {
    enum State: Equatable {
        case idle
        case syncing
        case accountUnavailable
        case error(String)
    }

    var state: State = .idle
}
