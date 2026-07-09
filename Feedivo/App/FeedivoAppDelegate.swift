import AppKit

// Fängt feedivo://-URL-Aufrufe zuverlässig ab — sowohl beim Kaltstart (bevor
// die SwiftUI-View-Hierarchie existiert) als auch bei laufender App.
// application(_:open:) ist der klassische AppKit-Einstiegspunkt dafür und
// feuert in beiden Fällen, anders als SwiftUIs .onOpenURL. Ersetzt .onOpenURL
// deshalb vollständig (siehe ContentView.swift), damit dieselbe URL nicht
// doppelt verarbeitet wird.
final class FeedivoAppDelegate: NSObject, NSApplicationDelegate {
    let pendingURLSchemeAction = PendingURLSchemeAction()

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if let action = FeedivoURLSchemeParser.action(for: url) {
                pendingURLSchemeAction.action = action
            }
        }
    }
}
