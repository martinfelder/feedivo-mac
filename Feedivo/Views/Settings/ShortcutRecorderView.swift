import AppKit
import SwiftUI

/// Eigener Shortcut-Recorder — SwiftUI hat kein eingebautes Control dafür.
/// Klick startet den Aufnahme-Modus (Border wird hervorgehoben), der nächste
/// Tastendruck mit mindestens einer Modifier-Taste wird als neue Kombination
/// gemeldet. Escape bricht ab, ohne etwas zu ändern.
struct ShortcutRecorderView: View {
    let spec: KeyboardShortcutSpec?
    let onCapture: (KeyboardShortcutSpec) -> Void
    let onClear: () -> Void

    @State private var isRecording = false

    private var displayText: String {
        if isRecording {
            return String(localized: "shortcuts.recorder.recording")
        }
        return spec?.displaySymbols ?? String(localized: "shortcuts.recorder.placeholder")
    }

    var body: some View {
        HStack(spacing: 6) {
            RecorderRepresentable(isRecording: $isRecording) { key, modifiers in
                onCapture(KeyboardShortcutSpec(key: key, modifiers: modifiers))
                isRecording = false
            }
            .frame(width: 104, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isRecording ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isRecording ? 2 : 1)
            )
            .overlay {
                Text(displayText)
                    .font(.system(size: 11.5, weight: spec == nil ? .regular : .semibold))
                    .foregroundStyle(spec == nil && !isRecording ? .secondary : .primary)
                    .allowsHitTesting(false)
            }
            .onTapGesture {
                isRecording = true
            }

            if spec != nil {
                Button {
                    onClear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(L10n.shortcutsClearButtonHelp)
            }
        }
    }
}

/// Fängt Tastendrücke ab, solange `isRecording` aktiv ist. Erzwingt mindestens
/// eine Modifier-Taste (verhindert versehentliche Ein-Buchstaben-Shortcuts, die
/// mit normalem Tippen kollidieren würden).
private final class RecorderNSView: NSView {
    var onCapture: ((String, Set<ShortcutModifier>) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        // Escape (keyCode 53) bricht die Aufnahme ab, ohne etwas zu ändern.
        guard event.keyCode != 53 else {
            onCancel?()
            return
        }

        var modifiers: Set<ShortcutModifier> = []
        if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
        if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
        if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        if event.modifierFlags.contains(.command) { modifiers.insert(.command) }

        guard !modifiers.isEmpty else {
            return
        }

        let key: String
        switch event.keyCode {
        case 126: key = SpecialKey.upArrow.rawValue
        case 125: key = SpecialKey.downArrow.rawValue
        case 36: key = SpecialKey.return.rawValue
        default:
            guard let character = event.charactersIgnoringModifiers?.lowercased(), !character.isEmpty else {
                return
            }
            key = character
        }

        onCapture?(key, modifiers)
    }

    override func resignFirstResponder() -> Bool {
        onCancel?()
        return super.resignFirstResponder()
    }
}

private struct RecorderRepresentable: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onCapture: (String, Set<ShortcutModifier>) -> Void

    func makeNSView(context: Context) -> RecorderNSView {
        let view = RecorderNSView()
        view.onCapture = onCapture
        view.onCancel = { isRecording = false }
        return view
    }

    func updateNSView(_ nsView: RecorderNSView, context: Context) {
        nsView.onCapture = onCapture

        DispatchQueue.main.async {
            if isRecording, nsView.window?.firstResponder !== nsView {
                nsView.window?.makeFirstResponder(nsView)
            } else if !isRecording, nsView.window?.firstResponder === nsView {
                nsView.window?.makeFirstResponder(nil)
            }
        }
    }
}
