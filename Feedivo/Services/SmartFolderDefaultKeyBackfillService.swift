import Foundation
import SwiftData

enum SmartFolderDefaultKeyBackfillService {
    // Einmalig: bestehende Default-Ordner (isDefault==true) ohne defaultKey
    // nach deutschem Namen -> defaultKey backfillen. 8 bekannte Namen.
    private static let backfillDoneKey = "smartFolderDefaultKeyBackfillDone_v1"

    // Deutsche Source-Namen -> defaultKey (Spec-Abschnitt 3).
    private static let nameToKey: [String: String] = [
        "Alle Artikel": "all",
        "Ungelesen": "unread",
        "Mit Stern": "starred",
        "Heute": "today",
        "Ausgeblendet": "hidden",
        "Archiviert": "archived",
        "Diese Woche": "thisWeek",
        "Gespeichert": "saved"
    ]

    @MainActor
    @discardableResult
    static func backfillDefaultKeys(
        in context: ModelContext,
        defaults: UserDefaults = .standard
    ) throws -> Int {
        guard !defaults.bool(forKey: backfillDoneKey) else { return 0 }

        let folders = try context.fetch(FetchDescriptor<SmartFolder>())
        var updatedCount = 0
        for folder in folders where folder.defaultKey == nil && folder.isDefault {
            if let key = nameToKey[folder.name] {
                folder.defaultKey = key
                updatedCount += 1
            }
        }
        if updatedCount > 0 {
            try context.save()
        }
        defaults.set(true, forKey: backfillDoneKey)
        return updatedCount
    }
}