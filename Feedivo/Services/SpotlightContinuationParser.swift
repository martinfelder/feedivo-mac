import Foundation
import CoreSpotlight

/// Reine Parsing-Logik für die `NSUserActivity`, die macOS beim Klick auf ein
/// Spotlight-Suchresultat an die App liefert. Kein AppKit-/App-Bezug, dadurch
/// isoliert unit-testbar — analog zu `FeedivoURLSchemeParser`. Unbekannte
/// Aktivitätstypen oder fehlende/kaputte IDs liefern `nil` — der Aufrufer
/// ignoriert die Aktivität dann still.
enum SpotlightContinuationParser {
    static func articleID(from userActivity: NSUserActivity) -> UUID? {
        guard userActivity.activityType == CSSearchableItemActionType,
              let identifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String
        else {
            return nil
        }

        return UUID(uuidString: identifier)
    }
}
