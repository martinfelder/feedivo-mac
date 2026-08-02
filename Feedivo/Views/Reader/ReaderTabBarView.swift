import SwiftUI
import AppKit

/// Chrome-Register-artige Tab-Leiste über dem Reader-Bereich des
/// Hauptfensters. Rein präsentational — DB-Mutationen (Tab aktivieren,
/// schließen, neu anlegen) laufen ausschließlich über die vom Parent
/// übergebenen Closures, siehe docs/superpowers/specs/2026-08/
/// 2026-08-02-artikel-tabs-design.md.
struct ReaderTabBarView: View {
    let tabs: [ReaderTab]
    let activeTabID: ReaderTab.ID?
    let database: FeedivoDatabase?
    let onActivate: (ReaderTab.ID) -> Void
    let onClose: (ReaderTab.ID) -> Void
    let onNewTab: () -> Void

    @State private var metadataByArticleID: [String: ArticleListSnapshot] = [:]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                tabView(for: tab)
            }

            Button(action: onNewTab) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
            .padding(.bottom, 4)
            .help(L10n.readerTabNewCommand)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.top, 6)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
        .task(id: tabs.map(\.articleID)) {
            await loadMetadata()
        }
    }

    @ViewBuilder
    private func tabView(for tab: ReaderTab) -> some View {
        let metadata = metadataByArticleID[tab.articleID]
        let isActive = tab.id == activeTabID
        let displayTitle = metadata?.title ?? L10n.readerTabArticleUnavailable

        TabRow(
            displayTitle: displayTitle,
            isActive: isActive,
            faviconContent: { faviconView(for: metadata) },
            onActivate: { onActivate(tab.id) },
            onClose: { onClose(tab.id) }
        )
    }

    /// Eigene Zeilen-View statt eines Closures innerhalb von `tabView`, damit
    /// `@State private var isHovering` eine eigene, pro Tab stabile
    /// Identität hat (ein `@State` in einem `@ViewBuilder`-Funktionsergebnis
    /// würde bei jedem Neuaufbau von `tabs` zurückgesetzt).
    private struct TabRow<Favicon: View>: View {
        let displayTitle: String
        let isActive: Bool
        @ViewBuilder let faviconContent: () -> Favicon
        let onActivate: () -> Void
        let onClose: () -> Void

        @State private var isHovering = false

        var body: some View {
            HStack(spacing: 6) {
                faviconContent()
                    .frame(width: 14, height: 14)

                Text(displayTitle)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(.plain)
                .opacity(isActive || isHovering ? 0.6 : 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minWidth: 60, maxWidth: 160)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isActive ? Color(nsColor: .controlBackgroundColor) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isActive ? Color(nsColor: .separatorColor) : Color.clear)
            )
            .contentShape(Rectangle())
            .onTapGesture(perform: onActivate)
            .onHover { isHovering = $0 }
            .help(displayTitle)
        }
    }

    @ViewBuilder
    private func faviconView(for metadata: ArticleListSnapshot?) -> some View {
        if let faviconURLString = metadata?.faviconURL, let url = URL(string: faviconURLString) {
            CachedRemoteImageView(url: url) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                faviconFallback
            }
        } else {
            faviconFallback
        }
    }

    private var faviconFallback: some View {
        Image(systemName: "dot.radiowaves.left.and.right")
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
    }

    /// Lädt Titel/Feed-Favicon für alle offenen Tabs in einem Rutsch. Läuft
    /// per `Task.detached`, da `ArticleDatabase.fetchArticles(...)`
    /// synchron ist und das Projekt `SWIFT_DEFAULT_ACTOR_ISOLATION =
    /// MainActor` setzt (siehe Gotcha in CLAUDE.md) — ein einfaches `Task {}`
    /// würde sonst weiterhin auf dem MainActor blockieren.
    private func loadMetadata() async {
        guard let database else {
            metadataByArticleID = [:]
            return
        }

        let articleIDs = Set(tabs.map(\.articleID))
        guard !articleIDs.isEmpty else {
            metadataByArticleID = [:]
            return
        }

        let snapshots = await Task.detached(priority: .userInitiated) {
            (try? ArticleDatabase(database: database).fetchArticles(articleIDs: articleIDs)) ?? []
        }.value

        metadataByArticleID = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id, $0) })
    }
}
