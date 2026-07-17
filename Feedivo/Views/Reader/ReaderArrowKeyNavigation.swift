import Foundation

/// Reine Übergangslogik für die feste (nicht über die Shortcuts-Einstellungen
/// anpassbare) Rechts-Pfeiltasten-Navigation im Reader: Rechts schaltet zwischen
/// nativer Ansicht und eingebetteter Originalansicht hin und her. Das Öffnen im
/// externen Browser läuft über eine eigene Taste (Eingabetaste), nicht über
/// diesen Umschalter — Nutzer-Korrektur nach Live-Test: eine reine
/// Vorwärts-Kette (nativ → Web → Browser) machte den Rückweg von Web zu nativ
/// über Rechts unerreichbar, ein separates Links nur für den Rückweg fühlte
/// sich uneinheitlich an. Als eigener Typ isoliert, damit die Zustandsübergänge
/// unabhängig von der `.onKeyPress`-Verdrahtung in `ContentView.swift`
/// unit-testbar sind (SwiftUI-Tastatur-Events selbst sind in diesem Projekt
/// nicht automatisiert testbar).
enum ReaderArrowKeyNavigation {
    static func toggleMode(currentMode: ReaderDisplayMode) -> ReaderDisplayMode {
        switch currentMode {
        case .native:
            return .web
        case .web:
            return .native
        }
    }
}
