import Foundation
import Observation
import Sparkle
import OSLog

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
    let isHomebrewInstall: Bool

    private var updater: SPUUpdater?
    private var pendingUpdateChoice: ((SPUUserUpdateChoice) -> Void)?
    private var pendingInstallChoice: ((SPUUserUpdateChoice) -> Void)?
    private var pendingCancellation: (() -> Void)?

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

    func installUpdate() {
        pendingInstallChoice?(.install)
        pendingInstallChoice = nil
    }

    func cancelDownload() {
        pendingCancellation?()
        pendingCancellation = nil
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
        let info = SparkleReleaseInfo(
            tagName: appcastItem.displayVersionString,
            name: appcastItem.title,
            htmlURL: appcastItem.infoURL ?? URL(string: "https://github.com/martinfelder/feedivo-mac/releases")!,
            bodyHTML: appcastItem.itemDescription
        )
        self.state = .updateAvailable(info)
        hasUnseenUpdate = true
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

    nonisolated func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        Task { @MainActor in self.state = .installing }
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool) async {
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
