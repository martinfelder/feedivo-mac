import Foundation
import Testing
@testable import Feedivo

struct FeedRefreshThrottleTests {
    @Test func shouldSkipIstFalseWennNieVersucht() {
        let result = FeedRefreshThrottle.shouldSkip(
            lastAttemptAt: nil,
            now: Date(timeIntervalSince1970: 1_000)
        )

        #expect(result == false)
    }

    @Test func shouldSkipIstTrueInnerhalbDesMindestabstands() {
        let lastAttemptAt = Date(timeIntervalSince1970: 1_000)
        let now = lastAttemptAt.addingTimeInterval(5 * 60)

        let result = FeedRefreshThrottle.shouldSkip(
            lastAttemptAt: lastAttemptAt,
            now: now,
            minimumInterval: 9 * 60
        )

        #expect(result == true)
    }

    @Test func shouldSkipIstFalseNachAblaufDesMindestabstands() {
        let lastAttemptAt = Date(timeIntervalSince1970: 1_000)
        let now = lastAttemptAt.addingTimeInterval(10 * 60)

        let result = FeedRefreshThrottle.shouldSkip(
            lastAttemptAt: lastAttemptAt,
            now: now,
            minimumInterval: 9 * 60
        )

        #expect(result == false)
    }

    @Test func shouldSkipIstFalseGenauAnDerSchwelle() {
        let lastAttemptAt = Date(timeIntervalSince1970: 1_000)
        let now = lastAttemptAt.addingTimeInterval(9 * 60)

        let result = FeedRefreshThrottle.shouldSkip(
            lastAttemptAt: lastAttemptAt,
            now: now,
            minimumInterval: 9 * 60
        )

        #expect(result == false)
    }
}
