import Foundation

/// Reine Übergangslogik für die feste (nicht über die Shortcuts-Einstellungen
/// anpassbare) Rechts-/Links-Pfeiltasten-Navigation im Reader: Rechts wechselt
/// von der nativen Ansicht zur eingebetteten Originalansicht, ein zweites Mal
/// Rechts öffnet den Artikel im externen Browser; Links geht von der
/// Originalansicht zurück zur nativen Ansicht. Als eigener Typ isoliert, damit
/// die Zustandsübergänge unabhängig von der `.onKeyPress`-Verdrahtung in
/// `ContentView.swift` unit-testbar sind (SwiftUI-Tastatur-Events selbst sind
/// in diesem Projekt nicht automatisiert testbar).
enum ReaderArrowKeyNavigation {
    enum RightArrowResult: Equatable {
        case switchToWeb
        case openInBrowser
    }

    static func rightArrowResult(currentMode: ReaderDisplayMode) -> RightArrowResult {
        switch currentMode {
        case .native:
            return .switchToWeb
        case .web:
            return .openInBrowser
        }
    }

    static func leftArrowShouldSwitchToNative(currentMode: ReaderDisplayMode) -> Bool {
        currentMode == .web
    }
}
