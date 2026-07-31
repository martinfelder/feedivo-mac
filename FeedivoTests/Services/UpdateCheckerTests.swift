import Testing
import Foundation
@testable import Feedivo

private struct FakeReleaseFetcher: GitHubReleaseFetching {
    let releases: [GitHubRelease]
    let error: Error?

    func fetchReleases() async throws -> [GitHubRelease] {
        if let error {
            throw error
        }
        return releases
    }
}

struct UpdateCheckerTests {

    private func makeRelease(tag: String) -> GitHubRelease {
        GitHubRelease(
            tagName: tag,
            name: "Test",
            htmlURL: URL(string: "https://github.com/martinfelder/feedivo-mac/releases/tag/\(tag)")!,
            bodyHTML: "<p>Notes</p>",
            publishedAt: nil
        )
    }

    @Test func checkLiefertUpdateAvailableBeiNeuerReleaseListe() async {
        let fetcher = FakeReleaseFetcher(releases: [makeRelease(tag: "v1.0-12")], error: nil)
        let checker = UpdateChecker(releaseFetching: fetcher)

        let outcome = await checker.check(currentMarketingVersion: "1.0", currentBuildNumber: 11)

        #expect(outcome == .updateAvailable(makeRelease(tag: "v1.0-12")))
    }

    @Test func checkLiefertUpToDateBeiGleicherVersion() async {
        let fetcher = FakeReleaseFetcher(releases: [makeRelease(tag: "v1.0-11")], error: nil)
        let checker = UpdateChecker(releaseFetching: fetcher)

        let outcome = await checker.check(currentMarketingVersion: "1.0", currentBuildNumber: 11)

        #expect(outcome == .upToDate(latestKnownRelease: makeRelease(tag: "v1.0-11")))
    }

    @Test func checkLiefertUpToDateBeiLeererReleaseListe() async {
        let fetcher = FakeReleaseFetcher(releases: [], error: nil)
        let checker = UpdateChecker(releaseFetching: fetcher)

        let outcome = await checker.check(currentMarketingVersion: "1.0", currentBuildNumber: 11)

        #expect(outcome == .upToDate(latestKnownRelease: nil))
    }

    @Test func checkLiefertUpToDateBeiUnknownVergleichsergebnis() async {
        let fetcher = FakeReleaseFetcher(releases: [makeRelease(tag: "nightly")], error: nil)
        let checker = UpdateChecker(releaseFetching: fetcher)

        let outcome = await checker.check(currentMarketingVersion: "1.0", currentBuildNumber: 11)

        #expect(outcome == .upToDate(latestKnownRelease: makeRelease(tag: "nightly")))
    }

    @Test func checkLiefertFailedBeiFehlerImFetcher() async {
        let fetcher = FakeReleaseFetcher(releases: [], error: GitHubReleaseCheckError.httpError(statusCode: 403))
        let checker = UpdateChecker(releaseFetching: fetcher)

        let outcome = await checker.check(currentMarketingVersion: "1.0", currentBuildNumber: 11)

        guard case .failed(let message) = outcome else {
            Issue.record("Erwartete .failed, bekam \(outcome)")
            return
        }
        #expect(!message.isEmpty)
    }
}
