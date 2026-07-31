import Foundation

/// Liest die aktuell laufende App-Version aus dem Bundle — dieselben Felder,
/// die `scripts/create_github_release.sh` zum Bauen des Release-Tags
/// (`v{MARKETING_VERSION}-{BUILD_NUMBER}`) verwendet.
enum AppVersionInfo {
    static var marketingVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    static var buildNumber: Int {
        let raw = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return Int(raw) ?? 0
    }
}
