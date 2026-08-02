import Foundation
import Observation
import Sparkle
import OSLog
import AppKit

/// Ersetzt den entfernten UpdateInstaller/UpdateChecker-Stack vollständig.
/// Kapselt SPUUpdater + eine eigene SPUUserDriver-Konformität, damit die
/// bereits gestylte UI (UpdateAvailableSheet etc.) erhalten bleibt, statt auf
/// Sparkles eigene Standardfenster zu wechseln. EIN Coordinator pro
/// App-Prozess - wird in FeedivoApp.swift als einziges @State erzeugt und
/// per Environment durchgereicht, da SPUUpdater selbst als Singleton pro
/// Prozess gedacht ist.
@Observable
@MainActor
final class SparkleUpdateCoordinator: NSObject {
    private(set) var state: SparkleUpdateState = .idle
    private(set) var hasUnseenUpdate = false
    // Fix Whole-Branch-Review (Critical 1): `state` allein reicht nicht aus, um
    // UpdateAvailableSheet über den kompletten In-Flight-Verlauf (.updateAvailable
    // -> .downloading -> .extracting -> .readyToInstall -> .installing) hinweg zu
    // befüllen - nur der .updateAvailable-Fall trägt ein SparkleReleaseInfo, jeder
    // Folgezustand nicht. FeedivoApp.swifts Sheet-Content-Closure wertet bei jeder
    // state-Änderung neu aus; ohne einen separaten, über den ganzen Vorgang hinweg
    // gültigen Zwischenspeicher rendert die Closure ab .downloading EmptyView() -
    // ein leeres Sheet ohne Fortschritt/Install-Button. currentRelease wird beim
    // Auffinden eines Updates gesetzt und erst beim vollständigen Verlassen des
    // Update-Vorgangs (Abbruch oder erfolgreiche Installation) wieder geleert.
    private(set) var currentRelease: SparkleReleaseInfo?
    let isHomebrewInstall: Bool

    private var updater: SPUUpdater?
    // Fix Whole-Branch-Review (Important 7): von `private` auf `internal`
    // (keinen Modifier) gelockert, damit `SparkleUpdateCoordinatorTests`
    // (`@testable import Feedivo`, gleiches Modul) die Continuation-Auflösung
    // von `installUpdate()`/`cancelDownload()` isoliert prüfen kann, ohne den
    // kompletten SPUUserDriver-Callback-Pfad nachstellen zu müssen - `private`
    // wäre selbst über `@testable` aus einer anderen Datei nicht sichtbar.
    var pendingUpdateChoice: ((SPUUserUpdateChoice) -> Void)?
    var pendingInstallChoice: ((SPUUserUpdateChoice) -> Void)?
    var pendingCancellation: (() -> Void)?

    override init() {
        self.isHomebrewInstall = HomebrewInstallationDetector.isHomebrewCaskInstall(
            bundleURL: Bundle.main.bundleURL
        )
        super.init()
    }

    /// Muss einmalig beim App-Start aufgerufen werden (FeedivoApp.swift).
    /// Bei Homebrew-Installationen bewusst KEIN SPUUpdater erzeugt - Sparkle
    /// bleibt in dem Fall komplett inaktiv, Updates laufen ausschließlich
    /// über `brew upgrade` (siehe Spec, Abschnitt 3).
    func start() {
        guard !isHomebrewInstall else {
            AppLogger.dataAccess.info("SparkleUpdateCoordinator: Homebrew-Installation erkannt, Sparkle bleibt inaktiv.")
            return
        }
        let updater = SPUUpdater(
            hostBundle: Bundle.main,
            applicationBundle: Bundle.main,
            userDriver: self,
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
            state = .failed(error.localizedDescription)
        }
    }

    func checkForUpdatesManually() {
        guard !isHomebrewInstall else { return }
        hasUnseenUpdate = false
        state = .checking
        updater?.checkForUpdates()
    }

    /// Fix Whole-Branch-Review (Important 2): `checkForUpdatesManually()` ist für
    /// Homebrew-Installationen ein stiller No-Op (siehe Guard oben, Sparkle bleibt
    /// dort komplett inaktiv, `start()` erzeugt gar keinen SPUUpdater) - der
    /// App-Menü-Befehl "Nach Updates suchen…" rief das bisher unbedingt auf und gab
    /// Homebrew-Nutzern dadurch nie irgendeine Rückmeldung. Diese Methode setzt
    /// stattdessen `state` auf `.failed(...)` mit dem bereits bestehenden
    /// Homebrew-Hinweistext - der `.failed`-Alert in
    /// `SparkleUpdatePresentationModifier` übernimmt die Anzeige, ohne dass der
    /// Menübefehl selbst `state` direkt setzen müsste (bleibt `private(set)`).
    func showHomebrewHint() {
        state = .failed(String(localized: "updateCheck.homebrewHint"))
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

    /// Der Nutzer kann "Installieren" von zwei verschiedenen Dialogen aus
    /// auslösen: entweder direkt bei "Update gefunden" (löst
    /// `pendingUpdateChoice` auf, was Sparkles Download/Extraktion startet)
    /// oder erst bei "Bereit zur Installation" (löst `pendingInstallChoice`
    /// auf, was den eigentlichen Installations-/Neustart-Vorgang startet).
    /// KRITISCHER FIX (Task-Review-Fund): Die ursprüngliche Fassung löste
    /// ausschließlich `pendingInstallChoice` auf - `pendingUpdateChoice`
    /// wurde zwar in `showUpdateFound(with:state:)` gesetzt, aber nie
    /// irgendwo gelesen/aufgerufen. Der "Installieren"-Klick auf ein frisch
    /// gefundenes Update war dadurch ein dauerhafter No-Op, und Sparkles
    /// Continuation blieb für immer offen - die interne Download-Pipeline
    /// kam nie in Gang. Fix: zuerst `pendingUpdateChoice` prüfen (falls
    /// gesetzt, sind wir im "Update gefunden"-Dialog), sonst
    /// `pendingInstallChoice` (falls gesetzt, sind wir im "Bereit zur
    /// Installation"-Dialog) - die beiden Zustände schließen sich laut
    /// Sparkles Protokollablauf gegenseitig aus.
    func installUpdate() {
        if let choice = pendingUpdateChoice {
            pendingUpdateChoice = nil
            choice(.install)
        } else {
            pendingInstallChoice?(.install)
            pendingInstallChoice = nil
        }
    }

    /// Fix Whole-Branch-Review (Important 1): löste bisher ausschließlich
    /// `pendingCancellation` auf und setzte `state = .idle` - eine noch offene
    /// `pendingUpdateChoice`/`pendingInstallChoice`-Continuation (aus
    /// `showUpdateFound`/`showReadyToInstallAndRelaunch`, jeweils per
    /// `withCheckedContinuation` erzeugt) wurde dabei NIE aufgelöst. Jeder
    /// Dismiss-Pfad des Sheets (onDismiss, beide `isPresented`-set-Closures in
    /// FeedivoApp.swift) läuft über diese Methode - das ließ Sparkles
    /// Continuation dauerhaft offen (Leak) und Sparkle erfuhr nie, dass der
    /// Nutzer abgebrochen hat, wodurch ein späterer `checkForUpdatesManually()`
    /// Sparkle ggf. noch mitten in der alten Session vorfand und wirkungslos
    /// blieb. Fix: zuerst eine noch ausstehende Choice-Continuation mit
    /// `.dismiss` auflösen (dieselbe Priorisierung `pendingUpdateChoice` vor
    /// `pendingInstallChoice` wie in `installUpdate()`, da sich beide laut
    /// Sparkles Protokollablauf gegenseitig ausschließen) - nur wenn keine von
    /// beiden gesetzt ist (z. B. während eines laufenden Downloads, der über
    /// `showDownloadInitiated(cancellation:)` läuft), auf die alte
    /// `pendingCancellation`-Closure zurückfallen.
    func cancelDownload() {
        if let choice = pendingUpdateChoice {
            pendingUpdateChoice = nil
            choice(.dismiss)
        } else if let choice = pendingInstallChoice {
            pendingInstallChoice = nil
            choice(.dismiss)
        } else {
            pendingCancellation?()
        }
        pendingCancellation = nil
        currentRelease = nil
        state = .idle
    }
}

// MARK: - SPUUserDriver

extension SparkleUpdateCoordinator: SPUUserDriver {
    nonisolated func show(_ request: SPUUpdatePermissionRequest) async -> SUUpdatePermissionResponse {
        // Automatische Checks sind über Sparkles SUEnableAutomaticChecks-
        // Verhalten gesteuert - wir erlauben pauschal, ohne eigenen Dialog
        // (entspricht dem bisherigen Verhalten: automatischer, stiller
        // Start-Check ohne Rückfrage an den Nutzer).
        SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false)
    }

    /// Nicht im ursprünglichen Implementierungsvorschlag enthalten -
    /// installierte Sparkle-Version (2.9.4) verlangt diese Methode zusätzlich
    /// zu den unten stehenden async-Varianten (per Compiler-Fehler
    /// "does not conform to protocol 'SPUUserDriver'" ermittelt, nicht Teil
    /// der ursprünglich dokumentierten API-Referenz). Wird aufgerufen, sobald
    /// ein manuell ausgelöster Check startet (VOR showUpdateFound/
    /// showUpdateNotFoundWithError) - die Cancellation wird wie beim
    /// Download-Fall in `pendingCancellation` abgelegt, damit `cancelDownload()`
    /// auch einen laufenden Check abbrechen kann.
    nonisolated func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        Task { @MainActor in
            self.pendingCancellation = cancellation
        }
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state updateState: SPUUserUpdateState) async -> SPUUserUpdateChoice {
        // Fix Whole-Branch-Review (Important 5): `appcastItem.displayVersionString`
        // allein liefert nur `sparkle:shortVersionString` (z. B. "1.0", vom
        // Release-Skript geschrieben) - verliert dadurch die Build-Nummer, die im
        // Rest der App (installedVersion hier, AppVersionInfo überall sonst) immer
        // als "1.0 (15)" formatiert wird. "Version 1.0 verfügbar" neben
        // "installiert: 1.0 (15)" ist kaum vergleichbar. `versionString` trägt die
        // rohe `sparkle:version` (= Build-Nummer, siehe
        // scripts/create_github_release.sh) - beide zusammen ergeben wieder das
        // gewohnte "1.0 (15)"-Format.
        let info = SparkleReleaseInfo(
            tagName: "\(appcastItem.displayVersionString) (\(appcastItem.versionString))",
            name: appcastItem.title,
            htmlURL: appcastItem.infoURL ?? URL(string: "https://github.com/martinfelder/feedivo-mac/releases")!,
            bodyHTML: appcastItem.itemDescription
        )
        currentRelease = info
        hasUnseenUpdate = true
        // Fix Whole-Branch-Review (Important 6): das entfernte, alte
        // `performSilentUpdateCheckIfNeeded()` zeigte für einen automatischen/
        // stillen Check bewusst KEIN UI, nur ein Badge. Diese Methode wird
        // sowohl von automatischen (Sparkles `automaticallyChecksForUpdates`)
        // als auch von nutzerausgelösten (`checkForUpdatesManually()`) Checks
        // aufgerufen - `updateState.userInitiated` unterscheidet beide Fälle.
        // Nur bei einem nutzerausgelösten Check wird `state` auf
        // `.updateAvailable` gesetzt (löst das Sheet in
        // SparkleUpdatePresentationModifier aus); ein automatischer Fund kurz
        // nach dem App-Start würde sonst ungefragt ein modales Sheet über den
        // Nutzer werfen - genau das, was der alte Code verhinderte.
        //
        // KRITISCHER REGRESSIONS-FIX (Re-Review nach obigem Fix): Für den
        // automatischen Fall wurde hier weiterhin bedingungslos per
        // `withCheckedContinuation` auf eine Nutzerentscheidung gewartet, die
        // NIE kommt (kein Sheet, kein Button, der `pendingUpdateChoice`
        // auflöst) - Sparkles `SPUUIBasedUpdateDriver` betrachtet sich dadurch
        // dauerhaft als "zeigt gerade ein Update", die App implementiert die
        // optionale `showUpdateInFocus()`-Methode nicht, wodurch ein späterer
        // manueller Check (`checkForUpdatesManually()`) auf diesen feststeckenden
        // Zustand trifft und wirkungslos verpufft - `state` bleibt dabei auf
        // `.checking` hängen, ohne dass je ein Driver-Callback feuert. Fix:
        // für einen automatischen Fund sofort `.dismiss` zurückgeben statt auf
        // eine Continuation zu warten - schließt Sparkles Update-Session für
        // diesen stillen Fund sauber ab (entspricht der Semantik des früher
        // entfernten `performSilentUpdateCheckIfNeeded()`: nur Badge, keine
        // hängende UI-Session), `currentRelease`/`hasUnseenUpdate` bleiben
        // gesetzt, damit das Badge weiterhin sichtbar ist. Ein späterer
        // manueller Check startet dadurch eine komplett frische Sparkle-
        // Session und zeigt das Sheet korrekt.
        guard updateState.userInitiated else {
            return .dismiss
        }
        self.state = .updateAvailable(info)
        return await withCheckedContinuation { continuation in
            pendingUpdateChoice = { choice in continuation.resume(returning: choice) }
        }
    }

    nonisolated func showDownloadInitiated(cancellation: @escaping () -> Void) {
        Task { @MainActor in
            self.pendingCancellation = cancellation
            self.state = .downloading(fractionCompleted: 0, downloadedBytes: 0, totalBytes: 0)
        }
    }

    nonisolated func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        Task { @MainActor in
            if case .downloading(_, let downloaded, _) = self.state {
                self.state = .downloading(fractionCompleted: 0, downloadedBytes: downloaded, totalBytes: Int64(expectedContentLength))
            }
        }
    }

    nonisolated func showDownloadDidReceiveData(ofLength length: UInt64) {
        Task { @MainActor in
            guard case .downloading(_, let downloaded, let total) = self.state else { return }
            let newDownloaded = downloaded + Int64(length)
            let fraction = total > 0 ? Double(newDownloaded) / Double(total) : 0
            self.state = .downloading(fractionCompleted: fraction, downloadedBytes: newDownloaded, totalBytes: total)
        }
    }

    nonisolated func showDownloadDidStartExtractingUpdate() {
        Task { @MainActor in self.state = .extracting(progress: 0) }
    }

    nonisolated func showExtractionReceivedProgress(_ progress: Double) {
        Task { @MainActor in self.state = .extracting(progress: progress) }
    }

    func showReadyToInstallAndRelaunch() async -> SPUUserUpdateChoice {
        state = .readyToInstall
        return await withCheckedContinuation { continuation in
            pendingInstallChoice = { choice in continuation.resume(returning: choice) }
        }
    }

    /// Fix (2026-08-02, live per Unified-Log verifiziert): Sparkles eigener
    /// `SPUStandardUserDriver` schließt sein Status-Fenster in genau diesem
    /// Callback synchron per direktem AppKit-Aufruf (`[_statusController close]`),
    /// bevor `applicationTerminated` erstmals `true` wird - nicht über eine
    /// deklarative Bindung. Grund: Ein rein state-gesteuertes SwiftUI-`.sheet`
    /// reagiert asynchron (unser bisheriger Code setzte `state` nur innerhalb
    /// eines `Task { @MainActor in ... }`), Sparkle schickt das Quit-AppleEvent
    /// aber ggf. bevor dieses Update tatsächlich das angehängte NSWindow-Sheet
    /// gelöst hat - AppKit verweigert dann die Terminierung mit "App termination
    /// blocked by modal sheet", die App hängt für immer bei "Wird installiert".
    /// Schließt deshalb bei `applicationTerminated == false` (dem Aufruf VOR dem
    /// eigentlichen Quit-Versuch) alle angehängten Sheets sofort und synchron
    /// über AppKit selbst, unabhängig von SwiftUIs Render-Zyklus.
    nonisolated func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        if !applicationTerminated {
            let closeAttachedSheets = {
                for window in NSApp.windows {
                    if let sheet = window.attachedSheet {
                        window.endSheet(sheet)
                    }
                }
            }
            if Thread.isMainThread {
                closeAttachedSheets()
            } else {
                DispatchQueue.main.sync(execute: closeAttachedSheets)
            }
        }
        Task { @MainActor in self.state = .installing }
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool) async {
        currentRelease = nil
        state = .idle
    }

    func showUpdaterError(_ error: any Error) async {
        state = .failed(error.localizedDescription)
    }

    func showUpdateNotFoundWithError(_ error: any Error) async {
        state = .upToDate
    }

    nonisolated func dismissUpdateInstallation() {
        Task { @MainActor in self.state = .idle }
    }

    /// Ebenfalls nicht im ursprünglichen Implementierungsvorschlag enthalten
    /// (siehe Kommentar bei `showUserInitiatedUpdateCheck` oben) - wird nur
    /// aufgerufen, wenn `appcastItem.releaseNotesURL` gesetzt ist (separater
    /// Download der Release-Notes statt eingebetteter `itemDescription`).
    /// Feedivo nutzt ausschließlich `itemDescription` (siehe
    /// `showUpdateFound(with:state:)` oben) - reiner No-Op-Stub für
    /// Protokollkonformität, keine UI zeigt separate Release-Notes-Downloads an.
    nonisolated func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    /// Pendant zu `showUpdateReleaseNotes(with:)` oben - ebenfalls No-Op, da
    /// Feedivo nie separat heruntergeladene Release-Notes anzeigt.
    nonisolated func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}
}
