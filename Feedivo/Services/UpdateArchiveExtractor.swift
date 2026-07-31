import Foundation

protocol UpdateArchiveExtracting: Sendable {
    /// Entpackt die ZIP-Datei in ein neues temporäres Verzeichnis, entfernt das
    /// Quarantäne-Flag von der enthaltenen .app und liefert deren URL zurück.
    /// `nonisolated` + `async`, damit `ditto`/`xattr` (Process.waitUntilExit blockiert)
    /// nicht synchron auf dem MainActor laufen (Whole-Branch-Review-Fund).
    nonisolated func extractAndUnquarantine(zipURL: URL) async throws -> URL
}

/// Nutzt `ditto` (dasselbe Tool, mit dem `scripts/create_github_release.sh` die ZIP
/// packt) zum Entpacken sowie `xattr` zum Entfernen des macOS-Quarantäne-Flags. Die
/// Quarantäne-Entfernung ist bewusst Teil dieses Schritts, nicht optional: die ZIP wurde
/// zuvor bereits per SHA256 gegen eine vom eigenen, privaten Release-Prozess
/// veröffentlichte Prüfsumme verifiziert (siehe UpdateInstaller) - das ist der
/// Vertrauensanker, der die Quarantäne-Entfernung rechtfertigt.
struct DittoUpdateArchiveExtractor: UpdateArchiveExtracting {
    nonisolated func extractAndUnquarantine(zipURL: URL) async throws -> URL {
        let destinationDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        try run("/usr/bin/ditto", arguments: ["-x", "-k", zipURL.path, destinationDirectory.path])

        let contents = try FileManager.default.contentsOfDirectory(at: destinationDirectory, includingPropertiesForKeys: nil)
        guard let appURL = contents.first(where: { $0.pathExtension == "app" }) else {
            throw UpdateInstallError.unzipFailed
        }

        try run("/usr/bin/xattr", arguments: ["-dr", "com.apple.quarantine", appURL.path])

        return appURL
    }

    nonisolated private func run(_ executablePath: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateInstallError.unzipFailed
        }
    }
}
