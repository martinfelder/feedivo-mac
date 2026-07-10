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
/// eine deklarative SwiftUI-Scene. Deshalb beobachtet dieser Controller die
/// relevanten `UserDefaults`-Keys SELBST per KVO (siehe `observedKeys`), statt
/// sich auf `.task`/`.onChange`-Modifier einer bestimmten SwiftUI-View zu
/// verlassen. Eine frühere Version hängte diese Reaktivität an die
/// `ContentView` der Haupt-`WindowGroup` — das brach, sobald der Nutzer das
/// Hauptfenster schloss (z. B. beim Testen von „App ohne Dock-Icon", dem
/// Kernszenario dieses Features): die View-Hierarchie inkl. `.onChange`-
/// Handlern wird von SwiftUI beim Fenster-Schließen zerstört, wodurch das
/// Menubar-Icon beim Aktivieren der Einstellung nicht mehr erschien und die
/// App ohne Dock-Icon/Menubar-Icon keinen Wiedereinstiegspunkt mehr hatte
/// (gefunden 2026-07-10, Nutzer-Report nach der ersten Implementierung).
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

    /// `UserDefaults`-Keys, deren Änderung das Menubar-Icon/Popover bzw. die
    /// Dock-Icon-Sichtbarkeit betreffen. Per KVO beobachtet statt per SwiftUI-
    /// `.onChange`, damit die Reaktivität nicht von der Lebensdauer eines
    /// bestimmten Fensters abhängt — `hidesDockIconKey` gehört bewusst mit
    /// dazu: ohne Dock-Icon ist das Menubar-Icon der einzige Wiedereinstiegs-
    /// punkt in die App, beide Zustände müssen also aus demselben,
    /// fenster-unabhängigen Mechanismus gepflegt werden.
    private static let observedKeys = [
        MenubarSettings.isEnabledKey,
        MenubarSettings.hidesDockIconKey,
        SQLiteDataInvalidation.statusVersionKey,
        "appLanguage",
        InterfaceTextSize.storageKey,
        AppAppearance.storageKey
    ]

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

        for key in Self.observedKeys {
            UserDefaults.standard.addObserver(self, forKeyPath: key, options: [], context: nil)
        }
        applyCurrentSettings()
    }

    /// KVO-Callback für `observedKeys` — feuert unabhängig davon, ob gerade
    /// ein SwiftUI-Fenster geöffnet ist. `nonisolated`, weil `NSObject`s
    /// `@objc`-KVO-Mechanismus die Methode auf beliebigem Thread aufrufen
    /// kann; die eigentliche Arbeit läuft über `Task { @MainActor in … }`
    /// zurück im `@MainActor`-Kontext dieser Klasse.
    nonisolated override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        Task { @MainActor in
            self.applyCurrentSettings()
        }
    }

    /// Legt das Status-Item an bzw. entfernt es und aktualisiert Badge und
    /// gehosteten Inhalt — liest alle relevanten Einstellungen direkt aus
    /// `UserDefaults`, damit ein einzelner Aufruf (initial oder per KVO)
    /// immer den vollständigen, aktuellen Zustand herstellt.
    private func applyCurrentSettings() {
        let defaults = UserDefaults.standard
        let isEnabled = defaults.object(forKey: MenubarSettings.isEnabledKey) as? Bool
            ?? MenubarSettings.defaultIsEnabled
        setEnabled(isEnabled)

        let hidesDockIcon = defaults.object(forKey: MenubarSettings.hidesDockIconKey) as? Bool
            ?? MenubarSettings.defaultHidesDockIcon
        NSApp.setActivationPolicy(hidesDockIcon ? .accessory : .regular)

        if let sidebarFeeds = try? FeedStore(database: feedivoDatabase).sidebarFeeds() {
            unreadCount = AppIconBadgeService.unreadCount(in: sidebarFeeds)
            applyIconAppearance()
        }

        let appLanguageRawValue = defaults.string(forKey: "appLanguage") ?? AppLanguage.system.rawValue
        let interfaceTextSizeRawValue = defaults.string(forKey: InterfaceTextSize.storageKey)
            ?? InterfaceTextSize.defaultSize.rawValue
        let appAppearanceRawValue = defaults.string(forKey: AppAppearance.storageKey)
            ?? AppAppearance.defaultMode.rawValue

        applyHostedEnvironment(
            locale: AppLanguage.resolved(from: appLanguageRawValue).locale,
            interfaceTextSize: InterfaceTextSize.resolved(from: interfaceTextSizeRawValue),
            colorScheme: AppAppearance.resolved(from: appAppearanceRawValue).colorScheme
        )
    }

    private func setEnabled(_ enabled: Bool) {
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

    private func applyIconAppearance() {
        guard let button = statusItem?.button else { return }

        let image = NSImage(
            systemSymbolName: Self.symbolName(forUnreadCount: unreadCount),
            accessibilityDescription: nil
        )
        // Menubar-Icons müssen als Template-Bild markiert sein, damit AppKit sie
        // automatisch korrekt in Hell/Dunkel/selektiertem Zustand einfärbt — ohne
        // das kann das Icon je nach Systemzustand falsch oder unsichtbar wirken.
        image?.isTemplate = true
        button.image = image
        button.title = Self.badgeText(forUnreadCount: unreadCount)
        button.imagePosition = .imageLeading
    }

    private func applyHostedEnvironment(locale: Locale, interfaceTextSize: InterfaceTextSize, colorScheme: ColorScheme?) {
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
