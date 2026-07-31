import Foundation
import Testing
@testable import Feedivo

struct UpdateVersionComparatorTests {

    @Test func parseTagLiestMarketingVersionUndBuildNummer() {
        let parsed = UpdateVersionComparator.parseTag("v1.0-11")

        #expect(parsed?.marketingVersion == "1.0")
        #expect(parsed?.buildNumber == 11)
    }

    @Test func parseTagLiefertNilBeiFehlendemVPraefix() {
        #expect(UpdateVersionComparator.parseTag("1.0-11") == nil)
    }

    @Test func parseTagLiefertNilBeiNichtNumerischerBuildNummer() {
        #expect(UpdateVersionComparator.parseTag("v1.0-elf") == nil)
    }

    @Test func parseTagLiefertNilOhneBindestrich() {
        #expect(UpdateVersionComparator.parseTag("v1.0") == nil)
    }

    private func makeRelease(tag: String) -> GitHubRelease {
        GitHubRelease(
            tagName: tag,
            name: "Test Release",
            htmlURL: URL(string: "https://github.com/martinfelder/feedivo-mac/releases/tag/\(tag)")!,
            bodyHTML: "<p>Notes</p>",
            publishedAt: nil
        )
    }

    @Test func compareErkenntNeuerenBuildBeiGleicherMarketingVersion() {
        let result = UpdateVersionComparator.compare(
            latestRelease: makeRelease(tag: "v1.0-12"),
            currentMarketingVersion: "1.0",
            currentBuildNumber: 11
        )

        #expect(result == .updateAvailable(makeRelease(tag: "v1.0-12")))
    }

    @Test func compareErkenntGleichenBuildAlsAktuell() {
        let result = UpdateVersionComparator.compare(
            latestRelease: makeRelease(tag: "v1.0-11"),
            currentMarketingVersion: "1.0",
            currentBuildNumber: 11
        )

        #expect(result == .upToDate)
    }

    @Test func compareErkenntAelterenBuildAlsAktuell() {
        let result = UpdateVersionComparator.compare(
            latestRelease: makeRelease(tag: "v1.0-9"),
            currentMarketingVersion: "1.0",
            currentBuildNumber: 11
        )

        #expect(result == .upToDate)
    }

    @Test func compareErkenntMarketingVersionSprungUnabhaengigVomBuild() {
        let result = UpdateVersionComparator.compare(
            latestRelease: makeRelease(tag: "v1.1-1"),
            currentMarketingVersion: "1.0",
            currentBuildNumber: 999
        )

        #expect(result == .updateAvailable(makeRelease(tag: "v1.1-1")))
    }

    @Test func compareLiefertUnknownBeiKaputtemTag() {
        let result = UpdateVersionComparator.compare(
            latestRelease: makeRelease(tag: "nightly-build"),
            currentMarketingVersion: "1.0",
            currentBuildNumber: 11
        )

        #expect(result == .unknown)
    }
}
