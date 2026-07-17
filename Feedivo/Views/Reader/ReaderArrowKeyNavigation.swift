import Foundation

/// Reine Übergangslogik für die feste (nicht über die Shortcuts-Einstellungen
/// anpassbare) Rechts-/Links-Pfeiltasten-Navigation im Reader: Rechts wechselt
/// nur vorwärts von der nativen zur eingebetteten Originalansicht, Links geht
/// von dort wieder zurück — klassisches Vorwärts-/Rückwärts-Paar, analog zur
/// Browser-Navigation. Das Öffnen im externen Browser läuft über eine eigene
/// Taste (Eingabetaste), unabhängig vom aktuellen Ansicht-Zustand. Zweite
/// Nutzer-Korrektur nach Live-Test: eine erste Fassung machte Rechts zu einem
/// beidseitigen Umschalter und entfernte Links komplett — das brach die
/// gewohnte Erwartung, mit Links aus der Web-Ansicht zurückzukehren. Als
/// eigener Typ isoliert, damit die Zustandsübergänge unabhängig von der
/// `.onKeyPress`-Verdrahtung in `ContentView.swift` unit-testbar sind
/// (SwiftUI-Tastatur-Events selbst sind in diesem Projekt nicht automatisiert
/// testbar).
enum ReaderArrowKeyNavigation {
    static func rightArrowShouldSwitchToWeb(currentMode: ReaderDisplayMode) -> Bool {
        currentMode == .native
    }

    static func leftArrowShouldSwitchToNative(currentMode: ReaderDisplayMode) -> Bool {
        currentMode == .web
    }
}
