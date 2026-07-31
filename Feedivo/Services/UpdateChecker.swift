import Foundation

/// Ergebnis eines vollständigen Update-Checks (Netzwerk + Versionsvergleich),
/// als flaches Enum statt als throws — Aufrufer (App-Menü, Settings-Tab)
/// wollen für JEDEN Fall (Update da / aktuell / Fehler) eine sichtbare
/// Reaktion zeigen, kein einfaches "still fehlgeschlagen" per throw.
enum UpdateCheckOutcome: Equatable {
    case updateAvailable(GitHubRelease)
    // Führt das zuletzt auf GitHub gefundene Release mit - nil nur, wenn die
    // Release-Liste komplett leer war. Aufrufer zeigen damit im "Kein
    // Update"-Dialog zusätzlich zur installierten Version auch die aktuell
    // auf GitHub verfügbare Version an.
    case upToDate(latestKnownRelease: GitHubRelease?)
    case failed(String)
}

/// Stateless - hält keinen UI-Zustand, kann von mehreren unabhängigen
/// Aufrufstellen (App-Menü, Settings-Tab "Über") gleichzeitig verwendet
/// werden, ohne dass sich deren Präsentationszustand überschneidet.
struct UpdateChecker {
    private let releaseFetching: GitHubReleaseFetching

    init(releaseFetching: GitHubReleaseFetching = GitHubReleaseCheckService()) {
        self.releaseFetching = releaseFetching
    }

    func check(currentMarketingVersion: String, currentBuildNumber: Int) async -> UpdateCheckOutcome {
        do {
            let releases = try await releaseFetching.fetchReleases()
            guard let latest = releases.first else {
                return .upToDate(latestKnownRelease: nil)
            }

            switch UpdateVersionComparator.compare(
                latestRelease: latest,
                currentMarketingVersion: currentMarketingVersion,
                currentBuildNumber: currentBuildNumber
            ) {
            case .updateAvailable(let release):
                return .updateAvailable(release)
            case .upToDate, .unknown:
                return .upToDate(latestKnownRelease: latest)
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
