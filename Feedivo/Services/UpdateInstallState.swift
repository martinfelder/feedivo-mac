import Foundation

/// Zustand des In-App-Update-Installationsvorgangs, siehe `UpdateInstaller`.
enum UpdateInstallState: Equatable {
    case idle
    case downloading(fractionCompleted: Double, downloadedBytes: Int64, totalBytes: Int64)
    case verifying
    case readyToInstall
    case installing
    case failed(UpdateInstallError)
}

enum UpdateInstallError: Equatable, LocalizedError {
    case downloadFailed
    case checksumMismatch
    case unzipFailed
    case folderAccessDenied
    case replaceFailed
    case relaunchFailed

    var errorDescription: String? {
        switch self {
        case .downloadFailed:
            String(localized: "updateInstall.error.downloadFailed")
        case .checksumMismatch:
            String(localized: "updateInstall.error.checksumMismatch")
        case .unzipFailed:
            String(localized: "updateInstall.error.unzipFailed")
        case .folderAccessDenied:
            String(localized: "updateInstall.error.folderAccessDenied")
        case .replaceFailed:
            String(localized: "updateInstall.error.replaceFailed")
        case .relaunchFailed:
            String(localized: "updateInstall.error.relaunchFailed")
        }
    }

    /// `true`: "Erneut versuchen" muss den kompletten Download neu starten.
    /// `false`: Download/Verifikation/Entpacken waren bereits erfolgreich - "Erneut
    /// versuchen" wiederholt nur den Installationsschritt (Ordnerzugriff + Austausch).
    var requiresFullRedownload: Bool {
        switch self {
        case .downloadFailed, .checksumMismatch, .unzipFailed:
            true
        case .folderAccessDenied, .replaceFailed, .relaunchFailed:
            false
        }
    }
}
