import Testing
@testable import Feedivo

struct FeedNotificationServiceTests {
    @Test func summaryIgnoriertFeedsOhneAktiveBenachrichtigungOderNeueArtikel() {
        let summary = FeedNotificationService.summary(
            from: [
                FeedRefreshNotificationResult(
                    feedTitle: "Heise",
                    newArticleCount: 0,
                    isNotificationEnabled: true
                ),
                FeedRefreshNotificationResult(
                    feedTitle: "Mac & i",
                    newArticleCount: 2,
                    isNotificationEnabled: false
                )
            ]
        )

        #expect(summary == nil)
    }

    @Test func summaryFasstNeueArtikelAktiverFeedsZusammen() throws {
        let summary = try #require(
            FeedNotificationService.summary(
                from: [
                    FeedRefreshNotificationResult(
                        feedTitle: "Heise",
                        newArticleCount: 3,
                        isNotificationEnabled: true
                    ),
                    FeedRefreshNotificationResult(
                        feedTitle: "Mac & i",
                        newArticleCount: 2,
                        isNotificationEnabled: true
                    ),
                    FeedRefreshNotificationResult(
                        feedTitle: "Privat",
                        newArticleCount: 4,
                        isNotificationEnabled: false
                    )
                ]
            )
        )

        #expect(summary.newArticleCount == 5)
        #expect(summary.feedTitles == ["Heise", "Mac & i"])
        #expect(summary.title == "5 neue Artikel")
        #expect(summary.body == "Heise, Mac & i")
    }
}
