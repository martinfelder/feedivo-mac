import Foundation

/// Ergebnis eines Versionsvergleichs gegen ein GitHub-Release.
enum UpdateCheckResult: Equatable {
    case upToDate
    case updateAvailable(GitHubRelease)
    /// Tag entspricht nicht dem erwarteten Schema `v{Version}-{Build}` — kein
    /// verlässlicher Vergleich möglich, wird von Aufrufern konservativ wie
    /// "kein Update" behandelt (keine Falsch-Meldung).
    case unknown
}

/// Vergleicht ein GitHub-Release-Tag (Format `v{MARKETING_VERSION}-{BUILD_NUMBER}`,
/// siehe scripts/create_github_release.sh) gegen die laufende App-Version.
enum UpdateVersionComparator {
    static func compare(
        latestRelease: GitHubRelease,
        currentMarketingVersion: String,
        currentBuildNumber: Int
    ) -> UpdateCheckResult {
        guard let parsed = parseTag(latestRelease.tagName) else {
            return .unknown
        }

        let latestComponents = versionComponents(parsed.marketingVersion)
        let currentComponents = versionComponents(currentMarketingVersion)

        if isVersion(latestComponents, greaterThan: currentComponents) {
            return .updateAvailable(latestRelease)
        }
        if isVersion(currentComponents, greaterThan: latestComponents) {
            return .upToDate
        }
        // Gleiche Marketing-Version -> Build-Nummer entscheidet als Tiebreaker.
        return parsed.buildNumber > currentBuildNumber
            ? .updateAvailable(latestRelease)
            : .upToDate
    }

    /// Zerlegt z. B. "v1.0-11" in ("1.0", 11). Liefert nil bei jeder Abweichung
    /// vom erwarteten Schema (fehlendes "v", fehlender Bindestrich, nicht-
    /// numerische Build-Nummer, leere Marketing-Version).
    static func parseTag(_ tagName: String) -> (marketingVersion: String, buildNumber: Int)? {
        guard tagName.hasPrefix("v") else { return nil }
        let withoutPrefix = tagName.dropFirst()

        guard let lastDashIndex = withoutPrefix.lastIndex(of: "-") else { return nil }

        let marketingVersion = String(withoutPrefix[withoutPrefix.startIndex..<lastDashIndex])
        let buildNumberString = String(withoutPrefix[withoutPrefix.index(after: lastDashIndex)...])

        guard !marketingVersion.isEmpty, let buildNumber = Int(buildNumberString) else {
            return nil
        }

        return (marketingVersion, buildNumber)
    }

    private static func versionComponents(_ version: String) -> [Int] {
        version.split(separator: ".").compactMap { Int($0) }
    }

    /// Komponentenweiser Vergleich, fehlende Komponenten zählen als 0
    /// (z. B. "1.0" vs. "1.0.1").
    private static func isVersion(_ lhs: [Int], greaterThan rhs: [Int]) -> Bool {
        let maxCount = max(lhs.count, rhs.count)
        for index in 0..<maxCount {
            let lhsComponent = index < lhs.count ? lhs[index] : 0
            let rhsComponent = index < rhs.count ? rhs[index] : 0
            if lhsComponent != rhsComponent {
                return lhsComponent > rhsComponent
            }
        }
        return false
    }
}
