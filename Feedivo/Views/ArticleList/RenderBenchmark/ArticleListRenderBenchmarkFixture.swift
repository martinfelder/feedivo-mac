import AppKit
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

    // Whole-Branch-Review-Fund: `https://example.com/...`-URLs lösen NIE auf
    // echte Bilder auf. `ImageCacheService` cached fehlgeschlagene Fetches
    // nicht negativ, wodurch jeder `NativeArticleRowCellView.configure(...)`-
    // Aufruf (also jede Zellwiederverwendung beim Scrollen) zwei live
    // fehlschlagende Netzwerk-Requests auslöst — auf ewig, ohne dass je ein
    // Bild sichtbar wird. Das hätte den eigentlichen Zweck des Benchmarks
    // (die Bild-Flicker-Hypothese beobachten) unmöglich gemacht und die
    // native Seite unfair zusätzlich belastet. Fix: eine einzige, lokal
    // erzeugte PNG-Datei per `file://`-URL, für jeden Snapshot mit Bild
    // wiederverwendet — der tatsächliche Bildinhalt ist für diesen Benchmark
    // irrelevant, nur ein garantiert erfolgreicher, cachefähiger Ladevorgang
    // zählt.
    private static let generatedImageURL: URL = {
        let size = NSSize(width: 8, height: 8)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            preconditionFailure("Konnte kein PNG für den Render-Benchmark erzeugen")
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("render-benchmark-fixture-image.png")
        try? pngData.write(to: url)
        return url
    }()

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
            imageURL: hasImage ? generatedImageURL.absoluteString : nil,
            publishedAt: publishedAt,
            arrivedAt: publishedAt,
            estimatedReadingMinutes: hasSummary ? 1 + (index % 8) : nil,
            isRead: index % 5 == 0,
            isStarred: index % 11 == 0,
            isArchived: false,
            isHidden: false,
            faviconURL: hasImage ? generatedImageURL.absoluteString : nil
        )
    }

    private static func makeWords(prefix: String, wordCount: Int, seed: Int) -> String {
        (0 ..< wordCount)
            .map { "\(prefix)-\(seed)-\($0)" }
            .joined(separator: " ")
    }
}
#endif
