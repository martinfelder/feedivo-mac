import SwiftUI
import AppKit

/// Safari-artige Tab-Leiste über dem Reader-Bereich des Hauptfensters —
/// freistehende, abgerundete Tab-Pillen mit Abstand zueinander statt
/// aneinandergereihter Chrome-Register. Rein präsentational — DB-Mutationen
/// (Tab aktivieren, schließen, neu anlegen) laufen ausschließlich über die
/// vom Parent übergebenen Closures, siehe docs/superpowers/specs/2026-08/
/// 2026-08-02-artikel-tabs-design.md.
struct ReaderTabBarView: View {
    let tabs: [ReaderTab]
    let activeTabID: ReaderTab.ID?
    let database: FeedivoDatabase?
    let onActivate: (ReaderTab.ID) -> Void
    let onClose: (ReaderTab.ID) -> Void
    let onNewTab: () -> Void

    @State private var metadataByArticleID: [String: ArticleListSnapshot] = [:]

    // Reagiert zusätzlich auf statusVersion (nicht nur auf die Tab-Menge), damit
    // der Unread-Punkt verschwindet, sobald ein Hintergrund-Tab durch Aktivierung
    // als gelesen markiert wird — ohne das würde metadataByArticleID nach dem
    // ersten Laden stehen bleiben und beim erneuten Deaktivieren des Tabs
    // fälschlich wieder einen Punkt zeigen (isRead wäre nie neu geladen worden).
    @AppStorage(SQLiteDataInvalidation.statusVersionKey)
    private var sqliteStatusVersion = 0

    private struct MetadataReloadKey: Equatable {
        let articleIDs: [String]
        let statusVersion: Int
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tabs) { tab in
                tabView(for: tab)
            }

            Button(action: onNewTab) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .frame(width: 26, height: 26)
            .background(.secondary.opacity(0.08), in: Circle())
            .overlay {
                Circle().stroke(.secondary.opacity(0.16), lineWidth: 1)
            }
            .help(L10n.readerTabNewCommand)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
        .task(id: MetadataReloadKey(articleIDs: tabs.map(\.articleID), statusVersion: sqliteStatusVersion)) {
            await loadMetadata()
        }
    }

    @ViewBuilder
    private func tabView(for tab: ReaderTab) -> some View {
        let metadata = metadataByArticleID[tab.articleID]
        let isActive = tab.id == activeTabID
        let displayTitle = metadata?.title ?? L10n.readerTabArticleUnavailable
        let isUnvisited = !isActive && metadata?.isRead == false

        TabRow(
            displayTitle: displayTitle,
            isActive: isActive,
            isUnvisited: isUnvisited,
            faviconContent: { faviconView(for: metadata) },
            onActivate: { onActivate(tab.id) },
            onClose: { onClose(tab.id) }
        )
    }

    /// Eigene Zeilen-View statt eines Closures innerhalb von `tabView`, damit
    /// `@State private var isHovering` eine eigene, pro Tab stabile
    /// Identität hat (ein `@State` in einem `@ViewBuilder`-Funktionsergebnis
    /// würde bei jedem Neuaufbau von `tabs` zurückgesetzt).
    // Kapsel-Form + ruhige `secondary.opacity(...)`-Füllung übernehmen bewusst
    // dieselbe Chip-Sprache wie Ordner-/Tag-Chips im Artikel-Header darunter
    // (readerFolderChip/readerTagChip in SQLiteReaderView.swift) — Tabs sollen
    // sich wie ein natürlicher Teil dieses bestehenden Systems lesen statt wie
    // eine separat aufgeklebte Browser-Adressleiste.
    private struct TabRow<Favicon: View>: View {
        let displayTitle: String
        let isActive: Bool
        let isUnvisited: Bool
        @ViewBuilder let faviconContent: () -> Favicon
        let onActivate: () -> Void
        let onClose: () -> Void

        @State private var isHovering = false
        @Environment(\.interfaceTextSize) private var interfaceTextSize

        var body: some View {
            HStack(spacing: 6) {
                faviconContent()
                    .frame(width: 14, height: 14)
                    .overlay(alignment: .topTrailing) {
                        if isUnvisited {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 7, height: 7)
                                .overlay {
                                    Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5)
                                }
                                .offset(x: 3, y: -3)
                        }
                    }

                Text(displayTitle)
                    .font(interfaceTextSize.font(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .opacity(isActive || isHovering ? 0.6 : 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(minWidth: 90, maxWidth: 220)
            .background(
                Capsule()
                    .fill(
                        isActive
                            ? Color.accentColor.opacity(0.12)
                            : Color.secondary.opacity(isHovering ? 0.14 : 0.08)
                    )
            )
            .overlay(
                Capsule()
                    .strokeBorder(isActive ? Color.accentColor.opacity(0.32) : Color.clear, lineWidth: 1)
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
