import AppKit
import Testing
@testable import Feedivo

private func measureMilliseconds<T>(
    _ name: String,
    _ block: () -> T
) -> (value: T, milliseconds: Double) {
    let start = ProcessInfo.processInfo.systemUptime
    let result = block()
    let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1_000
    print(String(format: "PERF_METRIC %@ %.3f ms", name, elapsed))
    return (result, elapsed)
}

@Suite("ArticleListRenderBenchmark")
struct ArticleListRenderBenchmarkTests {
    // Bewusst nur eine Proxy-Metrik für die AppKit-Seite (siehe Design-Doc,
    // Abschnitt 5): eine vergleichbar faire, headless Messung für die
    // SwiftUI-`List`-Seite ist technisch nicht zuverlässig möglich, da `List`
    // ihren internen Render-Server erst mit einem echten Fenster/Compositor
    // aufbaut. Diese Zahl ist ein Regressions-Wächter für den Prototyp
    // selbst, kein A/B-Beweis gegen die Baseline — der eigentliche Vergleich
    // läuft über die manuelle Instruments-Messung.
    // @MainActor ist hier zwingend nötig, nicht nur Stil: Swift Testing führt
    // @Test-Funktionen standardmäßig auf einem Hintergrund-Thread des
    // kooperativen Executors aus (anders als das alte XCTest, das immer auf
    // dem Main Thread lief) — das App-Target setzt zwar projektweit
    // SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor (siehe CLAUDE.md-Gotcha),
    // aber NICHT das FeedivoTests-Target selbst. Ohne diese Annotation stirbt
    // der Test reproduzierbar mit einem vom Main Thread Checker erzwungenen
    // SIGABRT beim `NSWindow.init(...)`-Aufruf ("UI API called on a
    // background thread") — live per Crash-Report/Unified-Log verifiziert,
    // kein reines Stilrisiko.
    @Test @MainActor func nativeTableViewLayoutMitTausendZeilenBleibtSchnell() {
        let snapshots = ArticleListRenderBenchmarkFixture.makeSnapshots(count: 1_000)
        let coordinator = NativeArticleTableView.Coordinator()
        coordinator.snapshots = snapshots

        let measurement = measureMilliseconds("native_table_view_layout_1000_rows") {
            let tableView = NSTableView()
            tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main")))
            tableView.headerView = nil
            tableView.rowHeight = ArticleRowHeightMetrics.height(
                interfaceTextSize: .standard,
                imagePosition: .left,
                summaryLineCount: ArticleListSummaryLineCount.defaultValue
            )
            tableView.dataSource = coordinator
            tableView.delegate = coordinator

            let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 800))
            scrollView.documentView = tableView

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 800),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.contentView = scrollView
            tableView.reloadData()
            window.contentView?.layoutSubtreeIfNeeded()
        }

        #expect(measurement.milliseconds < 2_000)
    }
}
