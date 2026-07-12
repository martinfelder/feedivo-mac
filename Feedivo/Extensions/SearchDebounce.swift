import Foundation

/// Gemeinsamer Debounce-Baustein für Suchfeld-Verzögerung (Artikelliste,
/// Suchfenster). Ersetzt zwei zuvor unabhängig implementierte
/// `Task.sleep`-Aufrufe mit identischer Verzögerung, aber unterschiedlicher
/// API (Millisekunden-`Duration` vs. rohe Nanosekunden).
enum SearchDebounce {
    /// Wartezeit, bis ein eingegebener Suchtext als "fertig getippt" gilt.
    static let delayMilliseconds = 250

    /// Wartet `delayMilliseconds` ab. Gibt `true` zurück, wenn die Wartezeit
    /// ungestört durchgelaufen ist, `false`, wenn der aufrufende `Task`
    /// währenddessen abgebrochen wurde (z. B. weil `.task(id:)` durch neue
    /// Texteingabe neu gestartet wurde).
    static func wait() async -> Bool {
        try? await Task.sleep(for: .milliseconds(delayMilliseconds))
        return !Task.isCancelled
    }
}
