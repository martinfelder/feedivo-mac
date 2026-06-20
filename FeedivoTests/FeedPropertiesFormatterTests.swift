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

    @Test func latestArticleWaehltNeuestenVeroeffentlichtenArtikel() {
        let older = Article(title: "Aelter", publishedAt: Date(timeIntervalSince1970: 100))
        let newest = Article(title: "Neu", publishedAt: Date(timeIntervalSince1970: 300))
        let undated = Article(title: "Ohne Datum")

        let latestArticle = FeedPropertiesFormatter.latestArticle(in: [older, undated, newest])

        #expect(latestArticle?.id == newest.id)
        #expect(FeedPropertiesFormatter.latestArticle(in: [undated])?.id == undated.id)
    }

    @Test func latestLogEntriesBegrenztAufZwanzigNeuesteEintraege() {
        let entries = (0..<25).map { index in
            FeedLogEntry(
                createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
                kind: "info",
                message: "Eintrag \(index)"
            )
        }

        let latestEntries = FeedPropertiesFormatter.latestLogEntries(entries)

        #expect(latestEntries.count == 20)
        #expect(latestEntries.first?.message == "Eintrag 24")
        #expect(latestEntries.last?.message == "Eintrag 5")
    }

    @Test func latestLogEntryCountZaehltNurSichtbareEintraege() {
        let entries = (0..<25).map { index in
            FeedLogEntry(
                createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
                kind: "info",
                message: "Eintrag \(index)"
            )
        }

        #expect(FeedPropertiesFormatter.latestLogEntryCount(entries) == 20)
        #expect(FeedPropertiesFormatter.latestLogEntryCount(entries, limit: 3) == 3)
    }

    @Test func copyableXMLAddressTrimmtAdresseUndIgnoriertLeereWerte() {
        #expect(FeedPropertiesFormatter.copyableXMLAddress("  https://example.com/feed.xml  ") == "https://example.com/feed.xml")
        #expect(FeedPropertiesFormatter.copyableXMLAddress("   ") == nil)
    }
}
