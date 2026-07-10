import AppKit
import SwiftUI

/// Bündelt AppKit-`NSStatusItem` + `NSPopover` für das Menubar-Icon (Feature 21.1).
///
/// Ersetzt die zuvor verwendete SwiftUI-`MenuBarExtra`-Scene, die auf der zum
/// Entstehungszeitpunkt genutzten Xcode/macOS-Kombination einen 100%-CPU-
/// Endlos-Spin beim App-Start verursachte (Layout-Thrashing durch
/// `AppMenuBarExtrasController`-Reconciliation — siehe CLAUDE.md-Gotcha vom
/// 2026-07-10). `NSStatusItem` ist eine deutlich ältere AppKit-API, die nicht
/// auf SwiftUIs Scene-Reconciliation angewiesen ist und dieses Problem umgeht.
///
/// `NSHostingController` beobachtet externe Zustandsänderungen (Sprache,
/// Textgröße, Darstellung, Ungelesen-Zähler) NICHT automatisch — anders als
/// eine deklarative SwiftUI-Scene. Aufrufer müssen `updateUnreadCount(_:)`
/// bzw. `updateEnvironment(...)` explizit bei jeder relevanten Änderung
/// aufrufen (siehe `FeedivoApp.swift`).
@MainActor
final class MenubarStatusItemController: NSObject {
    private let feedivoDatabase: FeedivoDatabase
    private let feedViewModel: FeedViewModel

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    // `AnyView`, weil `.environment`/`.dynamicTypeSize`/`.preferredColorScheme` den
    // konkreten View-Typ bei jedem Aufruf in einen neuen `ModifiedContent<...>`-Typ
    // wandeln — `NSHostingController` braucht aber einen über die Lebensdauer stabilen
    // generischen Parameter, um `rootView` später neu zuweisen zu können.
    private let hostingController: NSHostingController<AnyView>

    private var unreadCount = 0
    private var locale = Locale.current
    private var interfaceTextSize = InterfaceTextSize.defaultSize
    private var colorScheme: ColorScheme?

    init(feedivoDatabase: FeedivoDatabase, feedViewModel: FeedViewModel) {
        self.feedivoDatabase = feedivoDatabase
        self.feedViewModel = feedViewModel
        self.hostingController = NSHostingController(
            rootView: AnyView(
                MenubarDropdownView(feedViewModel: feedViewModel)
                    .environment(\.feedivoDatabase, feedivoDatabase)
            )
        )
        super.init()
        popover.behavior = .transient
        popover.contentViewController = hostingController
    }

    /// Legt das Status-Item an bzw. entfernt es — angebunden an
    /// `MenubarSettings.isEnabledKey`.
    func setEnabled(_ enabled: Bool) {
        guard enabled else {
            if let statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
            }
            statusItem = nil
            return
        }

        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.target = self
        item.button?.action = #selector(togglePopover(_:))
        statusItem = item
        applyIconAppearance()
    }

    func updateUnreadCount(_ count: Int) {
        unreadCount = count
        applyIconAppearance()
    }

    func updateEnvironment(locale: Locale, interfaceTextSize: InterfaceTextSize, colorScheme: ColorScheme?) {
        self.locale = locale
        self.interfaceTextSize = interfaceTextSize
        self.colorScheme = colorScheme
        applyHostedEnvironment()
    }

    private func applyIconAppearance() {
        guard let button = statusItem?.button else { return }

        button.image = NSImage(
            systemSymbolName: Self.symbolName(forUnreadCount: unreadCount),
            accessibilityDescription: nil
        )
        button.title = Self.badgeText(forUnreadCount: unreadCount)
        button.imagePosition = .imageLeading
    }

    private func applyHostedEnvironment() {
        hostingController.rootView = AnyView(
            MenubarDropdownView(feedViewModel: feedViewModel)
                .environment(\.feedivoDatabase, feedivoDatabase)
                .environment(\.locale, locale)
                .environment(\.interfaceTextSize, interfaceTextSize)
                .dynamicTypeSize(interfaceTextSize.dynamicTypeSize)
                .preferredColorScheme(colorScheme)
        )
    }

    @objc
    private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }
    }

    /// Testbare Icon-Logik (Feature 21.1) — analog `AppIconBadgeService`s
    /// reinen Funktionen, ohne echtes `NSStatusItem` aufrufbar. `nonisolated`,
    /// da rein wertbasiert (kein Zugriff auf `@MainActor`-Instanzzustand) —
    /// sonst erben sie die `@MainActor`-Isolation der umschließenden Klasse
    /// und wären aus synchronen Tests heraus nicht aufrufbar.
    nonisolated static func symbolName(forUnreadCount count: Int) -> String {
        count > 0 ? "tray.full" : "tray"
    }

    nonisolated static func badgeText(forUnreadCount count: Int) -> String {
        count > 0 ? "\(count)" : ""
    }
}
