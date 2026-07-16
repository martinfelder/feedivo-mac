import Foundation
import SwiftUI

/// Persistierte Nutzer-Überschreibungen für Feature "Shortcuts anpassen". Wird als
/// JSON-codierter String in einem einzigen `@AppStorage`-Key abgelegt (analog dem
/// String-Raw-Value-Muster von `ArticleSortOption`/`ReaderFontPreset` — 12 Einzel-
/// Keys wären hier unübersichtlicher als ein Blob).
///
/// `values` ist bewusst `[String: KeyboardShortcutSpec?]` (Wert selbst optional) statt
/// nur `[String: KeyboardShortcutSpec]`, um drei Zustände pro Shortcut zu unterscheiden:
/// - Schlüssel fehlt → nicht angepasst, `CustomizableShortcut.defaultSpec` gilt
/// - Schlüssel vorhanden mit Wert → auf diese Kombination umgelegt
/// - Schlüssel vorhanden mit `nil` → bewusst gelöscht, gar kein Shortcut
///
/// Achtung beim Schreiben: `values[id] = nil` (bare nil) ENTFERNT den Schlüssel
/// (Zustand 1), `values[id] = .some(nil)` setzt ihn explizit auf "gelöscht"
/// (Zustand 3) — das ist Swifts Standardverhalten bei optionalen Dictionary-Werten,
/// kein Bug.
struct KeyboardShortcutOverrides: Equatable {
    var values: [String: KeyboardShortcutSpec?]

    init(values: [String: KeyboardShortcutSpec?] = [:]) {
        self.values = values
    }

    static let storageKey = "customKeyboardShortcuts"

    static func resolved(from rawValue: String) -> KeyboardShortcutOverrides {
        guard let data = rawValue.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: KeyboardShortcutSpec?].self, from: data)
        else {
            return KeyboardShortcutOverrides()
        }

        return KeyboardShortcutOverrides(values: decoded)
    }

    var rawValue: String {
        guard let data = try? JSONEncoder().encode(values),
              let string = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }

        return string
    }
}

enum KeyboardShortcutsSettings {
    static let storageKey = KeyboardShortcutOverrides.storageKey

    static func spec(
        for shortcut: CustomizableShortcut,
        in overrides: KeyboardShortcutOverrides
    ) -> KeyboardShortcutSpec? {
        if let override = overrides.values[shortcut.id] {
            return override
        }

        return shortcut.defaultSpec
    }

    static func conflictingShortcut(
        for spec: KeyboardShortcutSpec,
        excluding: CustomizableShortcut,
        in overrides: KeyboardShortcutOverrides
    ) -> CustomizableShortcut? {
        CustomizableShortcut.allCases.first { candidate in
            candidate != excluding && Self.spec(for: candidate, in: overrides) == spec
        }
    }

    /// Modifier-freie Shortcuts (nur ein Zeichen oder Leertaste) brauchen den
    /// `TextEditingFocusMonitor`-Schutz in `customizableKeyboardShortcut`, da sie
    /// sonst als normales `NSMenuItem`-Tastenkürzel jede Texteingabe blockieren
    /// würden. Als eigene Funktion extrahiert, damit sowohl die Menü-Verdrahtung
    /// als auch die Warnzeile in den Einstellungen (Task 7) dieselbe Bedingung
    /// nutzen, statt sie unabhängig voneinander zu duplizieren.
    static func needsTextFieldGuard(for spec: KeyboardShortcutSpec) -> Bool {
        spec.modifiers.isEmpty
    }
}

extension View {
    /// Wendet den nutzerdefinierten (oder Default-)Shortcut für `shortcut` an — oder
    /// gar keinen, wenn der Nutzer ihn in den Einstellungen bewusst gelöscht hat.
    /// Modifier-freie Shortcuts werden zusätzlich deaktiviert, solange gerade ein
    /// Textfeld editiert wird (`TextEditingFocusMonitor`) — sonst würde z. B. das
    /// Tippen von „j" im Suchfeld statt eines „j" den Menübefehl auslösen.
    @ViewBuilder
    func customizableKeyboardShortcut(
        _ shortcut: CustomizableShortcut,
        overrides: KeyboardShortcutOverrides
    ) -> some View {
        if let spec = KeyboardShortcutsSettings.spec(for: shortcut, in: overrides) {
            if KeyboardShortcutsSettings.needsTextFieldGuard(for: spec) {
                self.keyboardShortcut(spec.keyEquivalent, modifiers: spec.eventModifiers)
                    .disabled(TextEditingFocusMonitor.shared.isEditingText)
            } else {
                self.keyboardShortcut(spec.keyEquivalent, modifiers: spec.eventModifiers)
            }
        } else {
            self
        }
    }
}
