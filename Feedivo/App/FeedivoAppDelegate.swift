import AppKit
import UserNotifications

// Fängt feedivo://-URL-Aufrufe zuverlässig ab — sowohl beim Kaltstart (bevor
// die SwiftUI-View-Hierarchie existiert) als auch bei laufender App.
// application(_:open:) ist der klassische AppKit-Einstiegspunkt dafür und
// feuert in beiden Fällen, anders als SwiftUIs .onOpenURL. Ersetzt .onOpenURL
// deshalb vollständig (siehe ContentView.swift), damit dieselbe URL nicht
// doppelt verarbeitet wird.
final class FeedivoAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
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
        // Ohne eigenen Delegate unterdrückt macOS Benachrichtigungs-Banner
        // standardmäßig, solange die App im Vordergrund ist — die Zustellung an
        // UNUserNotificationCenter gelingt dabei trotzdem fehlerfrei, nur ohne
        // sichtbaren Banner. willPresent(...) unten macht die Darstellung auch
        // im Vordergrund explizit.
        UNUserNotificationCenter.current().delegate = self

        guard let feedivoDatabase = menubarFeedivoDatabase, let feedViewModel = menubarFeedViewModel else {
            return
        }

        menubarStatusItemController = MenubarStatusItemController(
            feedivoDatabase: feedivoDatabase,
            feedViewModel: feedViewModel
        )
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if let action = FeedivoURLSchemeParser.action(for: url) {
                pendingURLSchemeAction.action = action
            }
        }
    }
}
