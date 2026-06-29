import Foundation
import SwiftData
import Testing
@testable import Feedivo

@MainActor
struct FeedPropertiesQueryTests {

    // MARK: - latestArticle

    @Test func latestArticleLiefertNeuestenDatiertenArtikel() throws {
        let context = try testContext()
        let feed = Feed(url: "https://example.com/feed", title: "Beispiel")
        context.insert(feed)
        try context.save()

        let older = Article(title: "Älter", publishedAt: Date(timeIntervalSince1970: 100), feed: feed)
        let newest = Article(title: "Neu", publishedAt: Date(timeIntervalSince1970: 300), feed: feed)
        let undated = Article(title: "Ohne Datum", feed: feed)
        [older, undated, newest].forEach { context.insert($0) }
        try context.save()

        let latest = FeedPropertiesQuery.latestArticle(in: context, for: feed)

        #expect(latest?.id == newest.id)
    }

    @Test func latestArticleFaelltAufUndatiertenZurueckWennKeinDatumVorliegt() throws {
        let context = try testContext()
        let feed = Feed(url: "https://example.com/feed", title: "Beispiel")
        context.insert(feed)
        try context.save()

        let undated = Article(title: "Ohne Datum", feed: feed)
        context.insert(undated)
        try context.save()

        let latest = FeedPropertiesQuery.latestArticle(in: context, for: feed)

        #expect(latest?.id == undated.id)
    }

    @Test func latestArticleIstNilBeiLeeremFeed() throws {
        let context = try testContext()
        let feed = Feed(url: "https://example.com/feed", title: "Beispiel")
        context.insert(feed)
        try context.save()

        let latest = FeedPropertiesQuery.latestArticle(in: context, for: feed)

        #expect(latest == nil)
    }

    @Test func latestArticleFiltertNurArtikelDiesesFeeds() throws {
        let context = try testContext()
        let feedA = Feed(url: "https://a.example.com/feed", title: "A")
        let feedB = Feed(url: "https://b.example.com/feed", title: "B")
        context.insert(feedA)
        context.insert(feedB)
        try context.save()

        // Älterer Artikel in Feed A, neuerer in Feed B — darf A nicht sehen.
        let aArticle = Article(title: "A-Artikel", publishedAt: Date(timeIntervalSince1970: 100), feed: feedA)
        let bArticle = Article(title: "B-Artikel", publishedAt: Date(timeIntervalSince1970: 500), feed: feedB)
        context.insert(aArticle)
        context.insert(bArticle)
        try context.save()

        let latest = FeedPropertiesQuery.latestArticle(in: context, for: feedA)

        #expect(latest?.id == aArticle.id)
    }

    // MARK: - latestLogEntries

    @Test func latestLogEntriesBegrenztAufLimitUndSortiertAbsteigend() throws {
        let context = try testContext()
        let feed = Feed(url: "https://example.com/feed", title: "Beispiel")
        context.insert(feed)
        try context.save()

        let entries = (0..<25).map { index in
            FeedLogEntry(
                createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
                kind: .info,
                message: "Eintrag \(index)",
                feed: feed
            )
        }
        entries.forEach { context.insert($0) }
        try context.save()

        let latest = FeedPropertiesQuery.latestLogEntries(in: context, for: feed)

        #expect(latest.count == 20)
        #expect(latest.first?.message == "Eintrag 24")
        #expect(latest.last?.message == "Eintrag 5")
    }

    @Test func latestLogEntriesFiltertNurEintraegeDiesesFeeds() throws {
        let context = try testContext()
        let feedA = Feed(url: "https://a.example.com/feed", title: "A")
        let feedB = Feed(url: "https://b.example.com/feed", title: "B")
        context.insert(feedA)
        context.insert(feedB)
        try context.save()

        (0..<3).forEach { index in
            context.insert(FeedLogEntry(createdAt: Date(timeIntervalSince1970: TimeInterval(index)), kind: .info, message: "A\(index)", feed: feedA))
        }
        (0..<2).forEach { index in
            context.insert(FeedLogEntry(createdAt: Date(timeIntervalSince1970: TimeInterval(index)), kind: .info, message: "B\(index)", feed: feedB))
        }
        try context.save()

        let latest = FeedPropertiesQuery.latestLogEntries(in: context, for: feedA)

        #expect(latest.count == 3)
        #expect(Set(latest.map(\.message)) == ["A0", "A1", "A2"])
    }

    @Test func latestLogEntriesIstLeerBeiFeedOhneEintraege() throws {
        let context = try testContext()
        let feed = Feed(url: "https://example.com/feed", title: "Beispiel")
        context.insert(feed)
        try context.save()

        let latest = FeedPropertiesQuery.latestLogEntries(in: context, for: feed)

        #expect(latest.isEmpty)
    }

    // MARK: - latestLogEntryCount

    @Test func latestLogEntryCountGibtSichtbareAnzahlBisLimit() throws {
        let context = try testContext()
        let feed = Feed(url: "https://example.com/feed", title: "Beispiel")
        context.insert(feed)
        try context.save()

        (0..<25).forEach { index in
            context.insert(FeedLogEntry(createdAt: Date(timeIntervalSince1970: TimeInterval(index)), kind: .info, message: "Eintrag \(index)", feed: feed))
        }
        try context.save()

        #expect(FeedPropertiesQuery.latestLogEntryCount(in: context, for: feed) == 20)
        #expect(FeedPropertiesQuery.latestLogEntryCount(in: context, for: feed, limit: 3) == 3)
    }

    @Test func latestLogEntryCountUnterLimitGibtGesamtanzahl() throws {
        let context = try testContext()
        let feed = Feed(url: "https://example.com/feed", title: "Beispiel")
        context.insert(feed)
        try context.save()

        (0..<5).forEach { index in
            context.insert(FeedLogEntry(createdAt: Date(timeIntervalSince1970: TimeInterval(index)), kind: .info, message: "Eintrag \(index)", feed: feed))
        }
        try context.save()

        #expect(FeedPropertiesQuery.latestLogEntryCount(in: context, for: feed) == 5)
    }

    // MARK: - recentArticleCount

    @Test func recentArticleCountZaehltNurDiesenFeedSeitGrenzdatum() throws {
        let context = try testContext()
        let feedA = Feed(url: "https://a.example.com/feed", title: "A")
        let feedB = Feed(url: "https://b.example.com/feed", title: "B")
        context.insert(feedA)
        context.insert(feedB)
        try context.save()

        let now = Date(timeIntervalSince1970: 1_000_000)
        let cutoffDate = now.addingTimeInterval(-7 * 24 * 60 * 60)
        let recentA = Article(title: "A neu", publishedAt: now.addingTimeInterval(-60), feed: feedA)
        let boundaryA = Article(title: "A Grenze", publishedAt: cutoffDate, feed: feedA)
        let oldA = Article(title: "A alt", publishedAt: cutoffDate.addingTimeInterval(-1), feed: feedA)
        let undatedA = Article(title: "A ohne Datum", feed: feedA)
        let futureA = Article(title: "A Zukunft", publishedAt: now.addingTimeInterval(60), feed: feedA)
        let recentB = Article(title: "B neu", publishedAt: now, feed: feedB)
        [recentA, boundaryA, oldA, undatedA, futureA, recentB].forEach { context.insert($0) }
        try context.save()

        let count = FeedPropertiesQuery.recentArticleCount(
            in: context,
            for: feedA,
            since: cutoffDate,
            until: now
        )

        #expect(count == 2)
    }

    // MARK: - Konsistenz mit Formatter

    @Test func latestArticleKonsistentMitFormatterBeiGemischtenArtikeln() throws {
        let context = try testContext()
        let feed = Feed(url: "https://example.com/feed", title: "Beispiel")
        context.insert(feed)
        try context.save()

        let older = Article(title: "Älter", publishedAt: Date(timeIntervalSince1970: 100), feed: feed)
        let newest = Article(title: "Neu", publishedAt: Date(timeIntervalSince1970: 300), feed: feed)
        let undated = Article(title: "Ohne Datum", feed: feed)
        [older, undated, newest].forEach { context.insert($0) }
        try context.save()

        let viaQuery = FeedPropertiesQuery.latestArticle(in: context, for: feed)
        let viaFormatter = FeedPropertiesFormatter.latestArticle(in: [older, undated, newest])

        #expect(viaQuery?.id == viaFormatter?.id)
    }

    // MARK: - Hilfskontext

    private func testContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Feed.self,
            FeedFolder.self,
            FeedLogEntry.self,
            Article.self,
            Tag.self,
            Rule.self,
            RuleCondition.self,
            SmartFolder.self,
            SmartFolderCondition.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }
}
