import SwiftUI

/// Modifier-Tasten einer nutzerdefinierbaren Tastenkombination. Anzeige-Reihenfolge
/// folgt der macOS-Konvention ⌃⌥⇧⌘ (Control, Option, Shift, Command).
enum ShortcutModifier: String, Codable, CaseIterable, Sendable {
    case control
    case option
    case shift
    case command

    var eventModifier: EventModifiers {
        switch self {
        case .control: .control
        case .option: .option
        case .shift: .shift
        case .command: .command
        }
    }

    var symbol: String {
        switch self {
        case .control: "⌃"
        case .option: "⌥"
        case .shift: "⇧"
        case .command: "⌘"
        }
    }
}

/// Nicht-druckbare Tasten, die die App aktuell als Shortcuts verwendet (Pfeiltasten,
/// Return). Alles andere wird als einzelnes Zeichen in `KeyboardShortcutSpec.key`
/// abgelegt.
enum SpecialKey: String, Codable, CaseIterable, Sendable {
    case upArrow
    case downArrow
    case `return`

    var keyEquivalent: KeyEquivalent {
        switch self {
        case .upArrow: .upArrow
        case .downArrow: .downArrow
        case .return: .return
        }
    }

    var displaySymbol: String {
        switch self {
        case .upArrow: "↑"
        case .downArrow: "↓"
        case .return: "↩"
        }
    }
}

/// Eine vollständige, nutzerdefinierbare Tastenkombination (Feature: Shortcuts in
/// den Einstellungen anpassen). `key` ist entweder der Rohwert eines `SpecialKey`
/// oder ein einzelnes druckbares Zeichen als String.
struct KeyboardShortcutSpec: Codable, Equatable, Sendable {
    var key: String
    var modifiers: Set<ShortcutModifier>

    var keyEquivalent: KeyEquivalent {
        if let specialKey = SpecialKey(rawValue: key) {
            return specialKey.keyEquivalent
        }

        return KeyEquivalent(key.first ?? " ")
    }

    var eventModifiers: EventModifiers {
        modifiers.reduce(into: EventModifiers()) { result, modifier in
            result.insert(modifier.eventModifier)
        }
    }

    /// Für die Einstellungen-Liste, z. B. "⌘⇧R".
    var displaySymbols: String {
        let modifierSymbols = ShortcutModifier.allCases
            .filter { modifiers.contains($0) }
            .map(\.symbol)
            .joined()
        let keySymbol = SpecialKey(rawValue: key)?.displaySymbol ?? key.uppercased()
        return modifierSymbols + keySymbol
    }
}
