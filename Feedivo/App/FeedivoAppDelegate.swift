import AppKit

// Fängt feedivo://-URL-Aufrufe zuverlässig ab — sowohl beim Kaltstart (bevor
// die SwiftUI-View-Hierarchie existiert) als auch bei laufender App.
// application(_:open:) ist der klassische AppKit-Einstiegspunkt dafür und
// feuert in beiden Fällen, anders als SwiftUIs .onOpenURL. Ersetzt .onOpenURL
// deshalb vollständig (siehe ContentView.swift), damit dieselbe URL nicht
// doppelt verarbeitet wird.
final class FeedivoAppDelegate: NSObject, NSApplicationDelegate {
    let pendingURLSchemeAction = PendingURLSchemeAction()

    // Feature 21.1: `NSStatusItem` darf erst in `applicationDidFinishLaunching`
    // angelegt werden — in `FeedivoApp.init()` (also vor Abschluss des App-
    // Launches) erzeugt, blieb das Icon unsichtbar (Nutzer-Report 2026-07-10).
    // `FeedivoApp.init()` reicht die Abhängigkeiten früh per
    // `configureMenubarController` durch, der eigentliche Controller entsteht
    // aber erst hier.
    private var menubarFeedivoDatabase: FeedivoDatabase?
    private var menubarFeedViewModel: FeedViewModel?
    private(set) var menubarStatusItemController: MenubarStatusItemController?

    func configureMenubarController(feedivoDatabase: FeedivoDatabase, feedViewModel: FeedViewModel) {
        menubarFeedivoDatabase = feedivoDatabase
        menubarFeedViewModel = feedViewModel
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let feedivoDatabase = menubarFeedivoDatabase, let feedViewModel = menubarFeedViewModel else {
            return
        }

        menubarStatusItemController = MenubarStatusItemController(
            feedivoDatabase: feedivoDatabase,
            feedViewModel: feedViewModel
        )
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if let action = FeedivoURLSchemeParser.action(for: url) {
                pendingURLSchemeAction.action = action
            }
        }
    }
}
