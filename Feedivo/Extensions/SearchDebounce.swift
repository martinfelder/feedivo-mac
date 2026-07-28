import Foundation

/// Gemeinsamer Debounce-Baustein für Suchfeld-Verzögerung (Artikelliste,
/// Suchfenster). Ersetzt zwei zuvor unabhängig implementierte
/// `Task.sleep`-Aufrufe mit identischer Verzögerung, aber unterschiedlicher
/// API (Millisekunden-`Duration` vs. rohe Nanosekunden).
enum SearchDebounce {
    /// Wartezeit, bis ein eingegebener Suchtext als "fertig getippt" gilt.
    static let delayMilliseconds = 250

    /// Wartet `milliseconds` ab (Standard: `delayMilliseconds`, für
    /// Sucheingabe). Gibt `true` zurück, wenn die Wartezeit ungestört
    /// durchgelaufen ist, `false`, wenn der aufrufende `Task` währenddessen
    /// abgebrochen wurde (z. B. weil `.task(id:)` durch einen neuen Wert
    /// neu gestartet wurde). Der Parameter erlaubt Wiederverwendung für
    /// andere Debounce-Zwecke mit abweichender Wartezeit (z. B.
    /// Status-Version-Bündelung), statt einer dritten, abweichenden
    /// `Task.sleep`-Implementierung.
    static func wait(milliseconds: Int = delayMilliseconds) async -> Bool {
        try? await Task.sleep(for: .milliseconds(milliseconds))
        return !Task.isCancelled
    }
}
