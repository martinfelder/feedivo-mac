import Foundation
import Observation
import Sparkle
import OSLog
import AppKit

/// Kapselt SPUUpdater + Sparkles EIGENEN `SPUStandardUserDriver` - EIN
/// Coordinator pro App-Prozess, wird in FeedivoApp.swift als einziges @State
/// erzeugt und per Environment durchgereicht, da SPUUpdater selbst als
/// Singleton pro Prozess gedacht ist.
///
/// Architektur-Wechsel (2026-08-02): Ersetzt eine vollständig selbstgebaute
/// `SPUUserDriver`-Konformität (eigene SwiftUI-Sheets für "Update gefunden"/
/// "Bereit zur Installation"/"Wird installiert") - Root-Cause-Analyse eines
/// live reproduzierten "hängt für immer bei 'Wird installiert'"-Bugs zeigte:
/// Sparkle fordert im .installing-Zustand per Quit-AppleEvent das Beenden der
/// App an, damit der externe Relauncher den Dateitausch abschließen kann.
/// Ein eigenes SwiftUI-`.sheet` blockiert AppKits automatische Terminierung
/// ("App termination blocked by modal sheet", live per Unified-Log
/// verifiziert) - selbst ein synchroner, direkter `NSWindow.endSheet(_:)`-Fix
/// im richtigen Callback (siehe Git-Historie) loeste das Symptom nur
/// teilweise: die App beendete sich zwar, relaunchte sich aber nicht mehr
/// zuverlässig. Vergleich mit NetNewsWires echter, produktiver Sparkle-
/// Integration (`/Users/martinfelder/Developer/NetNewsWire-main/Mac/
/// AppDelegate.swift`) zeigte: NetNewsWire nutzt ausschließlich Sparkles
/// eigenen `SPUStandardUserDriver` - ein battle-tested, von den Sparkle-
/// Maintainern selbst gegen genau diese Fensterlebenszyklus-/Terminierungs-
/// Fallstricke abgesichertes Verhalten - und implementiert dabei NICHT eine
/// einzige der optionalen `SPUStandardUserDriverDelegate`/`SPUUpdaterDelegate`-
/// Methoden. Feedivo übernimmt exakt dasselbe Muster: kein eigener Sheet-/
/// State-Code mehr, Sparkles native Fenster für Suche/Fortschritt/Installation
/// übernehmen komplett. `UpdateAvailableSheet`/`UpdateUpToDateSheet`/
/// `SparkleUpdateState`/`SparkleReleaseInfo` sind dadurch entfallen.
@Observable
@MainActor
final class SparkleUpdateCoordinator: NSObject {
    let isHomebrewInstall: Bool

    private var updater: SPUUpdater?
    private var userDriver: SPUStandardUserDriver?

    override init() {
        self.isHomebrewInstall = HomebrewInstallationDetector.isHomebrewCaskInstall(
            bundleURL: Bundle.main.bundleURL
        )
        super.init()
    }

    /// Muss einmalig beim App-Start aufgerufen werden (FeedivoApp.swift).
    /// Bei Homebrew-Installationen bewusst KEIN SPUUpdater erzeugt - Sparkle
    /// bleibt in dem Fall komplett inaktiv, Updates laufen ausschließlich
    /// über `brew upgrade`.
    func start() {
        guard !isHomebrewInstall else {
            AppLogger.dataAccess.info("SparkleUpdateCoordinator: Homebrew-Installation erkannt, Sparkle bleibt inaktiv.")
            return
        }
        let userDriver = SPUStandardUserDriver(hostBundle: Bundle.main, delegate: nil)
        self.userDriver = userDriver
        let updater = SPUUpdater(
            hostBundle: Bundle.main,
            applicationBundle: Bundle.main,
            userDriver: userDriver,
            delegate: nil
        )
        self.updater = updater
        // object(forKey:) != nil-Guard statt defaultValue-Kurzschluss - reiner
        // .bool(forKey:) würde bei fehlendem gespeichertem Wert immer `false`
        // liefern statt UpdateCheckSettings.defaultIsAutomaticCheckEnabled
        // (bekannter Gotcha, siehe CLAUDE.md zu retentionDays).
        let storedIsAutomaticCheckEnabled = UserDefaults.standard.object(forKey: UpdateCheckSettings.isAutomaticCheckEnabledKey) as? Bool
            ?? UpdateCheckSettings.defaultIsAutomaticCheckEnabled
        updater.automaticallyChecksForUpdates = storedIsAutomaticCheckEnabled
        do {
            try updater.start()
        } catch {
            AppLogger.dataAccess.error("SparkleUpdateCoordinator: SPUUpdater konnte nicht gestartet werden: \(error.localizedDescription, privacy: .public)")
        }
    }

    func checkForUpdatesManually() {
        guard !isHomebrewInstall else { return }
        updater?.checkForUpdates()
    }

    /// Homebrew-Installationen haben gar keinen SPUUpdater (siehe Guard in
    /// `start()`) - der App-Menü-Befehl "Nach Updates suchen…" zeigt hier
    /// stattdessen einen einfachen, direkten NSAlert-Hinweis statt eines
    /// eigenen Sheets (das mit dem Wechsel auf SPUStandardUserDriver entfallen
    /// ist).
    func showHomebrewHint() {
        let alert = NSAlert()
        alert.messageText = String(localized: "updateCheck.homebrewHint")
        alert.alertStyle = .informational
        alert.addButton(withTitle: String(localized: "common.ok"))
        alert.runModal()
    }

    /// Bindet den bestehenden "Automatischer Check"-Schalter (AboutSettingsView,
    /// @AppStorage(UpdateCheckSettings.isAutomaticCheckEnabledKey)) an Sparkles
    /// eigenes automatisches-Check-Verhalten - ohne diesen Aufruf würde der
    /// Schalter nach der Umstellung wirkungslos bleiben, da SPUUpdater seine
    /// automatischen Checks über eine eigene Property steuert, nicht über
    /// unsere UserDefaults. Wird beim Start (aus dem aktuell gespeicherten
    /// Wert) UND bei jeder Toggle-Änderung in AboutSettingsView aufgerufen.
    func setAutomaticChecksEnabled(_ enabled: Bool) {
        updater?.automaticallyChecksForUpdates = enabled
    }
}
