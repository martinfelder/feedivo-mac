import Foundation
import Testing
@testable import Feedivo

/// Charakterisierungs-Tests für `ArticleSortOption.shortReadingTimeFirst`.
///
/// P3 (Performance): `sorted(_:)` berechnet `readingMinutes` aktuell pro
/// Vergleich (O(N·logN·2) Wortzählungen). Der Refactor pre-computet die
/// Lesezeit einmal pro Artikel als `[UUID: Int]`-Map und nutzt im Komparator
/// nur noch Lookups. Diese Tests pinnen das Sort-Verhalten, damit der
/// Refactor das Ergebnis nicht still verändert.
@Suite(.serialized)
struct ArticleSortOptionTests {

    /// Weniger Wörter → kürzere Lesezeit → weiter vorne.
    @Test func shortReadingTimeFirstSortiertNachLesezeitAufsteigend() {
        let kurz = Article(
            title: "Kurz",
            content: "eins zwei", // 2 Wörter → 1 Min
            publishedAt: Date(timeIntervalSince1970: 300)
        )
        let mittel = Article(
            title: "Mittel",
            content: Array(repeating: "wort", count: 220).joined(separator: " "), // → 2 Min
            publishedAt: Date(timeIntervalSince1970: 200)
        )
        let lang = Article(
            title: "Lang",
            content: Array(repeating: "wort", count: 420).joined(separator: " "), // → 3 Min
            publishedAt: Date(timeIntervalSince1970: 100)
        )

        let sortiert = ArticleSortOption.shortReadingTimeFirst
            .sorted([lang, mittel, kurz])
            .map(\.title)

        #expect(sortiert == ["Kurz", "Mittel", "Lang"])
    }

    /// Artikel ohne content/summary → readingMinutes Int.max → ans Ende.
    /// Unter den „leeren" Artikeln entscheidet der newestFirst-Tiebreak
    /// (neuere publishedAt zuerst).
    @Test func shortReadingTimeFirstSetztArtikelOhneTextAnsEnde() {
        let mitText = Article(
            title: "MitText",
            content: "eins zwei", // 1 Min
            publishedAt: Date(timeIntervalSince1970: 100)
        )
        let leerNeu = Article(
            title: "LeerNeu",
            publishedAt: Date(timeIntervalSince1970: 300) // neuer
        )
        let leerAlt = Article(
            title: "LeerAlt",
            publishedAt: Date(timeIntervalSince1970: 200) // älter
        )

        let sortiert = ArticleSortOption.shortReadingTimeFirst
            .sorted([leerAlt, leerNeu, mitText])
            .map(\.title)

        // MitText (1 Min) zuerst, dann die leeren nach newestFirst (neu vor alt).
        #expect(sortiert == ["MitText", "LeerNeu", "LeerAlt"])
    }

    /// Gleiche Lesezeit → Tiebreak über newestFirst (neuere publishedAt zuerst),
    /// dann title, dann id.
    @Test func shortReadingTimeFirstBrichtGleichstandMitNewestFirstAuf() {
        let a = Article(
            title: "Alpha",
            content: "eins zwei", // 1 Min
            publishedAt: Date(timeIntervalSince1970: 100) // älter
        )
        let b = Article(
            title: "Beta",
            content: "drei vier", // 1 Min (gleiche Wortzahl)
            publishedAt: Date(timeIntervalSince1970: 300) // neuer
        )

        let sortiert = ArticleSortOption.shortReadingTimeFirst
            .sorted([a, b])
            .map(\.title)

        #expect(sortiert == ["Beta", "Alpha"])
    }

    /// Ist content vorhanden, wird summary ignoriert (content hat Vorrang).
    @Test func shortReadingTimeFirstBevorzugtContentGegenueberSummary() {
        let contentKurz = Article(
            title: "ContentKurz",
            summary: Array(repeating: "wort", count: 420).joined(separator: " "), // würde 3 Min ergeben
            content: "eins zwei", // 1 Min aus content (Vorrang)
            publishedAt: Date(timeIntervalSince1970: 100)
        )
        let summaryLang = Article(
            title: "SummaryLang",
            summary: Array(repeating: "wort", count: 420).joined(separator: " "), // 3 Min aus summary
            publishedAt: Date(timeIntervalSince1970: 300)
        )

        let sortiert = ArticleSortOption.shortReadingTimeFirst
            .sorted([summaryLang, contentKurz])
            .map(\.title)

        #expect(sortiert == ["ContentKurz", "SummaryLang"])
    }

    /// Artikel werden nach Feed-Titel aufsteigend gruppiert
    /// (localizedStandardCompare). „Alpha" vor „Beta".
    @Test func feedSortGruppiertArtikelNachFeedTitelAufsteigend() {
        let feedAlpha = Feed(url: "https://a.example/a.xml", title: "Alpha")
        let feedBeta = Feed(url: "https://b.example/b.xml", title: "Beta")
        let ausAlpha = Article(
            title: "AusAlpha",
            publishedAt: Date(timeIntervalSince1970: 100),
            feed: feedAlpha
        )
        let ausBeta = Article(
            title: "AusBeta",
            publishedAt: Date(timeIntervalSince1970: 300),
            feed: feedBeta
        )

        let sortiert = ArticleSortOption.feed.sorted([ausBeta, ausAlpha]).map(\.title)

        #expect(sortiert == ["AusAlpha", "AusBeta"])
    }

    /// Artikel ohne Feed (feed?.title == nil) sortieren hinter Artikel mit Feed.
    @Test func feedSortSetztArtikelOhneFeedHinterArtikelMitFeed() {
        let feed = Feed(url: "https://a.example/a.xml", title: "Alpha")
        let mitFeed = Article(
            title: "MitFeed",
            publishedAt: Date(timeIntervalSince1970: 100),
            feed: feed
        )
        let ohneFeedNeu = Article(
            title: "OhneFeedNeu",
            publishedAt: Date(timeIntervalSince1970: 300)
        )
        let ohneFeedAlt = Article(
            title: "OhneFeedAlt",
            publishedAt: Date(timeIntervalSince1970: 200)
        )

        let sortiert = ArticleSortOption.feed
            .sorted([ohneFeedAlt, ohneFeedNeu, mitFeed])
            .map(\.title)

        // MitFeed (Feed-Titel „Alpha") zuerst, dann die feedlosen nach
        // newestFirst-Tiebreak (neu vor alt).
        #expect(sortiert == ["MitFeed", "OhneFeedNeu", "OhneFeedAlt"])
    }

    /// Gleicher Feed-Titel → compareText liefert nil → newestFirst-Tiebreak
    /// (neuere publishedAt zuerst).
    @Test func feedSortBrichtGleichstandGleicherFeedMitNewestFirstAuf() {
        let feed = Feed(url: "https://a.example/a.xml", title: "Alpha")
        let aelter = Article(
            title: "Aelter",
            publishedAt: Date(timeIntervalSince1970: 100),
            feed: feed
        )
        let neuer = Article(
            title: "Neuer",
            publishedAt: Date(timeIntervalSince1970: 300),
            feed: feed
        )

        let sortiert = ArticleSortOption.feed.sorted([aelter, neuer]).map(\.title)

        #expect(sortiert == ["Neuer", "Aelter"])
    }
}