import Foundation
import Observation

/// Orchestriert Download -> Verifikation -> Entpacken -> Installation eines
/// GitHub-Releases. Alle I/O-Grenzen sind injizierbare Protokolle (siehe
/// UpdateAssetDownloading/UpdateArchiveExtracting/UpdateInstallLocationGranting/
/// UpdateAppSwapping) - macht die komplette Sequenzierungslogik hier ohne echtes
/// Netzwerk/Dateisystem/GUI testbar (siehe UpdateInstallerTests).
@Observable
@MainActor
final class UpdateInstaller {
    private(set) var state: UpdateInstallState = .idle

    private let downloader: UpdateAssetDownloading
    private let extractor: UpdateArchiveExtracting
    private let locationGrantor: UpdateInstallLocationGranting
    private let swapper: UpdateAppSwapping
    private let currentAppURL: URL

    private var extractedAppURL: URL?

    // Ersetzt ein vorheriges, geteiltes isCancelled-Bool: ein einzelnes Bool konnte von
    // einem zweiten startDownloadAndVerify-Aufruf zurückgesetzt werden, während der
    // ERSTE (eigentlich schon abgebrochene) Aufruf noch lief - seine guard-Checks gegen
    // das dann bereits wieder auf false stehende Flag hätten fälschlich "nicht
    // abgebrochen" ergeben und den State des zweiten, echten Versuchs überschrieben
    // (Whole-Branch-Review-Fund). Jeder Aufruf erhöht den Zähler und merkt sich seine
    // eigene Generation lokal - nur die zuletzt gestartete Generation darf noch state setzen.
    private var currentGeneration = 0

    // Hinweis zur Abweichung von der Brief-Vorlage: Die Standardwerte für
    // `downloader`/`extractor`/`locationGrantor`/`swapper` sind hier `nil` statt direkt
    // die konkreten Typen - ein echter, reproduzierbarer Build-Fehler (siehe
    // task-9-report.md), da `SecurityScopedInstallLocationGrantor` explizit
    // `@MainActor` ist: Swift wertet Default-Parameter-Ausdrücke NICHT in der
    // Isolation der umschließenden Funktion aus (auch wenn `UpdateInstaller` selbst
    // `@MainActor` ist), sondern in einem eigenen, synchronen, nicht-isolierten
    // Kontext - "call to main actor-isolated initializer 'init()' in a synchronous
    // nonisolated context". Die Instanziierung stattdessen in den Initializer-Body zu
    // verlegen (der wegen der Klassen-Isolation tatsächlich auf dem MainActor läuft)
    // behebt das, ohne das Aufrufverhalten für Produktivcode oder Tests zu ändern -
    // alle Tests in UpdateInstallerTests.swift übergeben ohnehin jeden Parameter
    // explizit und nutzen diese Defaults nie.
    init(
        downloader: UpdateAssetDownloading? = nil,
        extractor: UpdateArchiveExtracting? = nil,
        locationGrantor: UpdateInstallLocationGranting? = nil,
        swapper: UpdateAppSwapping? = nil,
        currentAppURL: URL = Bundle.main.bundleURL
    ) {
        self.downloader = downloader ?? URLSessionUpdateAssetDownloader()
        self.extractor = extractor ?? DittoUpdateArchiveExtractor()
        self.locationGrantor = locationGrantor ?? SecurityScopedInstallLocationGrantor()
        self.swapper = swapper ?? FileManagerUpdateAppSwapper()
        self.currentAppURL = currentAppURL
    }

    func startDownloadAndVerify(release: GitHubRelease) async {
        currentGeneration += 1
        let myGeneration = currentGeneration
        extractedAppURL = nil

        guard let zipAsset = GitHubReleaseAsset.zipAsset(in: release.assets) else {
            state = .failed(.downloadFailed)
            return
        }

        state = .downloading(fractionCompleted: 0, downloadedBytes: 0, totalBytes: 0)

        do {
            let zipURL = try await downloader.download(from: zipAsset.browserDownloadURL) { [weak self] fraction, downloaded, total in
                guard let self else { return }
                Task { @MainActor in
                    guard myGeneration == self.currentGeneration else { return }
                    self.state = .downloading(fractionCompleted: fraction, downloadedBytes: downloaded, totalBytes: total)
                }
            }
            guard myGeneration == currentGeneration else { return }

            state = .verifying
            try await verifyChecksum(zipURL: zipURL, release: release)
            guard myGeneration == currentGeneration else { return }

            let appURL = try await extractor.extractAndUnquarantine(zipURL: zipURL)
            guard myGeneration == currentGeneration else { return }

            extractedAppURL = appURL
            state = .readyToInstall
        } catch let error as UpdateInstallError {
            guard myGeneration == currentGeneration else { return }
            state = .failed(error)
        } catch {
            guard myGeneration == currentGeneration else { return }
            state = .failed(.downloadFailed)
        }
    }

    func cancelDownload() {
        currentGeneration += 1
        state = .idle
    }

    func install() async {
        guard let extractedAppURL else { return }
        state = .installing

        do {
            _ = try await locationGrantor.grantedInstallDirectory(
                currentAppDirectory: currentAppURL.deletingLastPathComponent()
            )
            try await swapper.replaceCurrentApp(at: currentAppURL, withNewAppAt: extractedAppURL)
            // Der Austausch ist ab hier bereits erfolgreich abgeschlossen - extractedAppURL
            // zeigt auf einen jetzt nicht mehr existierenden Pfad (replaceItemAt verschiebt
            // die Quelle). Löschen, damit ein erneuter install()-Versuch nach einem
            // fehlgeschlagenen Neustart NICHT nochmal versucht, dieselbe (verschwundene)
            // Datei zu verschieben (Whole-Branch-Review-Fund: sonst endlose .replaceFailed-
            // Schleife trotz bereits erfolgreich installierter neuer Version).
            self.extractedAppURL = nil

            let relaunched = await swapper.relaunchAndQuit(appURL: currentAppURL)
            if !relaunched {
                state = .failed(.relaunchFailed)
            }
        } catch let error as UpdateInstallError {
            state = .failed(error)
        } catch {
            state = .failed(.replaceFailed)
        }
    }

    private func verifyChecksum(zipURL: URL, release: GitHubRelease) async throws {
        guard let checksumAsset = GitHubReleaseAsset.checksumAsset(in: release.assets) else {
            throw UpdateInstallError.checksumMismatch
        }

        let checksumFileURL = try await downloader.download(from: checksumAsset.browserDownloadURL) { _, _, _ in }
        guard let expectedHex = try? String(contentsOf: checksumFileURL, encoding: .utf8) else {
            throw UpdateInstallError.checksumMismatch
        }

        let computedHex = try await computeChecksum(zipURL: zipURL)

        guard UpdateChecksumVerifier.matches(computedHex: computedHex, expectedHex: expectedHex) else {
            throw UpdateInstallError.checksumMismatch
        }
    }

    // @concurrent + async, damit das Lesen der kompletten ZIP-Datei plus SHA256-Hashing
    // (potenziell mehrere MB) NICHT synchron auf dem MainActor läuft und die UI währenddessen
    // einfriert (Whole-Branch-Review-Fund, siehe auch den bereits bestehenden CLAUDE.md-
    // Gotcha zur Spotlight-Backfill-Funktion: Task.detached allein reicht dafür nicht,
    // die Funktion selbst muss echt vom MainActor wegspringen). Reines `nonisolated` reicht
    // dafür NICHT: bei aktivem `SWIFT_APPROACHABLE_CONCURRENCY`
    // (`NonisolatedNonsendingByDefault`) läuft eine `nonisolated async`-Funktion weiterhin
    // auf dem Actor des Aufrufers - `@concurrent` erzwingt den tatsächlichen Wechsel.
    @concurrent private func computeChecksum(zipURL: URL) async throws -> String {
        let zipData = try Data(contentsOf: zipURL)
        return UpdateChecksumVerifier.sha256Hex(of: zipData)
    }
}
