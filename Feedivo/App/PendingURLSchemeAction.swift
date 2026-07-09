import Foundation
import Observation

// Hält eine über feedivo:// ausgelöste Aktion, bis ContentView bereit ist,
// sie zu konsumieren. Notwendig, weil NSApplicationDelegate.application(_:open:)
// beim Kaltstart feuert, bevor die SwiftUI-View-Hierarchie existiert —
// .onOpenURL allein verpasst dieses Launch-Apple-Event (siehe FeedivoAppDelegate).
@Observable
final class PendingURLSchemeAction {
    var action: FeedivoURLSchemeAction?
}
