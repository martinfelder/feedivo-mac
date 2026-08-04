import Foundation

#if DEBUG
/// Erzeugt einen deterministischen, rein synthetischen Satz von
/// `ArticleListSnapshot`s für den NSTableView-vs-List-Render-Benchmark
/// (docs/superpowers/specs/2026-08/2026-08-04-nstableview-vs-list-render-benchmark-design.md).
/// Bewusst ohne Datenbankzugriff — die SQL-Schicht ist laut
/// docs/performance/sqlite-large-dataset-results.md bereits nachweislich
/// schnell, dieser Benchmark isoliert ausschließlich die Render-Variable.
enum ArticleListRenderBenchmarkFixture {
    static let defaultCount = 1_000

    static func makeSnapshots(count: Int = defaultCount) -> [ArticleListSnapshot] {
        (0 ..< count).map(makeSnapshot)
    }

    static func makeSnapshot(index: Int) -> ArticleListSnapshot {
        let feedIndex = index % 25
        let hasImage = index % 3 != 0
        let hasSummary = index % 4 != 0
        let titleWordCount = 3 + (index % 6)
        let summaryWordCount = 8 + (index % 12)
        let publishedAt = Date(timeIntervalSinceReferenceDate: TimeInterval(-index * 3_600))

        return ArticleListSnapshot(
            id: "benchmark-article-\(index)",
            feedID: "benchmark-feed-\(feedIndex)",
            feedTitle: "Benchmark-Feed \(feedIndex)",
            title: makeWords(prefix: "Titelwort", wordCount: titleWordCount, seed: index),
            summary: hasSummary ? makeWords(prefix: "Zusammenfassung", wordCount: summaryWordCount, seed: index) : nil,
            link: "https://example.com/benchmark/article/\(index)",
            imageURL: hasImage ? "https://example.com/benchmark/image/\(index).jpg" : nil,
            publishedAt: publishedAt,
            arrivedAt: publishedAt,
            estimatedReadingMinutes: hasSummary ? 1 + (index % 8) : nil,
            isRead: index % 5 == 0,
            isStarred: index % 11 == 0,
            isArchived: false,
            isHidden: false,
            faviconURL: hasImage ? "https://example.com/benchmark/favicon/\(feedIndex).png" : nil
        )
    }

    private static func makeWords(prefix: String, wordCount: Int, seed: Int) -> String {
        (0 ..< wordCount)
            .map { "\(prefix)-\(seed)-\($0)" }
            .joined(separator: " ")
    }
}
#endif
