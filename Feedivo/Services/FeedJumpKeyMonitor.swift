import AppKit
import WebKit

/// App-lokaler Tastatur-Monitor für den automatischen Feed-Sprung (Feature:
/// Pfeil-Runter am Ende der ungelesenen Artikel eines Feeds springt zum
/// nächsten Feed mit ungelesenen Artikeln, Pfeil-Hoch symmetrisch rückwärts).
///
/// Ersetzt einen ursprünglich versuchten `.onKeyPress(.downArrow)`/
/// `.onKeyPress(.upArrow)`-Handler in `ContentView.swift`, der live bestätigt
/// wirkungslos war: macOS' native `List`-Tastatursteuerung konsumiert
/// Pfeil-Hoch/-Runter auch am Rand der Liste vollständig, bevor SwiftUIs
/// `.onKeyPress`-Mechanismus das Ereignis überhaupt sieht. Ein
/// `NSEvent.addLocalMonitorForEvents`-Monitor fängt das Ereignis dagegen ab,
/// BEVOR es an irgendeine View (auch `List`s interne `NSTableView`)
/// dispatcht wird — siehe
/// `docs/superpowers/specs/2026-07-17-feed-sprung-nsevent-monitor-design.md`.
@Observable
@MainActor
final class FeedJumpKeyMonitor {
    static let shared = FeedJumpKeyMonitor()

    enum Direction {
        case next
        case previous
    }

    /// Von `ContentView.configureFeedJumpKeyMonitor()` einmalig gesetzt.
    /// Liefert true, wenn ein Feed-Sprung in die jeweilige Richtung aktuell
    /// zulässig ist (Einzel-Feed-Auswahl, am Rand der ungelesenen Artikel,
    /// keine laufende Sprung-Sperre).
    var isEligible: (Direction) -> Bool = { _ in false }
    /// Führt den eigentlichen Sprung aus (ruft die bereits bestehenden
    /// ContentView-Methoden `selectNextFeedWithUnread()`/
    /// `selectPreviousFeedWithUnread()` auf).
    var performJump: (Direction) -> Void = { _ in }
    /// Von der neuen `ContentWindowObserver`-Bridge-View gesetzt — die
    /// `NSWindow`, die `ContentView` tatsächlich hostet. Verhindert, dass
    /// Pfeiltasten-Ereignisse in anderen Fenstern (Suche, Organizer,
    /// Einstellungen, Artikel-Popout) fälschlich einen Feed-Sprung im
    /// Hauptfenster auslösen.
    weak var contentWindow: NSWindow?

    private var monitor: Any?

    private init() {}

    func startMonitoring() {
        guard monitor == nil else { return }

        // @MainActor auf der Closure ist dieselbe von Apple empfohlene Brücke
        // wie in TextEditingFocusMonitor.startObserving() — ohne die
        // Annotation würde der Zugriff auf self.contentWindow/isEligible/
        // performJump (alles MainActor-isolierte Properties) unter
        // SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor nicht kompilieren.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { @MainActor [weak self] event in
            guard let self else { return event }

            let modifierFlagsAreEmpty = event.modifierFlags
                .intersection(.deviceIndependentFlagsMask)
                .isEmpty
            guard let direction = Self.direction(
                for: event.specialKey,
                modifierFlagsAreEmpty: modifierFlagsAreEmpty
            ) else {
                return event
            }
            guard !TextEditingFocusMonitor.shared.isEditingText else { return event }
            guard let contentWindow = self.contentWindow, event.window === contentWindow else {
                return event
            }
            guard !self.firstResponderIsExcluded(in: contentWindow) else { return event }
            guard self.isEligible(direction) else { return event }

            self.performJump(direction)
            return nil
        }
    }

    /// Reine Klassifikation, unabhängig vom Fenster-/Fokus-Zustand — deshalb
    /// `nonisolated`: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` würde eine
    /// unannotierte `static func` auf dieser `@MainActor`-Klasse sonst aus
    /// synchronem Test-Code heraus unaufrufbar machen (siehe CLAUDE.md-Gotcha
    /// zu `MenubarStatusItemController`).
    nonisolated static func direction(
        for specialKey: NSEvent.SpecialKey?,
        modifierFlagsAreEmpty: Bool
    ) -> Direction? {
        guard modifierFlagsAreEmpty else { return nil }

        switch specialKey {
        case .some(.downArrow):
            return .next
        case .some(.upArrow):
            return .previous
        default:
            return nil
        }
    }

    /// Schließt zwei bekannte, eigenständig pfeiltasten-navigierbare
    /// AppKit-Bereiche im Hauptfenster aus: das eingebettete `WKWebView`
    /// (Reader-„Web-Ansicht" — dort soll Pfeil-Hoch/-Runter normal scrollen)
    /// und die Sidebar-`NSOutlineView` (dort soll Pfeil-Hoch/-Runter normal
    /// zwischen Feed-Zeilen wechseln). Aufstieg durch die `superview`-Kette
    /// ab dem First Responder — beides öffentliche AppKit-/WebKit-
    /// Basisklassen, keine fragilen privaten Klassennamen nötig.
    private func firstResponderIsExcluded(in window: NSWindow) -> Bool {
        var view = window.firstResponder as? NSView
        while let current = view {
            if current is WKWebView || current is NSOutlineView {
                return true
            }
            view = current.superview
        }
        return false
    }
}
