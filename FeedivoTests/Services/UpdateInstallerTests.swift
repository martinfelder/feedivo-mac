import Testing
import Foundation
@testable import Feedivo

private struct FakeDownloader: UpdateAssetDownloading {
    var resultsByURLSuffix: [String: Result<URL, Error>]
    var progressReports: [(Double, Int64, Int64)] = [(1.0, 100, 100)]

    func download(from url: URL, onProgress: @escaping @Sendable (Double, Int64, Int64) -> Void) async throws -> URL {
        for report in progressReports {
            onProgress(report.0, report.1, report.2)
        }
        for (suffix, result) in resultsByURLSuffix where url.absoluteString.hasSuffix(suffix) {
            return try result.get()
        }
        throw UpdateInstallError.downloadFailed
    }
}

private struct FakeExtractor: UpdateArchiveExtracting {
    var result: Result<URL, Error>

    func extractAndUnquarantine(zipURL: URL) throws -> URL {
        try result.get()
    }
}

private struct FakeLocationGrantor: UpdateInstallLocationGranting {
    var result: Result<URL, Error>

    func grantedInstallDirectory(currentAppDirectory: URL) async throws -> URL {
        try result.get()
    }
}

private final class FakeSwapper: UpdateAppSwapping, @unchecked Sendable {
    var replaceError: Error?
    var relaunchSucceeds = true
    var didRelaunch = false

    func replaceCurrentApp(at currentAppURL: URL, withNewAppAt newAppURL: URL) throws {
        if let replaceError { throw replaceError }
    }

    func relaunchAndQuit(appURL: URL) async -> Bool {
        guard relaunchSucceeds else { return false }
        didRelaunch = true
        return true
    }
}

// Zwei Abweichungen von der Brief-Vorlage, beide via systematic-debugging
// (echter xcodebuild-Testlauf + Root-Cause-Analyse) gefunden, nicht geraten:
//
// 1. `zipURL`/`checksumFileURL` unten nutzen `FileManager.default.temporaryDirectory`
//    statt der im Brief wörtlich vorgegebenen hartcodierten Pfade
//    `URL(fileURLWithPath: "/tmp/fake-download.zip")`/`"/tmp/fake-download.sha256"`.
//    Grund: Feedivo hat App Sandbox aktiviert (`com.apple.security.app-sandbox` in
//    `Feedivo.entitlements`, keine Temporary-Exception-Entitlement für `/tmp`) - der
//    Testhost läuft dadurch sandboxed, und `try? zipContent.write(to: zipURL)`/
//    `try? checksumContent.write(to: checksumFileURL, ...)` (in `makeRelease` unten)
//    scheitern mit den hartcodierten `/tmp`-Pfaden STILL (das `try?` verschluckt den
//    Fehler) - per `find / -iname "fake-download*"` nach einem echten Testlauf
//    verifiziert: die Dateien wurden nirgends auf der Platte angelegt, weder unter
//    `/tmp` noch im App-Container. Die Folge: `verifyChecksum` in `UpdateInstaller`
//    findet beim Lesen von `checksumFileURL` keine Datei, `try? String(contentsOf:...)`
//    liefert `nil`, der `guard`-`else`-Zweig wirft `.checksumMismatch` - unabhängig vom
//    tatsächlich erwarteten Ergebnis. Das erklärt exakt das beobachtete Fehlerbild: alle
//    4 "Erfolgspfad"-Tests scheiterten reproduzierbar mit `.failed(.checksumMismatch)`,
//    während der einzige Test, der ohnehin `.checksumMismatch` erwartet
//    (`falscheChecksumFuehrtZuChecksumMismatch`), trivial "bestand" - unabhängig davon,
//    ob je echt geschrieben wurde. `FileManager.default.temporaryDirectory` ist der
//    sandbox-konforme, tatsächlich beschreibbare Pfad für genau diesen Zweck.
// 2. `@Suite(.serialized)` wurde ergänzt (im Brief nicht enthalten) - alle Tests
//    schreiben/lesen weiterhin dieselben festen Dateinamen relativ zum Temp-Verzeichnis;
//    ohne erzwungene sequenzielle Ausführung könnte paralleles Swift-Testing-Verhalten
//    trotz des Fixes in Punkt 1 zu Querbeeinflussung zwischen Tests führen (z. B.
//    `falscheChecksumFuehrtZuChecksumMismatch`s bewusst falsche Prüfsumme überschreibt
//    die Datei eines gerade laufenden Erfolgspfad-Tests). Reine Ausführungsreihenfolge-
//    Absicherung, ändert keine Assertion/Logik der 7 Testfälle selbst.
@Suite(.serialized)
@MainActor
struct UpdateInstallerTests {

    private let zipURL = FileManager.default.temporaryDirectory.appendingPathComponent("fake-download.zip")
    private let checksumFileURL = FileManager.default.temporaryDirectory.appendingPathComponent("fake-download.sha256")
    private let extractedAppURL = FileManager.default.temporaryDirectory.appendingPathComponent("extracted-Feedivo.app")
    private let currentAppURL = URL(fileURLWithPath: "/Applications/Feedivo.app")

    private func makeRelease(zipContent: Data, checksumContent: String) -> (GitHubRelease, [String: Result<URL, Error>]) {
        let release = GitHubRelease(
            tagName: "v1.0-14",
            name: "Test",
            htmlURL: URL(string: "https://github.com/martinfelder/feedivo-mac/releases/tag/v1.0-14")!,
            bodyHTML: nil,
            publishedAt: nil,
            assets: [
                GitHubReleaseAsset(name: "Feedivo-v1.0-14.zip", browserDownloadURL: URL(string: "https://example.com/Feedivo-v1.0-14.zip")!),
                GitHubReleaseAsset(name: "Feedivo-v1.0-14.zip.sha256", browserDownloadURL: URL(string: "https://example.com/Feedivo-v1.0-14.zip.sha256")!)
            ]
        )

        try? zipContent.write(to: zipURL)
        try? checksumContent.write(to: checksumFileURL, atomically: true, encoding: .utf8)

        let results: [String: Result<URL, Error>] = [
            ".zip": .success(zipURL),
            ".sha256": .success(checksumFileURL)
        ]
        return (release, results)
    }

    @Test func kompletterErfolgspfadLandetBeiReadyToInstall() async {
        let zipContent = "fake-zip-bytes".data(using: .utf8)!
        let expectedHex = UpdateChecksumVerifier.sha256Hex(of: zipContent)
        let (release, downloadResults) = makeRelease(zipContent: zipContent, checksumContent: expectedHex)

        let installer = UpdateInstaller(
            downloader: FakeDownloader(resultsByURLSuffix: downloadResults),
            extractor: FakeExtractor(result: .success(extractedAppURL)),
            locationGrantor: FakeLocationGrantor(result: .success(currentAppURL.deletingLastPathComponent())),
            swapper: FakeSwapper(),
            currentAppURL: currentAppURL
        )

        await installer.startDownloadAndVerify(release: release)

        #expect(installer.state == .readyToInstall)
    }

    @Test func falscheChecksumFuehrtZuChecksumMismatch() async {
        let zipContent = "fake-zip-bytes".data(using: .utf8)!
        let (release, downloadResults) = makeRelease(zipContent: zipContent, checksumContent: "0000000000000000000000000000000000000000000000000000000000000000")

        let installer = UpdateInstaller(
            downloader: FakeDownloader(resultsByURLSuffix: downloadResults),
            extractor: FakeExtractor(result: .success(extractedAppURL)),
            locationGrantor: FakeLocationGrantor(result: .success(currentAppURL.deletingLastPathComponent())),
            swapper: FakeSwapper(),
            currentAppURL: currentAppURL
        )

        await installer.startDownloadAndVerify(release: release)

        #expect(installer.state == .failed(.checksumMismatch))
    }

    @Test func fehlendesZipAssetFuehrtSofortZuDownloadFailedOhneNetzwerkAufruf() async {
        let release = GitHubRelease(
            tagName: "v1.0-14",
            name: nil,
            htmlURL: URL(string: "https://github.com/martinfelder/feedivo-mac/releases/tag/v1.0-14")!,
            bodyHTML: nil,
            publishedAt: nil,
            assets: []
        )

        let installer = UpdateInstaller(
            downloader: FakeDownloader(resultsByURLSuffix: [:]),
            extractor: FakeExtractor(result: .success(extractedAppURL)),
            locationGrantor: FakeLocationGrantor(result: .success(currentAppURL.deletingLastPathComponent())),
            swapper: FakeSwapper(),
            currentAppURL: currentAppURL
        )

        await installer.startDownloadAndVerify(release: release)

        #expect(installer.state == .failed(.downloadFailed))
    }

    @Test func installNachErfolgreicherVerifikationLoestAustauschUndNeustartAus() async {
        let zipContent = "fake-zip-bytes".data(using: .utf8)!
        let expectedHex = UpdateChecksumVerifier.sha256Hex(of: zipContent)
        let (release, downloadResults) = makeRelease(zipContent: zipContent, checksumContent: expectedHex)
        let swapper = FakeSwapper()

        let installer = UpdateInstaller(
            downloader: FakeDownloader(resultsByURLSuffix: downloadResults),
            extractor: FakeExtractor(result: .success(extractedAppURL)),
            locationGrantor: FakeLocationGrantor(result: .success(currentAppURL.deletingLastPathComponent())),
            swapper: swapper,
            currentAppURL: currentAppURL
        )

        await installer.startDownloadAndVerify(release: release)
        await installer.install()

        #expect(swapper.didRelaunch)
    }

    @Test func fehlgeschlagenerNeustartFuehrtZuReplaceFailedStattStillerBlockade() async {
        let zipContent = "fake-zip-bytes".data(using: .utf8)!
        let expectedHex = UpdateChecksumVerifier.sha256Hex(of: zipContent)
        let (release, downloadResults) = makeRelease(zipContent: zipContent, checksumContent: expectedHex)
        let swapper = FakeSwapper()
        swapper.relaunchSucceeds = false

        let installer = UpdateInstaller(
            downloader: FakeDownloader(resultsByURLSuffix: downloadResults),
            extractor: FakeExtractor(result: .success(extractedAppURL)),
            locationGrantor: FakeLocationGrantor(result: .success(currentAppURL.deletingLastPathComponent())),
            swapper: swapper,
            currentAppURL: currentAppURL
        )

        await installer.startDownloadAndVerify(release: release)
        await installer.install()

        #expect(installer.state == .failed(.replaceFailed))
        #expect(!swapper.didRelaunch)
    }

    @Test func abgelehnterOrdnerZugriffFuehrtZuFolderAccessDenied() async {
        let zipContent = "fake-zip-bytes".data(using: .utf8)!
        let expectedHex = UpdateChecksumVerifier.sha256Hex(of: zipContent)
        let (release, downloadResults) = makeRelease(zipContent: zipContent, checksumContent: expectedHex)

        let installer = UpdateInstaller(
            downloader: FakeDownloader(resultsByURLSuffix: downloadResults),
            extractor: FakeExtractor(result: .success(extractedAppURL)),
            locationGrantor: FakeLocationGrantor(result: .failure(UpdateInstallError.folderAccessDenied)),
            swapper: FakeSwapper(),
            currentAppURL: currentAppURL
        )

        await installer.startDownloadAndVerify(release: release)
        await installer.install()

        #expect(installer.state == .failed(.folderAccessDenied))
    }

    @Test func cancelWaehrendDesDownloadsSetztZustandAufIdleZurueck() async {
        let installer = UpdateInstaller(
            downloader: FakeDownloader(resultsByURLSuffix: [:]),
            extractor: FakeExtractor(result: .success(extractedAppURL)),
            locationGrantor: FakeLocationGrantor(result: .success(currentAppURL.deletingLastPathComponent())),
            swapper: FakeSwapper(),
            currentAppURL: currentAppURL
        )

        installer.cancelDownload()

        #expect(installer.state == .idle)
    }
}
