import Foundation
import Testing
@testable import Feedivo

struct FeedPropertiesFormatterTests {

    @Test func nextRefreshDateBerechnetZeitpunktAusLetztemAbrufUndIntervall() {
        let lastRefreshed = Date(timeIntervalSince1970: 1_000)

        let nextRefresh = FeedPropertiesFormatter.nextRefreshDate(
            lastRefreshed: lastRefreshed,
            intervalMinutes: 30
        )

        #expect(nextRefresh == Date(timeIntervalSince1970: 2_800))
        #expect(FeedPropertiesFormatter.nextRefreshDate(lastRefreshed: nil, intervalMinutes: 30) == nil)
    }

    @Test func copyableXMLAddressTrimmtAdresseUndIgnoriertLeereWerte() {
        #expect(FeedPropertiesFormatter.copyableXMLAddress("  https://example.com/feed.xml  ") == "https://example.com/feed.xml")
        #expect(FeedPropertiesFormatter.copyableXMLAddress("   ") == nil)
    }

    @Test func linkURLTrimmtGueltigeWebAdressenUndIgnoriertUngueltigeWerte() {
        #expect(FeedPropertiesFormatter.linkURL("  https://example.com/feed.xml  ") == URL(string: "https://example.com/feed.xml"))
        #expect(FeedPropertiesFormatter.linkURL("https://example.com") == URL(string: "https://example.com"))
        #expect(FeedPropertiesFormatter.linkURL("example.com") == nil)
        #expect(FeedPropertiesFormatter.linkURL("   ") == nil)
    }
}
