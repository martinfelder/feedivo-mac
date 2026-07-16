import AppKit
import SwiftUI

/// Beobachtet app-weit, ob gerade ein `NSTextField`/`NSTextView` editiert wird (SwiftUI
/// `TextField` läuft auf macOS intern über `NSTextField`, löst dieselben Notifications
/// aus). Grundlage für den Textfeld-Schutz modifier-freier Shortcuts — siehe
/// `KeyboardShortcutsSettings.customizableKeyboardShortcut(_:overrides:)`.
///
/// Bekannte Grenze: Textfelder innerhalb einer im `WKWebView` geladenen Webseite
/// (Originalartikel-Ansicht) laufen nicht über `NSControl` und lösen diese
/// Notifications nicht aus — dort bleibt ein theoretisches Kollisionsrisiko für
/// modifier-freie Shortcuts bestehen (dokumentierte, nicht behobene Einschränkung).
@Observable
@MainActor
final class TextEditingFocusMonitor {
    static let shared = TextEditingFocusMonitor()

    private(set) var isEditingText = false
    private var beginObserver: NSObjectProtocol?
    private var endObserver: NSObjectProtocol?

    init() {}

    /// `queue: .main` + `@MainActor`-Closure ist die von Apple empfohlene Brücke
    /// zwischen `NotificationCenter` und MainActor-isolierten Swift-Typen — eine
    /// naive nicht-isolierte Closure würde bei aktivem `SWIFT_DEFAULT_ACTOR_ISOLATION
    /// = MainActor` (siehe CLAUDE.md-Gotcha) nicht kompilieren.
    func startObserving(center: NotificationCenter = .default) {
        beginObserver = center.addObserver(
            forName: NSControl.textDidBeginEditingNotification,
            object: nil,
            queue: .main
        ) { @MainActor [weak self] _ in
            self?.isEditingText = true
        }

        endObserver = center.addObserver(
            forName: NSControl.textDidEndEditingNotification,
            object: nil,
            queue: .main
        ) { @MainActor [weak self] _ in
            self?.isEditingText = false
        }
    }
}
