import Foundation

/// Erkennt, ob die laufende App-Instanz aus einem Homebrew-Cask-verwalteten
/// Caskroom-Pfad heraus läuft (statt z. B. aus /Applications, nach ZIP-Download
/// per Hand entpackt). Steuert, ob Sparkles Update-Check aktiv ist -
/// Homebrew-Installationen aktualisieren ausschließlich über `brew upgrade`,
/// siehe SparkleUpdateCoordinator.
enum HomebrewInstallationDetector {
    static func isHomebrewCaskInstall(bundleURL: URL) -> Bool {
        let pathComponents = bundleURL.standardizedFileURL.pathComponents
        return pathComponents.contains("Caskroom")
    }
}
