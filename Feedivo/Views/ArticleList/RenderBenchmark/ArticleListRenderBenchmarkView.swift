import SwiftUI

#if DEBUG
/// Debug-only Fenster-Inhalt für den NSTableView-vs-List-Render-Benchmark
/// (docs/superpowers/specs/2026-08/2026-08-04-nstableview-vs-list-render-benchmark-design.md).
/// Erlaubt das Umschalten zwischen Baseline und Prototyp im laufenden
/// Debug-Build, ohne die App neu zu starten — gedacht für Instruments-Traces
/// gegen dieselben 1000 synthetischen Zeilen.
struct ArticleListRenderBenchmarkView: View {
    static let windowID = "render-benchmark"

    enum Variant: String, CaseIterable, Identifiable {
        case baseline
        case native

        var id: String { rawValue }

        var title: String {
            switch self {
            case .baseline: "SwiftUI List (Baseline)"
            case .native: "NSTableView (Prototyp)"
            }
        }
    }

    @State private var variant: Variant = .baseline
    @State private var selectedID: String?
    private let snapshots = ArticleListRenderBenchmarkFixture.makeSnapshots()

    var body: some View {
        VStack(spacing: 0) {
            Picker("Variante", selection: $variant) {
                ForEach(Variant.allCases) { variant in
                    Text(variant.title).tag(variant)
                }
            }
            .pickerStyle(.segmented)
            .padding(8)

            Divider()

            switch variant {
            case .baseline:
                ArticleListRenderBenchmarkBaselineView(snapshots: snapshots, selectedID: $selectedID)
            case .native:
                NativeArticleTableView(
                    snapshots: snapshots,
                    selectedID: $selectedID,
                    onToggleStarred: { _ in }
                )
            }
        }
        .frame(minWidth: 420, minHeight: 500)
    }
}
#endif
