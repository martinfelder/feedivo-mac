import SwiftUI

#if DEBUG
/// SwiftUI-`List`-Baseline für den Render-Benchmark — rendert dieselben
/// Snapshots wie `NativeArticleTableView`, aber über das unveränderte,
/// produktive `ArticleRowView`.
struct ArticleListRenderBenchmarkBaselineView: View {
    let snapshots: [ArticleListSnapshot]
    @Binding var selectedID: String?

    var body: some View {
        List(selection: $selectedID) {
            ForEach(snapshots) { snapshot in
                ArticleRowView(
                    snapshot: ArticleListItemSnapshot(sqliteSnapshot: snapshot),
                    hasAvailableTags: false,
                    onToggleRead: {},
                    onToggleStarred: {},
                    onToggleArchived: {},
                    onRequestAssignTag: {},
                    onCreateRule: {},
                    onCopyLink: {},
                    onOpenOriginal: {},
                    onShareOriginal: {},
                    onOpenInNewTab: {},
                    onOpenInWindow: {},
                    onExport: {},
                    onDelete: {},
                    onMarkAllRead: {}
                )
                .tag(snapshot.id)
            }
        }
    }
}
#endif
