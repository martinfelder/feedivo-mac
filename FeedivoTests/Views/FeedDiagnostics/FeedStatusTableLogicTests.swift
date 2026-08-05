import Foundation
import Testing
@testable import Feedivo

struct FeedStatusTableLogicTests {
    private func diagnostic(
        feedID: String = "feed-1",
        feedTitle: String,
        feedURL: String = "https://example.com/feed",
        consecutiveFailureCount: Int = 1
    ) -> FeedFailureDiagnostic {
        FeedFailureDiagnostic(
            feedID: feedID,
            feedTitle: feedTitle,
            feedURL: feedURL,
            feedWebsiteURL: nil,
            feedFaviconURL: nil,
            lastAttemptAt: Date(timeIntervalSince1970: 1_000),
            errorMessage: "Fehler",
            httpStatusCode: nil,
            consecutiveFailureCount: consecutiveFailureCount
        )
    }

    @Test func filteredLiefertAlleBeiLeeremSuchtext() {
        let diagnostics = [diagnostic(feedTitle: "GoogleWatchBlog"), diagnostic(feedTitle: "Android Police")]

        let result = FeedStatusTableLogic.filtered(diagnostics, matching: "")

        #expect(result.count == 2)
    }

    @Test func filteredFindetTitelTreffer() {
        let diagnostics = [diagnostic(feedTitle: "GoogleWatchBlog"), diagnostic(feedTitle: "Android Police")]

        let result = FeedStatusTableLogic.filtered(diagnostics, matching: "google")

        #expect(result.map(\.feedTitle) == ["GoogleWatchBlog"])
    }

    @Test func filteredFindetURLTreffer() {
        let diagnostics = [
            diagnostic(feedTitle: "GoogleWatchBlog", feedURL: "https://googlewatchblog.de/feed"),
            diagnostic(feedTitle: "Android Police", feedURL: "https://androidpolice.com/feed")
        ]

        let result = FeedStatusTableLogic.filtered(diagnostics, matching: "androidpolice")

        #expect(result.map(\.feedTitle) == ["Android Police"])
    }

    @Test func filteredIstUnabhaengigVonGrossKleinschreibung() {
        let diagnostics = [diagnostic(feedTitle: "GoogleWatchBlog")]

        let result = FeedStatusTableLogic.filtered(diagnostics, matching: "GOOGLEWATCHBLOG")

        #expect(result.count == 1)
    }

    @Test func filteredLiefertLeeresArrayOhneTreffer() {
        let diagnostics = [diagnostic(feedTitle: "GoogleWatchBlog")]

        let result = FeedStatusTableLogic.filtered(diagnostics, matching: "macrumors")

        #expect(result.isEmpty)
    }

    @Test func sortedByFailureCountDescendingSortiertAbsteigend() {
        let diagnostics = [
            diagnostic(feedID: "a", feedTitle: "A", consecutiveFailureCount: 2),
            diagnostic(feedID: "b", feedTitle: "B", consecutiveFailureCount: 9),
            diagnostic(feedID: "c", feedTitle: "C", consecutiveFailureCount: 1)
        ]

        let result = FeedStatusTableLogic.sortedByFailureCountDescending(diagnostics)

        #expect(result.map(\.feedID) == ["b", "a", "c"])
    }

    @Test func severityIstNewBeiEinemFehlschlag() {
        #expect(FeedFailureSeverity.forConsecutiveFailureCount(1) == .new)
    }

    @Test func severityIstWarningZwischenZweiUndVier() {
        #expect(FeedFailureSeverity.forConsecutiveFailureCount(2) == .warning)
        #expect(FeedFailureSeverity.forConsecutiveFailureCount(4) == .warning)
    }

    @Test func severityIstCriticalAbFuenf() {
        #expect(FeedFailureSeverity.forConsecutiveFailureCount(5) == .critical)
        #expect(FeedFailureSeverity.forConsecutiveFailureCount(9) == .critical)
    }
}
